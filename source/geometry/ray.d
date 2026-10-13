module geometry.ray;

import base.numbers : isInfinite, isNan;
import geometry.lorentz : Motion, Normal, Point, Vec4;

enum float MAX_TANH_DISTANCE = 0.999f;

struct Ray {
    Point!float start;
    Normal!float heading;

    Vec4!float at(float tanhDistance) const {
        return start.v + heading.v * tanhDistance;
    }

    Ray movedBy(Motion!float motion) const {
        return Ray(motion * start, motion * heading);
    }

    float crossing(Normal!float plane) const {
        float t = -plane.minkowski(start.v) / plane.minkowski(heading.v);
        if (!isNan(t) && !isInfinite(t) && t > 0.0f) {
            return t;
        } else {
            return float.nan;
        }
    }
}
