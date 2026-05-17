module common.chunk_collision;

import common.collision_math;
import common.math;
import common.node;
import common.voxel_math;
import common.world;
import std.math : isNaN, sinh;
import std.algorithm : min;

struct ChunkCollisionHit {
    float tanhDistance;
    MVector!float normal;
}

/// Performs sphere casting against voxels in a chunk
ChunkCollisionHit chunkSphereCast(
    float colliderRadius,
    const ref VoxelData voxelData,
    const ref ChunkLayout layout,
    const ref Ray ray,
    float tanhDistance
) {
    ChunkCollisionHit hit;
    hit.tanhDistance = float.nan;

    float currentDist() {
        return !isNaN(hit.tanhDistance) ? hit.tanhDistance : tanhDistance;
    }

    foreach (tAxis; 0 .. 3) {
        auto newHit = findFaceCollision(colliderRadius, voxelData, layout, tAxis, ray, currentDist());
        if (!isNaN(newHit.tanhDistance)) hit = newHit;
    }

    foreach (tAxis; 0 .. 3) {
        auto newHit = findEdgeCollision(colliderRadius, voxelData, layout, tAxis, ray, currentDist());
        if (!isNaN(newHit.tanhDistance)) hit = newHit;
    }

    auto vertHit = findVertexCollision(colliderRadius, voxelData, layout, ray, currentDist());
    if (!isNaN(vertHit.tanhDistance)) hit = vertHit;

    return hit;
}

private ChunkCollisionHit findFaceCollision(
    float colliderRadius,
    const ref VoxelData voxelData,
    const ref ChunkLayout layout,
    size_t tAxis,
    const ref Ray ray,
    float tanhDistance
) {
    ChunkCollisionHit hit;
    hit.tanhDistance = float.nan;

    size_t uAxis = (tAxis + 1) % 3;
    size_t vAxis = (tAxis + 2) % 3;
    float sinhR = sinh(colliderRadius);

    foreach (t; 0 .. layout.dimension + 1) {
        float[4] nData = [0, 0, 0, 0];
        nData[tAxis] = 1.0f;
        nData[3] = layout.gridToDual(cast(ubyte) t);
        auto normal = MVector!float(nData[0], nData[1], nData[2], nData[3]).normalizedDirection();

        float newDist = ray.solveSphereePlaneIntersection(normal, sinhR);
        if (isNaN(newDist)) continue;
        if (newDist >= (!isNaN(hit.tanhDistance) ? hit.tanhDistance : tanhDistance)) continue;

        MDirection!float faceNormal;
        ubyte voxelT;
        if (ray.direction.mip(normal) < 0.0f) {
            if (t == 0) continue;
            faceNormal = normal;
            voxelT = cast(ubyte)(t - 1);
        } else {
            if (t == layout.dimension) continue;
            faceNormal = -normal;
            voxelT = cast(ubyte) t;
        }

        auto rayEndpoint = ray.rayPoint(newDist);
        auto contact = rayEndpoint - faceNormal.vec * rayEndpoint.mip(faceNormal.vec);

        int voxelU = layout.dualToVoxel(contact.data[uAxis] / contact.data[3]);
        if (voxelU < 0) continue;
        int voxelV = layout.dualToVoxel(contact.data[vAxis] / contact.data[3]);
        if (voxelV < 0) continue;

        ubyte[3] coords;
        coords[tAxis] = voxelT;
        coords[uAxis] = cast(ubyte) voxelU;
        coords[vAxis] = cast(ubyte) voxelV;
        if (!voxelIsSolid(voxelData, layout, coords)) continue;

        hit.tanhDistance = newDist;
        hit.normal = faceNormal.vec;
    }

    return hit;
}

private ChunkCollisionHit findEdgeCollision(
    float colliderRadius,
    const ref VoxelData voxelData,
    const ref ChunkLayout layout,
    size_t tAxis,
    const ref Ray ray,
    float tanhDistance
) {
    ChunkCollisionHit hit;
    hit.tanhDistance = float.nan;

    size_t uAxis = (tAxis + 1) % 3;
    size_t vAxis = (tAxis + 2) % 3;
    float sinhR = sinh(colliderRadius);

    foreach (u; 0 .. layout.dimension + 1) {
        foreach (v; 0 .. layout.dimension + 1) {
            float[4] n0Data = [0, 0, 0, 0];
            n0Data[uAxis] = 1.0f;
            n0Data[3] = layout.gridToDual(cast(ubyte) u);
            auto edgeNormal0 = MVector!float(n0Data[0], n0Data[1], n0Data[2], n0Data[3]).normalizedDirection();

            float[4] n1Data = [0, 0, 0, 0];
            n1Data[vAxis] = 1.0f;
            n1Data[3] = layout.gridToDual(cast(ubyte) v);
            auto en1 = MVector!float(n1Data[0], n1Data[1], n1Data[2], n1Data[3]);
            auto edgeNormal1 = (en1 - edgeNormal0.vec * edgeNormal0.mip(en1)).normalizedDirection();

            float newDist = ray.solveSpherLineIntersection(edgeNormal0, edgeNormal1, sinhR);
            if (isNaN(newDist)) continue;
            if (newDist >= (!isNaN(hit.tanhDistance) ? hit.tanhDistance : tanhDistance)) continue;

            auto rayEndpoint = ray.rayPoint(newDist);
            auto contact = rayEndpoint - edgeNormal0.vec * rayEndpoint.mip(edgeNormal0.vec)
                                       - edgeNormal1.vec * rayEndpoint.mip(edgeNormal1.vec);

            int voxelT = layout.dualToVoxel(contact.data[tAxis] / contact.data[3]);
            if (voxelT < 0) continue;

            // Check neighboring voxels
            bool hasSolid = false;
            foreach (vu; neighborRange(layout.dimension, cast(ubyte) u)) {
                foreach (vv; neighborRange(layout.dimension, cast(ubyte) v)) {
                    ubyte[3] coords;
                    coords[tAxis] = cast(ubyte) voxelT;
                    coords[uAxis] = vu;
                    coords[vAxis] = vv;
                    if (voxelIsSolid(voxelData, layout, coords)) {
                        hasSolid = true;
                        break;
                    }
                }
                if (hasSolid) break;
            }
            if (!hasSolid) continue;

            hit.tanhDistance = newDist;
            hit.normal = rayEndpoint - contact;
        }
    }

    return hit;
}

private ChunkCollisionHit findVertexCollision(
    float colliderRadius,
    const ref VoxelData voxelData,
    const ref ChunkLayout layout,
    const ref Ray ray,
    float tanhDistance
) {
    ChunkCollisionHit hit;
    hit.tanhDistance = float.nan;

    float sinhR = sinh(colliderRadius);

    foreach (x; 0 .. layout.dimension + 1) {
        foreach (y; 0 .. layout.dimension + 1) {
            foreach (z; 0 .. layout.dimension + 1) {
                // Check neighboring voxels
                bool hasSolid = false;
                foreach (vx; neighborRange(layout.dimension, cast(ubyte) x)) {
                    foreach (vy; neighborRange(layout.dimension, cast(ubyte) y)) {
                        foreach (vz; neighborRange(layout.dimension, cast(ubyte) z)) {
                            if (voxelIsSolid(voxelData, layout, [vx, vy, vz])) {
                                hasSolid = true;
                                break;
                            }
                        }
                        if (hasSolid) break;
                    }
                    if (hasSolid) break;
                }
                if (!hasSolid) continue;

                auto vn0 = MVector!float(1.0f, 0, 0, layout.gridToDual(cast(ubyte) x)).normalizedDirection();
                auto vn1v = MVector!float(0, 1.0f, 0, layout.gridToDual(cast(ubyte) y));
                auto vn1 = (vn1v - vn0.vec * vn0.mip(vn1v)).normalizedDirection();
                auto vn2v = MVector!float(0, 0, 1.0f, layout.gridToDual(cast(ubyte) z));
                auto vn2 = (vn2v - vn0.vec * vn0.mip(vn2v) - vn1.vec * vn1.mip(vn2v)).normalizedDirection();

                float newDist = ray.solveSpherePointIntersection(vn0, vn1, vn2, sinhR);
                if (isNaN(newDist)) continue;
                if (newDist >= (!isNaN(hit.tanhDistance) ? hit.tanhDistance : tanhDistance)) continue;

                auto vertexPos = MVector!float(
                    layout.gridToDual(cast(ubyte) x),
                    layout.gridToDual(cast(ubyte) y),
                    layout.gridToDual(cast(ubyte) z),
                    1.0f
                ).normalizedPoint();

                auto rayEndpoint = ray.rayPoint(newDist);
                hit.tanhDistance = newDist;
                hit.normal = rayEndpoint - vertexPos.vec;
            }
        }
    }

    return hit;
}

private bool voxelIsSolid(const ref VoxelData voxelData, const ref ChunkLayout layout, ubyte[3] coords) {
    if (coords[0] >= layout.dimension || coords[1] >= layout.dimension || coords[2] >= layout.dimension) {
        return false;
    }
    return voxelData.get(Coords(coords).toIndex(layout.dimension)) != Material.Void;
}

private auto neighborRange(ubyte dimension, ubyte gridCoord) {
    ubyte lo = gridCoord > 0 ? cast(ubyte)(gridCoord - 1) : 0;
    ubyte hi = min(cast(ubyte)(gridCoord + 1), cast(ubyte)(dimension - 1));
    struct Range {
        ubyte lo, hi;
        bool empty() const { return lo > hi; }
        ubyte front() const { return lo; }
        void popFront() { lo++; }
    }
    return Range(lo, hi);
}
