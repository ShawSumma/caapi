/// A hyperbolic plane for use with world generation.
module common.worldgen.plane;

import std.math : asinh, log, exp, fabs, copysign;
import common.dodeca;
import common.math;

/// A hyperbolic plane. Uses a separate "exponent" field to allow for planes
/// very far from the origin.
struct Plane {
    MVector!float scaledNormal;
    float exponent = 0.0f;

    /// Construct from a direction (plane through origin)
    static Plane fromDirection(MDirection!float normal) {
        return Plane(normal.vec, 0.0f);
    }

    /// Construct from a Side (surface overlapping with a dodecahedron side)
    static Plane fromSide(Side side) {
        return Plane.fromDirection(sideNormal(side));
    }

    /// Negate the plane (flip orientation)
    Plane opUnary(string op)() const if (op == "-") {
        return Plane(-scaledNormal, exponent);
    }

    /// Reflect this plane across a side
    Plane reflectAcross(Side side) const {
        return transformBy(sideReflection(side));
    }

    /// Transform this plane by an isometry
    Plane transformBy(const ref MIsometry!float iso) const {
        auto newNormal = iso * scaledNormal;
        return Plane(newNormal, exponent).updateExponent();
    }

    /// Shortest distance between the plane and a point
    float distanceTo(const ref MPoint!float point) const {
        float mipVal = scaledNormal.mip(point.vec);
        if (exponent == 0.0f) {
            return asinh(mipVal);
        } else {
            float mip2 = mipVal * 2.0f;
            return (log(fabs(mip2)) + exponent) * copysign(1.0f, mip2);
        }
    }

    /// Like distanceTo, but using chunk coordinates for a chunk in the same node space
    float distanceToChunk(Vertex chunk, float[3] coord) const {
        auto chunkToNode = vertexChunkToNode(chunk);
        auto v = MVector!float(coord[0], coord[1], coord[2], 1.0f);
        auto transformed = chunkToNode * v;
        auto pos = transformed.normalizedPoint();
        return distanceTo(pos);
    }

    private Plane updateExponent() {
        auto result = this;
        while (fabs(result.scaledNormal.w) > 1.0e8f) {
            result.scaledNormal = result.scaledNormal * exp(-16.0f);
            result.exponent += 16.0f;
        }
        return result;
    }
}
