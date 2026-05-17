module common.collision_math;

import common.math;
import std.math : sqrt, isFinite;

/// A ray in hyperbolic space. Position and direction must be orthogonal.
struct Ray {
    MPoint!float position;
    MDirection!float direction;

    static Ray create(MPoint!float pos, MDirection!float dir) {
        return Ray(pos, dir);
    }

    /// Returns an unnormalized vector representing a point along this ray
    MVector!float rayPoint(float tanhDistance) const {
        return position.vec + direction.vec * tanhDistance;
    }

    /// Sphere-plane intersection
    float solveSphereePlaneIntersection(const ref MDirection!float planeNormal, float sinhRadius) const {
        float mipPosA = position.mip(planeNormal);
        float mipDirA = direction.mip(planeNormal);
        return solveQuadratic(
            mipPosA * mipPosA - sinhRadius * sinhRadius,
            mipPosA * mipDirA,
            mipDirA * mipDirA + sinhRadius * sinhRadius,
        );
    }

    /// Sphere-line intersection
    float solveSpherLineIntersection(
        const ref MDirection!float lineNormal1,
        const ref MDirection!float lineNormal0,
        float sinhRadius
    ) const {
        float mipPosA = position.mip(lineNormal0);
        float mipDirA = direction.mip(lineNormal0);
        float mipPosB = position.mip(lineNormal1);
        float mipDirB = direction.mip(lineNormal1);
        return solveQuadratic(
            mipPosA * mipPosA + mipPosB * mipPosB - sinhRadius * sinhRadius,
            mipPosA * mipDirA + mipPosB * mipDirB,
            mipDirA * mipDirA + mipDirB * mipDirB + sinhRadius * sinhRadius,
        );
    }

    /// Sphere-point intersection
    float solveSpherePointIntersection(
        const ref MDirection!float n0,
        const ref MDirection!float n1,
        const ref MDirection!float n2,
        float sinhRadius
    ) const {
        float mipPosA = position.mip(n0);
        float mipDirA = direction.mip(n0);
        float mipPosB = position.mip(n1);
        float mipDirB = direction.mip(n1);
        float mipPosC = position.mip(n2);
        float mipDirC = direction.mip(n2);
        return solveQuadratic(
            mipPosA * mipPosA + mipPosB * mipPosB + mipPosC * mipPosC - sinhRadius * sinhRadius,
            mipPosA * mipDirA + mipPosB * mipDirB + mipPosC * mipDirC,
            mipDirA * mipDirA + mipDirB * mipDirB + mipDirC * mipDirC + sinhRadius * sinhRadius,
        );
    }

    /// Point-plane intersection
    float solvePointPlaneIntersection(const ref MDirection!float planeNormal) const {
        float mipPosA = position.mip(planeNormal);
        float mipDirA = direction.mip(planeNormal);
        float result = -mipPosA / mipDirA;
        if (isFinite(result) && result > 0.0f) {
            return result;
        }
        return float.nan;
    }
}

/// Transform a ray by an isometry
Ray transformRay(const ref MIsometry!float iso, const ref Ray ray) {
    return Ray(
        iso * ray.position,
        iso * ray.direction,
    );
}

/// Solve quadratic: constant + 2*halfLinear*x + quadratic*x^2 == 0
/// Returns the lower non-negative solution, or NaN if none exists.
private float solveQuadratic(float constantTerm, float halfLinearTerm, float quadraticTerm) {
    enum float EPSILON = 1e-4f;

    if (halfLinearTerm >= 0.0f) {
        return float.nan;
    }

    if (constantTerm <= 0.0f) {
        return constantTerm > -EPSILON ? 0.0f : float.nan;
    }

    float discriminant = halfLinearTerm * halfLinearTerm - quadraticTerm * constantTerm;
    if (discriminant <= 0.0f) {
        return float.nan;
    }

    return constantTerm / (-halfLinearTerm + sqrt(discriminant));
}
