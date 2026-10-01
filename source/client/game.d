module client.game;

import core.stdc.math : acoshf, fabsf, tanhf;
import client.local_character_controller : LocalCharacterController, createLocalCharacterController;
import client.local_world : LocalWorld, Placement, breakBlock, createLocalWorld, placementTarget, releaseLocalWorld, setVoxel, updateLocalWorld;
import client.worldgen_driver : settleWorldgen;
import common.character_controller.controller : CharacterState, getRelativeUp, runCharacterStep;
import common.graph_collision : Capsule, capsuleOverlapsVoxel;
import common.math : MPoint;
import common.proto : CharacterInput, Position;
import common.sim_config : SimConfig, SimConfigRaw, simConfigFromRaw;
import common.vector3 : dot3;
import common.world : Material;
import common.worldgen.generation : NodeState;

enum float MIN_ACCELERATION_DT = 1e-6f;

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
    Position odometerPrevious;
    Position cameraPrevious;
    SimConfig simConfig;
    float simTime = 0;
    float traveled = 0;
    float vacc = 0;
    float previousVerticalVelocity = 0;
    uint materialIndex;
    bool flyMode = true;
    bool noClip;
    bool settleWorldgenEachFrame;
    bool haveVerticalVelocity;
}

Game createGame(bool flatWorldgen, float reachMeters) {
    SimConfigRaw raw;
    Game game;
    game.simConfig = simConfigFromRaw(raw);
    game.world = createLocalWorld(raw.chunkSize, flatWorldgen, tanhf(reachMeters * game.simConfig.metersToAbsolute));
    game.character = createLocalCharacterController();
    game.character.position = game.world.cameraPosition;
    game.character.up = getRelativeUp(&game.world.graph, game.character.position);
    game.character.eyeOffset = game.simConfig.character.eyeOffset;
    game.character.alignToGravity();
    game.characterState.position = game.character.position;
    game.odometerPrevious = game.character.position;
    game.cameraPrevious = game.world.cameraPosition;
    return game;
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
    float result = float.nan;
    if (state !is null) {
        result = state.surface.distanceTo(game.characterState.position.local * MPoint!float.origin());
    }
    return result;
}

void stepGame(Game* game, FrameInput input, float dt) {
    gameLook(game, input.yaw, input.pitch);
    float moveX = axisValue(input.held[Key.right]) - axisValue(input.held[Key.left]);
    float moveY = axisValue(input.held[Key.up]) - axisValue(input.held[Key.down]);
    float moveZ = axisValue(input.held[Key.back]) - axisValue(input.held[Key.fwd]);
    Position beforeStep = game.characterState.position;
    bool wasOnGround = game.characterState.onGround;

    CharacterInput characterInput;
    characterInput.noClip = game.noClip;
    characterInput.fly = game.flyMode;
    if (game.noClip) {
        characterInput.movement = game.character.viewOrientation().rotate([moveX, moveY, moveZ]);
    } else if (game.flyMode) {
        characterInput.movement = game.character.orientation.rotate([moveX, moveY, moveZ]);
    } else {
        characterInput.movement = game.character.orientation.rotate([moveX, 0, moveZ]);
        characterInput.jump = input.held[Key.up];
    }
    runCharacterStep(&game.simConfig, &game.world.graph, &game.characterState, characterInput, dt);

    float[3] newUp = getRelativeUp(&game.world.graph, game.characterState.position);
    float groundedRise = 0;
    if ((wasOnGround || game.characterState.onGround) && beforeStep.node == game.characterState.position.node) {
        MPoint!float moved = (beforeStep.local.inverse() * game.characterState.position.local) * MPoint!float.origin();
        groundedRise = dot3(moved.vec.xyz(), newUp);
    }
    game.character.smoothEyeVertical(groundedRise, dt);
    game.character.updatePosition(game.characterState.position, newUp);
    game.character.alignToGravity();
    game.world.cameraPosition = game.character.orientedPosition();

    trackVerticalAcceleration(game, newUp, dt);
    trackOdometer(game);
    updateLocalWorld(&game.world);
    if (game.settleWorldgenEachFrame) {
        settleWorldgen(&game.world.worldgenDriver, &game.world.graph);
    }
    game.simTime += dt;
}

void trackVerticalAcceleration(Game* game, float[3] up, float dt) {
    game.vacc = 0;
    if (game.world.cameraPosition.node == game.cameraPrevious.node && dt > MIN_ACCELERATION_DT) {
        MPoint!float cameraMoved = (game.cameraPrevious.local.inverse() * game.world.cameraPosition.local) * MPoint!float.origin();
        float verticalVelocity = dot3(cameraMoved.vec.xyz(), up) / dt;
        if (game.haveVerticalVelocity) {
            game.vacc = fabsf((verticalVelocity - game.previousVerticalVelocity) / dt);
        }
        game.previousVerticalVelocity = verticalVelocity;
        game.haveVerticalVelocity = true;
    } else {
        game.haveVerticalVelocity = false;
    }
    game.cameraPrevious = game.world.cameraPosition;
}

void trackOdometer(Game* game) {
    if (game.characterState.position.node == game.odometerPrevious.node) {
        MPoint!float start = game.odometerPrevious.local * MPoint!float.origin();
        float cosh = -start.mip((game.characterState.position.local * MPoint!float.origin()).vec);
        if (cosh > 1.0f) {
            game.traveled += acoshf(cosh);
        }
    }
    game.odometerPrevious = game.characterState.position;
}

bool setMode(Game* game, const(char)[] name) {
    bool known = true;
    if (name == "walk") {
        game.flyMode = false;
        game.noClip = false;
    } else if (name == "fly") {
        game.flyMode = true;
        game.noClip = false;
    } else if (name == "noclip") {
        game.noClip = true;
    } else {
        known = false;
    }
    return known;
}

const(char)* modeName(const(Game)* game) {
    const(char)* result = "walk";
    if (game.noClip) {
        result = "noclip";
    } else if (game.flyMode) {
        result = "fly";
    }
    return result;
}
