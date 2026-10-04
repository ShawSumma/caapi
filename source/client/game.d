module client.game;

import core.stdc.math : fabsf, tanhf;
import client.local_character_controller : LocalCharacterController;
import client.local_world : LocalWorld, Placement;
import client.worldgen_driver : generateNow;
import common.array : Array;
import common.character_controller.controller : CharacterState, Mover, Slide, relativeUp;
import common.graph : Graph;
import common.graph_collision : Capsule, isCapsuleOverlappingVoxel;
import common.math : MPoint;
import common.node : ChunkSlot;
import common.proto : CharacterInput, MovementMode, Position;
import common.sim_config : CharacterConfig, SimConfig, SimConfigRaw;
import common.world : Material;
import common.worldgen.generation : NodeState;
import common.worldgen.spawn : clearSpawnPosition, collectChunksNear;

enum uint MODE_COUNT = MovementMode.max + 1;

immutable string[MODE_COUNT] MODE_NAMES = [
    "walk",
    "fly",
    "noclip",
];

immutable Material[9] MATERIAL_PALETTE = [
    Material.WoodPlanks,
    Material.Wood,
    Material.Leaves,
    Material.GreyBrick,
    Material.WhiteBrick,
    Material.Sandstone,
    Material.Marble,
    Material.Granite,
    Material.Basalt,
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
}

KeyLookup keyFromName(const(char)[] name) {
    if (name == "jump") {
        return KeyLookup(Key.up, true);
    } else {
        foreach (i, keyName; KEY_NAMES) {
            if (keyName == name) {
                return KeyLookup(cast(Key) i, true);
            }
        }
        return KeyLookup(Key.init, false);
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
    LocalCharacterController character;
    CharacterState characterState;
    SimConfig simConfig;
    float simTime = 0;
    float traveled = 0;
    float vacc = 0;
    float cameraAltitude = 0;
    float cameraVerticalVelocity = 0;
    uint materialIndex;
    MovementMode mode = MovementMode.walk;
    bool isSettlingWorldgenEachFrame;
    bool hasCameraVerticalVelocity;

    static Game make(bool isFlat, float reachMeters) {
        SimConfigRaw raw;
        Game game;
        game.simConfig = SimConfig.fromRaw(raw);
        game.world = LocalWorld.make(raw.chunkSize, isFlat, tanhf(reachMeters * game.simConfig.metersToAbsolute));
        game.character = LocalCharacterController.make(game.simConfig.character.eyeOffset);
        game.placeAtSpawn();
        return game;
    }

    void placeAtSpawn() {
        const(CharacterConfig)* cfg = &simConfig.character;
        Graph* graph = &world.graph;
        bool isFlat = world.worldgenDriver.isFlat;
        float bodyReach = cfg.characterHalfHeight + cfg.characterRadius + cfg.contactSkin;
        Position position = clearSpawnPosition(graph, isFlat, bodyReach);
        Slide drop;
        while (!drop.hasLanded) {
            Array!ChunkSlot chunks = collectChunksNear(graph, position, 2.0f * bodyReach);
            foreach (chunk; chunks.slice()) {
                generateNow(graph, chunk, isFlat);
            }
            chunks.release();
            Mover mover = Mover.make(cfg, graph, graph.relativeUp(position));
            drop = mover.settle(position, bodyReach);
            position = graph.normalized(Position(drop.position.node, drop.position.local.renormalized()));
            graph.ensureNodeState(position.node);
        }
        characterState = CharacterState.init;
        characterState.position = position;
        characterState.isOnGround = true;
        characterState.groundNormal = drop.groundNormal;
        character.updatePosition(position, graph.relativeUp(position));
        character.alignToGravity();
        world.cameraPosition = character.orientedPosition();
        cameraAltitude = characterAltitude() + character.eyeOffset;
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
        Capsule capsule = Capsule(character.up, simConfig.character.characterRadius, simConfig.character.characterHalfHeight, simConfig.character.contactSkin);
        if (placement.isFound && !isCapsuleOverlappingVoxel(capsule, &world.graph, characterState.position, placement.chunk, placement.coords)) {
            return world.setVoxel(placement.chunk, placement.coords, MATERIAL_PALETTE[materialIndex]);
        } else {
            return false;
        }
    }

    void look(float yaw, float pitch) {
        character.lookLevel(-yaw, -pitch);
        world.cameraPosition = character.orientedPosition();
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
        traveled += characterState.runStep(&simConfig, &world.graph, characterInput(moveX, moveY, moveZ, input.isHeld[Key.up]), dt);
        world.graph.ensureNodeState(characterState.position.node);
        float altitude = characterAltitude();
        character.smoothEyeVertical(groundedRise(wasOnGround, altitude - altitudeBefore), simConfig.character.stepHeight, dt);
        character.updatePosition(characterState.position, relativeUp(&world.graph, characterState.position));
        character.alignToGravity();
        world.cameraPosition = character.orientedPosition();
        trackCameraAcceleration(altitude + character.eyeOffset - character.eyeLag, dt);
        world.update(isSettlingWorldgenEachFrame);
        if (isSettlingWorldgenEachFrame) {
            world.worldgenDriver.settle(&world.graph);
        }
        simTime += dt;
    }

    CharacterInput characterInput(float moveX, float moveY, float moveZ, bool isUpHeld) const {
        CharacterInput input;
        input.mode = mode;
        if (mode == MovementMode.noclip) {
            input.movement = character.viewOrientation().rotate([moveX, moveY, moveZ]);
        } else if (mode == MovementMode.fly) {
            input.movement = character.orientation.rotate([moveX, moveY, moveZ]);
        } else {
            input.movement = character.orientation.rotate([moveX, 0, moveZ]);
            input.isJumpHeld = isUpHeld;
        }
        return input;
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
            vacc = fabsf((verticalVelocity - cameraVerticalVelocity) / dt);
        } else {
            vacc = 0;
        }
        cameraAltitude = newCameraAltitude;
        cameraVerticalVelocity = verticalVelocity;
        hasCameraVerticalVelocity = true;
    }

    bool setMode(const(char)[] name) {
        foreach (i, candidate; MODE_NAMES) {
            if (candidate == name) {
                mode = cast(MovementMode) i;
                return true;
            }
        }
        return false;
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
