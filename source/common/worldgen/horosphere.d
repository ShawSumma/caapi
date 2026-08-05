module common.worldgen.horosphere;

import core.stdc.math : sqrtf;
import common.dodeca : vertexDualToChunkFactor;
import common.math : MVector, MPoint, MDirection, MIsometry;
import common.node : VoxelData;
import common.voxel_math : Coords;
import common.world : Material;

struct Horosphere {
    MVector!float pos;

    bool containsPoint(const ref MPoint!float point) const {
        return pos.mip(point.vec) >= -1.0f;
    }

    bool isInsideHalfSpace(const ref MDirection!float normal) const {
        return pos.mip(normal.vec) >= 1.0f;
    }

    bool intersectsHalfSpace(const ref MDirection!float normal) const {
        return pos.mip(normal.vec) >= -1.0f;
    }

    void renormalize() {
        float[3] xyz = pos.xyz();
        pos.w = sqrtf(xyz[0] * xyz[0] + xyz[1] * xyz[1] + xyz[2] * xyz[2]);
    }

    Horosphere transform(const ref MIsometry!float iso) const {
        return Horosphere(iso * pos);
    }
}

struct HorosphereChunk {
    Horosphere horosphere;

    void generate(ref VoxelData voxels, ubyte chunkSize) {
        foreach (z; 0 .. chunkSize) {
            foreach (y; 0 .. chunkSize) {
                foreach (x; 0 .. chunkSize) {
                    MPoint!float pos = MVector!float(
                        cast(float) x + 0.5f,
                        cast(float) y + 0.5f,
                        cast(float) z + 0.5f,
                        cast(float) chunkSize * vertexDualToChunkFactor(),
                    ).normalizedPoint();
                    if (horosphere.containsPoint(pos)) {
                        ubyte[3] voxel = [
                            cast(ubyte) x,
                            cast(ubyte) y,
                            cast(ubyte) z,
                        ];
                        size_t idx = Coords(voxel).toIndex(chunkSize);
                        voxels.dataMut(chunkSize)[idx] = Material.RedSandstone;
                    }
                }
            }
        }
    }
}
