module common.worldgen.plane;

import core.stdc.math : asinhf, copysignf, expf, fabsf, logf;
import common.dodeca : Side, Vertex, sideNormal, sideReflection;
import common.dodeca : vertexChunkToNode;
import common.math : Matrix4, MVector, MPoint, MDirection, MIsometry;

struct Plane {
    MVector!float scaledNormal;
    float exponent = 0.0f;

    static Plane fromDirection(MDirection!float normal) {
        return Plane(normal.vec, 0.0f);
    }

    static Plane fromSide(Side side) {
        return Plane.fromDirection(sideNormal(side));
    }

    Plane opUnary(string op)() const if (op == "-") {
        return Plane(-scaledNormal, exponent);
    }

    Plane reflectAcross(Side side) const {
        return transformBy(sideReflection(side));
    }

    Plane transformBy(const ref MIsometry!float iso) const {
        MVector!float newNormal = iso * scaledNormal;
        return Plane(newNormal, exponent).updateExponent();
    }

    float distanceTo(const ref MPoint!float point) const {
        float mipVal = scaledNormal.mip(point.vec);
        if (exponent == 0.0f) {
            return asinhf(mipVal);
        }
        float mip2 = mipVal * 2.0f;
        return (logf(fabsf(mip2)) + exponent) * copysignf(1.0f, mip2);
    }

    float distanceToChunk(Vertex chunk, float[3] coord) const {
        Matrix4!float chunkToNode = vertexChunkToNode(chunk);
        MVector!float v = MVector!float(coord[0], coord[1], coord[2], 1.0f);
        MVector!float transformed = chunkToNode * v;
        MPoint!float pos = transformed.normalizedPoint();
        return distanceTo(pos);
    }

    Plane updateExponent() {
        Plane result = this;
        while (fabsf(result.scaledNormal.w) > 1.0e8f) {
            result.scaledNormal = result.scaledNormal * expf(-16.0f);
            result.exponent = result.exponent + 16.0f;
        }
        return result;
    }
}
