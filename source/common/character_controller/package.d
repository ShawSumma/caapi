module common.character_controller;

import std.math : sqrt, exp, isNaN;

import common.math : MIsometry, MPoint, projectToPlane, sanitizeMotionInput;
import common.graph : Graph, NodeId;
import common.proto : Position, CharacterInput;
import common.sim_config : SimConfig, CharacterConfig;
import common.character_controller.collision : CollisionContext, CollisionCheckingResult, Collision, checkCollision;
import common.character_controller.vector_bounds : BoundedVectors, VectorBound, dot3, magnitude3, scale3, add3, sub3, neg3, normalize3, zero3, isZero3;

void runCharacterStep(
    const ref SimConfig simConfig,
    const ref Graph graph,
    ref Position position,
    ref float[3] velocity,
    ref bool onGround,
    const ref CharacterInput input,
    float dtSeconds,
) {
    CharacterControllerContext ctx = CharacterControllerContext(
        CollisionContext(&graph, simConfig.character.characterRadius),
        getRelativeUp(&graph, &position),
        &simConfig.character,
        dtSeconds,
        sanitizeMotionInput(input.movement),
        input.jump,
    );

    if (input.noClip) {
        runNoClipCharacterStep(ctx, position, velocity, onGround);
    }
    else {
        runStandardCharacterStep(ctx, position, velocity, onGround);
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
    applyVelocity(ctx, expectedDisplacement, position, velocity, hasGroundNormal, groundNormal);

    onGround = hasGroundNormal;
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

        if (collisionResult.collision !is null) {
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

float[3] getRelativeUp(const Graph* graph, const Position* position) {
    return [0.0f, 1.0f, 0.0f];
}

struct CharacterControllerContext {
    CollisionContext collisionContext;
    float[3] up;
    const(CharacterConfig)* cfg;
    float dtSeconds;
    float[3] movementInput;
    bool jumpInput;
}
