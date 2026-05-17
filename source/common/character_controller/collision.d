/// This module encapsulates character collision checking for the character controller.
module common.character_controller.collision;

import std.math : sqrt, tanh, atanh, isNaN;

import common.math : MPoint, MDirection, MIsometry, MVector;
import common.collision_math : Ray;
import common.graph : Graph, NodeId;
import common.graph_collision : GraphCollisionHit, sphereCast;
import common.proto : Position;
import common.character_controller.vector_bounds : magnitude3, scale3, zero3;

/// Contains information about the character and the world that is only relevant for collision checking
struct CollisionContext {
    const(Graph)* graph;
    float radius;
}

/// Result of a collision check
struct CollisionCheckingResult {
    /// The displacement allowed for the character before hitting a wall.
    float[3] displacementVector;

    /// Multiplying the character's position by this matrix will move the character as far as it can
    /// up to its intended displacement until it hits the wall.
    MIsometry!float displacementTransform;

    /// If a collision occurred, contains the collision info
    Collision* collision;

    // Storage for the collision (to avoid GC allocation in hot path)
    private Collision _collisionStorage;

    static CollisionCheckingResult stationary() {
        CollisionCheckingResult r;
        r.displacementVector = zero3();
        r.displacementTransform = MIsometry!float.identity();
        r.collision = null;
        return r;
    }
}

/// Contains collision normal facing away from the collision surface
struct Collision {
    /// Normal faces away from the collision surface, given in the perspective of the character
    /// after it is transformed by the allowed displacement. The 4th coordinate is assumed 0.
    float[3] normal;
}

/// Checks for collisions when a character moves with a character-relative displacement vector.
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

    // Create ray from origin in the displacement direction
    auto ray = Ray(
        MPoint!float.origin(),
        MDirection!float(MVector!float(displacementNormalized[0], displacementNormalized[1], displacementNormalized[2], 0)),
    );
    float tanhDist = tanh(displacementNorm);

    bool outOfBounds;
    auto castHit = sphereCast(
        collisionContext.radius,
        *collisionContext.graph,
        position.node,
        position.local,
        ray,
        tanhDist,
        outOfBounds,
    );

    // Determine actual distance
    float hitTanhDist = tanhDist;
    bool hasHit = !isNaN(castHit.tanhDistance);
    if (hasHit) {
        hitTanhDist = castHit.tanhDistance;
    }

    float distance = atanh(hitTanhDist);

    float[3] displacementVector = scale3(displacementNormalized, distance);
    auto displacementTransform = MIsometry!float.translationAlong(displacementVector);

    CollisionCheckingResult result;
    result.displacementVector = displacementVector;
    result.displacementTransform = displacementTransform;

    if (hasHit) {
        // Transform the hit normal to be relative to the character after displacement
        auto invTransform = displacementTransform.inverse();
        auto transformedNormal = invTransform.mat * castHit.normal;
        float[3] normalXyz = transformedNormal.xyz();

        // Normalize the xyz components
        float normalMag = magnitude3(normalXyz);
        if (normalMag > 1e-16) {
            result._collisionStorage = Collision([
                normalXyz[0] / normalMag,
                normalXyz[1] / normalMag,
                normalXyz[2] / normalMag,
            ]);
        } else {
            result._collisionStorage = Collision([0.0f, 1.0f, 0.0f]);
        }
        result.collision = &result._collisionStorage;
    } else {
        result.collision = null;
    }

    return result;
}
