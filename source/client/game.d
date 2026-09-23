module client.game;

import std.math : acosh, tanh;
import client.local_character_controller : LocalCharacterController;
import client.local_world : LocalWorld;
import common.character_controller : runCharacterStep, getRelativeUp;
import common.character_controller.vector_bounds : dot3;
import common.math : MPoint;
import common.proto : CharacterInput, Position;
import common.sim_config : SimConfig;
import common.world : Material;

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

/// Script and recording names, indexed by Key.
immutable string[Key.max + 1] KEY_NAMES = [
    "fwd", "back", "left", "right", "up", "down",
    "yaw_left", "yaw_right", "pitch_up", "pitch_down",
];

bool keyFromName(const(char)[] name, out Key key) {
    if (name == "jump") {
        key = Key.up;
        return true;
    }
    foreach (i, n; KEY_NAMES) {
        if (n == name) {
            key = cast(Key) i;
            return true;
        }
    }
    return false;
}

/// Held-key state, tracked per key so opposite keys don't cancel each
/// other's release, and clearable in one go when the window loses focus.
struct InputState {
    bool[Key.max + 1] held;

    bool opIndex(Key key) const {
        return held[key];
    }

    void clear() {
        held[] = false;
    }
}

/// One simulated frame's input: held keys plus the final look deltas in
/// radians (sensitivity and invert already applied).
struct FrameInput {
    InputState keys;
    float yaw = 0;
    float pitch = 0;
}

/// The local player in the world: character control, camera, block edits,
/// and the motion metrics headless runs check. Knows nothing of windows.
struct Game {
    SimConfig simCfg;
    LocalWorld world;
    LocalCharacterController character;
    float[3] velocity = [0, 0, 0];
    bool onGround = false;
    bool flyMode = true;
    bool noClip = false;
    int materialIndex = 0;
    float simTime = 0;
    // Wait for chunk generation every frame so results don't depend on
    // worker timing (headless runs).
    bool settleWorldgen = false;

    // Traversal odometer in absolute units.
    float traveled = 0;
    Position odoPrev;
    // Vertical camera acceleration magnitude over the last frame (the bounce
    // metric), in absolute units per second squared; 0 when undefined.
    float vacc = 0;
    Position camPrev;
    float prevVertVel = 0;
    bool haveVertVel = false;

    static Game create(ubyte dimension, bool flatWorldgen, float reachMeters) {
        Game g;
        g.simCfg = SimConfig.fromRaw();
        g.world = LocalWorld.create(dimension, flatWorldgen);
        g.world.reach = tanh(reachMeters * g.simCfg.metersToAbsolute);
        g.character = LocalCharacterController.create();
        g.character.position = g.world.camPos;
        g.character.up = getRelativeUp(&g.world.graph, &g.character.position);
        g.character.eyeOffset = g.simCfg.character.eyeOffset;
        g.character.alignToGravity();
        g.odoPrev = g.character.position;
        g.camPrev = g.world.camPos;
        return g;
    }

    Material material() const {
        return MATERIAL_PALETTE[materialIndex];
    }

    bool breakBlock() {
        return world.breakBlock();
    }

    bool placeBlock() {
        return world.placeBlock(material());
    }

    /// Advances the character by one frame, moves the camera with it, and
    /// updates the world around the new camera position.
    void step(const ref FrameInput input, float dt) {
        // The quaternion axes are mirrored relative to the camera's rotation
        // convention, hence the negated deltas.
        character.lookLevel(-input.yaw, -input.pitch);

        float mx = axis(input.keys[Key.right]) - axis(input.keys[Key.left]);
        float my = axis(input.keys[Key.up]) - axis(input.keys[Key.down]);
        float mz = axis(input.keys[Key.back]) - axis(input.keys[Key.fwd]);

        Position beforeStep = character.position;
        bool wasGround = onGround;

        CharacterInput cin;
        cin.noClip = noClip;
        cin.fly = flyMode;
        if (noClip) {
            // Debug free-flight: fully view-relative.
            cin.movement = character.viewOrientation().rotate([mx, my, mz]);
        } else if (flyMode) {
            // Creative flight: forward/strafe in the yaw plane, and
            // Space/Shift along actual world up/down.
            cin.movement = character.horizontalOrientation().rotate([mx, my, mz]);
        } else {
            cin.movement = character.horizontalOrientation().rotate([mx, 0, mz]);
            cin.jump = input.keys[Key.up];
        }
        runCharacterStep(simCfg, world.graph, character.position,
            velocity, onGround, cin, dt);

        // Holonomy mitigation: "down" is re-derived from the world at the
        // new position every step, the view is transported to follow it,
        // and any residual roll is aligned away, so carrying the frame
        // around a loop can't accumulate rotation.
        float[3] newUp = getRelativeUp(&world.graph, &character.position);

        // Smooth grounded vertical motion (stair steps, hop launches and
        // landings) out of the eye.
        float groundedRise = 0;
        if ((wasGround || onGround) && beforeStep.node == character.position.node) {
            MPoint!float moved = (beforeStep.local.inverse() * character.position.local)
                * MPoint!float.origin();
            groundedRise = dot3(moved.vec.xyz(), newUp);
        }
        character.smoothEyeVertical(groundedRise, dt);

        character.updatePosition(character.position, newUp, true);
        // The yaw frame stays up-aligned by construction; this only
        // scrubs out accumulated float noise.
        character.alignToGravity();
        character.renormalizeOrientation();
        world.camPos = character.orientedPosition();

        trackVerticalAcceleration(newUp, dt);
        trackOdometer();

        world.update();
        if (settleWorldgen) {
            world.worldgenDriver.settle(world.graph, world.dimension);
        }
        simTime += dt;
    }

    void trackVerticalAcceleration(float[3] up, float dt) {
        vacc = 0;
        if (world.camPos.node == camPrev.node && dt > 1e-6f) {
            MPoint!float camMoved = (camPrev.local.inverse() * world.camPos.local)
                * MPoint!float.origin();
            float vertVel = dot3(camMoved.vec.xyz(), up) / dt;
            if (haveVertVel) {
                vacc = (vertVel - prevVertVel) / dt;
                if (vacc < 0) {
                    vacc = -vacc;
                }
            }
            prevVertVel = vertVel;
            haveVertVel = true;
        } else {
            haveVertVel = false;
        }
        camPrev = world.camPos;
    }

    void trackOdometer() {
        if (character.position.node == odoPrev.node) {
            MPoint!float a = odoPrev.local * MPoint!float.origin();
            MPoint!float b = character.position.local * MPoint!float.origin();
            float m = -a.mip(b.vec);
            if (m > 1.0f) {
                traveled += acosh(m);
            }
        }
        odoPrev = character.position;
    }
}

float axis(bool held) {
    return held ? 1.0f : 0.0f;
}

/// Sets walk, fly, or noclip; false for an unknown name.
bool setMode(ref Game game, const(char)[] name) {
    switch (name) {
        case "walk":
            game.flyMode = false;
            game.noClip = false;
            return true;
        case "fly":
            game.flyMode = true;
            game.noClip = false;
            return true;
        case "noclip":
            game.noClip = true;
            return true;
        default:
            return false;
    }
}

string modeName(bool flyMode, bool noClip) {
    if (noClip) {
        return "noclip";
    }
    return flyMode ? "fly" : "walk";
}
