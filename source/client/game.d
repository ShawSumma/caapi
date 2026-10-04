module client.game;

import core.stdc.math : fabsf, tanhf;
import client.local_character_controller : LocalCharacterController, createLocalCharacterController;
import client.local_world : LocalWorld, Placement, breakBlock, createLocalWorld, placementTarget, releaseLocalWorld, setVoxel, updateLocalWorld;
import client.worldgen_driver : generateNow, settleWorldgen;
import common.array : Array;
import common.character_controller.controller : CharacterState, Mover, Slide, createMover, getRelativeUp, runCharacterStep, settle;
import common.graph : Graph;
import common.graph_collision : Capsule, capsuleOverlapsVoxel;
import common.math : MPoint;
import common.node : ChunkSlot;
import common.proto : CharacterInput, MovementMode, Position;
import common.sim_config : CharacterConfig, SimConfig, SimConfigRaw, simConfigFromRaw;
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
    bool found;
}

KeyLookup keyFromName(const(char)[] name) {
    KeyLookup result;
    if (name == "jump") {
        result = KeyLookup(Key.up, true);
    } else {
        foreach (i, keyName; KEY_NAMES) {
            if (keyName == name) {
                result = KeyLookup(cast(Key) i, true);
            }
        }
    }
    return result;
}

struct FrameInput {
    float yaw = 0;
    float pitch = 0;
    bool[KEY_COUNT] held;
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
    bool settleWorldgenEachFrame;
    bool haveCameraVerticalVelocity;
}

Game createGame(bool flatWorldgen, float reachMeters) {
    SimConfigRaw raw;
    Game game;
    game.simConfig = simConfigFromRaw(raw);
    game.world = createLocalWorld(raw.chunkSize, flatWorldgen, tanhf(reachMeters * game.simConfig.metersToAbsolute));
    game.character = createLocalCharacterController();
    game.character.eyeOffset = game.simConfig.character.eyeOffset;
    placeAtSpawn(&game);
    return game;
}

void placeAtSpawn(Game* game) {
    const(CharacterConfig)* cfg = &game.simConfig.character;
    Graph* graph = &game.world.graph;
    bool flat = game.world.worldgenDriver.flatWorldgen;
    float bodyReach = cfg.characterHalfHeight + cfg.characterRadius + cfg.contactSkin;
    Position position = clearSpawnPosition(graph, flat, bodyReach);
    Array!ChunkSlot chunks;
    Slide drop;
    while (!drop.landed) {
        chunks.clear();
        collectChunksNear(graph, position, 2.0f * bodyReach, &chunks);
        foreach (chunk; chunks.slice()) {
            generateNow(graph, chunk, flat);
        }
        Mover mover = createMover(cfg, graph, getRelativeUp(graph, position));
        drop = settle(&mover, position, bodyReach);
        position.local = drop.position.local.renormalized();
        position.node = graph.normalizeTransform(drop.position.node, &position.local);
        graph.ensureNodeState(position.node);
    }
    chunks.release();
    game.characterState = CharacterState.init;
    game.characterState.position = position;
    game.characterState.onGround = true;
    game.characterState.groundNormal = drop.groundNormal;
    game.character.updatePosition(position, getRelativeUp(graph, position));
    game.character.alignToGravity();
    game.world.cameraPosition = game.character.orientedPosition();
    game.cameraAltitude = characterAltitude(game) + game.character.eyeOffset;
    game.haveCameraVerticalVelocity = false;
}

void setWorldgen(Game* game, bool flat) {
    ubyte dimension = game.world.graph.layout.dimension;
    float reach = game.world.reach;
    uint epoch = game.world.epoch;
    releaseLocalWorld(&game.world);
    game.world = createLocalWorld(dimension, flat, reach);
    game.world.epoch = epoch + 1;
    placeAtSpawn(game);
}

void releaseGame(Game* game) {
    releaseLocalWorld(&game.world);
}

bool gameBreakBlock(Game* game) {
    return breakBlock(&game.world);
}

bool gamePlaceBlock(Game* game) {
    Placement placement = placementTarget(&game.world);
    Capsule capsule = Capsule(game.character.up, game.simConfig.character.characterRadius, game.simConfig.character.characterHalfHeight, game.simConfig.character.contactSkin);
    bool result = false;
    if (placement.found && !capsuleOverlapsVoxel(capsule, &game.world.graph, game.characterState.position.node, game.characterState.position.local, placement.chunk, placement.coords)) {
        result = setVoxel(&game.world, placement.chunk, placement.coords, MATERIAL_PALETTE[game.materialIndex]);
    }
    return result;
}

float axisValue(bool held) {
    float result = 0.0f;
    if (held) {
        result = 1.0f;
    }
    return result;
}

void gameLook(Game* game, float yaw, float pitch) {
    game.character.lookLevel(-yaw, -pitch);
    game.world.cameraPosition = game.character.orientedPosition();
}

float characterAltitude(const(Game)* game) {
    const(NodeState)* state = game.world.graph.nodeState(game.characterState.position.node);
    return state.surface.distanceTo(game.characterState.position.local * MPoint!float.origin());
}

void stepGame(Game* game, FrameInput input, float dt) {
    gameLook(game, input.yaw, input.pitch);
    float moveX = axisValue(input.held[Key.right]) - axisValue(input.held[Key.left]);
    float moveY = axisValue(input.held[Key.up]) - axisValue(input.held[Key.down]);
    float moveZ = axisValue(input.held[Key.back]) - axisValue(input.held[Key.fwd]);
    float altitudeBefore = characterAltitude(game);
    bool wasOnGround = game.characterState.onGround;

    CharacterInput characterInput;
    characterInput.mode = game.mode;
    if (game.mode == MovementMode.noclip) {
        characterInput.movement = game.character.viewOrientation().rotate([moveX, moveY, moveZ]);
    } else if (game.mode == MovementMode.fly) {
        characterInput.movement = game.character.orientation.rotate([moveX, moveY, moveZ]);
    } else {
        characterInput.movement = game.character.orientation.rotate([moveX, 0, moveZ]);
        characterInput.jump = input.held[Key.up];
    }
    game.traveled += runCharacterStep(&game.simConfig, &game.world.graph, &game.characterState, characterInput, dt);
    game.world.graph.ensureNodeState(game.characterState.position.node);

    float altitude = characterAltitude(game);
    float groundedRise = 0;
    if (wasOnGround && game.characterState.onGround) {
        groundedRise = altitude - altitudeBefore;
    }
    game.character.smoothEyeVertical(groundedRise, game.simConfig.character.stepHeight, dt);
    game.character.updatePosition(game.characterState.position, getRelativeUp(&game.world.graph, game.characterState.position));
    game.character.alignToGravity();
    game.world.cameraPosition = game.character.orientedPosition();

    trackCameraAcceleration(game, altitude + game.character.eyeOffset - game.character.eyeLag, dt);
    updateLocalWorld(&game.world, game.settleWorldgenEachFrame);
    if (game.settleWorldgenEachFrame) {
        settleWorldgen(&game.world.worldgenDriver, &game.world.graph);
    }
    game.simTime += dt;
}

void trackCameraAcceleration(Game* game, float cameraAltitude, float dt) {
    float verticalVelocity = (cameraAltitude - game.cameraAltitude) / dt;
    game.vacc = 0;
    if (game.haveCameraVerticalVelocity) {
        game.vacc = fabsf((verticalVelocity - game.cameraVerticalVelocity) / dt);
    }
    game.cameraAltitude = cameraAltitude;
    game.cameraVerticalVelocity = verticalVelocity;
    game.haveCameraVerticalVelocity = true;
}

bool setMode(Game* game, const(char)[] name) {
    bool known = false;
    foreach (i, candidate; MODE_NAMES) {
        if (candidate == name) {
            game.mode = cast(MovementMode) i;
            known = true;
        }
    }
    return known;
}

void toggleMode(Game* game, MovementMode toggled) {
    if (game.mode == toggled) {
        game.mode = MovementMode.fly;
    } else {
        game.mode = toggled;
    }
}

const(char)* modeName(const(Game)* game) {
    return MODE_NAMES[game.mode].ptr;
}
