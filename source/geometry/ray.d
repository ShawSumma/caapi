module geometry.ray;

import base.numbers : isInfinite, isNan;
import geometry.lorentz : Motion, Normal, Point, Vec4;

enum float MAX_TANH_DISTANCE = 0.999f;

// A geodesic from a point in a unit direction tangent to it. Positions along it are measured by the tanh of the
// distance, which keeps them projective: start + heading * t, unnormalized, lies on the ray at tanh distance t.
struct Ray {
    Point!float start;
    Normal!float heading;

    Vec4!float at(float tanhDistance) const {
        return start.v + heading.v * tanhDistance;
    }

    Ray movedBy(Motion!float motion) const {
        return Ray(motion * start, motion * heading);
    }

    // Where the ray meets the plane, or NaN when it runs parallel or the plane lies behind.
    float crossing(Normal!float plane) const {
        float t = -plane.minkowski(start.v) / plane.minkowski(heading.v);
        if (!isNan(t) && !isInfinite(t) && t > 0.0f) {
            return t;
        } else {
            return float.nan;
        }
    }
}
