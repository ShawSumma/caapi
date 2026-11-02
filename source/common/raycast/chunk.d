module common.raycast.chunk;

import core.stdc.math : fabsf;
import base.numbers : isNan, lowerOf;
import common.node : ChunkLayout, Voxels, cellIndex;
import geometry.cube : AXIS_COUNT, Axis, Cell, Sign;
import geometry.ray : Ray;
import plugins.api.api : Material;

enum float PARALLEL_TOLERANCE = 1e-6f;

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
            if (fabsf(rate) <= PARALLEL_TOLERANCE * (fabsf(along) + fabsf(drift))) {
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
        float size = layout.gridToKlein(dimension);
        foreach (axis; 0 .. AXIS_COUNT) {
            float klein = start[axis] / start[3];
            float past = -klein;
            float ahead = klein - size;
            int nearWall = dimension;
            int farWall = 0;
            if (steps[axis] > 0) {
                past = klein - size;
                ahead = -klein;
                nearWall = 0;
                farWall = dimension;
            }
            if (steps[axis] == 0) {
                if (klein < 0 || klein > size) {
                    return ChunkRayCastHit.init;
                }
            } else if (past > 0) {
                return ChunkRayCastHit.init;
            } else {
                if (ahead > 0) {
                    float near = wallCrossing(axis, nearWall);
                    if (!(near <= entry)) {
                        entry = near;
                        entryAxis = axis;
                    }
                }
                exit = lowerOf(wallCrossing(axis, farWall), exit);
            }
        }
        if (!(entry < exit)) {
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
        while (true) {
            size_t axis = nearestOf(next);
            cell[axis] += steps[axis];
            if (!(next[axis] < exit) || cell[axis] < 0 || cell[axis] >= layout.dimension) {
                return ChunkRayCastHit.init;
            } else if (isFilled(voxels, cell)) {
                return hitAt(next[axis], cell, axis);
            } else {
                next[axis] = nextWall(axis, cell[axis], next[axis]);
            }
        }
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

size_t nearestOf(float[AXIS_COUNT] crossings) {
    size_t nearest = 0;
    foreach (axis; 1 .. AXIS_COUNT) {
        if (crossings[axis] < crossings[nearest]) {
            nearest = axis;
        }
    }
    return nearest;
}
