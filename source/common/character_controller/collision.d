module common.character_controller.collision;

import core.math : sqrt;
import core.stdc.math : atanhf, tanhf;
import common.chunk_collision : MAX_FEATURE_SURFACES;
import common.collision_math : Ray;
import common.graph : Graph;
import common.graph_collision : Capsule, GraphCollisionHit, shapeCast;
import common.math : MDirection, MIsometry, MPoint, MVector;
import common.proto : Position;
import common.vector3 : dot3, magnitude3, scale3, zero3;

enum double MIN_DISPLACEMENT_SQUARED = 1e-16;

struct CollisionContext {
    const(Graph)* graph;
    Capsule capsule;

    CollisionCheckingResult check(Position position, float[3] relativeDisplacement) const {
        float displacementSquared = relativeDisplacement.dot3(relativeDisplacement);
        if (displacementSquared < MIN_DISPLACEMENT_SQUARED) {
            return CollisionCheckingResult.none();
        } else {
            float displacementNorm = sqrt(displacementSquared);
            float[3] direction = relativeDisplacement.scale3(1.0f / displacementNorm);
            Ray ray = Ray(MPoint!float.origin(), MDirection!float(MVector!float(direction[0], direction[1], direction[2], 0)));
            GraphCollisionHit castHit = shapeCast(capsule, graph, position, ray, tanhf(displacementNorm));
            if (castHit.isHit()) {
                return CollisionCheckingResult.fromHit(castHit, direction.scale3(atanhf(castHit.stopDistance)));
            } else {
                return CollisionCheckingResult.unobstructed(direction.scale3(displacementNorm));
            }
        }
    }
}

struct CollisionCheckingResult {
    MIsometry!float displacementTransform;
    float[3][MAX_FEATURE_SURFACES] surfaces;
    float[3] displacementVector;
    float[3] normal;
    float gap;
    uint surfaceCount;
    bool hasCollision;
    bool isLowestSection;

    static CollisionCheckingResult none() {
        CollisionCheckingResult result;
        result.displacementVector = zero3();
        result.displacementTransform = MIsometry!float.identity();
        return result;
    }

    static CollisionCheckingResult unobstructed(float[3] displacement) {
        CollisionCheckingResult result;
        result.displacementVector = displacement;
        result.displacementTransform = MIsometry!float.translationAlong(displacement);
        return result;
    }

    static CollisionCheckingResult fromHit(GraphCollisionHit castHit, float[3] displacement) {
        CollisionCheckingResult result = unobstructed(displacement);
        MIsometry!float toContactFrame = result.displacementTransform.inverse();
        result.hasCollision = true;
        result.normal = unitXyz(toContactFrame, castHit.normal);
        foreach (i; 0 .. castHit.surfaceCount) {
            result.surfaces[i] = unitXyz(toContactFrame, castHit.surfaces[i]);
        }
        result.surfaceCount = castHit.surfaceCount;
        result.gap = castHit.gap;
        result.isLowestSection = castHit.isLowestSection;
        return result;
    }
}

float[3] unitXyz(MIsometry!float toContactFrame, MVector!float v) {
    float[3] xyz = (toContactFrame * v).xyz();
    return xyz.scale3(1.0f / xyz.magnitude3);
}
