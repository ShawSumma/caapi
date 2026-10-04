module client.game;

import core.stdc.math : fabsf, tanhf;
import client.camera : Camera;
import client.streaming : generateNow;
import client.world : LocalWorld, Placement;
import common.array : Array;
import common.character.controller : CharacterInput, CharacterState, MovementMode, Mover, Slide, relativeUp;
import common.collision.graph : Capsule, isCapsuleOverlappingVoxel;
import common.material : Material;
import common.math : MPoint;
import common.node : ChunkSlot;
import common.position : Position;
import common.settings : SimConfig, SimMeters;
import common.vector3 : ZERO_VECTOR;
import common.worldgen.generation : NodeState;
import common.worldgen.spawn : clearSpawnPosition, collectChunksNear;

enum uint MODE_COUNT = MovementMode.max + 1;

immutable string[MODE_COUNT] MODE_NAMES = [
    "walk",
    "fly",
    "noclip",
];

immutable Material[9] MATERIAL_PALETTE = [
    Material.woodPlanks,
    Material.wood,
    Material.leaves,
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

immutable string[KEY_COUNT] KEY_NAMES = [
    "fwd",
    "back",
    "left",
    "right",
    "up",
    "down",
    "yaw_left",
    "yaw_right",
    "pitch_up",
    "pitch_down",
];

struct KeyLookup {
    Key key;
    bool isFound;

    static KeyLookup fromName(const(char)[] name) {
        if (name == "jump") {
            return KeyLookup(Key.up, true);
        } else {
            uint key = 0;
            while (key < KEY_COUNT && KEY_NAMES[key] != name) {
                key += 1;
            }
            if (key < KEY_COUNT) {
                return KeyLookup(cast(Key) key, true);
            } else {
                return KeyLookup(Key.init, false);
            }
        }
    }
}

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

struct Game {
    LocalWorld world;
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
    bool isSettlingWorldgenEachFrame;
    bool hasCameraVerticalVelocity;

    static Game make(bool isFlat, float reachMeters) {
        SimMeters meters;
        SimConfig simConfig = SimConfig.fromMeters(meters);
        Game game;
        game.simConfig = simConfig;
        game.world = LocalWorld.make(meters.chunkSize, isFlat, tanhf(reachMeters * simConfig.metersToAbsolute));
        game.camera = Camera.make(simConfig.character.eyeOffset);
        game.placeAtSpawn();
        return game;
    }

    void placeAtSpawn() {
        bool isFlat = world.streamer.isFlat;
        float bodyReach = simConfig.character.characterHalfHeight + simConfig.character.characterRadius + simConfig.character.contactSkin;
        Position position = world.graph.clearSpawnPosition(isFlat, bodyReach);
        Slide drop;
        while (!drop.hasLanded) {
            Array!ChunkSlot chunks = world.graph.collectChunksNear(position, 2.0f * bodyReach);
            foreach (chunk; chunks.slice()) {
                world.graph.generateNow(chunk, isFlat);
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
        world.cameraPosition = camera.orientedPosition();
        cameraAltitude = characterAltitude() + camera.eyeOffset;
        hasCameraVerticalVelocity = false;
    }

    void setWorldgen(bool isFlat) {
        ubyte dimension = world.graph.layout.dimension;
        float reach = world.reach;
        uint epoch = world.epoch;
        world.release();
        world = LocalWorld.make(dimension, isFlat, reach);
        world.epoch = epoch + 1;
        placeAtSpawn();
    }

    void release() {
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
        traveled += characterState.runStep(simConfig, world.graph, characterInput(moveX, moveY, moveZ, input.isHeld[Key.up]), dt);
        world.graph.ensureNodeState(characterState.position.node);
        float altitude = characterAltitude();
        camera.smoothEyeVertical(groundedRise(wasOnGround, altitude - altitudeBefore), simConfig.character.stepHeight, dt);
        camera.updatePosition(characterState.position, world.graph.relativeUp(characterState.position));
        camera.alignToGravity();
        world.cameraPosition = camera.orientedPosition();
        trackCameraAcceleration(altitude + camera.eyeOffset - camera.eyeLag, dt);
        world.update(isSettlingWorldgenEachFrame);
        if (isSettlingWorldgenEachFrame) {
            world.streamer.settle(world.graph);
        }
        simTime += dt;
    }

    CharacterInput characterInput(float moveX, float moveY, float moveZ, bool isUpHeld) const {
        if (mode == MovementMode.noclip) {
            return CharacterInput(camera.viewOrientation().rotate([moveX, moveY, moveZ]), mode, false);
        } else if (mode == MovementMode.fly) {
            return CharacterInput(camera.orientation.rotate([moveX, moveY, moveZ]), mode, false);
        } else {
            return CharacterInput(camera.orientation.rotate([moveX, 0, moveZ]), mode, isUpHeld);
        }
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

    bool setMode(const(char)[] name) {
        uint index = 0;
        while (index < MODE_COUNT && MODE_NAMES[index] != name) {
            index += 1;
        }
        if (index < MODE_COUNT) {
            mode = cast(MovementMode) index;
            return true;
        } else {
            return false;
        }
    }

    void toggleMode(MovementMode toggled) {
        if (mode == toggled) {
            mode = MovementMode.fly;
        } else {
            mode = toggled;
        }
    }

    const(char)* modeName() const {
        return MODE_NAMES[mode].ptr;
    }
}
