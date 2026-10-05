module client.game;

import core.stdc.math : atan2f, ceilf, fabsf, tanhf;
import client.camera : Camera;
import client.streaming : generateNow;
import client.world : LocalWorld, Placement;
import common.array : Array;
import common.character.controller : CharacterInput, CharacterState, MovementMode, Mover, Slide, relativeUp;
import common.character.frame : BodyFrame, UpMode;
import common.collision.graph : Capsule, isCapsuleOverlappingVoxel;
import common.dodeca : Side, faceDirection, faceDistance;
import common.graph : NodeId;
import common.material : Material;
import common.math : MIsometry, MPoint;
import common.node : ChunkSlot, GridSpacing;
import common.position : Position;
import common.settings : SimConfig, SimMeters;
import common.traversal : NearbyNode, NearbyScratch;
import common.vector3 : ZERO_VECTOR, cross, dot, magnitude, negated, rejectAlong, scaled;
import common.worldgen.building : Building;
import common.worldgen.generation : NodeState, Worldgen, WorldgenKind, stairLimits;
import common.worldgen.spawn : clearSpawnPosition, collectChunksNear;

enum float STRUCTURE_SEARCH_RADIUS = 4.0f;
enum float STAIR_SEARCH_RADIUS = 2.0f;

immutable float[3] CAMERA_FORWARD = [0, 0, -1];

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
    float yaw = 0;
    float pitch = 0;
    bool[KEY_COUNT] isHeld;
}

float axisValue(bool isHeld) {
    if (isHeld) {
        return 1.0f;
    } else {
        return 0.0f;
    }
}

struct StairWaypoint {
    float yawRadians = 0;
    float horizontal = 0;
    float rise = 0;
    bool isFound;
}

struct Game {
    LocalWorld world;
    Array!(MPoint!float) stairRoute;
    Camera camera;
    CharacterState characterState;
    SimConfig simConfig;
    float simTime = 0;
    float traveled = 0;
    float cameraVerticalAcceleration = 0;
    float cameraAltitude = 0;
    float cameraVerticalVelocity = 0;
    uint materialIndex;
    MovementMode mode = MovementMode.walk;
    UpMode upMode;
    bool isSettlingWorldgenEachFrame;
    bool hasCameraVerticalVelocity;

    static Game make(Worldgen worldgen, float reachMeters) {
        SimMeters meters;
        SimConfig simConfig = SimConfig.fromMeters(meters);
        Game game;
        game.simConfig = simConfig;
        game.world = LocalWorld.make(meters.chunkSize, worldgen, tanhf(reachMeters * simConfig.metersToAbsolute));
        game.camera = Camera.make(simConfig.character.eyeOffset);
        game.placeAtSpawn();
        return game;
    }

    void placeAtSpawn() {
        float bodyReach = simConfig.character.characterHalfHeight + simConfig.character.characterRadius + simConfig.character.contactSkin;
        Position position = world.graph.clearSpawnPosition(bodyReach);
        Slide drop;
        while (!drop.hasLanded) {
            Array!ChunkSlot chunks = world.graph.collectChunksNear(position, 2.0f * bodyReach);
            foreach (chunk; chunks.slice()) {
                world.graph.generateNow(chunk);
            }
            chunks.release();
            Mover mover = Mover.make(simConfig.character, world.graph, world.graph.relativeUp(position));
            drop = mover.settle(position, bodyReach);
            position = world.graph.normalized(Position(drop.position.node, drop.position.local.renormalized()));
            world.graph.ensureNodeState(position.node);
        }
        characterState = CharacterState(position, ZERO_VECTOR, drop.groundNormal, true);
        camera.updatePosition(position, world.graph.relativeUp(position));
        camera.alignToGravity();
        if (world.graph.worldgen.kind == WorldgenKind.structure) {
            camera.lookLevel(yawToward(directionToNode(world.graph.worldgen.structure.base)), 0);
        } else if (world.graph.worldgen.groundTiltRadians() != 0) {
            camera.lookLevel(yawToward(uphillDirection()), 0);
        }
        world.cameraPosition = camera.orientedPosition();
        cameraAltitude = characterAltitude() + camera.eyeOffset;
        hasCameraVerticalVelocity = false;
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

    float[3] directionToNode(NodeId node) {
        return (characterState.position.local.inverse() * nodeTransform(node, STRUCTURE_SEARCH_RADIUS) * MPoint!float.origin()).vec.xyz();
    }

    float[3] uphillDirection() const {
        const(NodeState)* state = world.graph.nodeState(characterState.position.node);
        return (characterState.position.local.inverse() * state.reference.scaledNormal).xyz().negated;
    }

    float yawToward(float[3] direction) const {
        float[3] forward = camera.orientation.rotate(CAMERA_FORWARD).rejectAlong(camera.up);
        float[3] level = direction.rejectAlong(camera.up);
        return atan2f(camera.up.dot(forward.cross(level)), forward.dot(level));
    }

    void enterStructure(float metersUp) {
        float[3] up = Side.a.faceDirection.negated;
        float rise = metersUp * simConfig.metersToAbsolute - faceDistance();
        uint stepCount = cast(uint) ceilf(fabsf(rise) / faceDistance());
        Position target = Position(world.graph.worldgen.structure.base, MIsometry!float.identity());
        foreach (_; 0 .. stepCount) {
            target = world.graph.ensureNormalized(Position(target.node, (target.local * MIsometry!float.fromDisplacement(up.scaled(rise / stepCount))).renormalized()));
        }
        placeAt(target);
    }

    bool enterStairs() {
        uint base = world.graph.slotOf(world.graph.worldgen.structure.base);
        Building building = Building.make(world.graph.ensureStructureAt(base), world.graph.nodeAt(base).state.surface, world.graph.layout, stairLimits());
        stairRoute.clear();
        foreach (cell; building.route.slice()) {
            stairRoute.append(building.shape.cellCenter(cell));
        }
        if (building.route.length > 0) {
            MPoint!float start = building.shape.cellCenter(building.route.ptr[0]);
            Position center = world.graph.ensureNormalized(Position(world.graph.worldgen.structure.base, MIsometry!float.fromTranslation(MPoint!float.origin(), start)));
            placeAt(center);
            float lift = simConfig.character.characterHalfHeight + simConfig.character.contactSkin - characterAltitude();
            placeAt(world.graph.ensureNormalized(Position(center.node, (center.local * MIsometry!float.fromDisplacement(world.graph.relativeUp(center).scaled(lift))).renormalized())));
        }
        building.release();
        return stairRoute.length > 0;
    }

    StairWaypoint stairWaypoint(size_t index) {
        if (index < stairRoute.length) {
            MIsometry!float toBase = nodeTransform(world.graph.worldgen.structure.base, STAIR_SEARCH_RADIUS);
            float[3] offset = (characterState.position.local.inverse() * toBase * stairRoute.ptr[index]).vec.xyz();
            return StairWaypoint(yawToward(offset), offset.rejectAlong(camera.up).magnitude, offset.dot(camera.up), true);
        } else {
            return StairWaypoint.init;
        }
    }

    void placeAt(Position target) {
        world.graph.ensureNodeState(target.node);
        characterState = CharacterState(target, ZERO_VECTOR, characterState.groundNormal, false);
        camera = Camera.make(simConfig.character.eyeOffset);
        camera.updatePosition(target, world.graph.relativeUp(target));
        camera.alignToGravity();
        world.cameraPosition = camera.orientedPosition();
        cameraAltitude = characterAltitude() + camera.eyeOffset;
        hasCameraVerticalVelocity = false;
    }

    void cycleSpacing() {
        Worldgen worldgen = world.graph.worldgen;
        worldgen.spacing = cast(GridSpacing)((worldgen.spacing + 1) % (GridSpacing.max + 1));
        setWorldgen(worldgen);
    }

    void setWorldgen(Worldgen worldgen) {
        ubyte dimension = world.graph.layout.dimension;
        float reach = world.reach;
        uint epoch = world.epoch;
        world.release();
        stairRoute.clear();
        world = LocalWorld.make(dimension, worldgen, reach);
        world.epoch = epoch + 1;
        placeAtSpawn();
    }

    void release() {
        stairRoute.release();
        world.release();
    }

    bool breakBlock() {
        return world.breakBlock();
    }

    bool placeBlock() {
        Placement placement = world.placementTarget();
        Capsule capsule = Capsule(camera.up, simConfig.character.characterRadius, simConfig.character.characterHalfHeight, simConfig.character.contactSkin);
        if (placement.isFound && !world.graph.isCapsuleOverlappingVoxel(capsule, characterState.position, placement.chunk, placement.coords)) {
            return world.setVoxel(placement.chunk, placement.coords, MATERIAL_PALETTE[materialIndex]);
        } else {
            return false;
        }
    }

    void look(float yaw, float pitch) {
        camera.lookLevel(-yaw, -pitch);
        world.cameraPosition = camera.orientedPosition();
    }

    float characterAltitude() const {
        const(NodeState)* state = world.graph.nodeState(characterState.position.node);
        return state.surface.distanceTo(characterState.position.local * MPoint!float.origin());
    }

    void step(FrameInput input, float dt) {
        look(input.yaw, input.pitch);
        float moveX = axisValue(input.isHeld[Key.right]) - axisValue(input.isHeld[Key.left]);
        float moveY = axisValue(input.isHeld[Key.up]) - axisValue(input.isHeld[Key.down]);
        float moveZ = axisValue(input.isHeld[Key.back]) - axisValue(input.isHeld[Key.fwd]);
        float altitudeBefore = characterAltitude();
        bool wasOnGround = characterState.isOnGround;
        traveled += characterState.runStep(simConfig, world.graph, characterInput(moveX, moveY, moveZ, input.isHeld[Key.up], input.isHeld[Key.down]), dt);
        world.graph.ensureNodeState(characterState.position.node);
        BodyFrame frame = characterState.frameAt(simConfig.character, world.graph, upMode);
        float altitude = characterAltitude();
        camera.smoothEyeVertical(groundedRise(wasOnGround, altitude - altitudeBefore), simConfig.character.stepHeight, dt);
        camera.updatePosition(characterState.position, frame.viewUp);
        camera.alignToGravity();
        world.cameraPosition = camera.orientedPosition();
        trackCameraAcceleration(altitude + camera.eyeOffset - camera.eyeLag, dt);
        world.update(isSettlingWorldgenEachFrame);
        if (isSettlingWorldgenEachFrame) {
            world.streamer.settle(world.graph);
        }
        simTime += dt;
    }

    CharacterInput characterInput(float moveX, float moveY, float moveZ, bool isUpHeld, bool isDownHeld) const {
        if (mode == MovementMode.noclip) {
            return CharacterInput(camera.viewOrientation().rotate([moveX, moveY, moveZ]), mode, upMode, false, false);
        } else if (mode == MovementMode.fly) {
            return CharacterInput(camera.orientation.rotate([moveX, moveY, moveZ]), mode, upMode, false, false);
        } else {
            return CharacterInput(camera.orientation.rotate([moveX, 0, moveZ]), mode, upMode, isUpHeld, isDownHeld);
        }
    }

    void cycleUpMode() {
        upMode = cast(UpMode)((upMode + 1) % (UpMode.max + 1));
    }

    float groundedRise(bool wasOnGround, float rise) const {
        if (wasOnGround && characterState.isOnGround) {
            return rise;
        } else {
            return 0;
        }
    }

    void trackCameraAcceleration(float newCameraAltitude, float dt) {
        float verticalVelocity = (newCameraAltitude - cameraAltitude) / dt;
        if (hasCameraVerticalVelocity) {
            cameraVerticalAcceleration = fabsf((verticalVelocity - cameraVerticalVelocity) / dt);
        } else {
            cameraVerticalAcceleration = 0;
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
