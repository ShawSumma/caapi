module common.collision_math;

import core.math : sqrt;
import common.math : MDirection, MIsometry, MPoint, MVector, isInfinite, isNan;

enum float QUADRATIC_EPSILON = 1e-4f;
enum float MAX_TANH_DISTANCE = 0.999f;

struct Ray {
    MPoint!float position;
    MDirection!float direction;

    MVector!float rayPoint(float tanhDistance) const {
        return position.vec + direction.vec * tanhDistance;
    }

    float solveSpherePlaneIntersection(MDirection!float planeNormal, float sinhRadius) const {
        float positionA = position.mip(planeNormal.vec);
        float directionA = direction.mip(planeNormal.vec);
        float constantTerm = positionA * positionA - sinhRadius * sinhRadius;
        float halfLinearTerm = positionA * directionA;
        float quadraticTerm = directionA * directionA + sinhRadius * sinhRadius;
        return solveQuadratic(constantTerm, halfLinearTerm, quadraticTerm);
    }

    float solveSphereLineIntersection(MDirection!float lineNormal1, MDirection!float lineNormal0, float sinhRadius) const {
        float positionA = position.mip(lineNormal0.vec);
        float directionA = direction.mip(lineNormal0.vec);
        float positionB = position.mip(lineNormal1.vec);
        float directionB = direction.mip(lineNormal1.vec);
        float constantTerm = positionA * positionA + positionB * positionB - sinhRadius * sinhRadius;
        float halfLinearTerm = positionA * directionA + positionB * directionB;
        float quadraticTerm = directionA * directionA + directionB * directionB + sinhRadius * sinhRadius;
        return solveQuadratic(constantTerm, halfLinearTerm, quadraticTerm);
    }

    float solveSpherePointIntersection(MDirection!float n0, MDirection!float n1, MDirection!float n2, float sinhRadius) const {
        float positionA = position.mip(n0.vec);
        float directionA = direction.mip(n0.vec);
        float positionB = position.mip(n1.vec);
        float directionB = direction.mip(n1.vec);
        float positionC = position.mip(n2.vec);
        float directionC = direction.mip(n2.vec);
        float constantTerm = positionA * positionA + positionB * positionB + positionC * positionC - sinhRadius * sinhRadius;
        float halfLinearTerm = positionA * directionA + positionB * directionB + positionC * directionC;
        float quadraticTerm = directionA * directionA + directionB * directionB + directionC * directionC + sinhRadius * sinhRadius;
        return solveQuadratic(constantTerm, halfLinearTerm, quadraticTerm);
    }

    float solvePointPlaneIntersection(MDirection!float planeNormal) const {
        float candidate = -position.mip(planeNormal.vec) / direction.mip(planeNormal.vec);
        float result = float.nan;
        if (!isNan(candidate) && !isInfinite(candidate) && candidate > 0.0f) {
            result = candidate;
        }
        return result;
    }
}

Ray transformRay(MIsometry!float iso, Ray ray) {
    return Ray(iso * ray.position, iso * ray.direction);
}

float solveQuadratic(float constantTerm, float halfLinearTerm, float quadraticTerm) {
    float result = float.nan;
    if (!(halfLinearTerm >= 0.0f)) {
        if (constantTerm <= 0.0f) {
            if (constantTerm > -QUADRATIC_EPSILON) {
                result = 0.0f;
            }
        } else {
            float discriminant = halfLinearTerm * halfLinearTerm - quadraticTerm * constantTerm;
            if (!(discriminant <= 0.0f)) {
                result = constantTerm / (-halfLinearTerm + sqrt(discriminant));
            }
        }
    }
    return result;
}
