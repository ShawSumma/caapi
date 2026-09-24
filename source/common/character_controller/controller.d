module common.character_controller.controller;

import core.math : sqrt;
import core.stdc.math : expf;
import common.character_controller.collision : CollisionCheckingResult, CollisionContext, checkCollision;
import common.character_controller.vector_bounds : BoundedVectors, VectorBound, add3, createBoundedVectors, dot3, magnitude3, neg3, scale3, sub3, zero3;
import common.graph : Graph, ROOT_NODE, createGraph;
import common.graph_collision : regionPopulated;
import common.math : MIsometry, MPoint, isNan, projectToPlane, sanitizeMotionInput;
import common.proto : CharacterInput, Position, originPosition;
import common.sim_config : CharacterConfig, SimConfig;
import common.worldgen.generation : NodeState;

enum uint MAX_COLLISION_ITERATIONS = 6;
enum double MIN_INPUT_MAGNITUDE = 1e-16;
enum double MIN_DISPLACEMENT_MAGNITUDE = 1e-16;
enum float MIN_HORIZONTAL_MAGNITUDE = 1e-9f;
enum float MIN_BLOCKED_MAGNITUDE = 1e-6f;
enum float BLOCKED_PROGRESS_FRACTION = 0.5f;
enum float HOP_GAIN_FRACTION = 0.5f;
enum float HOP_PROGRESS_FRACTION = 0.5f;
enum float MIN_UP_LENGTH = 1e-9f;
enum float UP_PROBE_DISTANCE = 0.1f;
enum float UP_PROBE_MIN_GAIN = 0.05f;

struct CharacterState {
    Position position;
    float[3] velocity = [0, 0, 0];
    bool onGround;
}

struct CharacterControllerContext {
    CollisionContext collisionContext;
    const(CharacterConfig)* cfg;
    float[3] up;
    float[3] movementInput;
    float dtSeconds;
    bool jumpInput;
}

struct Motion {
    Position position;
    float[3] velocity;
    float[3] groundNormal;
    bool hasGroundNormal;
}

struct GroundContact {
    float[3] normal = [0, 0, 0];
    bool found;
}

struct SettleResult {
    Position position;
    float[3] normal = [0, 0, 0];
    bool found;
}

void runCharacterStep(const(SimConfig)* simConfig, const(Graph)* graph, CharacterState* state, CharacterInput input, float dtSeconds) {
    float[3] up = getRelativeUp(graph, state.position);
    const(CharacterConfig)* cfg = &simConfig.character;
    CharacterControllerContext context = CharacterControllerContext(CollisionContext(graph, up, cfg.characterRadius, cfg.characterHalfHeight), cfg, up, sanitizeMotionInput(input.movement), dtSeconds, input.jump);
    if (!input.noClip && !regionPopulated(graph, state.position.node, state.position.local, cfg.characterHalfHeight + cfg.characterRadius + cfg.groundDistanceTolerance)) {
        state.velocity = zero3();
    } else {
        if (input.noClip) {
            runNoClipCharacterStep(&context, state);
        } else if (input.fly) {
            runFlyCharacterStep(&context, state);
        } else {
            runStandardCharacterStep(&context, state);
        }
        state.position.local = state.position.local.renormalized();
        state.position.node = graph.normalizeTransform(state.position.node, &state.position.local);
    }
}

void runStandardCharacterStep(const(CharacterControllerContext)* context, CharacterState* state) {
    bool startedOnGround = state.onGround;
    bool hasGroundNormal = false;
    float[3] groundNormal = zero3();
    if (state.onGround) {
        GroundContact contact = getGroundNormal(context, state.position);
        hasGroundNormal = contact.found;
        groundNormal = contact.normal;
    }

    if (context.jumpInput && hasGroundNormal) {
        float[3] horizontalVelocity = sub3(state.velocity, scale3(context.up, dot3(context.up, state.velocity)));
        state.velocity = add3(horizontalVelocity, scale3(context.up, context.cfg.jumpSpeed));
        hasGroundNormal = false;
    }

    float[3] oldVelocity = state.velocity;
    if (hasGroundNormal) {
        state.velocity = applyGroundControls(context, groundNormal, state.velocity);
    } else {
        state.velocity = applyAirControls(context, state.velocity);
        state.velocity = scale3(state.velocity, expf(-context.cfg.airResistance * context.dtSeconds));
    }
    state.velocity = sub3(state.velocity, scale3(context.up, context.cfg.gravityAcceleration * context.dtSeconds));
    state.velocity = capMagnitude(state.velocity, context.cfg.speedCap);
    float[3] expectedDisplacement = scale3(scale3(add3(state.velocity, oldVelocity), 0.5f), context.dtSeconds);

    Position startPosition = state.position;
    Motion motion = Motion(state.position, state.velocity, groundNormal, hasGroundNormal);
    applyVelocity(context, expectedDisplacement, &motion);
    state.position = motion.position;
    state.velocity = motion.velocity;
    groundNormal = motion.groundNormal;
    hasGroundNormal = motion.hasGroundNormal;

    float[3] expectedHorizontal = sub3(expectedDisplacement, scale3(context.up, dot3(expectedDisplacement, context.up)));
    float expectedMagnitude = magnitude3(expectedHorizontal);
    float[3] expectedDirection = zero3();
    if (expectedMagnitude > MIN_HORIZONTAL_MAGNITUDE) {
        expectedDirection = scale3(expectedHorizontal, 1.0f / expectedMagnitude);
    }
    float progress = horizontalProgress(context, expectedDirection, startPosition, state.position);

    bool climbing = false;
    if (startedOnGround && !context.jumpInput && expectedMagnitude > MIN_BLOCKED_MAGNITUDE && progress < expectedMagnitude * BLOCKED_PROGRESS_FRACTION && canHopOver(context, state.position, expectedDirection, expectedMagnitude)) {
        float[3] runVelocity = scale3(context.movementInput, context.cfg.maxGroundSpeed);
        state.velocity = add3(runVelocity, scale3(context.up, context.cfg.autoClimbSpeed));
        hasGroundNormal = false;
        climbing = true;
    }

    if (startedOnGround && !context.jumpInput && !climbing && !hasGroundNormal) {
        SettleResult settled = settleToGround(context, state.position, context.cfg.stepHeight + context.cfg.groundDistanceTolerance);
        if (settled.found) {
            float budget = context.cfg.autoClimbSpeed * context.dtSeconds;
            if (-verticalGain(context, state.position, settled.position) <= budget) {
                state.position = settled.position;
            } else {
                state.position.local = state.position.local * MIsometry!float.translationAlong(scale3(neg3(context.up), budget));
            }
            hasGroundNormal = true;
            groundNormal = settled.normal;
        }
    }

    if (hasGroundNormal && !climbing) {
        state.velocity = projectToPlane(state.velocity, groundNormal, context.up, 0.0f);
    }
    state.onGround = hasGroundNormal;
}

bool canHopOver(const(CharacterControllerContext)* context, Position position, float[3] expectedDirection, float expectedMagnitude) {
    Motion probe = Motion(position, zero3(), zero3(), false);
    applyVelocity(context, scale3(context.up, context.cfg.stepHeight), &probe);
    bool result = false;
    if (!(verticalGain(context, position, probe.position) < context.cfg.stepHeight * HOP_GAIN_FRACTION)) {
        Position raised = probe.position;
        probe.hasGroundNormal = false;
        applyVelocity(context, scale3(expectedDirection, context.cfg.characterRadius + expectedMagnitude), &probe);
        result = horizontalProgress(context, expectedDirection, raised, probe.position) > context.cfg.characterRadius * HOP_PROGRESS_FRACTION;
    }
    return result;
}

float verticalGain(const(CharacterControllerContext)* context, Position start, Position end) {
    MPoint!float moved = (start.local.inverse() * end.local) * MPoint!float.origin();
    return dot3(moved.vec.xyz(), context.up);
}

SettleResult settleToGround(const(CharacterControllerContext)* context, Position position, float distance) {
    Motion probe = Motion(position, zero3(), zero3(), false);
    applyVelocity(context, scale3(neg3(context.up), distance), &probe);
    GroundContact contact = GroundContact(probe.groundNormal, probe.hasGroundNormal);
    if (!contact.found) {
        contact = getGroundNormal(context, probe.position);
    }
    SettleResult result;
    result.position = position;
    if (contact.found) {
        result.position = probe.position;
        result.normal = contact.normal;
        result.found = true;
    }
    return result;
}

float horizontalProgress(const(CharacterControllerContext)* context, float[3] intendedDirection, Position start, Position end) {
    MPoint!float moved = (start.local.inverse() * end.local) * MPoint!float.origin();
    float[3] delta = moved.vec.xyz();
    float[3] horizontal = sub3(delta, scale3(context.up, dot3(delta, context.up)));
    return dot3(horizontal, intendedDirection);
}

void runFlyCharacterStep(const(CharacterControllerContext)* context, CharacterState* state) {
    state.velocity = scale3(context.movementInput, context.cfg.flyMovementSpeed);
    state.onGround = false;
    Motion motion = Motion(state.position, state.velocity, zero3(), false);
    applyVelocity(context, scale3(state.velocity, context.dtSeconds), &motion);
    state.position = motion.position;
    state.velocity = motion.velocity;
}

void runNoClipCharacterStep(const(CharacterControllerContext)* context, CharacterState* state) {
    state.velocity = scale3(context.movementInput, context.cfg.noClipMovementSpeed);
    state.onGround = false;
    state.position.local = state.position.local * MIsometry!float.translationAlong(scale3(state.velocity, context.dtSeconds));
}

GroundContact getGroundNormal(const(CharacterControllerContext)* context, Position position) {
    BoundedVectors allowed = createBoundedVectors(scale3(neg3(context.up), context.cfg.groundDistanceTolerance), false, zero3());
    GroundContact contact;
    bool searching = true;
    uint iteration = 0;
    while (searching && iteration < MAX_COLLISION_ITERATIONS) {
        CollisionCheckingResult collision = checkCollision(&context.collisionContext, position, allowed.displacement);
        if (!collision.hasCollision) {
            searching = false;
        } else if (isGround(context, collision.normal)) {
            contact.normal = collision.normal;
            contact.found = true;
            searching = false;
        } else {
            allowed.addBound(VectorBound(collision.normal, collision.normal, true));
        }
        iteration += 1;
    }
    return contact;
}

bool isGround(const(CharacterControllerContext)* context, float[3] normal) {
    float slope = context.cfg.maxGroundSlope;
    return dot3(normal, context.up) > 1.0f / sqrt(slope * slope + 1.0f);
}

float[3] applyGroundControls(const(CharacterControllerContext)* context, float[3] groundNormal, float[3] velocity) {
    float movementNorm = magnitude3(context.movementInput);
    float[3] targetGroundVelocity = zero3();
    if (movementNorm >= MIN_INPUT_MAGNITUDE) {
        float[3] unitMovement = projectToPlane(scale3(context.movementInput, 1.0f / movementNorm), groundNormal, context.up, 0.0f);
        float unitMagnitude = magnitude3(unitMovement);
        if (unitMagnitude >= MIN_INPUT_MAGNITUDE) {
            unitMovement = scale3(unitMovement, 1.0f / unitMagnitude);
        }
        targetGroundVelocity = scale3(unitMovement, movementNorm * context.cfg.maxGroundSpeed);
    }
    float[3] currentToTarget = sub3(targetGroundVelocity, projectToPlane(velocity, groundNormal, context.up, 0.0f));
    float maxDeltaVelocity = context.cfg.groundAcceleration * context.dtSeconds;
    float distanceSquared = dot3(currentToTarget, currentToTarget);
    float[3] result = add3(velocity, currentToTarget);
    if (distanceSquared > maxDeltaVelocity * maxDeltaVelocity) {
        result = add3(velocity, scale3(currentToTarget, maxDeltaVelocity / sqrt(distanceSquared)));
    }
    return result;
}

float[3] applyAirControls(const(CharacterControllerContext)* context, float[3] velocity) {
    return add3(velocity, scale3(context.movementInput, context.cfg.airAcceleration * context.dtSeconds));
}

void applyVelocity(const(CharacterControllerContext)* context, float[3] expectedDisplacement, Motion* motion) {
    BoundedVectors bounded = createBoundedVectors(expectedDisplacement, true, motion.velocity);
    BoundedVectors withoutCollisions = bounded;
    bool groundCollisionHandled = false;
    bool resolving = true;
    uint iteration = 0;
    while (resolving && iteration < MAX_COLLISION_ITERATIONS) {
        CollisionCheckingResult collision = checkCollision(&context.collisionContext, motion.position, bounded.displacement);
        motion.position.local = motion.position.local * collision.displacementTransform;
        if (collision.hasCollision) {
            float displacementMagnitude = magnitude3(bounded.displacement);
            float reductionFactor = 1.0f;
            if (displacementMagnitude > MIN_DISPLACEMENT_MAGNITUDE) {
                reductionFactor = 1.0f - magnitude3(collision.displacementVector) / displacementMagnitude;
            }
            bounded.scaleDisplacement(reductionFactor);
            withoutCollisions.scaleDisplacement(reductionFactor);
            handleCollision(context, collision.normal, &withoutCollisions, &bounded, motion, &groundCollisionHandled);
        } else {
            resolving = false;
        }
        iteration += 1;
    }
    if (bounded.hasVelocity) {
        motion.velocity = bounded.velocity;
    }
}

void handleCollision(const(CharacterControllerContext)* context, float[3] normal, const(BoundedVectors)* withoutCollisions, BoundedVectors* bounded, Motion* motion, bool* groundCollisionHandled) {
    if (isGround(context, normal)) {
        if (!*groundCollisionHandled) {
            BoundedVectors previous = *bounded;
            *bounded = *withoutCollisions;
            bounded.addTempBound(VectorBound(normal, context.up, false));
            bounded.addBound(VectorBound(normal, context.up, true));
            foreach (i; 0 .. previous.boundCount) {
                bounded.addBound(previous.bounds[i]);
            }
            bounded.clearTempBounds();
            *groundCollisionHandled = true;
        } else {
            bounded.addTempBound(VectorBound(normal, context.up, false));
            bounded.addBound(VectorBound(normal, context.up, true));
            bounded.clearTempBounds();
        }
        motion.hasGroundNormal = true;
        motion.groundNormal = normal;
    } else {
        if (motion.hasGroundNormal) {
            bounded.addTempBound(VectorBound(motion.groundNormal, context.up, false));
        }
        bounded.addBound(VectorBound(normal, normal, true));
        bounded.clearTempBounds();
    }
}

float[3] capMagnitude(float[3] v, float maxMagnitude) {
    float magnitudeSquared = dot3(v, v);
    float[3] result = v;
    if (magnitudeSquared > maxMagnitude * maxMagnitude) {
        result = scale3(v, maxMagnitude / sqrt(magnitudeSquared));
    }
    return result;
}

float[3] getRelativeUp(const(Graph)* graph, Position position) {
    float[3] result = [0.0f, 1.0f, 0.0f];
    const(NodeState)* state = graph.nodeState(position.node);
    if (state !is null) {
        float[3] up = (position.local.inverse() * state.surface.scaledNormal).xyz();
        float length = sqrt(up[0] * up[0] + up[1] * up[1] + up[2] * up[2]);
        if (!(length < MIN_UP_LENGTH || isNan(length))) {
            result = [up[0] / length, up[1] / length, up[2] / length];
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
