module common.worldgen.plane;

import core.stdc.math : asinhf, copysignf, expf, fabsf, logf, sqrtf;
import common.character.chart : applied, gridJacobian;
import common.dodeca : Side, Vertex, chunkToNode, nodeToDual, normal, reflection;
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

    float[3] upAt(MIsometry!float local) const {
        float[3] gradient = (local.inverse() * scaledNormal).xyz();
        float length = sqrtf(gradient[0] * gradient[0] + gradient[1] * gradient[1] + gradient[2] * gradient[2]);
        return [gradient[0] / length, gradient[1] / length, gradient[2] / length];
    }

    float[3] gridUpAt(Vertex chunk, ref const ChunkLayout layout, float[3] grid) const {
        MPoint!float point = (chunk.chunkToNode * MVector!float([layout.gridToChunk(grid[0]), layout.gridToChunk(grid[1]), layout.gridToChunk(grid[2]), 1.0f])).normalizedPoint();
        MIsometry!float local = MIsometry!float.fromTranslation(MPoint!float.origin(), point);
        float[3] up = applied(gridJacobian(layout, chunk.nodeToDual * local), upAt(local));
        float length = sqrtf(up[0] * up[0] + up[1] * up[1] + up[2] * up[2]);
        return [up[0] / length, up[1] / length, up[2] / length];
    }

    int risingNeighbor(Vertex chunk, ref const ChunkLayout layout, int[3] cell) const {
        float[3] up = gridUpAt(chunk, layout, [cell[0] + 0.5f, cell[1] + 0.5f, cell[2] + 0.5f]);
        int rising = 0;
        float steepest = -float.infinity;
        foreach (axis; 0 .. 3) {
            if (fabsf(up[axis]) > steepest) {
                steepest = fabsf(up[axis]);
                rising = cast(int)(2 * axis) + (up[axis] > 0);
            }
        }
        return rising;
    }
}
