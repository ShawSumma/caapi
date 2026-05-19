module common.character_controller.collision;

import std.math : sqrt, tanh, atanh, isNaN;

import common.math : MPoint, MDirection, MIsometry, MVector;
import common.collision_math : Ray;
import common.graph : Graph, NodeId;
import common.graph_collision : GraphCollisionHit, sphereCast;
import common.proto : Position;
import common.character_controller.vector_bounds : magnitude3, scale3, zero3;

struct CollisionContext {
    const(Graph)* graph;
    float radius;
}

struct CollisionCheckingResult {
    float[3] displacementVector;
    MIsometry!float displacementTransform;
    Collision* collision;
    Collision _collisionStorage;

    static CollisionCheckingResult stationary() {
        CollisionCheckingResult r;
        r.displacementVector = zero3();
        r.displacementTransform = MIsometry!float.identity();
        r.collision = null;
        return r;
    }
}

struct Collision {
    float[3] normal;
}

CollisionCheckingResult checkCollision(
    const ref CollisionContext collisionContext,
    const ref Position position,
    const float[3] relativeDisplacement,
) {
    float displacementSqr = relativeDisplacement[0] * relativeDisplacement[0]
        + relativeDisplacement[1] * relativeDisplacement[1]
        + relativeDisplacement[2] * relativeDisplacement[2];

    if (displacementSqr < 1e-16) {
        return CollisionCheckingResult.stationary();
    }

    float displacementNorm = sqrt(displacementSqr);
    float[3] displacementNormalized = [
        relativeDisplacement[0] / displacementNorm,
        relativeDisplacement[1] / displacementNorm,
        relativeDisplacement[2] / displacementNorm,
    ];

    Ray ray = Ray(
        MPoint!float.origin(),
        MDirection!float(MVector!float(displacementNormalized[0], displacementNormalized[1], displacementNormalized[2], 0)),
    );
    float tanhDist = tanh(displacementNorm);

    bool outOfBounds;
    GraphCollisionHit castHit = sphereCast(
        collisionContext.radius,
        *collisionContext.graph,
        position.node,
        position.local,
        ray,
        tanhDist,
        outOfBounds,
    );

    float hitTanhDist = tanhDist;
    bool hasHit = !isNaN(castHit.tanhDistance);
    if (hasHit) {
        hitTanhDist = castHit.tanhDistance;
    }

    float distance = atanh(hitTanhDist);

    float[3] displacementVector = scale3(displacementNormalized, distance);
    MIsometry!float displacementTransform = MIsometry!float.translationAlong(displacementVector);

    CollisionCheckingResult result;
    result.displacementVector = displacementVector;
    result.displacementTransform = displacementTransform;

    if (hasHit) {
        MIsometry!float invTransform = displacementTransform.inverse();
        MVector!float transformedNormal = invTransform.mat * castHit.normal;
        float[3] normalXyz = transformedNormal.xyz();

        float normalMag = magnitude3(normalXyz);
        if (normalMag > 1e-16) {
            result._collisionStorage = Collision([
                normalXyz[0] / normalMag,
                normalXyz[1] / normalMag,
                normalXyz[2] / normalMag,
            ]);
        }
        else {
            result._collisionStorage = Collision([0.0f, 1.0f, 0.0f]);
        }
        result.collision = &result._collisionStorage;
    }
    else {
        result.collision = null;
    }

    return result;
}
