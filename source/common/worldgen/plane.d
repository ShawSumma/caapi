module common.worldgen.plane;

import core.stdc.math : asinhf, copysignf, expf, fabsf, logf;
import common.coords : CELL_NEIGHBOR_OFFSETS;
import common.dodeca : Side, Vertex, chunkToNode, normal, reflection;
import common.math : MIsometry, MPoint, MVector;
import common.node : ChunkLayout;

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

    float distanceToCell(Vertex chunk, ref const ChunkLayout layout, int[3] cell) const {
        return distanceToChunk(chunk, layout.cellCenter(cell));
    }

    int risingNeighbor(Vertex chunk, ref const ChunkLayout layout, int[3] cell) const {
        int rising = 0;
        float highest = -float.infinity;
        foreach (direction; 0 .. CELL_NEIGHBOR_OFFSETS.length) {
            int[3] offset = CELL_NEIGHBOR_OFFSETS[direction];
            float distance = distanceToCell(chunk, layout, [cell[0] + offset[0], cell[1] + offset[1], cell[2] + offset[2]]);
            if (distance > highest) {
                highest = distance;
                rising = cast(int) direction;
            }
        }
        return rising;
    }
}
