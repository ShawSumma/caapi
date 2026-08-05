module common.character_controller.collision;

import common.math : MPoint, MDirection, MIsometry, MVector;
import common.math : atanh, isNaN, sqrt, tanh;
import common.collision_math : Ray;
import common.graph : Graph, NodeId;
import common.graph_collision : GraphCollisionHit, shapeCast;
import common.proto : Position;
import common.character_controller.vector_bounds : dot3, magnitude3, scale3, zero3;

struct CollisionContext {
    const(Graph)* graph;
    float radius;
    float halfHeight;
    float[3] up = [0, 1, 0];
}

struct CollisionCheckingResult {
    float[3] displacementVector;
    MIsometry!float displacementTransform;
    // Stored by value: a self-pointer here dangles when the struct is
    // returned without NRVO, which silently corrupted collision normals.
    bool hasCollision;
    Collision collision;

    static CollisionCheckingResult stationary() {
        CollisionCheckingResult r;
        r.displacementVector = zero3();
        r.displacementTransform = MIsometry!float.identity();
        r.hasCollision = false;
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

    GraphCollisionHit castHit = shapeCast(
        collisionContext.radius,
        collisionContext.halfHeight,
        collisionContext.up,
        *collisionContext.graph,
        position.node,
        position.local,
        ray,
        tanhDist,
    );

    bool hasHit = !isNaN(castHit.tanhDistance);
    float[3] hitNormal = [0.0f, 1.0f, 0.0f];
    if (hasHit) {
        // Normal back in the caster frame at the hit position.
        MIsometry!float hitTransform = MIsometry!float.translationAlong(
            scale3(displacementNormalized, atanh(castHit.tanhDistance)));
        MVector!float transformedNormal = hitTransform.inverse().mat * castHit.normal;
        float[3] normalXyz = transformedNormal.xyz();
        float normalMag = magnitude3(normalXyz);
        if (normalMag > 1e-16) {
            hitNormal = scale3(normalXyz, 1.0f / normalMag);
        }

        // Grazing guard: a contact whose normal is (near-)orthogonal to the
        // motion cannot oppose it — the solver's touch zone plus float noise
        // otherwise wedges flush contacts against tangent sweeps (e.g. the
        // stair raise sliding along a wall the walker is pressed against).
        if (dot3(displacementNormalized, hitNormal) > -1e-3f) {
            hasHit = false;
        }
    }

    float hitTanhDist = tanhDist;
    if (hasHit) {
        hitTanhDist = castHit.tanhDistance;
    }

    float distance = atanh(hitTanhDist);

    float[3] displacementVector = scale3(displacementNormalized, distance);
    MIsometry!float displacementTransform = MIsometry!float.translationAlong(displacementVector);

    CollisionCheckingResult result;
    result.displacementVector = displacementVector;
    result.displacementTransform = displacementTransform;
    result.hasCollision = hasHit;
    if (hasHit) {
        result.collision = Collision(hitNormal);
    }

    return result;
}
