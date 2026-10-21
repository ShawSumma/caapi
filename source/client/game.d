module client.game;

import core.stdc.math : acoshf, atan2f, atanhf, coshf, fabs, fabsf, sinhf, sqrt, tanhf;
import base.array : Array;
import base.numbers : higherOf;
import base.units : Acceleration, Angle, Length, Speed, Time;
import base.vector3 : ZERO_VECTOR, cross, dot, magnitude, negated, plus, rejectAlong, scaled;
import client.arrivals : generateNow;
import client.camera : CAMERA_FORWARD, Camera;
import client.world : LocalWorld, Placement;
import common.character.controller : CharacterInput, CharacterState, MovementMode, Mover, Slide, Stepped, movedBy, regionReach;
import common.character.features : CellOverlap, CellRange, Features, LocalFrame, RequiredChunks, visitCells;
import common.character.sweep : Capsule, sectionCenters;
import common.graph : Graph, NodeId;
import common.node : ChunkSlot, ChunkState;
import common.position : Position;
import common.settings : CHUNK_DIMENSION, CharacterConfig;
import common.traversal : NOT_COLLECTED, NearbyNode, NearbyScratch;
import common.worldgen.blueprint : RouteStop;
import common.worldgen.generation : NodeState, Worldgen;
import common.worldgen.horospheres : ensureHorospheresAt, gravityAt;
import common.worldgen.spawn : clearSpawnPosition, collectChunksNear;
import common.worldgen.structure : SiteFrame, columnPoint, rootSite, siteToNode, sitePlacement, spawnBefore;
import geometry.honeycomb : CORNER_COUNT, Corner, Face, cornerToNode;
import geometry.lorentz : Motion, Point, Vec4;
import plugins.api.api : Material;

enum uint MAX_BODY_SECTIONS = 64;

immutable Material[9] MATERIAL_PALETTE = [
    Material.woodPlanks,
    Material.oakWood,
    Material.oakLeaves,
    Material.greyBrick,
    Material.whiteBrick,
    Material.sandstone,
    Material.marble,
    Material.granite,
    Material.basalt,
];

enum Key : ubyte {
    fwd,
    back,
    left,
    right,
    up,
    down,
    yawLeft,
    yawRight,
    pitchUp,
    pitchDown,
}

enum uint KEY_COUNT = Key.max + 1;

struct FrameInput {
    Angle yaw;
    Angle pitch;
    bool[KEY_COUNT] isHeld;
}

float axisValue(bool isHeld) {
    if (isHeld) {
        return 1.0f;
    } else {
        return 0.0f;
    }
}

struct UnloadedCount {
    uint fresh;
    uint generating;
    uint dropped;
    uint missingNodes;
    uint awaitingBuilding;

    void visitMissingNode(uint, Face) {
        missingNodes += 1;
    }

    void visitChunk(ref const Graph graph, LocalFrame, ChunkSlot slot, CellRange) {
        final switch (graph.chunks.at(slot).state) {
            case ChunkState.fresh:
                if (graph.structures.at(slot.slot).isBuildingQueued) {
                    awaitingBuilding += 1;
                } else {
                    fresh += 1;
                }
                break;
            case ChunkState.generating:
                generating += 1;
                break;
            case ChunkState.dropped:
                dropped += 1;
                break;
            case ChunkState.populated:
                break;
        }
    }
}

struct RouteWaypoint {
    Angle yaw;
    Length horizontal;
    Length rise;
    bool isFound;
}

struct Game {
    LocalWorld world;
    Camera camera;
    CharacterState characterState;
    CharacterConfig character;
    Time time;
    Length traveled;
    Length altitude;
    Acceleration cameraVerticalAcceleration;
    Length cameraAltitude;
    Speed cameraVerticalVelocity;
    uint materialIndex;
    MovementMode mode = MovementMode.walk;
    bool isGeneratingOnDemand;
    bool hasCameraVerticalVelocity;
    bool wasJumpHeld;

    static Game make(Worldgen worldgen, Length reach) {
        Game game;
        game.world = LocalWorld.make(CHUNK_DIMENSION, worldgen, tanhf(reach.value));
        game.camera = Camera.make(game.character.eyeOffset);
        return game;
    }

    Length bodyExtent() const {
        return character.halfHeight + character.skin;
    }

    Length bodyReach() const {
        return bodyExtent() + character.radius;
    }

    Capsule bodyCapsule() const {
        return Capsule(characterState.up, character.radius.value, character.halfHeight.value, character.skin.value);
    }

    void generateAround(Position position, Length reach) {
        Array!ChunkSlot picked = world.graph.collectChunksNear(position, atanhf(world.tanhReach));
        foreach (chunk; picked.slice()) {
            world.graph.generateNow(chunk);
        }
        picked.release();
        RequiredChunks required;
        bool isComplete = false;
        while (!isComplete) {
            required.clear();
            visitCells(world.graph, position, reach, required);
            foreach (missing; required.missing.slice()) {
                world.graph.ensureNeighborSlot(missing.slot, missing.side);
            }
            foreach (chunk; required.chunks.slice()) {
                world.graph.generateNow(chunk);
            }
            isComplete = required.missing.length == 0;
        }
        required.release();
    }

    void placeAtSpawn() {
        if (world.graph.structures.blueprint.hasEntrance) {
            RouteStop entrance = world.graph.structures.blueprint.entrance;
            placeAt(sitePosition(entrance.site, spawnBefore(world.graph.layout, entrance.spot)), bodyExtent() + character.skin);
        } else {
            Position spawn = world.graph.clearSpawnPosition(bodyReach().value);
            float[3] up = world.graph.gravityAt(spawn).up;
            characterState = CharacterState(spawn, ZERO_VECTOR, [0, 1, 0], up, up, false);
        }
        settleToGround();
        resetView();
        if (world.graph.structures.blueprint.hasEntrance) {
            camera.turn(yawToward(directionToDoor()), Angle(0));
        } else if (world.graph.worldgen.groundTiltRadians() != 0) {
            camera.turn(yawToward(uphillDirection()), Angle(0));
        }
        updateView();
    }

    void settleToGround() {
        Length reach = regionReach(character) + bodyReach();
        Features features;
        Slide drop;
        while (!drop.hasLanded) {
            generateAround(characterState.position, reach);
            world.graph.ensureState(world.graph.slotOf(characterState.position.node));
            characterState.up = world.graph.gravityAt(characterState.position).up;
            characterState.pull = characterState.up;
            features.collect(world.graph, characterState.position, reach);
            drop = Mover.make(character, features, characterState.up, Length(0)).settle(ZERO_VECTOR, bodyReach());
            characterState.position = world.graph.movedBy(characterState.position, drop.position);
        }
        features.release();
        characterState.groundNormal = drop.groundNormal;
        characterState.isOnGround = true;
    }

    void resetView() {
        camera = Camera.make(character.eyeOffset);
        altitude = currentAltitude();
        followBody();
        updateView();
        cameraAltitude = altitude + camera.eyeOffset;
        hasCameraVerticalVelocity = false;
    }

    Length currentAltitude() {
        Position position = characterState.position;
        return Length(world.graph.ensureState(world.graph.slotOf(position.node)).surface.distanceTo(position.local * Point!float.origin()));
    }

    float[3] directionToDoor() {
        RouteStop entrance = world.graph.structures.blueprint.entrance;
        Motion!float siteToBody = characterState.position.local.inverse() * world.graph.view.siteToNode(entrance.site, world.graph.slotOf(characterState.position.node));
        return (siteToBody * columnPoint(world.graph.layout, entrance.spot)).v.spatial();
    }

    float[3] uphillDirection() const {
        return world.graph.stateAt(world.graph.slotOf(characterState.position.node)).reference.upAt(characterState.position.local).negated;
    }

    Angle yawToward(float[3] direction) const {
        float[3] forward = camera.heading.rotate(CAMERA_FORWARD);
        float[3] level = direction.rejectAlong(camera.viewUp);
        return Angle(atan2f(camera.viewUp.dot(forward.cross(level)), forward.dot(level)));
    }

    void enterStructure(Length height) {
        placeAt(sitePosition(rootSite(world.graph.anchorSlot), Point!float(Vec4!float([0, sinhf(height.value), 0, coshf(height.value)]))), Length(0));
    }

    Position sitePosition(SiteFrame site, Point!float inSite) {
        Point!float point = sitePlacement(site, world.graph.layout) * inSite;
        return world.graph.ensureNormalized(Position(world.graph.idAt(site.node), Motion!float.shiftTo(point)));
    }

    void enterRoute() {
        RouteStop stop = world.graph.structures.blueprint.route.ptr[0];
        placeAt(sitePosition(stop.site, columnPoint(world.graph.layout, stop.spot)), bodyExtent() + character.skin);
    }

    RouteWaypoint routeWaypoint(size_t index) {
        if (index >= world.graph.structures.blueprint.route.length) {
            return RouteWaypoint.init;
        } else {
            RouteStop stop = world.graph.structures.blueprint.route.ptr[index];
            Motion!float siteToBody = world.graph.view.siteToNode(stop.site, world.graph.slotOf(characterState.position.node));
            return waypointAt(siteToBody * columnPoint(world.graph.layout, stop.spot));
        }
    }

    RouteWaypoint waypointAt(Point!float floor) const {
        Vec4!float local = (characterState.position.local.inverse() * floor).v;
        float[3] direction = local.spatial();
        float length = direction.magnitude;
        float[3] toFloor = direction.scaled(acoshf(local.c[3]) / length);
        float[3] fromFeet = toFloor.plus(characterState.up.scaled(bodyExtent().value));
        return RouteWaypoint(yawToward(toFloor), Length(fromFeet.rejectAlong(characterState.up).magnitude), Length(fromFeet.dot(characterState.up)), true);
    }

    void placeAt(Position target, Length lift) {
        world.graph.ensureState(world.graph.slotOf(target.node));
        world.graph.view.ensureHorospheresAt(world.graph.slotOf(target.node));
        float[3] up = world.graph.gravityAt(target).up;
        Position lifted = world.graph.ensureNormalized(Position(target.node, (target.local * Motion!float.shift(up.scaled(lift.value))).orthonormalized()));
        world.graph.ensureState(world.graph.slotOf(lifted.node));
        world.graph.view.ensureHorospheresAt(world.graph.slotOf(lifted.node));
        float[3] liftedUp = world.graph.gravityAt(lifted).up;
        characterState = CharacterState(lifted, ZERO_VECTOR, characterState.groundNormal, liftedUp, liftedUp, false);
        resetView();
    }

    void rebuildWorld(Worldgen worldgen) {
        ubyte dimension = world.graph.layout.dimension;
        float tanhReach = world.tanhReach;
        uint epoch = world.epoch;
        world.release();
        world = LocalWorld.make(dimension, worldgen, tanhReach);
        world.epoch = epoch + 1;
    }

    void release() {
        world.release();
    }

    bool breakBlock() {
        return world.breakBlock();
    }

    bool placeBlock() {
        Placement placement = world.placementTarget();
        if (placement.isFound && !isBodyOverlapping(ChunkSlot(world.graph.slotOf(placement.chunk.node), placement.chunk.corner), placement)) {
            return world.setVoxel(placement.chunk, placement.coords, MATERIAL_PALETTE[materialIndex]);
        } else {
            return false;
        }
    }

    bool isBodyOverlapping(ChunkSlot slot, Placement placement) const {
        float[3][MAX_BODY_SECTIONS] storage;
        CellOverlap overlap = CellOverlap(sectionCenters(bodyCapsule(), ZERO_VECTOR, storage[]), slot, placement.coords, character.radius.value);
        visitCells(world.graph, characterState.position, regionReach(character), overlap);
        return overlap.isOverlapping;
    }

    void look(Angle yaw, Angle pitch) {
        camera.turn(-yaw, -pitch);
        updateView();
    }

    void followBody() {
        Motion!float eye = Motion!float.shift(characterState.up.scaled(camera.eyeOffset.value));
        camera.follow(characterState.position, eye, characterState.up);
    }

    void updateView() {
        world.cameraPosition = camera.orientedPosition();
    }

    void step(FrameInput input, Time dt) {
        look(input.yaw, input.pitch);
        float moveX = axisValue(input.isHeld[Key.right]) - axisValue(input.isHeld[Key.left]);
        float moveY = axisValue(input.isHeld[Key.up]) - axisValue(input.isHeld[Key.down]);
        float moveZ = axisValue(input.isHeld[Key.back]) - axisValue(input.isHeld[Key.fwd]);
        bool isJumping = input.isHeld[Key.up] && !wasJumpHeld;
        wasJumpHeld = input.isHeld[Key.up];
        Stepped stepped = runCharacter(characterInput(moveX, moveY, moveZ, isJumping), dt);
        traveled = traveled + stepped.traveled;
        altitude = currentAltitude();
        followBody();
        updateView();
        trackCameraAcceleration(altitude + camera.eyeOffset, dt);
        if (!isGeneratingOnDemand) {
            world.update(false);
        }
        time = time + dt;
    }

    Length frameDrift(Length radius) {
        NearbyScratch scratch;
        NearbyNode[] fresh = scratch.collectAll(world.graph, world.cameraPosition, radius.value);
        const(NearbyScratch)* drawn = &world.nearby[world.published];
        Motion!float fromFrame = world.cameraInNearbyFrame().inverse();
        Motion!float fromNode = world.cameraPosition.local.inverse();
        double most = 0;
        foreach (node; fresh) {
            uint index = drawn.indexOf(node.slot);
            if (index != NOT_COLLECTED) {
                Motion!float drawnToCamera = fromFrame * drawn.nodes.ptr[index].transform;
                Motion!float freshToCamera = fromNode * node.transform;
                foreach (corner; 0 .. CORNER_COUNT) {
                    Motion!float toNode = (cast(Corner) corner).cornerToNode;
                    Vec4!double apart = (drawnToCamera * toNode * Point!float.origin()).v.as!double() - (freshToCamera * toNode * Point!float.origin()).v.as!double();
                    most = higherOf(sqrt(fabs(apart.minkowski(apart))), most);
                }
            }
        }
        scratch.release();
        return Length(cast(float) most);
    }

    UnloadedCount unloadedWithin(Length radius) const {
        UnloadedCount counted;
        visitCells(world.graph, characterState.position, radius, counted);
        return counted;
    }

    bool isLoadedAround() const {
        Features features;
        features.collect(world.graph, characterState.position, regionReach(character));
        bool isLoaded = features.isLoaded;
        features.release();
        return isLoaded;
    }

    Stepped runCharacter(CharacterInput input, Time dt) {
        if (isGeneratingOnDemand) {
            return runGenerating(input, dt);
        } else {
            return characterState.runStep(character, world.graph, input, dt);
        }
    }

    Stepped runGenerating(CharacterInput input, Time dt) {
        generateAround(characterState.position, regionReach(character));
        CharacterState trial = characterState;
        Stepped stepped = trial.runStep(character, world.graph, input, dt);
        while (stepped.isStalled) {
            generateAround(trial.position, regionReach(character));
            trial = characterState;
            stepped = trial.runStep(character, world.graph, input, dt);
        }
        characterState = trial;
        return stepped;
    }

    CharacterInput characterInput(float moveX, float moveY, float moveZ, bool isJumping) const {
        if (mode == MovementMode.noclip) {
            return CharacterInput(camera.orientation.rotate([moveX, moveY, moveZ]), mode, false);
        } else if (mode == MovementMode.fly) {
            return CharacterInput(levelMove(moveX, moveZ).plus(characterState.up.scaled(moveY)), mode, false);
        } else {
            return CharacterInput(levelMove(moveX, moveZ), mode, isJumping);
        }
    }

    float[3] levelMove(float moveX, float moveZ) const {
        return camera.heading.rotate([1, 0, 0]).scaled(moveX).plus(camera.heading.rotate([0, 0, 1]).scaled(moveZ));
    }

    void trackCameraAcceleration(Length newCameraAltitude, Time dt) {
        Speed verticalVelocity = (newCameraAltitude - cameraAltitude) / dt;
        if (hasCameraVerticalVelocity) {
            cameraVerticalAcceleration = Acceleration(fabsf(((verticalVelocity - cameraVerticalVelocity) / dt).value));
        } else {
            cameraVerticalAcceleration = Acceleration(0);
        }
        cameraAltitude = newCameraAltitude;
        cameraVerticalVelocity = verticalVelocity;
        hasCameraVerticalVelocity = true;
    }

    void toggleMode(MovementMode toggled) {
        if (mode == toggled) {
            mode = MovementMode.fly;
        } else {
            mode = toggled;
        }
    }
}
