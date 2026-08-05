module common.character_controller;

import common.math : MIsometry, MPoint, MVector;
import common.math : projectToPlane, sanitizeMotionInput;
import common.math : exp, isNaN, sqrt;
import common.graph : Graph, NodeId;
import common.graph_collision : regionPopulated;
import common.worldgen : NodeState;
import common.proto : Position, CharacterInput;
import common.sim_config : SimConfig, CharacterConfig;
import common.character_controller.collision : CollisionContext;
import common.character_controller.collision : CollisionCheckingResult;
import common.character_controller.collision : Collision, checkCollision;
import common.character_controller.vector_bounds : BoundedVectors, VectorBound;
import common.character_controller.vector_bounds : dot3, magnitude3, scale3;
import common.character_controller.vector_bounds : add3, sub3, neg3;
import common.character_controller.vector_bounds : normalize3, zero3, isZero3;

void runCharacterStep(
    const ref SimConfig simConfig,
    const ref Graph graph,
    ref Position position,
    ref float[3] velocity,
    ref bool onGround,
    const ref CharacterInput input,
    float dtSeconds,
) {
    float[3] up = getRelativeUp(&graph, &position);
    CharacterControllerContext ctx = CharacterControllerContext(
        CollisionContext(&graph, simConfig.character.characterRadius,
            simConfig.character.characterHalfHeight, up),
        up,
        &simConfig.character,
        dtSeconds,
        sanitizeMotionInput(input.movement),
        input.jump,
    );

    if (input.noClip) {
        runNoClipCharacterStep(ctx, position, velocity, onGround);
    }
    else {
        // Unloaded world is impassable: freeze until generation catches up,
        // or async chunks would materialize around the body and embed it.
        float regionReach = simConfig.character.characterHalfHeight
            + simConfig.character.characterRadius
            + simConfig.character.groundDistanceTolerance;
        if (!regionPopulated(graph, position.node, position.local, regionReach)) {
            velocity = [0, 0, 0];
            return;
        }

        if (input.fly) {
            runFlyCharacterStep(ctx, position, velocity, onGround);
        }
        else {
            runStandardCharacterStep(ctx, position, velocity, onGround);
        }
    }

    position.local = position.local.renormalized();
    NodeId nextNode = graph.normalizeTransform(position.node, position.local);
    if (nextNode != position.node) {
        position.node = nextNode;
    }
}

void runStandardCharacterStep(
    const ref CharacterControllerContext ctx,
    ref Position position,
    ref float[3] velocity,
    ref bool onGround,
) {
    bool startedOnGround = onGround;
    bool hasGroundNormal = false;
    float[3] groundNormal = zero3();

    if (onGround) {
        hasGroundNormal = getGroundNormal(ctx, position, groundNormal);
    }

    if (ctx.jumpInput && hasGroundNormal) {
        float upDotVel = dot3(ctx.up, velocity);
        float[3] horizontalVelocity = sub3(velocity, scale3(ctx.up, upDotVel));
        velocity = add3(horizontalVelocity, scale3(ctx.up, ctx.cfg.jumpSpeed));
        hasGroundNormal = false;
    }

    float[3] oldVelocity = velocity;

    if (hasGroundNormal) {
        applyGroundControls(ctx, groundNormal, velocity);
    }
    else {
        applyAirControls(ctx, velocity);
        float factor = exp(-ctx.cfg.airResistance * ctx.dtSeconds);
        velocity = scale3(velocity, factor);
    }

    velocity = sub3(velocity, scale3(ctx.up, ctx.cfg.gravityAcceleration * ctx.dtSeconds));

    velocity = capMagnitude(velocity, ctx.cfg.speedCap);

    float[3] averageVelocity = scale3(add3(velocity, oldVelocity), 0.5f);

    float[3] expectedDisplacement = scale3(averageVelocity, ctx.dtSeconds);

    Position startPos = position;
    applyVelocity(ctx, expectedDisplacement, position, velocity, hasGroundNormal, groundNormal);

    float expUp = dot3(expectedDisplacement, ctx.up);
    float[3] expHorizontal = sub3(expectedDisplacement, scale3(ctx.up, expUp));
    float expHMag = magnitude3(expHorizontal);
    float[3] expDir = expHMag > 1e-9f ? scale3(expHorizontal, 1.0f / expHMag) : zero3();
    float progress = horizontalProgress(ctx, expDir, startPos, position);

    bool climbing = false;
    if (startedOnGround && !ctx.jumpInput && expHMag > 1e-6f && progress < expHMag * 0.5f) {
        // Grounded motion is blocked. With gravity diagonal to the voxel
        // lattice the terrain is corrugated staircases; a steppable riser is
        // cleared with a minimal ballistic hop (just over one block — the
        // flight arc supplies the forward travel a single frame can't), and
        // the camera smoothing absorbs the vertical motion. Probe first so
        // walls and low ceilings don't trigger hopping.
        if (canHopOver(ctx, position, expDir, expHMag)) {
            float[3] runVelocity = scale3(ctx.movementInput, ctx.cfg.maxGroundSpeed);
            velocity = add3(runVelocity, scale3(ctx.up, ctx.cfg.autoClimbSpeed));
            hasGroundNormal = false;
            climbing = true;
        }
    }

    // Ground snap: a grounded character that didn't jump is constrained to
    // the walking surface — including down a step. The descent is rate
    // limited so stepping off a ledge glides instead of teleporting; drops
    // deeper than stepHeight leave the ground normally.
    if (startedOnGround && !ctx.jumpInput && !climbing && !hasGroundNormal) {
        float[3] snapNormal = zero3();
        Position snapped = position;
        if (settleToGround(ctx, snapped,
                ctx.cfg.stepHeight + ctx.cfg.groundDistanceTolerance, snapNormal)) {
            float drop = -verticalGain(ctx, position, snapped);
            float budget = ctx.cfg.autoClimbSpeed * ctx.dtSeconds;
            if (drop <= budget) {
                position = snapped;
            } else {
                position.local = position.local
                    * MIsometry!float.translationAlong(scale3(neg3(ctx.up), budget));
            }
            hasGroundNormal = true;
            groundNormal = snapNormal;
        }
    }

    // While grounded, velocity lives in the contact plane: project out any
    // residual vertical component (kept for slopes by projecting along up).
    // Climb frames keep their injected vertical velocity.
    if (hasGroundNormal && !climbing) {
        projectToPlane(velocity, groundNormal, ctx.up, 0.0f);
    }

    onGround = hasGroundNormal;
}

/// Probe for auto-jump: is there headroom above, and does the space at
/// raised height open up in the direction of travel? Tall walls fail the
/// forward probe; low ceilings fail the headroom probe.
bool canHopOver(
    const ref CharacterControllerContext ctx,
    const ref Position pos,
    const float[3] expDir,
    float expHMag,
) {
    Position probe = pos;
    float[3] dummyVel = zero3();
    bool dummyGround = false;
    float[3] dummyNormal = zero3();

    applyVelocity(ctx, scale3(ctx.up, ctx.cfg.stepHeight),
        probe, dummyVel, dummyGround, dummyNormal);
    if (verticalGain(ctx, pos, probe) < ctx.cfg.stepHeight * 0.5f) {
        return false;
    }

    Position raised = probe;
    float probeDist = ctx.cfg.characterRadius + expHMag;
    dummyGround = false;
    applyVelocity(ctx, scale3(expDir, probeDist),
        probe, dummyVel, dummyGround, dummyNormal);
    return horizontalProgress(ctx, expDir, raised, probe) > ctx.cfg.characterRadius * 0.5f;
}

float verticalGain(
    const ref CharacterControllerContext ctx,
    const ref Position start,
    const ref Position end,
) {
    MIsometry!float rel = start.local.inverse() * end.local;
    MPoint!float p = rel * MPoint!float.origin();
    return dot3(p.vec.xyz(), ctx.up);
}

/// Sweeps the position down by `dist` with constraint sliding and reports
/// whether it ends up standing on walkable ground; only then is the position
/// updated.
bool settleToGround(
    const ref CharacterControllerContext ctx,
    ref Position pos,
    float dist,
    ref float[3] outNormal,
) {
    float[3] dummyVel = zero3();
    bool ground = false;
    float[3] normal = zero3();
    Position p = pos;
    applyVelocity(ctx, scale3(neg3(ctx.up), dist), p, dummyVel, ground, normal);
    if (!ground) {
        ground = getGroundNormal(ctx, p, normal);
    }
    if (ground) {
        pos = p;
        outNormal = normal;
        return true;
    }
    return false;
}

/// Progress along the intended horizontal direction between two positions in
/// the same node frame (small-displacement approximation in the start frame).
/// Directional on purpose: sliding sideways along a wall is not progress.
float horizontalProgress(
    const ref CharacterControllerContext ctx,
    const float[3] intendedDir,
    const ref Position start,
    const ref Position end,
) {
    MIsometry!float rel = start.local.inverse() * end.local;
    MPoint!float p = rel * MPoint!float.origin();
    float[3] d = p.vec.xyz();
    float dUp = dot3(d, ctx.up);
    float[3] horizontal = sub3(d, scale3(ctx.up, dUp));
    return dot3(horizontal, intendedDir);
}

/// Creative-style flight: no gravity, full collision.
void runFlyCharacterStep(
    const ref CharacterControllerContext ctx,
    ref Position position,
    ref float[3] velocity,
    ref bool onGround,
) {
    velocity = scale3(ctx.movementInput, ctx.cfg.flyMovementSpeed);
    onGround = false;
    float[3] displacement = scale3(velocity, ctx.dtSeconds);
    bool hasGroundNormal = false;
    float[3] groundNormal = zero3();
    applyVelocity(ctx, displacement, position, velocity, hasGroundNormal, groundNormal);
}

void runNoClipCharacterStep(
    const ref CharacterControllerContext ctx,
    ref Position position,
    ref float[3] velocity,
    ref bool onGround,
) {
    velocity = scale3(ctx.movementInput, ctx.cfg.noClipMovementSpeed);
    onGround = false;
    position.local = position.local * MIsometry!float.translationAlong(scale3(velocity, ctx.dtSeconds));
}

bool getGroundNormal(
    const ref CharacterControllerContext ctx,
    const ref Position position,
    ref float[3] outNormal,
) {
    int maxCollisionIterations = 6;
    BoundedVectors allowedDisplacement = BoundedVectors.create(
        scale3(neg3(ctx.up), ctx.cfg.groundDistanceTolerance),
        false,
    );

    foreach (_; 0 .. maxCollisionIterations) {
        CollisionCheckingResult collisionResult = checkCollision(
            ctx.collisionContext,
            position,
            allowedDisplacement.getDisplacement(),
        );
        if (collisionResult.hasCollision) {
            if (isGround(ctx, collisionResult.collision.normal)) {
                outNormal = collisionResult.collision.normal;
                return true;
            }
            allowedDisplacement.addBound(VectorBound.create(
                collisionResult.collision.normal,
                collisionResult.collision.normal,
                true,
            ));
        }
        else {
            return false;
        }
    }
    return false;
}

bool isGround(const ref CharacterControllerContext ctx, const float[3] normal) {
    float minSlopeUpComponent = 1.0f / sqrt(ctx.cfg.maxGroundSlope * ctx.cfg.maxGroundSlope + 1.0f);
    return dot3(normal, ctx.up) > minSlopeUpComponent;
}

void applyGroundControls(
    const ref CharacterControllerContext ctx,
    const float[3] groundNormal,
    ref float[3] velocity,
) {
    float movementNorm = magnitude3(ctx.movementInput);
    float[3] targetGroundVelocity = zero3();

    if (movementNorm >= 1e-16) {
        float[3] unitMovement = scale3(ctx.movementInput, 1.0f / movementNorm);
        projectToPlane(unitMovement, groundNormal, ctx.up, 0.0f);
        float um = magnitude3(unitMovement);
        if (um >= 1e-16) {
            unitMovement = scale3(unitMovement, 1.0f / um);
        }
        targetGroundVelocity = scale3(unitMovement, movementNorm * ctx.cfg.maxGroundSpeed);
    }

    float[3] groundVelocity = velocity;
    projectToPlane(groundVelocity, groundNormal, ctx.up, 0.0f);

    float[3] currentToTarget = sub3(targetGroundVelocity, groundVelocity);
    float maxDeltaVelocity = ctx.cfg.groundAcceleration * ctx.dtSeconds;
    float ctNormSq = dot3(currentToTarget, currentToTarget);

    if (ctNormSq > maxDeltaVelocity * maxDeltaVelocity) {
        float ctNorm = sqrt(ctNormSq);
        velocity = add3(velocity, scale3(currentToTarget, maxDeltaVelocity / ctNorm));
    }
    else {
        velocity = add3(velocity, currentToTarget);
    }
}

void applyAirControls(const ref CharacterControllerContext ctx, ref float[3] velocity) {
    velocity = add3(velocity, scale3(ctx.movementInput, ctx.cfg.airAcceleration * ctx.dtSeconds));
}

void applyVelocity(
    const ref CharacterControllerContext ctx,
    float[3] expectedDisplacement,
    ref Position position,
    ref float[3] velocity,
    ref bool hasGroundNormal,
    ref float[3] groundNormal,
) {
    int maxCollisionIterations = 6;

    BoundedVectors boundedVectors = BoundedVectors.create(expectedDisplacement, true, velocity);
    BoundedVectors boundedVectorsWithoutCollisions = boundedVectors.dup();

    bool groundCollisionHandled = false;
    bool allCollisionsResolved = false;

    foreach (_; 0 .. maxCollisionIterations) {
        CollisionCheckingResult collisionResult = checkCollision(
            ctx.collisionContext,
            position,
            boundedVectors.getDisplacement(),
        );
        position.local = position.local * collisionResult.displacementTransform;

        if (collisionResult.hasCollision) {
            float dispMag = magnitude3(boundedVectors.getDisplacement());
            float reductionFactor = 1.0f;
            if (dispMag > 1e-16) {
                reductionFactor = 1.0f - magnitude3(collisionResult.displacementVector) / dispMag;
            }
            boundedVectors.scaleDisplacement(reductionFactor);
            boundedVectorsWithoutCollisions.scaleDisplacement(reductionFactor);

            handleCollision(
                ctx,
                collisionResult.collision,
                boundedVectorsWithoutCollisions,
                boundedVectors,
                hasGroundNormal,
                groundNormal,
                groundCollisionHandled,
            );
        }
        else {
            allCollisionsResolved = true;
            break;
        }
    }

    if (boundedVectors.hasVelocity) {
        velocity = boundedVectors.getVelocity();
    }
}

void handleCollision(
    const ref CharacterControllerContext ctx,
    const ref Collision collision,
    const ref BoundedVectors boundedVectorsWithoutCollisions,
    ref BoundedVectors boundedVectors,
    ref bool hasGroundNormal,
    ref float[3] groundNormal,
    ref bool groundCollisionHandled,
) {
    if (isGround(ctx, collision.normal)) {
        if (!groundCollisionHandled) {
            const(VectorBound)[] oldBounds = boundedVectors.getBounds();
            boundedVectors = boundedVectorsWithoutCollisions.dup();
            boundedVectors.addTempBound(VectorBound.create(collision.normal, ctx.up, false));
            boundedVectors.addBound(VectorBound.create(collision.normal, ctx.up, true));
            foreach (ref bound; oldBounds) {
                boundedVectors.addBound(bound);
            }
            boundedVectors.clearTempBounds();
            groundCollisionHandled = true;
        }
        else {
            boundedVectors.addTempBound(VectorBound.create(collision.normal, ctx.up, false));
            boundedVectors.addBound(VectorBound.create(collision.normal, ctx.up, true));
            boundedVectors.clearTempBounds();
        }
        hasGroundNormal = true;
        groundNormal = collision.normal;
    }
    else {
        if (hasGroundNormal) {
            boundedVectors.addTempBound(VectorBound.create(groundNormal, ctx.up, false));
        }
        boundedVectors.addBound(VectorBound.create(collision.normal, collision.normal, true));
        boundedVectors.clearTempBounds();
    }
}

float[3] capMagnitude(float[3] v, float maxMag) {
    float magSq = dot3(v, v);
    if (magSq > maxMag * maxMag) {
        float mag = sqrt(magSq);
        return scale3(v, maxMag / mag);
    }
    return v;
}

/// "Up" at a place, derived from the world rather than carried along with
/// the character: the direction of increasing distance to the node's terrain
/// surface plane, expressed in the character's local frame. Re-anchoring to
/// this every step is what keeps holonomy from accumulating into the frame —
/// transporting a frame around a loop in hyperbolic space rotates it, but a
/// reference recomputed from world geometry can't drift.
float[3] getRelativeUp(const Graph* graph, const Position* position) {
    const(NodeState)* state = null;
    if (graph.contains(position.node)) {
        state = graph.nodeState(position.node);
    }
    if (state is null) {
        return [0.0f, 1.0f, 0.0f];
    }

    // The gradient of the plane's signed distance, projected into the tangent
    // space at the character's origin, is just the spatial part of the plane
    // normal expressed in that frame.
    MVector!float n = position.local.inverse() * state.surface.scaledNormal;
    float[3] up = n.xyz();
    float len = sqrt(up[0] * up[0] + up[1] * up[1] + up[2] * up[2]);
    if (len < 1e-9f || isNaN(len)) {
        return [0.0f, 1.0f, 0.0f];
    }
    return [up[0] / len, up[1] / len, up[2] / len];
}

unittest {
    // Moving along the reported up direction must increase the distance to
    // the node's surface plane.
    Graph graph = Graph.create(12);
    graph.ensureNodeState(NodeId.ROOT);
    Position pos = Position.origin();

    float[3] up = getRelativeUp(&graph, &pos);
    const(NodeState)* state = graph.nodeState(NodeId.ROOT);
    MPoint!float p0 = pos.local * MPoint!float.origin();
    float d0 = state.surface.distanceTo(p0);

    pos.local = pos.local * MIsometry!float.translationAlong([up[0] * 0.1f, up[1] * 0.1f, up[2] * 0.1f]);
    MPoint!float p1 = pos.local * MPoint!float.origin();
    float d1 = state.surface.distanceTo(p1);

    assert(d1 > d0 + 0.05f);
}

struct CharacterControllerContext {
    CollisionContext collisionContext;
    float[3] up;
    const(CharacterConfig)* cfg;
    float dtSeconds;
    float[3] movementInput;
    bool jumpInput;
}
