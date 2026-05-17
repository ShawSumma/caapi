module common.chunk_ray_casting;

import common.collision_math;
import common.math;
import common.node;
import common.voxel_math;
import common.world;
import std.math : isNaN;

struct ChunkRayCastHit {
    float tanhDistance;
    Coords voxelCoords;
    CoordAxis faceAxis;
    CoordSign faceSign;
}

/// Performs ray casting against the voxels in a chunk
ChunkRayCastHit chunkRayCast(
    const ref VoxelData voxelData,
    const ref ChunkLayout layout,
    const ref Ray ray,
    float tanhDistance
) {
    ChunkRayCastHit hit;
    hit.tanhDistance = float.nan;

    foreach (tAxis; 0 .. 3) {
        auto newHit = findFaceCollision(voxelData, layout, tAxis, ray,
            !isNaN(hit.tanhDistance) ? hit.tanhDistance : tanhDistance);
        if (!isNaN(newHit.tanhDistance)) {
            hit = newHit;
        }
    }

    return hit;
}

private ChunkRayCastHit findFaceCollision(
    const ref VoxelData voxelData,
    const ref ChunkLayout layout,
    size_t tAxis,
    const ref Ray ray,
    float tanhDistance
) {
    ChunkRayCastHit hit;
    hit.tanhDistance = float.nan;

    size_t uAxis = (tAxis + 1) % 3;
    size_t vAxis = (tAxis + 2) % 3;

    foreach (t; 0 .. layout.dimension + 1) {
        // Normal to the grid plane
        float[4] nData = [0, 0, 0, 0];
        nData[tAxis] = 1.0f;
        nData[3] = layout.gridToDual(cast(ubyte) t);
        auto normal = MVector!float(nData[0], nData[1], nData[2], nData[3]).normalizedDirection();

        float newTanhDist = ray.solvePointPlaneIntersection(normal);
        if (isNaN(newTanhDist)) continue;
        if (newTanhDist >= (!isNaN(hit.tanhDistance) ? hit.tanhDistance : tanhDistance)) continue;

        // Determine face sign and voxel_t
        CoordSign faceSign;
        ubyte voxelT;
        if (ray.direction.mip(normal) < 0.0f) {
            if (t == 0) continue;
            faceSign = CoordSign.Plus;
            voxelT = cast(ubyte)(t - 1);
        } else {
            if (t == layout.dimension) continue;
            faceSign = CoordSign.Minus;
            voxelT = cast(ubyte) t;
        }

        auto rayEndpoint = ray.rayPoint(newTanhDist);
        auto contact = rayEndpoint - normal.vec * rayEndpoint.mip(normal.vec);

        int voxelU = layout.dualToVoxel(contact.data[uAxis] / contact.data[3]);
        if (voxelU < 0) continue;
        int voxelV = layout.dualToVoxel(contact.data[vAxis] / contact.data[3]);
        if (voxelV < 0) continue;

        // Check if voxel is solid
        ubyte[3] coords;
        coords[tAxis] = voxelT;
        coords[uAxis] = cast(ubyte) voxelU;
        coords[vAxis] = cast(ubyte) voxelV;
        if (!voxelIsSolid(voxelData, layout, coords)) continue;

        hit.tanhDistance = newTanhDist;
        hit.voxelCoords = Coords(coords);
        hit.faceAxis = cast(CoordAxis) tAxis;
        hit.faceSign = faceSign;
    }

    return hit;
}

private bool voxelIsSolid(const ref VoxelData voxelData, const ref ChunkLayout layout, ubyte[3] coords) {
    return voxelData.get(Coords(coords).toIndex(layout.dimension)) != Material.Void;
}
