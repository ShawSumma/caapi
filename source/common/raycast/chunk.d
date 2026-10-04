module common.raycast.chunk;

import common.collision.chunk : isVoxelSolid;
import common.coords : CoordAxis, CoordSign, Coords;
import common.math : MDirection, MVector, isNan;
import common.node : ChunkLayout, VoxelData;
import common.ray : Ray;

struct ChunkRayCastHit {
    float tanhDistance = float.nan;
    Coords voxelCoords;
    CoordAxis faceAxis;
    CoordSign faceSign;

    bool isHit() const {
        return !isNan(tanhDistance);
    }

    float limitWithin(float tanhLimit) const {
        if (isHit()) {
            return tanhDistance;
        } else {
            return tanhLimit;
        }
    }
}

ChunkRayCastHit chunkRayCast(ref const VoxelData voxelData, ChunkLayout layout, Ray ray, float tanhDistance) {
    ChunkRayCastHit hit;
    foreach (tAxis; 0 .. 3) {
        ChunkRayCastHit newHit = voxelData.findFaceCollision(layout, tAxis, ray, hit.limitWithin(tanhDistance));
        if (newHit.isHit()) {
            hit = newHit;
        }
    }
    return hit;
}

ChunkRayCastHit findFaceCollision(ref const VoxelData voxelData, ChunkLayout layout, size_t tAxis, Ray ray, float tanhDistance) {
    ChunkRayCastHit hit;
    foreach (t; 0 .. layout.dimension + 1) {
        ChunkRayCastHit planeHit = voxelData.planeCollision(layout, tAxis, cast(ubyte) t, ray, hit.limitWithin(tanhDistance));
        if (planeHit.isHit()) {
            hit = planeHit;
        }
    }
    return hit;
}

ChunkRayCastHit planeCollision(ref const VoxelData voxelData, ChunkLayout layout, size_t tAxis, ubyte t, Ray ray, float limit) {
    size_t uAxis = (tAxis + 1) % 3;
    size_t vAxis = (tAxis + 2) % 3;
    float[4] normalData = [0, 0, 0, 0];
    normalData[tAxis] = 1.0f;
    normalData[3] = layout.gridToDual(t);
    MDirection!float normal = MVector!float(normalData).normalizedDirection();
    float newTanhDistance = ray.solvePointPlaneIntersection(normal);
    bool isEntering = ray.direction.mip(normal.vec) < 0.0f;
    if (isNan(newTanhDistance) || newTanhDistance >= limit || (isEntering && t == 0) || (!isEntering && t == layout.dimension)) {
        return ChunkRayCastHit.init;
    } else {
        MVector!float rayEndpoint = ray.rayPoint(newTanhDistance);
        MVector!float contact = rayEndpoint - normal.vec * rayEndpoint.mip(normal.vec);
        int voxelU = layout.dualToVoxel(contact.data[uAxis] / contact.data[3]);
        int voxelV = layout.dualToVoxel(contact.data[vAxis] / contact.data[3]);
        ubyte[3] coords;
        coords[tAxis] = enteredVoxel(t, isEntering);
        coords[uAxis] = cast(ubyte) voxelU;
        coords[vAxis] = cast(ubyte) voxelV;
        if (voxelU >= 0 && voxelV >= 0 && voxelData.isVoxelSolid(layout, coords)) {
            return ChunkRayCastHit(newTanhDistance, Coords(coords), cast(CoordAxis) tAxis, enteredFaceSign(isEntering));
        } else {
            return ChunkRayCastHit.init;
        }
    }
}

ubyte enteredVoxel(ubyte t, bool isEntering) {
    if (isEntering) {
        return cast(ubyte)(t - 1);
    } else {
        return t;
    }
}

CoordSign enteredFaceSign(bool isEntering) {
    if (isEntering) {
        return CoordSign.plus;
    } else {
        return CoordSign.minus;
    }
}
