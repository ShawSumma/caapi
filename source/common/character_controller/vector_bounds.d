module common.character_controller.vector_bounds;

import core.math : sqrt;
import common.math : projectToPlane;

enum uint MAX_BOUNDS = 32;
enum uint MAX_TEMP_BOUNDS = 8;
enum float ERROR_MARGIN_FACTOR = 1e-4f;
enum float FRONT_FACING_MARGIN = 0.5f;
enum float BACK_FACING_MARGIN = 1.5f;
enum double MIN_CONSTRAINED_DIRECTION = 1e-5;

float dot3(float[3] a, float[3] b) {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

float magnitude3(float[3] v) {
    return sqrt(dot3(v, v));
}

float[3] scale3(float[3] v, float s) {
    float[3] result = [v[0] * s, v[1] * s, v[2] * s];
    return result;
}

float[3] add3(float[3] a, float[3] b) {
    float[3] result = [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
    return result;
}

float[3] sub3(float[3] a, float[3] b) {
    float[3] result = [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
    return result;
}

float[3] neg3(float[3] v) {
    float[3] result = [-v[0], -v[1], -v[2]];
    return result;
}

bool isZero3(float[3] v) {
    return v[0] == 0 && v[1] == 0 && v[2] == 0;
}

float[3] zero3() {
    float[3] result = [0.0f, 0.0f, 0.0f];
    return result;
}

struct VectorBound {
    float[3] normal;
    float[3] projectionDirection;
    bool frontFacing;

    float[3] constrained(float[3] subject, float errorMargin) const {
        return projectToPlane(subject, normal, projectionDirection, errorMargin);
    }

    bool checkVector(float[3] subject, float errorMargin) const {
        bool result = true;
        if (!isZero3(subject)) {
            float d = dot3(subject, normal);
            if (frontFacing) {
                result = d >= errorMargin * FRONT_FACING_MARGIN;
            } else {
                result = d <= errorMargin * BACK_FACING_MARGIN;
            }
        }
        return result;
    }

    ConstrainedBound selfConstrainedWithBound(VectorBound bound) const {
        float[3] orthogonalDirection = projectToPlane(projectionDirection, bound.normal, bound.projectionDirection, 0.0f);
        float m = magnitude3(orthogonalDirection);
        ConstrainedBound result;
        if (!(m < MIN_CONSTRAINED_DIRECTION)) {
            float[3] direction = [orthogonalDirection[0] / m, orthogonalDirection[1] / m, orthogonalDirection[2] / m];
            result.bound = VectorBound(normal, direction, frontFacing);
            result.valid = true;
        }
        return result;
    }
}

struct ConstrainedBound {
    VectorBound bound;
    bool valid;
}

struct BoundedVectors {
    VectorBound[MAX_BOUNDS] bounds;
    VectorBound[MAX_TEMP_BOUNDS] tempBounds;
    float[3] displacement;
    float[3] velocity;
    float errorMargin;
    uint boundCount;
    uint tempBoundCount;
    bool hasVelocity;

    void scaleDisplacement(float scaleFactor) {
        displacement = scale3(displacement, scaleFactor);
        errorMargin *= scaleFactor;
    }

    void addBound(VectorBound newBound) {
        applyBound(newBound);
        if (boundCount < MAX_BOUNDS) {
            bounds[boundCount] = newBound;
            boundCount += 1;
        }
    }

    void addTempBound(VectorBound newBound) {
        applyBound(newBound);
        if (tempBoundCount < MAX_TEMP_BOUNDS) {
            tempBounds[tempBoundCount] = newBound;
            tempBoundCount += 1;
        }
    }

    void clearTempBounds() {
        tempBoundCount = 0;
    }

    VectorBound boundAt(uint index) const {
        VectorBound result;
        if (index < boundCount) {
            result = bounds[index];
        } else {
            result = tempBounds[index - boundCount];
        }
        return result;
    }

    bool allBoundsSatisfiedFor(float[3] candidate) const {
        bool satisfied = true;
        foreach (i; 0 .. boundCount + tempBoundCount) {
            if (!boundAt(i).checkVector(candidate, errorMargin)) {
                satisfied = false;
            }
        }
        return satisfied;
    }

    void applyBound(VectorBound newBound) {
        if (!newBound.checkVector(displacement, errorMargin)) {
            displacement = newBound.constrained(displacement, errorMargin);
            if (hasVelocity) {
                velocity = newBound.constrained(velocity, 0.0f);
            }
        }
        if (!allBoundsSatisfiedFor(displacement)) {
            bool resolved = false;
            foreach (i; 0 .. boundCount + tempBoundCount) {
                VectorBound bound = boundAt(i);
                if (!resolved && !bound.checkVector(displacement, errorMargin)) {
                    ConstrainedBound orthogonal = bound.selfConstrainedWithBound(newBound);
                    if (orthogonal.valid) {
                        float[3] candidate = orthogonal.bound.constrained(displacement, errorMargin);
                        if (allBoundsSatisfiedFor(candidate)) {
                            displacement = candidate;
                            if (hasVelocity) {
                                velocity = orthogonal.bound.constrained(velocity, 0.0f);
                            }
                            resolved = true;
                        }
                    }
                }
            }
            if (!resolved) {
                displacement = zero3();
                if (hasVelocity) {
                    velocity = zero3();
                }
            }
        }
    }
}

BoundedVectors createBoundedVectors(float[3] displacement, bool hasVelocity, float[3] velocity) {
    BoundedVectors result;
    result.displacement = displacement;
    result.velocity = velocity;
    result.hasVelocity = hasVelocity;
    result.errorMargin = magnitude3(displacement) * ERROR_MARGIN_FACTOR;
    return result;
}

unittest {
    float[3] displacement = [-8.39314e-05, -8.87924e-05, -0.000122182];
    float[3] velocity = [-0.0104914, -0.011099, -0.0152727];
    float[3] normal = [0.670735, 0.741697, -4.62294e-06];
    float[3] up = [0.686935, 0.726719, 0];
    BoundedVectors bounded = createBoundedVectors(displacement, true, velocity);
    bounded.addTempBound(VectorBound(normal, up, false));
    bounded.addBound(VectorBound(normal, up, true));
    assert(!isZero3(bounded.displacement));
    assert(!isZero3(bounded.velocity));
    assert(bounded.displacement[2] < -1e-4);
    assert(bounded.velocity[2] < -1e-2);
}
