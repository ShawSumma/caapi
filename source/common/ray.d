module common.ray;

import core.math : sqrt;
import core.stdc.math : asinhf;
import common.math : MDirection, MIsometry, MPoint, MVector, isInfinite, isNan;

enum float MAX_TANH_DISTANCE = 0.999f;

struct ContactTerms {
    float separationSquared;
    float approach;
    float directionSquared;

    float contactTime(float sinhRadius) const {
        float constantTerm = separationSquared - sinhRadius * sinhRadius;
        float quadraticTerm = directionSquared + sinhRadius * sinhRadius;
        float discriminant = approach * approach - quadraticTerm * constantTerm;
        if (approach >= 0.0f) {
            return float.nan;
        } else if (constantTerm <= 0.0f && separationSquared - approach * approach / quadraticTerm < separationSquared) {
            return 0.0f;
        } else if (constantTerm <= 0.0f) {
            return float.nan;
        } else if (discriminant > 0.0f) {
            return constantTerm / (-approach + sqrt(discriminant));
        } else {
            return float.nan;
        }
    }

    float separationDistance() const {
        return asinhf(sqrt(separationSquared));
    }
}

struct Ray {
    MPoint!float position;
    MDirection!float direction;

    MVector!float rayPoint(float tanhDistance) const {
        return position.vec + direction.vec * tanhDistance;
    }

    Ray transformedBy(MIsometry!float iso) const {
        return Ray(iso * position, iso * direction);
    }

    ContactTerms planeTerms(MDirection!float planeNormal) const {
        float positionA = position.mip(planeNormal.vec);
        float directionA = direction.mip(planeNormal.vec);
        return ContactTerms(positionA * positionA, positionA * directionA, directionA * directionA);
    }

    ContactTerms lineTerms(MDirection!float lineNormal0, MDirection!float lineNormal1) const {
        float positionA = position.mip(lineNormal0.vec);
        float directionA = direction.mip(lineNormal0.vec);
        float positionB = position.mip(lineNormal1.vec);
        float directionB = direction.mip(lineNormal1.vec);
        return ContactTerms(positionA * positionA + positionB * positionB, positionA * directionA + positionB * directionB, directionA * directionA + directionB * directionB);
    }

    ContactTerms pointTerms(MDirection!float n0, MDirection!float n1, MDirection!float n2) const {
        float positionA = position.mip(n0.vec);
        float directionA = direction.mip(n0.vec);
        float positionB = position.mip(n1.vec);
        float directionB = direction.mip(n1.vec);
        float positionC = position.mip(n2.vec);
        float directionC = direction.mip(n2.vec);
        return ContactTerms(positionA * positionA + positionB * positionB + positionC * positionC, positionA * directionA + positionB * directionB + positionC * directionC, directionA * directionA + directionB * directionB + directionC * directionC);
    }

    float solvePointPlaneIntersection(MDirection!float planeNormal) const {
        float candidate = -position.mip(planeNormal.vec) / direction.mip(planeNormal.vec);
        if (!isNan(candidate) && !isInfinite(candidate) && candidate > 0.0f) {
            return candidate;
        } else {
            return float.nan;
        }
    }
}

unittest {
    Ray ray = Ray(MPoint!float.origin(), MDirection!float(MVector!float([1, 0, 0, 0])));
    MDirection!float wall = MVector!float([-1, 0, 0, -0.5f]).normalizedDirection();
    ContactTerms terms = ray.planeTerms(wall);
    assert(ray.position.mip(wall.vec) > 0);
    float far = terms.contactTime(0.1f);
    float near = terms.contactTime(0.2f);
    assert(!isNan(far) && near < far);
    Ray away = Ray(MPoint!float.origin(), MDirection!float(MVector!float([-1, 0, 0, 0])));
    assert(isNan(away.planeTerms(wall).contactTime(0.1f)));
    Ray along = Ray(MPoint!float.origin(), MDirection!float(MVector!float([0, 1, 0, 0])));
    assert(isNan(along.planeTerms(wall).contactTime(0.1f)));
}

unittest {
    float sinhRadius = 0.1f;
    float inside = 0.9f * sinhRadius * sinhRadius;
    assert(ContactTerms(inside, -0.01f, 1).contactTime(sinhRadius) == 0);
    assert(isNan(ContactTerms(inside, -1e-12f, 1).contactTime(sinhRadius)));
}
