module common.ray;

import common.math : MDirection, MIsometry, MPoint, MVector, isInfinite, isNan;

enum float MAX_TANH_DISTANCE = 0.999f;

struct Ray {
    MPoint!float position;
    MDirection!float direction;

    MVector!float rayPoint(float tanhDistance) const {
        return position.vec + direction.vec * tanhDistance;
    }

    Ray transformedBy(MIsometry!float iso) const {
        return Ray(iso * position, iso * direction);
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
