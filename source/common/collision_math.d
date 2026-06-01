module common.collision_math;

import std.math : sqrt, isFinite;
import common.math : MPoint, MDirection, MVector, MIsometry;

struct Ray {
    MPoint!float position;
    MDirection!float direction;

    static Ray create(MPoint!float pos, MDirection!float dir) {
        return Ray(pos, dir);
    }

    MVector!float rayPoint(float tanhDistance) const {
        return position.vec + direction.vec * tanhDistance;
    }

    float solveSphereePlaneIntersection(const ref MDirection!float planeNormal, float sinhRadius) const {
        float mipPosA = position.mip(planeNormal);
        float mipDirA = direction.mip(planeNormal);
        return solveQuadratic(
            mipPosA * mipPosA - sinhRadius * sinhRadius,
            mipPosA * mipDirA,
            mipDirA * mipDirA + sinhRadius * sinhRadius,
        );
    }

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

Ray transformRay(const ref MIsometry!float iso, const ref Ray ray) {
    return Ray(
        iso * ray.position,
        iso * ray.direction,
    );
}

float solveQuadratic(float constantTerm, float halfLinearTerm, float quadraticTerm) {
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
