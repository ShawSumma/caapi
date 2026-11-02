module unit.raycast;

import common.node : ChunkLayout, Voxels, cellIndex;
import common.raycast.chunk : ChunkRayCastHit, castThroughChunk;
import geometry.cube : AXIS_COUNT, Axis, Cell, Sign;
import geometry.lorentz : Point, Vec4;
import geometry.ray : Ray;
import plugins.api.api : Material;

enum ubyte DIMENSION = 4;
immutable int[3] TARGET = [1, 2, 3];
enum float START_KLEIN = -0.2f;
enum float TOLERANCE = 1e-4f;
enum uint RAYS = 200;
enum uint MARCH_STEPS = 20000;
enum ulong SEED = 0x2545F4914F6CDD1D;

unittest {
    ChunkLayout layout = ChunkLayout.make(DIMENSION);
    Voxels voxels = Voxels.filled(Material.none);
    voxels.toDense(DIMENSION)[cellIndex(DIMENSION, TARGET[0], TARGET[1], TARGET[2])] = Material.granite;
    float[3] center = [layout.gridToKlein(TARGET[0] + 0.5f), layout.gridToKlein(TARGET[1] + 0.5f), layout.gridToKlein(TARGET[2] + 0.5f)];
    Point!float from = Vec4!float([START_KLEIN, center[1], center[2], 1]).toPoint();
    Point!float to = Vec4!float([center[0], center[1], center[2], 1]).toPoint();
    Ray ray = Ray(from, (to.v + from.v * from.minkowski(to.v)).toNormal());
    ChunkRayCastHit hit = castThroughChunk(voxels, layout, ray, 1);
    assert(hit.isHit() && hit.voxelCoords.c == [1, 2, 3] && hit.faceAxis == Axis.x && hit.faceSign == Sign.minus);
    Vec4!float reached = ray.at(hit.tanhDistance);
    float wall = layout.gridToKlein(TARGET[0]);
    assert(reached.c[0] / reached.c[3] - wall < TOLERANCE && wall - reached.c[0] / reached.c[3] < TOLERANCE);
    assert(!castThroughChunk(voxels, layout, ray, hit.tanhDistance).isHit());
    voxels.release();
}

int[3] cellOn(ChunkLayout layout, Ray ray, float t) {
    Vec4!float at = ray.at(t);
    int[3] cell;
    foreach (axis; 0 .. AXIS_COUNT) {
        cell[axis] = layout.kleinToCell(at.c[axis] / at.c[3]);
    }
    return cell;
}

ChunkRayCastHit marched(ref const Voxels voxels, ChunkLayout layout, Ray ray, float limit) {
    ChunkRayCastHit hit;
    int[3] first = cellOn(layout, ray, 0);
    uint step = 1;
    while (step < MARCH_STEPS && !hit.isHit()) {
        float t = limit * step / MARCH_STEPS;
        int[3] cell = cellOn(layout, ray, t);
        if (cell[0] >= 0 && cell[1] >= 0 && cell[2] >= 0 && cell != first && voxels.at(cellIndex(layout.dimension, cell[0], cell[1], cell[2])) != Material.none) {
            hit = ChunkRayCastHit(t, Cell([cast(ubyte) cell[0], cast(ubyte) cell[1], cast(ubyte) cell[2]]));
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
        float[3] from;
        float[3] to;
        foreach (axis; 0 .. AXIS_COUNT) {
            from[axis] = (shuffled(state) * 1.6f - 0.3f) * size;
            to[axis] = shuffled(state) * size;
        }
        Point!float start = Vec4!float([from[0], from[1], from[2], 1]).toPoint();
        Point!float aim = Vec4!float([to[0], to[1], to[2], 1]).toPoint();
        Ray ray = Ray(start, (aim.v + start.v * start.minkowski(aim.v)).toNormal());
        ChunkRayCastHit walked = castThroughChunk(voxels, layout, ray, 0.9f);
        ChunkRayCastHit expected = marched(voxels, layout, ray, 0.9f);
        assert(walked.isHit() == expected.isHit());
        if (walked.isHit()) {
            hits += 1;
            assert(walked.voxelCoords == expected.voxelCoords);
            assert(walked.tanhDistance <= expected.tanhDistance + 0.9f / MARCH_STEPS);
        }
    }
    assert(hits > RAYS / 4);
    voxels.release();
}
