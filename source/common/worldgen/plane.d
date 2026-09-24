module common.worldgen.plane;

import core.stdc.math : asinhf, copysignf, expf, fabsf, logf;
import common.dodeca : Side, Vertex, sideNormal, sideReflection, vertexChunkToNode;
import common.math : MIsometry, MPoint, MVector;

enum float EXPONENT_RESCALE_THRESHOLD = 1.0e8f;
enum float EXPONENT_STEP = 16.0f;

struct Plane {
    MVector!float scaledNormal;
    float exponent = 0.0f;

    Plane opUnary(string op)() const if (op == "-") {
        return Plane(-scaledNormal, exponent);
    }

    Plane reflectAcross(Side side) const {
        return transformBy(sideReflection(side));
    }

    Plane transformBy(MIsometry!float iso) const {
        return withUpdatedExponent(Plane(iso * scaledNormal, exponent));
    }

    float distanceTo(MPoint!float point) const {
        float product = scaledNormal.mip(point.vec);
        float result;
        if (exponent == 0.0f) {
            result = asinhf(product);
        } else {
            float doubled = product * 2.0f;
            result = (logf(fabsf(doubled)) + exponent) * copysignf(1.0f, doubled);
        }
        return result;
    }

    float distanceToChunk(Vertex chunk, float[3] coord) const {
        MVector!float transformed = vertexChunkToNode(chunk) * MVector!float(coord[0], coord[1], coord[2], 1.0f);
        return distanceTo(transformed.normalizedPoint());
    }
}

Plane planeFromSide(Side side) {
    return Plane(sideNormal(side).vec, 0.0f);
}

Plane withUpdatedExponent(Plane plane) {
    Plane result = plane;
    while (fabsf(result.scaledNormal.data[3]) > EXPONENT_RESCALE_THRESHOLD) {
        result.scaledNormal = result.scaledNormal * expf(-EXPONENT_STEP);
        result.exponent += EXPONENT_STEP;
    }
    return result;
}
