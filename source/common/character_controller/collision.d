module common.character_controller.collision;

import core.math : sqrt;
import core.stdc.math : atanhf, tanhf;
import common.collision_math : Ray;
import common.graph : Graph;
import common.graph_collision : GraphCollisionHit, shapeCast;
import common.math : MDirection, MIsometry, MPoint, MVector, isNan;
import common.proto : Position;
import common.vector3 : dot3, magnitude3, scale3, zero3;

enum double MIN_DISPLACEMENT_SQUARED = 1e-16;
enum double MIN_NORMAL_MAGNITUDE = 1e-16;

struct CollisionContext {
    const(Graph)* graph;
    float[3] up = [0, 1, 0];
    float radius;
    float halfHeight;
}

struct CollisionCheckingResult {
    MIsometry!float displacementTransform;
    float[3] displacementVector;
    float[3] normal;
    bool hasCollision;
}

CollisionCheckingResult checkCollision(const(CollisionContext)* context, Position position, float[3] relativeDisplacement) {
    CollisionCheckingResult result;
    result.displacementVector = zero3();
    result.displacementTransform = MIsometry!float.identity();
    result.hasCollision = false;
    float displacementSquared = dot3(relativeDisplacement, relativeDisplacement);
    if (!(displacementSquared < MIN_DISPLACEMENT_SQUARED)) {
        float displacementNorm = sqrt(displacementSquared);
        float[3] direction = [relativeDisplacement[0] / displacementNorm, relativeDisplacement[1] / displacementNorm, relativeDisplacement[2] / displacementNorm];
        Ray ray = Ray(MPoint!float.origin(), MDirection!float(MVector!float(direction[0], direction[1], direction[2], 0)));
        float tanhDistance = tanhf(displacementNorm);
        GraphCollisionHit castHit = shapeCast(context.radius, context.halfHeight, context.up, context.graph, position.node, position.local, ray, tanhDistance);
        bool hasHit = !isNan(castHit.tanhDistance);
        float[3] hitNormal = [0.0f, 1.0f, 0.0f];
        if (hasHit) {
            MIsometry!float hitTransform = MIsometry!float.translationAlong(scale3(direction, atanhf(castHit.tanhDistance)));
            float[3] normalXyz = (hitTransform.inverse().mat * castHit.normal).xyz();
            float normalMagnitude = magnitude3(normalXyz);
            if (normalMagnitude > MIN_NORMAL_MAGNITUDE) {
                hitNormal = scale3(normalXyz, 1.0f / normalMagnitude);
            }
        }
        float hitTanhDistance = tanhDistance;
        if (hasHit) {
            hitTanhDistance = castHit.tanhDistance;
        }
        result.displacementVector = scale3(direction, atanhf(hitTanhDistance));
        result.displacementTransform = MIsometry!float.translationAlong(result.displacementVector);
        result.hasCollision = hasHit;
        if (hasHit) {
            result.normal = hitNormal;
        }
    }
    return result;
}
