module common.raycast.chunk;

import core.stdc.math : fabsf;
import base.numbers : isNan, lowerOf;
import common.node : ChunkLayout, Voxels, cellIndex;
import geometry.cube : AXIS_COUNT, Axis, Cell, Sign;
import geometry.lorentz : Point, Vec4;
import geometry.ray : Ray;
import plugins.api.api : Material;

enum float PARALLEL_TOLERANCE = 1e-6f;
enum ubyte TEST_DIMENSION = 4;
immutable int[3] TEST_TARGET = [1, 2, 3];
enum float TEST_START_KLEIN = -0.2f;
enum float TEST_TOLERANCE = 1e-4f;
enum uint TEST_RAYS = 200;
enum uint TEST_MARCH_STEPS = 20000;
enum ulong TEST_SEED = 0x2545F4914F6CDD1D;

struct ChunkRayCastHit {
    float tanhDistance = float.nan;
    Cell voxelCoords;
    Axis faceAxis;
    Sign faceSign;

    bool isHit() const {
        return !isNan(tanhDistance);
    }
}

ChunkRayCastHit castThroughChunk(const Voxels voxels, ChunkLayout layout, Ray ray, float limit) {
    if (voxels.isFilledWith(Material.none)) {
        return ChunkRayCastHit.init;
    } else {
        GridWalk walk = GridWalk(ray, layout);
        return walk.run(voxels, limit);
    }
}

struct GridWalk {
    float[4] start;
    float[4] heading;
    ChunkLayout layout;
    int[AXIS_COUNT] steps;

    this(Ray ray, ChunkLayout chosen) {
        start = ray.start.v.c;
        heading = ray.heading.v.c;
        layout = chosen;
        foreach (axis; 0 .. AXIS_COUNT) {
            float along = heading[axis] * start[3];
            float drift = start[axis] * heading[3];
            float rate = along - drift;
            bool isParallel = fabsf(rate) <= PARALLEL_TOLERANCE * (fabsf(along) + fabsf(drift));
            if (isParallel) {
                steps[axis] = 0;
            } else if (rate > 0) {
                steps[axis] = 1;
            } else {
                steps[axis] = -1;
            }
        }
    }

    float crossing(size_t axis, float wall) const {
        float t = (wall * start[3] - start[axis]) / (heading[axis] - wall * heading[3]);
        if (t >= 0 && t < 1) {
            return t;
        } else {
            return float.infinity;
        }
    }

    float wallCrossing(size_t axis, int wall) const {
        return crossing(axis, layout.gridToKlein(wall));
    }

    float nextWall(size_t axis, int cell, float now) const {
        if (steps[axis] == 0) {
            return float.infinity;
        } else {
            int wall = cell;
            if (steps[axis] > 0) {
                wall += 1;
            }
            float t = wallCrossing(axis, wall);
            if (t >= now) {
                return t;
            } else {
                return float.infinity;
            }
        }
    }

    int cellAlong(size_t axis, float t) const {
        float klein = (start[axis] + t * heading[axis]) / (start[3] + t * heading[3]);
        float grid = layout.kleinToGrid(klein);
        if (grid < 0) {
            return 0;
        } else {
            return lowerOf(cast(int) grid, layout.dimension - 1);
        }
    }

    ChunkRayCastHit run(ref const Voxels voxels, float limit) const {
        int dimension = layout.dimension;
        float entry = 0;
        float exit = limit;
        int entryAxis = -1;
        bool isMissed = false;
        float size = layout.gridToKlein(dimension);
        foreach (axis; 0 .. AXIS_COUNT) {
            float klein = start[axis] / start[3];
            bool isBelow = klein < 0;
            bool isAbove = klein > size;
            bool isPast = isBelow;
            int nearWall = dimension;
            int farWall = 0;
            if (steps[axis] > 0) {
                isPast = isAbove;
                nearWall = 0;
                farWall = dimension;
            }
            if (steps[axis] == 0 || isPast) {
                isMissed = isMissed || isBelow || isAbove;
            } else {
                if (isBelow || isAbove) {
                    float near = wallCrossing(axis, nearWall);
                    if (!(near <= entry)) {
                        entry = near;
                        entryAxis = axis;
                    }
                }
                exit = lowerOf(wallCrossing(axis, farWall), exit);
            }
        }
        if (isMissed || !(entry < exit)) {
            return ChunkRayCastHit.init;
        } else {
            int[AXIS_COUNT] cell;
            foreach (axis; 0 .. AXIS_COUNT) {
                cell[axis] = cellAlong(axis, entry);
            }
            if (entryAxis >= 0) {
                if (steps[entryAxis] > 0) {
                    cell[entryAxis] = 0;
                } else {
                    cell[entryAxis] = dimension - 1;
                }
                if (isFilled(voxels, cell)) {
                    return hitAt(entry, cell, entryAxis);
                }
            }
            return walkFrom(voxels, cell, entry, exit);
        }
    }

    ChunkRayCastHit walkFrom(ref const Voxels voxels, int[AXIS_COUNT] first, float entry, float exit) const {
        int[AXIS_COUNT] cell = first;
        float[AXIS_COUNT] next;
        foreach (axis; 0 .. AXIS_COUNT) {
            next[axis] = nextWall(axis, cell[axis], entry);
        }
        ChunkRayCastHit hit;
        bool isDone = false;
        while (!isDone) {
            size_t axis = nearestOf(next);
            cell[axis] += steps[axis];
            if (!(next[axis] < exit) || cell[axis] < 0 || cell[axis] >= layout.dimension) {
                isDone = true;
            } else if (isFilled(voxels, cell)) {
                hit = hitAt(next[axis], cell, axis);
                isDone = true;
            } else {
                next[axis] = nextWall(axis, cell[axis], next[axis]);
            }
        }
        return hit;
    }

    bool isFilled(ref const Voxels voxels, int[AXIS_COUNT] cell) const {
        return voxels.at(cellIndex(layout.dimension, cell[0], cell[1], cell[2])) != Material.none;
    }

    ChunkRayCastHit hitAt(float t, int[AXIS_COUNT] cell, size_t axis) const {
        Cell coords = Cell([cast(ubyte) cell[0], cast(ubyte) cell[1], cast(ubyte) cell[2]]);
        Sign face = Sign.plus;
        if (steps[axis] > 0) {
            face = Sign.minus;
        }
        return ChunkRayCastHit(t, coords, cast(Axis) axis, face);
    }
}

unittest {
    ChunkLayout layout = ChunkLayout.make(TEST_DIMENSION);
    Voxels voxels = Voxels.filled(Material.none);
    voxels.toDense(TEST_DIMENSION)[cellIndex(TEST_DIMENSION, TEST_TARGET[0], TEST_TARGET[1], TEST_TARGET[2])] = Material.granite;
    float[3] center = [layout.gridToKlein(TEST_TARGET[0] + 0.5f), layout.gridToKlein(TEST_TARGET[1] + 0.5f), layout.gridToKlein(TEST_TARGET[2] + 0.5f)];
    Point!float from = Vec4!float([TEST_START_KLEIN, center[1], center[2], 1]).toPoint();
    Point!float to = Vec4!float([center[0], center[1], center[2], 1]).toPoint();
    Ray ray = Ray(from, (to.v + from.v * from.minkowski(to.v)).toNormal());
    ChunkRayCastHit hit = castThroughChunk(voxels, layout, ray, 1);
    assert(hit.isHit() && hit.voxelCoords.c == [1, 2, 3] && hit.faceAxis == Axis.x && hit.faceSign == Sign.minus);
    Vec4!float reached = ray.at(hit.tanhDistance);
    float wall = layout.gridToKlein(TEST_TARGET[0]);
    assert(reached.c[0] / reached.c[3] - wall < TEST_TOLERANCE && wall - reached.c[0] / reached.c[3] < TEST_TOLERANCE);
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
    while (step < TEST_MARCH_STEPS && !hit.isHit()) {
        float t = limit * step / TEST_MARCH_STEPS;
        int[3] cell = cellOn(layout, ray, t);
        bool isInside = cell[0] >= 0 && cell[1] >= 0 && cell[2] >= 0;
        if (isInside && cell != first && voxels.at(cellIndex(layout.dimension, cell[0], cell[1], cell[2])) != Material.none) {
            hit = ChunkRayCastHit(t, Cell([cast(ubyte) cell[0], cast(ubyte) cell[1], cast(ubyte) cell[2]]));
        }
        step += 1;
    }
    return hit;
}

float testRandom(ref ulong state) {
    state ^= state << 13;
    state ^= state >> 7;
    state ^= state << 17;
    return (state >> 40) / cast(float)(1 << 24);
}

unittest {
    ChunkLayout layout = ChunkLayout.make(TEST_DIMENSION);
    float size = layout.gridToKlein(TEST_DIMENSION);
    Voxels voxels = Voxels.filled(Material.none);
    Material[] cells = voxels.toDense(TEST_DIMENSION);
    ulong state = TEST_SEED;
    foreach (index; 0 .. cells.length) {
        cells[index] = Material.none;
        if (testRandom(state) < 0.15f) {
            cells[index] = Material.granite;
        }
    }
    uint hits = 0;
    foreach (_; 0 .. TEST_RAYS) {
        float[3] from;
        float[3] to;
        foreach (axis; 0 .. AXIS_COUNT) {
            from[axis] = (testRandom(state) * 1.6f - 0.3f) * size;
            to[axis] = testRandom(state) * size;
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
            assert(walked.tanhDistance <= expected.tanhDistance + 0.9f / TEST_MARCH_STEPS);
        }
    }
    assert(hits > TEST_RAYS / 4);
    voxels.release();
}

size_t nearestOf(float[AXIS_COUNT] crossings) {
    size_t nearest = 0;
    foreach (axis; 1 .. AXIS_COUNT) {
        if (crossings[axis] < crossings[nearest]) {
            nearest = axis;
        }
    }
    return nearest;
}
