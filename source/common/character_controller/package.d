/// Character controller - runs character physics step with collision handling.
module common.character_controller;

import std.math : sqrt, exp, isNaN;

import common.math : MIsometry, MPoint, projectToPlane, sanitizeMotionInput;
import common.graph : Graph, NodeId;
import common.proto : Position, CharacterInput;
import common.sim_config : SimConfig, CharacterConfig;
import common.character_controller.collision : CollisionContext, CollisionCheckingResult, Collision, checkCollision;
import common.character_controller.vector_bounds : BoundedVectors, VectorBound, dot3, magnitude3, scale3, add3, sub3, neg3, normalize3, zero3, isZero3;

/// Runs a single step of character movement
void runCharacterStep(
    const ref SimConfig simConfig,
    const ref Graph graph,
    ref Position position,
    ref float[3] velocity,
    ref bool onGround,
    const ref CharacterInput input,
    float dtSeconds,
) {
    auto ctx = CharacterControllerContext(
        CollisionContext(&graph, simConfig.character.characterRadius),
        getRelativeUp(&graph, &position),
        &simConfig.character,
        dtSeconds,
        sanitizeMotionInput(input.movement),
        input.jump,
    );

    if (input.noClip) {
        runNoClipCharacterStep(ctx, position, velocity, onGround);
    } else {
        runStandardCharacterStep(ctx, position, velocity, onGround);
    }

    // Renormalize
    position.local = position.local.renormalized();
    auto nextNode = graph.normalizeTransform(position.node, position.local);
    if (nextNode != position.node) {
        position.node = nextNode;
    }
}

private void runStandardCharacterStep(
    const ref CharacterControllerContext ctx,
    ref Position position,
    ref float[3] velocity,
    ref bool onGround,
) {
    bool hasGroundNormal = false;
    float[3] groundNormal = zero3();

    if (onGround) {
        hasGroundNormal = getGroundNormal(ctx, position, groundNormal);
    }

    // Handle jumping
    if (ctx.jumpInput && hasGroundNormal) {
        float upDotVel = dot3(ctx.up, velocity);
        float[3] horizontalVelocity = sub3(velocity, scale3(ctx.up, upDotVel));
        velocity = add3(horizontalVelocity, scale3(ctx.up, ctx.cfg.jumpSpeed));
        hasGroundNormal = false;
    }

    float[3] oldVelocity = velocity;

    // Update velocity
    if (hasGroundNormal) {
        applyGroundControls(ctx, groundNormal, velocity);
    } else {
        applyAirControls(ctx, velocity);
        // Apply air resistance
        float factor = exp(-ctx.cfg.airResistance * ctx.dtSeconds);
        velocity = scale3(velocity, factor);
    }

    // Apply gravity
    velocity = sub3(velocity, scale3(ctx.up, ctx.cfg.gravityAcceleration * ctx.dtSeconds));

    // Apply speed cap
    velocity = capMagnitude(velocity, ctx.cfg.speedCap);

    // Average velocity for smoother movement
    float[3] averageVelocity = scale3(add3(velocity, oldVelocity), 0.5f);

    // Handle actual movement
    float[3] expectedDisplacement = scale3(averageVelocity, ctx.dtSeconds);
    applyVelocity(ctx, expectedDisplacement, position, velocity, hasGroundNormal, groundNormal);

    onGround = hasGroundNormal;
}

private void runNoClipCharacterStep(
    const ref CharacterControllerContext ctx,
    ref Position position,
    ref float[3] velocity,
    ref bool onGround,
) {
    velocity = scale3(ctx.movementInput, ctx.cfg.noClipMovementSpeed);
    onGround = false;
    position.local = position.local * MIsometry!float.translationAlong(scale3(velocity, ctx.dtSeconds));
}

/// Returns the normal corresponding to the ground below the character.
private bool getGroundNormal(
    const ref CharacterControllerContext ctx,
    const ref Position position,
    ref float[3] outNormal,
) {
    enum MAX_COLLISION_ITERATIONS = 6;
    auto allowedDisplacement = BoundedVectors.create(
        scale3(neg3(ctx.up), ctx.cfg.groundDistanceTolerance),
        false,
    );

    foreach (_; 0 .. MAX_COLLISION_ITERATIONS) {
        auto collisionResult = checkCollision(
            ctx.collisionContext,
            position,
            allowedDisplacement.getDisplacement(),
        );
        if (collisionResult.collision !is null) {
            if (isGround(ctx, collisionResult.collision.normal)) {
                outNormal = collisionResult.collision.normal;
                return true;
            }
            allowedDisplacement.addBound(VectorBound.create(
                collisionResult.collision.normal,
                collisionResult.collision.normal,
                true,
            ));
        } else {
            return false;
        }
    }
    return false;
}

/// Checks whether the given normal is flat enough to be considered ground
private bool isGround(const ref CharacterControllerContext ctx, const float[3] normal) {
    float minSlopeUpComponent = 1.0f / sqrt(ctx.cfg.maxGroundSlope * ctx.cfg.maxGroundSlope + 1.0f);
    return dot3(normal, ctx.up) > minSlopeUpComponent;
}

/// Updates the velocity based on user input assuming the character is on the ground
private void applyGroundControls(
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

    // Get current ground-parallel velocity component
    float[3] groundVelocity = velocity;
    projectToPlane(groundVelocity, groundNormal, ctx.up, 0.0f);

    // Adjust toward target
    float[3] currentToTarget = sub3(targetGroundVelocity, groundVelocity);
    float maxDeltaVelocity = ctx.cfg.groundAcceleration * ctx.dtSeconds;
    float ctNormSq = dot3(currentToTarget, currentToTarget);

    if (ctNormSq > maxDeltaVelocity * maxDeltaVelocity) {
        float ctNorm = sqrt(ctNormSq);
        velocity = add3(velocity, scale3(currentToTarget, maxDeltaVelocity / ctNorm));
    } else {
        velocity = add3(velocity, currentToTarget);
    }
}

/// Updates the velocity based on user input assuming the character is in the air
private void applyAirControls(const ref CharacterControllerContext ctx, ref float[3] velocity) {
    velocity = add3(velocity, scale3(ctx.movementInput, ctx.cfg.airAcceleration * ctx.dtSeconds));
}

/// Updates the character's position based on the given average velocity while handling collisions.
private void applyVelocity(
    const ref CharacterControllerContext ctx,
    float[3] expectedDisplacement,
    ref Position position,
    ref float[3] velocity,
    ref bool hasGroundNormal,
    ref float[3] groundNormal,
) {
    enum MAX_COLLISION_ITERATIONS = 6;

    auto boundedVectors = BoundedVectors.create(expectedDisplacement, true, velocity);
    auto boundedVectorsWithoutCollisions = boundedVectors.dup();

    bool groundCollisionHandled = false;
    bool allCollisionsResolved = false;

    foreach (_; 0 .. MAX_COLLISION_ITERATIONS) {
        auto collisionResult = checkCollision(
            ctx.collisionContext,
            position,
            boundedVectors.getDisplacement(),
        );
        position.local = position.local * collisionResult.displacementTransform;

        if (collisionResult.collision !is null) {
            // Update expected displacement to represent reduction in remaining dt
            float dispMag = magnitude3(boundedVectors.getDisplacement());
            float reductionFactor = 1.0f;
            if (dispMag > 1e-16) {
                reductionFactor = 1.0f - magnitude3(collisionResult.displacementVector) / dispMag;
            }
            boundedVectors.scaleDisplacement(reductionFactor);
            boundedVectorsWithoutCollisions.scaleDisplacement(reductionFactor);

            handleCollision(
                ctx,
                *collisionResult.collision,
                boundedVectorsWithoutCollisions,
                boundedVectors,
                hasGroundNormal,
                groundNormal,
                groundCollisionHandled,
            );
        } else {
            allCollisionsResolved = true;
            break;
        }
    }

    if (boundedVectors.hasVelocity) {
        velocity = boundedVectors.getVelocity();
    }
}

/// Updates character information based on the results of a single collision
private void handleCollision(
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
            // Rewrite history: recompute as if ground collision was first
            auto oldBounds = boundedVectors.getBounds();
            boundedVectors = boundedVectorsWithoutCollisions.dup();
            boundedVectors.addTempBound(VectorBound.create(collision.normal, ctx.up, false));
            boundedVectors.addBound(VectorBound.create(collision.normal, ctx.up, true));
            foreach (ref bound; oldBounds) {
                boundedVectors.addBound(bound);
            }
            boundedVectors.clearTempBounds();
            groundCollisionHandled = true;
        } else {
            boundedVectors.addTempBound(VectorBound.create(collision.normal, ctx.up, false));
            boundedVectors.addBound(VectorBound.create(collision.normal, ctx.up, true));
            boundedVectors.clearTempBounds();
        }
        hasGroundNormal = true;
        groundNormal = collision.normal;
    } else {
        if (hasGroundNormal) {
            boundedVectors.addTempBound(VectorBound.create(groundNormal, ctx.up, false));
        }
        boundedVectors.addBound(VectorBound.create(collision.normal, collision.normal, true));
        boundedVectors.clearTempBounds();
    }
}

/// Cap the magnitude of a vector
private float[3] capMagnitude(float[3] v, float maxMag) {
    float magSq = dot3(v, v);
    if (magSq > maxMag * maxMag) {
        float mag = sqrt(magSq);
        return scale3(v, maxMag / mag);
    }
    return v;
}

/// Get the relative up direction for a position. Returns [0,1,0] as default.
private float[3] getRelativeUp(const Graph* graph, const Position* position) {
    // In hyperbolic space, "up" is typically the y-axis in the character's local frame.
    // This matches the Rust implementation's graph.get_relative_up which returns the
    // local up vector at the character's position.
    return [0.0f, 1.0f, 0.0f];
}

/// Contains all information about a character that the character controller doesn't change
/// during one of its simulation steps
private struct CharacterControllerContext {
    CollisionContext collisionContext;
    float[3] up;
    const(CharacterConfig)* cfg;
    float dtSeconds;
    float[3] movementInput;
    bool jumpInput;
}
