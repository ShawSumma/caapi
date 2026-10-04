module common.worldgen.plane;

import core.stdc.math : asinhf, copysignf, expf, fabsf, logf;
import common.dodeca : Side, Vertex, chunkToNode, normal, reflection;
import common.math : MIsometry, MPoint, MVector;

enum float EXPONENT_RESCALE_THRESHOLD = 1.0e8f;
enum float EXPONENT_STEP = 16.0f;

struct Plane {
    MVector!float scaledNormal;
    float exponent = 0.0f;

    static Plane fromSide(Side side) {
        return Plane(side.normal.vec, 0.0f);
    }

    Plane opUnary(string op)() const if (op == "-") {
        return Plane(-scaledNormal, exponent);
    }

    Plane reflectAcross(Side side) const {
        return transformBy(side.reflection);
    }

    Plane transformBy(MIsometry!float iso) const {
        return Plane(iso * scaledNormal, exponent).rescaled();
    }

    Plane rescaled() const {
        Plane result = this;
        while (fabsf(result.scaledNormal.data[3]) > EXPONENT_RESCALE_THRESHOLD) {
            result.scaledNormal = result.scaledNormal * expf(-EXPONENT_STEP);
            result.exponent += EXPONENT_STEP;
        }
        return result;
    }

    float distanceTo(MPoint!float point) const {
        float product = scaledNormal.mip(point.vec);
        if (exponent == 0.0f) {
            return asinhf(product);
        } else {
            float doubled = product * 2.0f;
            return (logf(fabsf(doubled)) + exponent) * copysignf(1.0f, doubled);
        }
    }

    float distanceToChunk(Vertex chunk, float[3] coord) const {
        MVector!float transformed = chunk.chunkToNode * MVector!float([coord[0], coord[1], coord[2], 1.0f]);
        return distanceTo(transformed.normalizedPoint());
    }
}
