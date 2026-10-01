module common.collision_math;

import core.math : sqrt;
import core.stdc.math : asinhf;
import common.math : MDirection, MIsometry, MPoint, MVector, isInfinite, isNan;

enum float MAX_TANH_DISTANCE = 0.999f;

struct ContactTerms {
    float separationSquared;
    float approach;
    float directionSquared;
}

struct Ray {
    MPoint!float position;
    MDirection!float direction;

    MVector!float rayPoint(float tanhDistance) const {
        return position.vec + direction.vec * tanhDistance;
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

float contactTime(ContactTerms terms, float sinhRadius) {
    float result = float.nan;
    if (terms.approach < 0.0f) {
        float constantTerm = terms.separationSquared - sinhRadius * sinhRadius;
        if (constantTerm <= 0.0f) {
            result = 0.0f;
        } else {
            float quadraticTerm = terms.directionSquared + sinhRadius * sinhRadius;
            float discriminant = terms.approach * terms.approach - quadraticTerm * constantTerm;
            if (discriminant > 0.0f) {
                result = constantTerm / (-terms.approach + sqrt(discriminant));
            }
        }
    }
    return result;
}

float separationDistance(ContactTerms terms) {
    return asinhf(sqrt(terms.separationSquared));
}

unittest {
    Ray ray = Ray(MPoint!float.origin(), MDirection!float(MVector!float(1, 0, 0, 0)));
    MDirection!float wall = MVector!float(-1, 0, 0, -0.5f).normalizedDirection();
    ContactTerms terms = ray.planeTerms(wall);
    assert(ray.position.mip(wall.vec) > 0);
    float far = contactTime(terms, 0.1f);
    float near = contactTime(terms, 0.2f);
    assert(!isNan(far) && near < far);
    Ray away = Ray(MPoint!float.origin(), MDirection!float(MVector!float(-1, 0, 0, 0)));
    assert(isNan(contactTime(away.planeTerms(wall), 0.1f)));
    Ray along = Ray(MPoint!float.origin(), MDirection!float(MVector!float(0, 1, 0, 0)));
    assert(isNan(contactTime(along.planeTerms(wall), 0.1f)));
}
