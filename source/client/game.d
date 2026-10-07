module client.game;

import core.stdc.math : acoshf, atan2f, atanhf, coshf, fabsf, sinhf, tanhf;
import client.camera : Camera;
import client.streaming : generateNow;
import client.world : LocalWorld, Placement;
import common.array : Array;
import common.character.controller : CharacterInput, CharacterState, MovementMode, Mover, Slide, Stepped, movedBy, regionReach;
import common.character.features : CellOverlap, Features, RequiredChunks, visitCells;
import common.character.sweep : Capsule, sectionCenters;
import common.graph : NodeId;
import common.material : Material;
import common.math : MIsometry, MPoint, MVector;
import common.node : ChunkSlot;
import common.position : Position;
import common.settings : CHUNK_DIMENSION, CharacterConfig;
import common.traversal : NearbyNode, NearbyScratch;
import common.units : Acceleration, Angle, Length, Speed, Time;
import common.vector3 : ZERO_VECTOR, cross, dot, magnitude, negated, plus, rejectAlong, scaled;
import common.worldgen.generation : NodeState, Worldgen, WorldgenKind;
import common.worldgen.spawn : clearSpawnPosition, collectChunksNear;
import common.worldgen.tower : NodeStructure, RouteStop, StructurePlan, columnPoint, routeStop;

enum float STRUCTURE_SEARCH_RADIUS = 4.0f;
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
        game.placeAtSpawn();
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
        if (world.graph.worldgen.kind == WorldgenKind.structure) {
            placeAt(linePosition(0, structurePlan().spawnPoint(world.graph.layout)), bodyExtent() + character.skin);
        } else {
            Position spawn = world.graph.clearSpawnPosition(bodyReach().value);
            characterState = CharacterState(spawn, ZERO_VECTOR, [0, 1, 0], world.graph.upAt(spawn), false);
        }
        settleToGround();
        resetView();
        if (world.graph.worldgen.kind == WorldgenKind.structure) {
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
            world.graph.ensureNodeState(characterState.position.node);
            characterState.up = world.graph.upAt(characterState.position);
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
        camera.level();
        updateView();
        cameraAltitude = altitude + camera.eyeOffset;
        hasCameraVerticalVelocity = false;
    }

    Length currentAltitude() {
        Position position = characterState.position;
        world.graph.ensureNodeState(position.node);
        return Length(world.graph.nodeState(position.node).surface.distanceTo(position.local * MPoint!float.origin()));
    }

    MIsometry!float nodeTransform(NodeId node, float radius) {
        NearbyScratch scratch;
        NearbyNode[] nearby = scratch.collectAll(world.graph, characterState.position, radius);
        size_t index = 0;
        while (index < nearby.length && nearby[index].id != node) {
            index += 1;
        }
        assert(index < nearby.length);
        MIsometry!float transform = nearby[index].transform;
        scratch.release();
        return transform;
    }

    StructurePlan structurePlan() const {
        return StructurePlan.fromKind(world.graph.worldgen.structure.kind, world.graph.layout);
    }

    float[3] directionToDoor() {
        NodeId base = world.graph.worldgen.structure.base;
        StructurePlan plan = structurePlan();
        MPoint!float door = world.graph.ensureStructureAt(world.graph.slotOf(base)).lineToNode(plan, 0) * columnPoint(world.graph.layout, plan.doorSpot(world.graph.layout.dimension));
        return (characterState.position.local.inverse() * nodeTransform(base, STRUCTURE_SEARCH_RADIUS) * door).vec.xyz();
    }

    float[3] uphillDirection() const {
        const(NodeState)* state = world.graph.nodeState(characterState.position.node);
        return (characterState.position.local.inverse() * state.reference.scaledNormal).xyz().negated;
    }

    Angle yawToward(float[3] direction) const {
        float[3] forward = camera.forward().rejectAlong(camera.viewUp);
        float[3] level = direction.rejectAlong(camera.viewUp);
        return Angle(atan2f(camera.viewUp.dot(forward.cross(level)), forward.dot(level)));
    }

    void enterStructure(Length height) {
        placeAt(linePosition(0, MPoint!float(MVector!float([0, sinhf(height.value), 0, coshf(height.value)]))), Length(0));
    }

    Position linePosition(uint line, MPoint!float inLine) {
        uint slot = world.graph.slotOf(world.graph.worldgen.structure.base);
        StructurePlan plan = structurePlan();
        MPoint!float point = world.graph.ensureStructureAt(slot).lineToNode(plan, line) * inLine;
        return world.graph.ensureNormalized(Position(world.graph.idAt(slot), MIsometry!float.fromTranslation(MPoint!float.origin(), point)));
    }

    void enterRoute() {
        StructurePlan plan = structurePlan();
        RouteStop stop = routeStop(plan, 0, world.graph.layout.dimension);
        placeAt(linePosition(stop.line, columnPoint(world.graph.layout, stop.spot)), bodyExtent() + character.skin);
    }

    RouteWaypoint routeWaypoint(size_t index) {
        if (world.graph.worldgen.kind != WorldgenKind.structure) {
            return RouteWaypoint.init;
        } else {
            StructurePlan plan = structurePlan();
            RouteStop stop = routeStop(plan, index, world.graph.layout.dimension);
            if (stop.spot.isFound) {
                NodeStructure structure = world.graph.ensureStructureAt(world.graph.slotOf(characterState.position.node));
                return waypointAt(structure.lineToNode(plan, stop.line) * columnPoint(world.graph.layout, stop.spot));
            } else {
                return RouteWaypoint.init;
            }
        }
    }

    RouteWaypoint waypointAt(MPoint!float floor) const {
        MVector!float local = (characterState.position.local.inverse() * floor).vec;
        float[3] direction = local.xyz();
        float length = direction.magnitude;
        float[3] toFloor = direction.scaled(acoshf(local.data[3]) / length);
        float[3] fromFeet = toFloor.plus(characterState.up.scaled(bodyExtent().value));
        return RouteWaypoint(yawToward(toFloor), Length(fromFeet.rejectAlong(characterState.up).magnitude), Length(fromFeet.dot(characterState.up)), true);
    }

    void placeAt(Position target, Length lift) {
        world.graph.ensureNodeState(target.node);
        float[3] up = world.graph.upAt(target);
        Position lifted = world.graph.ensureNormalized(Position(target.node, (target.local * MIsometry!float.fromDisplacement(up.scaled(lift.value))).renormalized()));
        world.graph.ensureNodeState(lifted.node);
        characterState = CharacterState(lifted, ZERO_VECTOR, characterState.groundNormal, world.graph.upAt(lifted), false);
        resetView();
    }

    void setWorldgen(Worldgen worldgen) {
        rebuildWorld(worldgen);
        placeAtSpawn();
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
        if (placement.isFound && !isBodyOverlapping(ChunkSlot(world.graph.slotOf(placement.chunk.node), placement.chunk.vertex), placement)) {
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
        MIsometry!float eye = MIsometry!float.fromDisplacement(characterState.up.scaled(camera.eyeOffset.value));
        camera.follow(characterState.position, eye, characterState.up);
        camera.levelRoll();
        camera.holdPitch();
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
        float[3] right = camera.orientation.rotate([1, 0, 0]).rejectAlong(characterState.up);
        float[3] back = camera.orientation.rotate([0, 0, 1]).rejectAlong(characterState.up);
        return right.scaled(moveX / right.magnitude).plus(back.scaled(moveZ / back.magnitude));
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
