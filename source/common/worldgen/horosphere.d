/// Horosphere data structures for world generation.
module common.worldgen.horosphere;

import std.math : sqrt, cos, sin, PI;
import common.dodeca;
import common.math;
import common.node;
import common.voxel_math;
import common.world;

/// A horosphere in hyperbolic space.
/// A vector `point` is on this horosphere exactly when `point.mip(pos) == -1`.
/// `pos` should always satisfy `pos.mip(pos) == 0` (light-like vector).
struct Horosphere {
    /// Light-like position vector representing the horosphere.
    MVector!float pos;

    /// Returns whether the point is inside the horosphere
    bool containsPoint(const ref MPoint!float point) const {
        return pos.mip(point.vec) >= -1.0f;
    }

    /// Returns whether the horosphere is entirely inside the half space
    /// in front of the plane defined by `normal`
    bool isInsideHalfSpace(const ref MDirection!float normal) const {
        return pos.mip(normal.vec) >= 1.0f;
    }

    /// Returns whether any part of the horosphere intersects the half space
    /// in front of the plane defined by `normal`
    bool intersectsHalfSpace(const ref MDirection!float normal) const {
        return pos.mip(normal.vec) >= -1.0f;
    }

    /// Ensures that the horosphere invariant holds (pos.mip(pos) == 0)
    void renormalize() {
        auto xyz = pos.xyz();
        pos.w = sqrt(xyz[0] * xyz[0] + xyz[1] * xyz[1] + xyz[2] * xyz[2]);
    }

    /// Transform by an isometry
    Horosphere transform(const ref MIsometry!float iso) const {
        return Horosphere(iso * pos);
    }
}

/// Represents a chunk's reference to a particular horosphere.
struct HorosphereChunk {
    /// The horosphere's location relative to the chunk
    Horosphere horosphere;

    /// Rasterizes the horosphere chunk into the given VoxelData
    void generate(ref VoxelData voxels, ubyte chunkSize) {
        foreach (z; 0 .. chunkSize) {
            foreach (y; 0 .. chunkSize) {
                foreach (x; 0 .. chunkSize) {
                    auto pos = MVector!float(
                        cast(float) x + 0.5f,
                        cast(float) y + 0.5f,
                        cast(float) z + 0.5f,
                        cast(float) chunkSize * vertexDualToChunkFactor(),
                    ).normalizedPoint();
                    if (horosphere.containsPoint(pos)) {
                        voxels.dataMut(chunkSize)[Coords([cast(ubyte) x, cast(ubyte) y, cast(ubyte) z]).toIndex(chunkSize)] =
                            Material.RedSandstone;
                    }
                }
            }
        }
    }
}
