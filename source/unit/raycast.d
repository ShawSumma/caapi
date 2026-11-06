module unit.raycast;

import base.maybe : Maybe;
import base.vector3 : Vec3;
import common.material : PLAIN_SOLID, including;
import common.node : ChunkLayout, Voxels, cellIndex;
import common.raycast.chunk : ChunkRayCastHit, castThroughChunk;
import geometry.cube : AXIS_COUNT, Axis, Sign;
import geometry.lorentz : Point, Vec4;
import geometry.ray : Ray;
import plugins.api.api : Material;

enum ubyte DIMENSION = 4;
immutable Vec3!int TARGET = Vec3!int(1, 2, 3);
enum float START_KLEIN = -0.2f;
enum float TOLERANCE = 1e-4f;
enum uint RAYS = 200;
enum uint MARCH_STEPS = 20000;
enum ulong SEED = 0x2545F4914F6CDD1D;

unittest {
    ChunkLayout layout = ChunkLayout.make(DIMENSION);
    Voxels voxels = Voxels.filled(Material.none);
    voxels.toDense(DIMENSION)[cellIndex(DIMENSION, TARGET.x, TARGET.y, TARGET.z)] = Material.granite;
    Vec3!float center = Vec3!float(layout.gridToKlein(TARGET.x + 0.5f), layout.gridToKlein(TARGET.y + 0.5f), layout.gridToKlein(TARGET.z + 0.5f));
    Point!float from = Vec4!float([START_KLEIN, center.y, center.z, 1]).toPoint();
    Point!float to = Vec4!float([center.x, center.y, center.z, 1]).toPoint();
    Ray ray = Ray(from, (to.v + from.v * from.minkowski(to.v)).toNormal());
    Maybe!ChunkRayCastHit hit = castThroughChunk(voxels, layout, ray, 1, PLAIN_SOLID);
    assert(hit.exists && hit.value.voxelCoords == TARGET.as!ubyte() && hit.value.faceAxis == Axis.x && hit.value.faceSign == Sign.minus);
    Vec4!float reached = ray.at(hit.value.tanhDistance);
    float wall = layout.gridToKlein(TARGET.x);
    assert(reached.c[0] / reached.c[3] - wall < TOLERANCE && wall - reached.c[0] / reached.c[3] < TOLERANCE);
    Maybe!ChunkRayCastHit stoppedShort = castThroughChunk(voxels, layout, ray, hit.value.tanhDistance, PLAIN_SOLID);
    assert(!stoppedShort.exists);
    voxels.toDense(DIMENSION)[cellIndex(DIMENSION, TARGET.x, TARGET.y, TARGET.z)] = Material.mistStone;
    assert(!castThroughChunk(voxels, layout, ray, 1, PLAIN_SOLID).exists);
    assert(castThroughChunk(voxels, layout, ray, 1, PLAIN_SOLID.including(Material.mistStone)).exists);
    voxels.release();
}

Maybe!(Vec3!int) cellOn(ChunkLayout layout, Ray ray, float t) {
    Vec4!float at = ray.at(t);
    Vec3!int cell;
    foreach (axis; 0 .. AXIS_COUNT) {
        Maybe!int along = layout.kleinToCell(at.c[axis] / at.c[3]);
        if (!along.exists) {
            return Maybe!(Vec3!int).init;
        }
        cell[axis] = along.value;
    }
    return Maybe!(Vec3!int).of(cell);
}

Maybe!ChunkRayCastHit marched(ref const Voxels voxels, ChunkLayout layout, Ray ray, float limit) {
    Maybe!ChunkRayCastHit hit;
    Maybe!(Vec3!int) first = cellOn(layout, ray, 0);
    uint step = 1;
    while (step < MARCH_STEPS && !hit.exists) {
        float t = limit * step / MARCH_STEPS;
        Maybe!(Vec3!int) found = cellOn(layout, ray, t);
        if (found.exists && found != first) {
            Vec3!int cell = found.value;
            if (voxels.at(cellIndex(layout.dimension, cell.x, cell.y, cell.z)) != Material.none) {
                hit = Maybe!ChunkRayCastHit.of(ChunkRayCastHit(t, cell.as!ubyte()));
            }
        }
        step += 1;
    }
    return hit;
}

float shuffled(ref ulong state) {
    state ^= state << 13;
    state ^= state >> 7;
    state ^= state << 17;
    return (state >> 40) / cast(float)(1 << 24);
}

unittest {
    ChunkLayout layout = ChunkLayout.make(DIMENSION);
    float size = layout.gridToKlein(DIMENSION);
    Voxels voxels = Voxels.filled(Material.none);
    Material[] cells = voxels.toDense(DIMENSION);
    ulong state = SEED;
    foreach (index; 0 .. cells.length) {
        cells[index] = Material.none;
        if (shuffled(state) < 0.15f) {
            cells[index] = Material.granite;
        }
    }
    uint hits = 0;
    foreach (_; 0 .. RAYS) {
        Vec3!float from;
        Vec3!float to;
        foreach (axis; 0 .. AXIS_COUNT) {
            from[axis] = (shuffled(state) * 1.6f - 0.3f) * size;
            to[axis] = shuffled(state) * size;
        }
        Point!float start = Vec4!float([from.x, from.y, from.z, 1]).toPoint();
        Point!float aim = Vec4!float([to.x, to.y, to.z, 1]).toPoint();
        Ray ray = Ray(start, (aim.v + start.v * start.minkowski(aim.v)).toNormal());
        Maybe!ChunkRayCastHit walked = castThroughChunk(voxels, layout, ray, 0.9f, PLAIN_SOLID);
        Maybe!ChunkRayCastHit expected = marched(voxels, layout, ray, 0.9f);
        assert(walked.exists == expected.exists);
        if (walked.exists) {
            hits += 1;
            assert(walked.value.voxelCoords == expected.value.voxelCoords);
            assert(walked.value.tanhDistance <= expected.value.tanhDistance + 0.9f / MARCH_STEPS);
        }
    }
    assert(hits > RAYS / 4);
    voxels.release();
}
