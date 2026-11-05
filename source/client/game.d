module client.game;

import core.stdc.math : acoshf, atan2f, atanhf, ceilf, coshf, fabs, fabsf, floorf, sinhf, sqrt, tanhf;
import base.array : Array;
import base.flags : Readiness;
import base.maybe : Maybe, MaybeIndex;
import base.numbers : higherOf;
import base.units : Acceleration, Angle, AngularSpeed, Length, Speed, Time;
import base.vector3 : Vec3, ZERO_VECTOR, cross, dot, magnitude, minus, negated, plus, rejectAlong, scaled;
import client.arrivals : generateNow;
import client.camera : CAMERA_FORWARD, Camera;
import client.config : ClientConfig, pitchSign;
import client.streaming : Pacing;
import client.world : LocalWorld, Placement;
import common.character.controller : CharacterInput, CharacterState, Footing, Jump, MovementMode, Mover, Slide, Stepped, movedBy, perpendicularTo, regionReach;
import common.character.features : CellOverlap, CellRange, Features, LocalFrame, RequiredChunks, gridPoint, isInsideGrid, visitCells;
import common.character.sweep : Capsule, sectionCenters;
import common.graph : Graph, NodeId;
import common.node : ChunkSlot, ChunkState, cellIndex;
import common.position : Position;
import common.settings : CHUNK_DIMENSION, CharacterConfig;
import common.traversal : NearbyNode, NearbyScratch;
import common.worldgen.blueprint : RouteStop;
import common.worldgen.generation : NodeState, Worldgen;
import common.worldgen.horospheres : Gravity, ensureGravityAt, gravityAt, isGravityKnown;
import common.worldgen.spawn : collectChunksNear, findSpawnPosition;
import common.worldgen.structure : SiteFrame, columnPoint, edgeLength, forwarded, moveToLevel, rootSite, sitePlacement, siteToNode, spawnBefore, turnSite;
import geometry.honeycomb : CORNER_COUNT, Corner, Face, cornerToNode, nodeToCorner;
import geometry.lorentz : Motion, Point, Vec4;
import plugins.api.api : Material, Turn;
import plugins.api.flags : Flags;

enum uint MAX_BODY_SECTIONS = 64;
enum float SUN_ELEVATION_COSINE = 0.82f;
enum float SUN_ELEVATION_SINE = 0.57f;
enum size_t MOST_THROWN = 8;
enum uint TRAIL_POINTS = 48;
enum float TRAIL_EVERY_SECONDS = 0.05f;
enum float THROW_SPEED = 1.4f;
enum float THROW_LIFT = 0.5f;
enum float THROWN_SECONDS = 20;
enum float THROWN_STEP = 0.02f;
enum float LEAST_COMPASS_LENGTH = 1e-3f;
enum double MAX_STEP_SECONDS = 0.1;

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

enum KeyStroke : ubyte {
    first,
    repeated,
}

enum Command : ubyte {
    walkMode,
    noclipMode,
    previousWorld,
    nextWorld,
    throwBlock,
}

struct KeyBinding(Symbol) {
    Symbol symbol;
    Key key;
}

struct CommandBinding(Symbol) {
    Symbol symbol;
    Command command;
}

Maybe!Command commandOf(Symbol)(const(CommandBinding!Symbol)[] bindings, Symbol symbol, KeyStroke press) {
    Maybe!Command found;
    if (press == KeyStroke.first) {
        foreach (binding; bindings) {
            if (binding.symbol == symbol) {
                found = Maybe!Command.of(binding.command);
            }
        }
    }
    return found;
}

void holdBound(Symbol)(ref Flags!Key held, const(KeyBinding!Symbol)[] bindings, Symbol symbol) {
    foreach (binding; bindings) {
        if (binding.symbol == symbol) {
            held.set(binding.key);
        }
    }
}

void letGoBound(Symbol)(ref Flags!Key held, const(KeyBinding!Symbol)[] bindings, Symbol symbol) {
    foreach (binding; bindings) {
        if (binding.symbol == symbol) {
            held.clear(binding.key);
        }
    }
}

enum ChunkSupply : ubyte {
    streamed,
    onDemand,
}

struct FrameInput {
    Angle yaw;
    Angle pitch;
    Flags!Key held;
}

float axisValue(Flags!Key held, Key key) {
    if (held.has(key)) {
        return 1.0f;
    } else {
        return 0.0f;
    }
}

FrameInput frameInputOf(ref const ClientConfig config, Flags!Key held, double mouseDx, double mouseDy, Time dt) {
    AngularSpeed yawRate = config.keyTurnRate * (axisValue(held, Key.yawRight) - axisValue(held, Key.yawLeft));
    AngularSpeed pitchRate = config.keyTurnRate * (axisValue(held, Key.pitchDown) - axisValue(held, Key.pitchUp));
    Angle yaw = yawRate * dt + config.mouseTurnPerCount * cast(float) mouseDx;
    Angle pitch = pitchRate * dt + config.mouseTurnPerCount * cast(float) mouseDy * pitchSign(config.pitchAxis);
    return FrameInput(yaw, pitch, held);
}

bool chooseMaterial(ref Game game, uint index) {
    bool changed = index < MATERIAL_PALETTE.length && index != game.materialIndex;
    if (changed) {
        game.materialIndex = index;
    }
    return changed;
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

struct SolidProbe {
    uint solidCells;

    void visitMissingNode(uint, Face) {
    }

    void visitChunk(ref const Graph graph, LocalFrame frame, ChunkSlot slot, CellRange) {
        Vec3!float grid = gridPoint(graph.layout, slot.corner.nodeToCorner * frame.toBody.inverse());
        if (isInsideGrid(grid, graph.layout.dimension) && graph.chunks.at(slot).state == ChunkState.populated) {
            size_t cell = cellIndex(graph.layout.dimension, cast(int) floorf(grid.x), cast(int) floorf(grid.y), cast(int) floorf(grid.z));
            if (graph.chunks.at(slot).voxels.at(cell) != Material.none) {
                solidCells += 1;
            }
        }
    }
}

enum ThrownMotion : ubyte {
    flying,
    resting,
    gone,
}

struct Thrown {
    Position position;
    Vec3!float velocity;
    Position[TRAIL_POINTS] trail;
    uint trailCount;
    float untilTrail = 0;
    float age = 0;
    ThrownMotion motion;

    void remember() {
        trail[trailCount % TRAIL_POINTS] = position;
        trailCount += 1;
        untilTrail = TRAIL_EVERY_SECONDS;
    }

    void advance(ref const Graph graph, float gravity, Time dt) {
        age += dt.value;
        if (age > THROWN_SECONDS || !graph.slotOf(position.node).exists) {
            motion = ThrownMotion.gone;
        } else if (motion == ThrownMotion.flying) {
            untilTrail -= dt.value;
            if (untilTrail <= 0) {
                remember();
            }
            fly(graph, gravity, dt);
        }
    }

    void fly(ref const Graph graph, float gravity, Time dt) {
        uint substeps = higherOf(cast(uint) ceilf(velocity.magnitude * dt.value / THROWN_STEP), 1u);
        float each = dt.value / substeps;
        foreach (_; 0 .. substeps) {
            MaybeIndex!uint slot = graph.slotOf(position.node);
            if (!slot.exists) {
                motion = ThrownMotion.gone;
                return;
            } else if (graph.isGravityKnown(slot.value)) {
                Gravity pull = graph.gravityAt(position);
                velocity = velocity.minus(pull.up.scaled(pull.strength * gravity * each));
            }
            Position next = graph.movedBy(position, velocity.scaled(each));
            SolidProbe probe;
            visitCells(graph, next, Length(0), probe);
            if (probe.solidCells > 0) {
                motion = ThrownMotion.resting;
                return;
            }
            position = next;
        }
    }
}

struct RouteWaypoint {
    Angle yaw;
    Length horizontal;
    Length rise;
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
    Array!Thrown thrown;
    Vec3!float compass = Vec3!float(0, 0, -1);
    uint materialIndex;
    MovementMode mode = MovementMode.walk;
    ChunkSupply supply;
    Readiness cameraVelocity;
    Flags!Key lastHeld;

    static Game make(Worldgen worldgen, Length reach) {
        Game game;
        game.world = LocalWorld.make(CHUNK_DIMENSION, worldgen, tanhf(reach.value));
        game.world.graph.bindView();
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
        do {
            required.clear();
            visitCells(world.graph, position, reach, required);
            foreach (missing; required.missing.slice()) {
                world.graph.ensureNeighborSlot(missing.slot, missing.side);
            }
            foreach (chunk; required.chunks.slice()) {
                world.graph.generateNow(chunk);
            }
        } while (required.missing.length > 0);
        required.release();
    }

    void placeAtSpawn() {
        Maybe!RouteStop entrance = world.graph.structures.blueprint.entrance;
        if (entrance.exists) {
            placeAt(ensureSitePosition(entrance.value.site, spawnBefore(world.graph.layout, entrance.value.spot)), bodyExtent() + character.skin);
        } else {
            Position spawn = world.graph.findSpawnPosition(bodyReach().value);
            Vec3!float up = world.graph.ensureGravityAt(spawn).up;
            characterState = CharacterState(spawn, ZERO_VECTOR, Vec3!float(0, 1, 0), up, up);
        }
        settleToGround();
        resetView();
        if (world.graph.structures.blueprint.entrance.exists) {
            camera.turn(yawToward(directionToDoor()), Angle(0));
        } else if (world.graph.worldgen.groundTiltRadians() != 0) {
            camera.turn(yawToward(uphillDirection()), Angle(0));
        }
        updateView();
        resetCompass();
        world.settleFogColor();
    }

    void resetCompass() {
        Vec3!float level = camera.heading.rotate(CAMERA_FORWARD).rejectAlong(characterState.up);
        compass = level.scaled(1.0f / level.magnitude);
    }

    void levelCompass() {
        Vec3!float level = compass.rejectAlong(characterState.up);
        float length = level.magnitude;
        if (length > LEAST_COMPASS_LENGTH) {
            compass = level.scaled(1.0f / length);
        }
    }

    Angle compassOff() const {
        return yawToward(compass);
    }

    void throwBlock() {
        if (thrown.length == MOST_THROWN) {
            foreach (index; 1 .. thrown.length) {
                thrown.ptr[index - 1] = thrown.ptr[index];
            }
            thrown.length -= 1;
        }
        Thrown made;
        made.position = world.cameraPosition;
        made.velocity = CAMERA_FORWARD.scaled(THROW_SPEED).plus(Vec3!float(0, THROW_LIFT, 0));
        made.remember();
        thrown.append(made);
    }

    void stepThrown(Time dt) {
        size_t index = 0;
        while (index < thrown.length) {
            thrown.ptr[index].advance(world.graph, character.gravity.value, dt);
            if (thrown.ptr[index].motion == ThrownMotion.gone) {
                foreach (later; index + 1 .. thrown.length) {
                    thrown.ptr[later - 1] = thrown.ptr[later];
                }
                thrown.length -= 1;
            } else {
                index += 1;
            }
        }
    }

    void settleToGround() {
        Length reach = regionReach(character) + bodyReach();
        Features features;
        Slide drop;
        while (!drop.hasLanded) {
            generateAround(characterState.position, reach);
            characterState.up = world.graph.ensureGravityAt(characterState.position).up;
            characterState.pull = characterState.up;
            features.collect(world.graph, characterState.position, reach);
            drop = Mover.make(character, features, characterState.up, Length(0)).settle(ZERO_VECTOR, bodyReach());
            characterState.position = world.graph.movedBy(characterState.position, drop.position);
        }
        features.release();
        characterState.groundNormal = drop.groundNormal;
        characterState.footing = Footing.grounded;
    }

    void resetView() {
        camera = Camera.make(character.eyeOffset);
        altitude = ensureAltitude();
        followBody();
        updateView();
        cameraAltitude = altitude + camera.eyeOffset;
        cameraVelocity = Readiness.pending;
    }

    Length ensureAltitude() {
        Position position = characterState.position;
        return Length(world.graph.horospheres.gravitySign() * world.graph.ensureState(world.graph.slotOf(position.node).value).surface.distanceTo(position.local * Point!float.origin()));
    }

    Vec3!float directionToDoor() const {
        RouteStop entrance = world.graph.structures.blueprint.entrance.value;
        Motion!float siteToBody = characterState.position.local.inverse() * world.graph.ownView.siteToNode(entrance.site, world.graph.slotOf(characterState.position.node).value);
        return (siteToBody * columnPoint(world.graph.layout, entrance.spot)).v.spatial();
    }

    Vec3!float uphillDirection() const {
        return world.graph.stateAt(world.graph.slotOf(characterState.position.node).value).reference.upAt(characterState.position.local).negated;
    }

    Angle yawToward(Vec3!float direction) const {
        Vec3!float forward = camera.heading.rotate(CAMERA_FORWARD);
        Vec3!float level = direction.rejectAlong(camera.viewUp);
        return Angle(atan2f(camera.viewUp.dot(forward.cross(level)), forward.dot(level)));
    }

    void enterStructure(Length height) {
        float edge = edgeLength(world.graph.layout).value;
        float edges = floorf(height.value / edge);
        float rest = height.value - edges * edge;
        SiteFrame tower = world.graph.view.turnSite(rootSite(world.graph.anchorSlot), Turn.pitchUp);
        SiteFrame at = world.graph.view.moveToLevel(forwarded(tower, cast(int) edges), 0);
        placeAt(ensureSitePosition(at, Point!float(Vec4!float([0, 0, sinhf(rest), coshf(rest)]))), Length(0));
    }

    Position ensureSitePosition(SiteFrame site, Point!float inSite) {
        Point!float point = sitePlacement(site, world.graph.layout) * inSite;
        return world.graph.ensureNormalized(Position(world.graph.idAt(site.node), Motion!float.shiftTo(point)));
    }

    void enterRoute(size_t index) {
        RouteStop stop = world.graph.structures.blueprint.route.ptr[index];
        placeAt(ensureSitePosition(stop.site, columnPoint(world.graph.layout, stop.spot)), bodyExtent() + character.skin);
    }

    Maybe!RouteWaypoint routeWaypoint(size_t index) const {
        if (index >= world.graph.structures.blueprint.route.length) {
            return Maybe!RouteWaypoint.init;
        } else {
            RouteStop stop = world.graph.structures.blueprint.route.ptr[index];
            Motion!float siteToBody = world.graph.ownView.siteToNode(stop.site, world.graph.slotOf(characterState.position.node).value);
            return Maybe!RouteWaypoint.of(waypointAt(siteToBody * columnPoint(world.graph.layout, stop.spot)));
        }
    }

    RouteWaypoint waypointAt(Point!float floor) const {
        Vec4!float local = (characterState.position.local.inverse() * floor).v;
        Vec3!float direction = local.spatial();
        float length = direction.magnitude;
        Vec3!float toFloor = direction.scaled(acoshf(local.c[3]) / length);
        Vec3!float fromFeet = toFloor.plus(characterState.up.scaled(bodyExtent().value));
        return RouteWaypoint(yawToward(toFloor), Length(fromFeet.rejectAlong(characterState.up).magnitude), Length(fromFeet.dot(characterState.up)));
    }

    void placeAt(Position target, Length lift) {
        Vec3!float up = world.graph.ensureGravityAt(target).up;
        Position lifted = world.graph.ensureNormalized(Position(target.node, (target.local * Motion!float.shift(up.scaled(lift.value))).orthonormalized()));
        Vec3!float liftedUp = world.graph.ensureGravityAt(lifted).up;
        characterState = CharacterState(lifted, ZERO_VECTOR, characterState.groundNormal, liftedUp, liftedUp);
        resetView();
        resetCompass();
    }

    void rebuildWorld(Worldgen worldgen) {
        ubyte dimension = world.graph.layout.dimension;
        float tanhReach = world.tanhReach;
        float renderRadius = world.renderRadius;
        uint epoch = world.epoch;
        thrown.clear();
        world.release();
        world = LocalWorld.make(dimension, worldgen, tanhReach);
        world.graph.bindView();
        world.renderRadius = renderRadius;
        world.epoch = epoch + 1;
    }

    void release() {
        thrown.release();
        world.release();
    }

    bool breakBlock() {
        return world.breakBlock();
    }

    bool placeBlock() {
        Maybe!Placement placement = world.placementTarget();
        if (placement.exists && !isBodyOverlapping(ChunkSlot(world.graph.slotOf(placement.value.chunk.node).value, placement.value.chunk.corner), placement.value)) {
            return world.setVoxel(placement.value.chunk, placement.value.coords, MATERIAL_PALETTE[materialIndex]);
        } else {
            return false;
        }
    }

    bool isBodyOverlapping(ChunkSlot slot, Placement placement) const {
        Vec3!float[MAX_BODY_SECTIONS] storage;
        CellOverlap overlap = CellOverlap(sectionCenters(bodyCapsule(), ZERO_VECTOR, storage[]), slot, placement.coords, character.radius.value);
        visitCells(world.graph, characterState.position, regionReach(character), overlap);
        return overlap.overlaps > 0;
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
        world.sunward = camera.orientation.inverted().rotate(sunInBody());
    }

    Vec3!float sunInBody() const {
        Vec3!float up = characterState.up;
        Vec3!float side = perpendicularTo(up).rejectAlong(up);
        return up.scaled(SUN_ELEVATION_COSINE).plus(side.scaled(SUN_ELEVATION_SINE / side.magnitude));
    }

    void step(FrameInput input, Time dt) {
        look(input.yaw, input.pitch);
        float moveX = axisValue(input.held, Key.right) - axisValue(input.held, Key.left);
        float moveY = axisValue(input.held, Key.up) - axisValue(input.held, Key.down);
        float moveZ = axisValue(input.held, Key.back) - axisValue(input.held, Key.fwd);
        Stepped stepped = runCharacter(characterInput(moveX, moveY, moveZ, jumpFrom(input.held)), dt);
        lastHeld = input.held;
        traveled = traveled + stepped.traveled;
        altitude = ensureAltitude();
        followBody();
        levelCompass();
        updateView();
        stepThrown(dt);
        world.approachFogColor(dt.value);
        trackCameraAcceleration(altitude + camera.eyeOffset, dt);
        if (supply == ChunkSupply.streamed) {
            world.update(Pacing.budgeted);
        }
        time = time + dt;
    }

    Length probeFrameDrift(Length radius) {
        NearbyScratch scratch;
        NearbyNode[] fresh = scratch.collectAll(world.graph, world.cameraPosition, radius.value);
        const(NearbyScratch)* drawn = &world.nearby[world.published];
        Motion!float fromFrame = world.cameraInNearbyFrame().inverse();
        Motion!float fromNode = world.cameraPosition.local.inverse();
        double most = 0;
        foreach (node; fresh) {
            MaybeIndex!uint index = drawn.indexOf(node.slot);
            if (index.exists) {
                Motion!float drawnToCamera = fromFrame * drawn.nodes.ptr[index.value].transform;
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
        uint unloaded = features.unloaded;
        features.release();
        return unloaded == 0;
    }

    Stepped runCharacter(CharacterInput input, Time dt) {
        if (supply == ChunkSupply.onDemand) {
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

    Jump jumpFrom(Flags!Key held) const {
        if (held.has(Key.up) && !lastHeld.has(Key.up)) {
            return Jump.pressed;
        } else {
            return Jump.none;
        }
    }

    CharacterInput characterInput(float moveX, float moveY, float moveZ, Jump jump) const {
        if (mode == MovementMode.noclip) {
            return CharacterInput(camera.orientation.rotate(Vec3!float(moveX, moveY, moveZ)), mode);
        } else if (mode == MovementMode.fly) {
            return CharacterInput(levelMove(moveX, moveZ).plus(characterState.up.scaled(moveY)), mode);
        } else {
            return CharacterInput(levelMove(moveX, moveZ), mode, jump);
        }
    }

    Vec3!float levelMove(float moveX, float moveZ) const {
        return camera.heading.rotate(Vec3!float(1, 0, 0)).scaled(moveX).plus(camera.heading.rotate(Vec3!float(0, 0, 1)).scaled(moveZ));
    }

    void trackCameraAcceleration(Length newCameraAltitude, Time dt) {
        Speed verticalVelocity = (newCameraAltitude - cameraAltitude) / dt;
        if (cameraVelocity == Readiness.ready) {
            cameraVerticalAcceleration = Acceleration(fabsf(((verticalVelocity - cameraVerticalVelocity) / dt).value));
        } else {
            cameraVerticalAcceleration = Acceleration(0);
        }
        cameraAltitude = newCameraAltitude;
        cameraVerticalVelocity = verticalVelocity;
        cameraVelocity = Readiness.ready;
    }

    void toggleMode(MovementMode toggled) {
        if (mode == toggled) {
            mode = MovementMode.fly;
        } else {
            mode = toggled;
        }
    }
}
