/// This module is used to transform vectors to ensure that they fit constraints discovered during collision checking.
module common.character_controller.vector_bounds;

import common.math : projectToPlane;
import std.math : sqrt;

/// Helper functions for float[3] vectors
float dot3(const float[3] a, const float[3] b) {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

float magnitude3(const float[3] v) {
    return sqrt(dot3(v, v));
}

float[3] normalize3(const float[3] v) {
    float m = magnitude3(v);
    if (m < 1e-16) {
        return [0.0f, 0.0f, 0.0f];
    }
    return [v[0] / m, v[1] / m, v[2] / m];
}

float[3] scale3(const float[3] v, float s) {
    return [v[0] * s, v[1] * s, v[2] * s];
}

float[3] add3(const float[3] a, const float[3] b) {
    return [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
}

float[3] sub3(const float[3] a, const float[3] b) {
    return [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
}

float[3] neg3(const float[3] v) {
    return [-v[0], -v[1], -v[2]];
}

float[3] cross3(const float[3] a, const float[3] b) {
    return [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ];
}

bool isZero3(const float[3] v) {
    return v[0] == 0 && v[1] == 0 && v[2] == 0;
}

float[3] zero3() {
    return [0.0f, 0.0f, 0.0f];
}

/// Represents a single constraint for a vector.
struct VectorBound {
    float[3] normal;
    float[3] projectionDirection;
    bool frontFacing;

    static VectorBound create(float[3] normal, float[3] projDir, bool frontFacing) {
        return VectorBound(normal, projDir, frontFacing);
    }

    /// Updates `subject` with a projection transformation based on the constraint given by `self`.
    void constrainVector(ref float[3] subject, float errorMargin) const {
        projectToPlane(subject, normal, projectionDirection, errorMargin);
    }

    /// Checks whether `subject` satisfies the constraint.
    bool checkVector(const float[3] subject, float errorMargin) const {
        if (isZero3(subject)) {
            return true;
        }

        float d = dot3(subject, normal);
        if (frontFacing) {
            return d >= errorMargin * 0.5f;
        } else {
            return d <= errorMargin * 1.5f;
        }
    }

    /// Returns a VectorBound that is an altered version of self so that it no longer interferes with `bound`.
    VectorBound* getSelfConstrainedWithBound(const ref VectorBound bound, ref VectorBound result) const {
        float[3] orthoProjDir = projectionDirection;
        projectToPlane(orthoProjDir, bound.normal, bound.projectionDirection, 0.0f);

        float m = magnitude3(orthoProjDir);
        if (m < 1e-5) {
            return null;
        }

        result = VectorBound(normal, [orthoProjDir[0] / m, orthoProjDir[1] / m, orthoProjDir[2] / m], frontFacing);
        return &result;
    }
}

/// Encapsulates all the information needed to constrain a vector (displacement) based on a set of VectorBounds
/// and apply those same constraints to a secondary vector (velocity).
struct BoundedVectors {
    float[3] displacement;
    float[3] velocity;
    bool hasVelocity;
    VectorBound[] bounds;
    VectorBound[] tempBounds;
    float errorMargin;

    static BoundedVectors create(float[3] disp, bool hasVel, float[3] vel = zero3()) {
        BoundedVectors bv;
        bv.displacement = disp;
        bv.velocity = vel;
        bv.hasVelocity = hasVel;
        bv.bounds = [];
        bv.tempBounds = [];
        bv.errorMargin = magnitude3(disp) * 1e-4f;
        return bv;
    }

    float[3] getDisplacement() const {
        return displacement;
    }

    /// Scales the displacement vector without invalidating any of the VectorBounds
    void scaleDisplacement(float scaleFactor) {
        displacement = scale3(displacement, scaleFactor);
        errorMargin *= scaleFactor;
    }

    float[3] getVelocity() const {
        return velocity;
    }

    const(VectorBound)[] getBounds() const {
        return bounds;
    }

    /// Constrains displacement with newBound while keeping existing constraints satisfied.
    void addBound(VectorBound newBound) {
        applyBound(newBound);
        bounds ~= newBound;
    }

    /// Temporarily constrains displacement with newBound.
    void addTempBound(VectorBound newBound) {
        applyBound(newBound);
        tempBounds ~= newBound;
    }

    /// Removes all temporary bounds
    void clearTempBounds() {
        tempBounds.length = 0;
    }

    /// Clone this struct (deep copy of dynamic arrays)
    BoundedVectors dup() const {
        BoundedVectors result;
        result.displacement = displacement;
        result.velocity = velocity;
        result.hasVelocity = hasVelocity;
        result.bounds = bounds.dup;
        result.tempBounds = tempBounds.dup;
        result.errorMargin = errorMargin;
        return result;
    }

    private void applyBound(const ref VectorBound newBound) {
        // Apply newBound if necessary
        if (!newBound.checkVector(displacement, errorMargin)) {
            newBound.constrainVector(displacement, errorMargin);
            if (hasVelocity) {
                newBound.constrainVector(velocity, 0.0f);
            }
        }

        // Check if all constraints are satisfied
        if (allBoundsSatisfied()) {
            return;
        }

        // Find the first constraint that if applied will satisfy remaining constraints
        foreach (ref bound; allBoundsRange()) {
            if (bound.checkVector(displacement, errorMargin)) {
                continue;
            }

            VectorBound orthoBoundStorage;
            auto orthoBound = bound.getSelfConstrainedWithBound(newBound, orthoBoundStorage);
            if (orthoBound is null) {
                continue;
            }

            float[3] candidate = displacement;
            orthoBound.constrainVector(candidate, errorMargin);

            if (allBoundsSatisfiedFor(candidate)) {
                displacement = candidate;
                if (hasVelocity) {
                    orthoBound.constrainVector(velocity, 0.0f);
                }
                return;
            }
        }

        // If no choice satisfies all constraints, zero out
        displacement = zero3();
        if (hasVelocity) {
            velocity = zero3();
        }
    }

    private bool allBoundsSatisfied() const {
        foreach (ref b; bounds) {
            if (!b.checkVector(displacement, errorMargin)) {
                return false;
            }
        }
        foreach (ref b; tempBounds) {
            if (!b.checkVector(displacement, errorMargin)) {
                return false;
            }
        }
        return true;
    }

    private bool allBoundsSatisfiedFor(const float[3] candidate) const {
        foreach (ref b; bounds) {
            if (!b.checkVector(candidate, errorMargin)) {
                return false;
            }
        }
        foreach (ref b; tempBounds) {
            if (!b.checkVector(candidate, errorMargin)) {
                return false;
            }
        }
        return true;
    }

    /// Returns a range over both bounds and tempBounds
    private const(VectorBound)[] allBoundsRange() const {
        return bounds ~ tempBounds;
    }
}
