module common.chunk_ray_casting;

import common.chunk_collision : voxelIsSolid;
import common.collision_math : Ray;
import common.math : MDirection, MVector, isNan;
import common.node : ChunkLayout, VoxelData;
import common.voxel_math : CoordAxis, CoordSign, Coords;

struct ChunkRayCastHit {
    float tanhDistance;
    Coords voxelCoords;
    CoordAxis faceAxis;
    CoordSign faceSign;
}

ChunkRayCastHit chunkRayCast(const(VoxelData)* voxelData, ChunkLayout layout, Ray ray, float tanhDistance) {
    ChunkRayCastHit hit;
    hit.tanhDistance = float.nan;
    foreach (tAxis; 0 .. 3) {
        float limit = tanhDistance;
        if (!isNan(hit.tanhDistance)) {
            limit = hit.tanhDistance;
        }
        ChunkRayCastHit newHit = findFaceCollision(voxelData, layout, tAxis, ray, limit);
        if (!isNan(newHit.tanhDistance)) {
            hit = newHit;
        }
    }
    return hit;
}

ChunkRayCastHit findFaceCollision(const(VoxelData)* voxelData, ChunkLayout layout, size_t tAxis, Ray ray, float tanhDistance) {
    ChunkRayCastHit hit;
    hit.tanhDistance = float.nan;
    size_t uAxis = (tAxis + 1) % 3;
    size_t vAxis = (tAxis + 2) % 3;
    foreach (t; 0 .. layout.dimension + 1) {
        float[4] normalData = [0, 0, 0, 0];
        normalData[tAxis] = 1.0f;
        normalData[3] = layout.gridToDual(cast(ubyte) t);
        MDirection!float normal = MVector!float(normalData[0], normalData[1], normalData[2], normalData[3]).normalizedDirection();
        float newTanhDistance = ray.solvePointPlaneIntersection(normal);
        float limit = tanhDistance;
        if (!isNan(hit.tanhDistance)) {
            limit = hit.tanhDistance;
        }
        bool entering = ray.direction.mip(normal.vec) < 0.0f;
        if (!isNan(newTanhDistance) && !(newTanhDistance >= limit) && !(entering && t == 0) && !(!entering && t == layout.dimension)) {
            CoordSign faceSign = CoordSign.Minus;
            ubyte voxelT = cast(ubyte) t;
            if (entering) {
                faceSign = CoordSign.Plus;
                voxelT = cast(ubyte)(t - 1);
            }
            MVector!float rayEndpoint = ray.rayPoint(newTanhDistance);
            MVector!float contact = rayEndpoint - normal.vec * rayEndpoint.mip(normal.vec);
            int voxelU = layout.dualToVoxel(contact.data[uAxis] / contact.data[3]);
            int voxelV = layout.dualToVoxel(contact.data[vAxis] / contact.data[3]);
            if (voxelU >= 0 && voxelV >= 0) {
                ubyte[3] coords;
                coords[tAxis] = voxelT;
                coords[uAxis] = cast(ubyte) voxelU;
                coords[vAxis] = cast(ubyte) voxelV;
                if (voxelIsSolid(voxelData, layout, coords)) {
                    hit.tanhDistance = newTanhDistance;
                    hit.voxelCoords = Coords(coords);
                    hit.faceAxis = cast(CoordAxis) tAxis;
                    hit.faceSign = faceSign;
                }
            }
        }
    }
    return hit;
}
