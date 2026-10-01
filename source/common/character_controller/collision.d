module common.character_controller.collision;

import core.math : sqrt;
import core.stdc.math : atanhf, tanhf;
import common.chunk_collision : MAX_FEATURE_SURFACES;
import common.collision_math : Ray;
import common.graph : Graph;
import common.graph_collision : Capsule, GraphCollisionHit, shapeCast;
import common.math : MDirection, MIsometry, MPoint, MVector, isNan;
import common.proto : Position;
import common.vector3 : dot3, magnitude3, scale3, zero3;

enum double MIN_DISPLACEMENT_SQUARED = 1e-16;

struct CollisionContext {
    const(Graph)* graph;
    Capsule capsule;
}

struct CollisionCheckingResult {
    MIsometry!float displacementTransform;
    float[3][MAX_FEATURE_SURFACES] surfaces;
    float[3] displacementVector;
    float[3] normal;
    float gap;
    uint surfaceCount;
    bool hasCollision;
    bool lowestSection;
}

float[3] unitXyz(MIsometry!float toContactFrame, MVector!float v) {
    float[3] xyz = (toContactFrame * v).xyz();
    return scale3(xyz, 1.0f / magnitude3(xyz));
}

CollisionCheckingResult checkCollision(const(CollisionContext)* context, Position position, float[3] relativeDisplacement) {
    CollisionCheckingResult result;
    result.displacementVector = zero3();
    result.displacementTransform = MIsometry!float.identity();
    float displacementSquared = dot3(relativeDisplacement, relativeDisplacement);
    if (!(displacementSquared < MIN_DISPLACEMENT_SQUARED)) {
        float displacementNorm = sqrt(displacementSquared);
        float[3] direction = scale3(relativeDisplacement, 1.0f / displacementNorm);
        Ray ray = Ray(MPoint!float.origin(), MDirection!float(MVector!float(direction[0], direction[1], direction[2], 0)));
        float tanhDistance = tanhf(displacementNorm);
        GraphCollisionHit castHit = shapeCast(context.capsule, context.graph, position.node, position.local, ray, tanhDistance);
        result.hasCollision = !isNan(castHit.stopDistance);
        float traveled = displacementNorm;
        if (result.hasCollision) {
            traveled = atanhf(castHit.stopDistance);
        }
        result.displacementVector = scale3(direction, traveled);
        result.displacementTransform = MIsometry!float.translationAlong(result.displacementVector);
        if (result.hasCollision) {
            MIsometry!float toContactFrame = result.displacementTransform.inverse();
            result.normal = unitXyz(toContactFrame, castHit.normal);
            foreach (i; 0 .. castHit.surfaceCount) {
                result.surfaces[i] = unitXyz(toContactFrame, castHit.surfaces[i]);
            }
            result.surfaceCount = castHit.surfaceCount;
            result.gap = castHit.gap;
            result.lowestSection = castHit.lowestSection;
        }
    }
    return result;
}
