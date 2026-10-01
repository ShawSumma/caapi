module common.character_controller.controller;

import core.math : sqrt;
import core.stdc.math : expf;
import common.character_controller.collision : CollisionCheckingResult, CollisionContext, checkCollision;
import common.graph : Graph, ROOT_NODE, createGraph;
import common.graph_collision : regionPopulated;
import common.math : MIsometry, MPoint, isNan, projectToPlane, sanitizeMotionInput;
import common.proto : CharacterInput, Position, originPosition;
import common.sim_config : CharacterConfig, SimConfig;
import common.vector3 : add3, capMagnitude3, cross3, dot3, magnitude3, moveToward3, neg3, rejectAlong, scale3, zero3;
import common.worldgen.generation : NodeState;

enum uint MAX_CONTACT_PLANES = 5;
enum float MIN_MOVE_ABSOLUTE = 1e-8f;
enum float CLIP_TOLERANCE_FRACTION = 1e-4f;
enum float CLIP_SEPARATION_FRACTION = 2e-3f;
enum float MIN_CREASE_LENGTH = 1e-6f;
enum float MIN_HORIZONTAL_NORMAL = 1e-3f;
enum float MIN_STEP_GAIN_FRACTION = 0.01f;
enum float MIN_STEP_RISE_FRACTION = 0.1f;
enum float STEP_DEPTH_MARGIN = 1.5f;
enum float MIN_UP_LENGTH = 1e-9f;
enum float UP_PROBE_DISTANCE = 0.1f;
enum float UP_PROBE_MIN_GAIN = 0.05f;
enum float TEST_TOLERANCE = 1e-5f;

struct CharacterState {
    Position position;
    float[3] velocity = [0, 0, 0];
    bool onGround;
}

enum Sliding : ubyte {
    free,
    walking,
}

struct Mover {
    CollisionContext collision;
    const(CharacterConfig)* cfg;
    float[3] up;
    float walkableUpDot;
    float minStepDepth;
    float minStepRise;
}

struct ContactPlane {
    float[3] normal;
    float[3] direction;
}

struct Slide {
    Position position;
    float[3] velocity = [0, 0, 0];
    bool hitWall;
    bool landed;
}

struct Step {
    Slide slide;
    bool valid;
}

void runCharacterStep(const(SimConfig)* simConfig, const(Graph)* graph, CharacterState* state, CharacterInput input, float dtSeconds) {
    const(CharacterConfig)* cfg = &simConfig.character;
    float[3] up = getRelativeUp(graph, state.position);
    float slope = cfg.maxGroundSlope;
    float slopeHypotenuse = sqrt(slope * slope + 1.0f);
    float ledgeOverhang = cfg.characterRadius * (1.0f - slope / slopeHypotenuse);
    Mover mover = Mover(CollisionContext(graph, up, cfg.characterRadius, cfg.characterHalfHeight), cfg, up, 1.0f / slopeHypotenuse, ledgeOverhang * STEP_DEPTH_MARGIN, cfg.stepHeight * MIN_STEP_RISE_FRACTION);
    float reach = cfg.characterHalfHeight + cfg.characterRadius + cfg.stepHeight;
    if (!input.noClip && !regionPopulated(graph, state.position.node, state.position.local, reach)) {
        state.velocity = zero3();
    } else {
        if (input.noClip) {
            noClipStep(&mover, state, input, dtSeconds);
        } else if (input.fly) {
            flyStep(&mover, state, input, dtSeconds);
        } else {
            walkStep(&mover, state, input, dtSeconds);
        }
        state.position.local = state.position.local.renormalized();
        state.position.node = graph.normalizeTransform(state.position.node, &state.position.local);
    }
}

void noClipStep(const(Mover)* mover, CharacterState* state, CharacterInput input, float dt) {
    state.velocity = scale3(sanitizeMotionInput(input.movement), mover.cfg.noClipMovementSpeed);
    state.onGround = false;
    state.position.local = state.position.local * MIsometry!float.translationAlong(scale3(state.velocity, dt));
}

void flyStep(const(Mover)* mover, CharacterState* state, CharacterInput input, float dt) {
    float[3] velocity = scale3(sanitizeMotionInput(input.movement), mover.cfg.flyMovementSpeed);
    Slide moved = slide(mover, state.position, scale3(velocity, dt), velocity, Sliding.free);
    state.position = moved.position;
    state.velocity = moved.velocity;
    state.onGround = false;
}

void walkStep(const(Mover)* mover, CharacterState* state, CharacterInput input, float dt) {
    const(CharacterConfig)* cfg = mover.cfg;
    float[3] wish = rejectAlong(sanitizeMotionInput(input.movement), mover.up);
    float[3] targetVelocity = scale3(wish, cfg.maxGroundSpeed);
    float[3] horizontalVelocity = rejectAlong(state.velocity, mover.up);
    float verticalSpeed = dot3(state.velocity, mover.up);
    if (state.onGround && !input.jump) {
        groundMove(mover, state, moveToward3(horizontalVelocity, targetVelocity, cfg.groundAcceleration * dt), dt);
    } else {
        if (state.onGround) {
            verticalSpeed = cfg.jumpSpeed;
        }
        if (dot3(wish, wish) > 0) {
            horizontalVelocity = moveToward3(horizontalVelocity, targetVelocity, cfg.airAcceleration * dt);
        }
        airMove(mover, state, horizontalVelocity, verticalSpeed, dt);
    }
}

void groundMove(const(Mover)* mover, CharacterState* state, float[3] velocity, float dt) {
    float[3] displacement = scale3(velocity, dt);
    Position start = state.position;
    Slide chosen = slide(mover, start, displacement, velocity, Sliding.walking);
    if (chosen.hitWall) {
        Step stepped = stepUp(mover, start, displacement, velocity);
        float required = horizontalProgress(mover, start, chosen.position, displacement) + MIN_STEP_GAIN_FRACTION * magnitude3(displacement);
        if (stepped.valid && horizontalProgress(mover, start, stepped.slide.position, displacement) > required) {
            chosen = stepped.slide;
        }
    }
    Slide ground = settle(mover, chosen.position, mover.cfg.stepHeight);
    state.position = chosen.position;
    state.velocity = rejectAlong(chosen.velocity, mover.up);
    state.onGround = ground.landed;
    if (ground.landed) {
        state.position = ground.position;
    }
}

void airMove(const(Mover)* mover, CharacterState* state, float[3] horizontalVelocity, float verticalSpeed, float dt) {
    const(CharacterConfig)* cfg = mover.cfg;
    float[3] startVelocity = add3(horizontalVelocity, scale3(mover.up, verticalSpeed));
    float[3] fallen = add3(horizontalVelocity, scale3(mover.up, verticalSpeed - cfg.gravityAcceleration * dt));
    float[3] endVelocity = capMagnitude3(scale3(fallen, expf(-cfg.airResistance * dt)), cfg.speedCap);
    float[3] displacement = scale3(add3(startVelocity, endVelocity), 0.5f * dt);
    Slide moved = slide(mover, state.position, displacement, endVelocity, Sliding.free);
    state.position = moved.position;
    state.velocity = moved.velocity;
    state.onGround = moved.landed;
    if (moved.landed) {
        state.velocity = rejectAlong(moved.velocity, mover.up);
    }
}

Step stepUp(const(Mover)* mover, Position start, float[3] displacement, float[3] velocity) {
    Step result;
    float[3] horizontal = rejectAlong(displacement, mover.up);
    float horizontalLength = magnitude3(horizontal);
    Slide raised = slide(mover, start, scale3(mover.up, mover.cfg.stepHeight), zero3(), Sliding.free);
    float rise = verticalGain(mover, start, raised.position);
    if (horizontalLength > MIN_MOVE_ABSOLUTE && rise > MIN_MOVE_ABSOLUTE) {
        float[3] tread = horizontal;
        if (horizontalLength < mover.minStepDepth) {
            tread = scale3(horizontal, mover.minStepDepth / horizontalLength);
        }
        Slide across = slide(mover, raised.position, tread, velocity, Sliding.walking);
        Slide drop = settle(mover, across.position, rise + mover.cfg.groundDistanceTolerance);
        if (drop.landed && verticalGain(mover, start, drop.position) > mover.minStepRise) {
            result.slide = across;
            result.slide.position = drop.position;
            result.valid = true;
        }
    }
    return result;
}

Slide settle(const(Mover)* mover, Position start, float distance) {
    return slide(mover, start, scale3(neg3(mover.up), distance), zero3(), Sliding.free);
}

float verticalGain(const(Mover)* mover, Position start, Position end) {
    MPoint!float moved = (start.local.inverse() * end.local) * MPoint!float.origin();
    return dot3(moved.vec.xyz(), mover.up);
}

Slide slide(const(Mover)* mover, Position start, float[3] displacement, float[3] velocity, Sliding sliding) {
    Slide result;
    result.position = start;
    result.velocity = velocity;
    ContactPlane[MAX_CONTACT_PLANES] planes;
    uint planeCount = 0;
    float[3] remaining = displacement;
    bool moving = true;
    while (moving && planeCount < MAX_CONTACT_PLANES) {
        float length = magnitude3(remaining);
        if (!(length > MIN_MOVE_ABSOLUTE)) {
            moving = false;
        } else {
            CollisionCheckingResult collision = checkCollision(&mover.collision, result.position, remaining);
            result.position.local = result.position.local * collision.displacementTransform;
            if (!collision.hasCollision) {
                moving = false;
            } else {
                remaining = scale3(remaining, 1.0f - magnitude3(collision.displacementVector) / length);
                bool walkable = isWalkable(mover, collision.normal);
                bool descending = dot3(remaining, mover.up) < 0;
                if (walkable && descending) {
                    result.landed = true;
                }
                if (!walkable) {
                    result.hitWall = true;
                }
                planes[planeCount] = ContactPlane(collision.normal, projectionDirection(mover, collision.normal, walkable && (descending || sliding == Sliding.walking), sliding));
                planeCount += 1;
                remaining = clipToPlanes(planes[0 .. planeCount], remaining, CLIP_SEPARATION_FRACTION);
                result.velocity = clipToPlanes(planes[0 .. planeCount], result.velocity, 0.0f);
            }
        }
    }
    return result;
}

float[3] projectionDirection(const(Mover)* mover, float[3] normal, bool supporting, Sliding sliding) {
    float[3] result = normal;
    if (supporting) {
        result = mover.up;
    } else if (sliding == Sliding.walking) {
        float[3] horizontal = rejectAlong(normal, mover.up);
        float horizontalLength = magnitude3(horizontal);
        if (horizontalLength > MIN_HORIZONTAL_NORMAL) {
            result = scale3(horizontal, 1.0f / horizontalLength);
        }
    }
    return result;
}

bool satisfiesPlanes(const(ContactPlane)[] planes, float[3] v, float tolerance) {
    bool result = true;
    foreach (plane; planes) {
        if (dot3(v, plane.normal) < tolerance) {
            result = false;
        }
    }
    return result;
}

float[3] clipToPlanes(const(ContactPlane)[] planes, float[3] v, float separationFraction) {
    float length = magnitude3(v);
    float tolerance = -CLIP_TOLERANCE_FRACTION * length;
    float[3] result = v;
    bool found = satisfiesPlanes(planes, v, tolerance);
    foreach (plane; planes) {
        if (!found && dot3(v, plane.normal) < tolerance) {
            float[3] candidate = projectToPlane(v, plane.normal, plane.direction, separationFraction * length);
            if (satisfiesPlanes(planes, candidate, tolerance)) {
                result = candidate;
                found = true;
            }
        }
    }
    foreach (i; 0 .. planes.length) {
        foreach (j; i + 1 .. planes.length) {
            float[3] crease = cross3(planes[i].normal, planes[j].normal);
            float creaseLength = magnitude3(crease);
            if (!found && creaseLength > MIN_CREASE_LENGTH) {
                float[3] line = scale3(crease, 1.0f / creaseLength);
                float[3] candidate = scale3(line, dot3(v, line));
                if (satisfiesPlanes(planes, candidate, tolerance)) {
                    result = candidate;
                    found = true;
                }
            }
        }
    }
    if (!found) {
        result = zero3();
    }
    return result;
}

bool isWalkable(const(Mover)* mover, float[3] normal) {
    return dot3(normal, mover.up) > mover.walkableUpDot;
}

float horizontalProgress(const(Mover)* mover, Position start, Position end, float[3] displacement) {
    MPoint!float moved = (start.local.inverse() * end.local) * MPoint!float.origin();
    float[3] horizontal = rejectAlong(displacement, mover.up);
    float horizontalLength = magnitude3(horizontal);
    float result = 0;
    if (horizontalLength > MIN_MOVE_ABSOLUTE) {
        result = dot3(rejectAlong(moved.vec.xyz(), mover.up), horizontal) / horizontalLength;
    }
    return result;
}

float[3] getRelativeUp(const(Graph)* graph, Position position) {
    float[3] result = [0.0f, 1.0f, 0.0f];
    const(NodeState)* state = graph.nodeState(position.node);
    if (state !is null) {
        float[3] up = (position.local.inverse() * state.surface.scaledNormal).xyz();
        float length = magnitude3(up);
        if (!(length < MIN_UP_LENGTH || isNan(length))) {
            result = scale3(up, 1.0f / length);
        }
    }
    return result;
}

unittest {
    Graph graph = createGraph(12);
    graph.ensureNodeState(ROOT_NODE);
    Position position = originPosition();
    float[3] up = getRelativeUp(&graph, position);
    const(NodeState)* state = graph.nodeState(ROOT_NODE);
    float startDistance = state.surface.distanceTo(position.local * MPoint!float.origin());
    position.local = position.local * MIsometry!float.translationAlong(scale3(up, UP_PROBE_DISTANCE));
    float endDistance = state.surface.distanceTo(position.local * MPoint!float.origin());
    assert(endDistance > startDistance + UP_PROBE_MIN_GAIN);
    graph.release();
}

unittest {
    float[3] up = [0, 1, 0];
    float[3] floorNormal = [0, 1, 0];
    float[3] wallNormal = [-1, 0, 0];
    float[3] horizontalWall = [-1, 0, 0];
    ContactPlane[2] planes = [
        ContactPlane(floorNormal, up),
        ContactPlane(wallNormal, horizontalWall),
    ];
    float[3] intoCorner = [1, -0.5f, 1];
    float[3] clipped = clipToPlanes(planes, intoCorner, 0.0f);
    assert(clipped[0] > -TEST_TOLERANCE && clipped[0] < TEST_TOLERANCE);
    assert(clipped[1] > -TEST_TOLERANCE);
    assert(clipped[2] > 1 - TEST_TOLERANCE);
    assert(magnitude3(clipped) <= magnitude3(intoCorner));
}

unittest {
    float[3] slopeNormal = [-0.5f, 0.8660254f, 0];
    float[3] up = [0, 1, 0];
    ContactPlane[1] walkable = [ContactPlane(slopeNormal, up)];
    float[3] uphill = [1, 0, 0];
    float[3] climbed = clipToPlanes(walkable, uphill, 0.0f);
    assert(climbed[0] == 1);
    assert(climbed[1] > 0);
    assert(dot3(climbed, slopeNormal) > -TEST_TOLERANCE);
    ContactPlane[1] free = [ContactPlane(slopeNormal, slopeNormal)];
    assert(magnitude3(clipToPlanes(free, uphill, 0.0f)) <= 1);
    assert(dot3(clipToPlanes(free, uphill, CLIP_SEPARATION_FRACTION), slopeNormal) > 0);
}

unittest {
    float[3] a = [-1, 0, 0];
    float[3] b = [0, 0, -1];
    float[3] c = [0, -1, 0];
    ContactPlane[3] boxed = [
        ContactPlane(a, a),
        ContactPlane(b, b),
        ContactPlane(c, c),
    ];
    float[3] intoAll = [1, 1, 1];
    float[3] clipped = clipToPlanes(boxed, intoAll, CLIP_SEPARATION_FRACTION);
    assert(magnitude3(clipped) == 0);
}
