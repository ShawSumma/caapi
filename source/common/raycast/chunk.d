module common.raycast.chunk;

import core.stdc.math : fabsf;
import base.maybe : Maybe;
import base.numbers : lowerOf;
import base.vector3 : Vec3;
import common.node : ChunkLayout, Voxels, cellIndex;
import geometry.cube : AXIS_COUNT, Axis, Cell, Sign;
import geometry.ray : Ray;
import plugins.api.api : Material;

enum float PARALLEL_TOLERANCE = 1e-6f;

struct ChunkRayCastHit {
    float tanhDistance;
    Cell voxelCoords;
    Axis faceAxis;
    Sign faceSign;
}

Maybe!ChunkRayCastHit castThroughChunk(const Voxels voxels, ChunkLayout layout, Ray ray, float limit) {
    if (voxels.isFilledWith(Material.none)) {
        return Maybe!ChunkRayCastHit.init;
    } else {
        GridWalk walk = GridWalk(ray, layout);
        return walk.run(voxels, limit);
    }
}

struct GridWalk {
    float[4] start;
    float[4] heading;
    ChunkLayout layout;
    Vec3!int steps;

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

    Maybe!float crossing(size_t axis, float wall) const {
        float t = (wall * start[3] - start[axis]) / (heading[axis] - wall * heading[3]);
        if (t >= 0 && t < 1) {
            return Maybe!float.of(t);
        } else {
            return Maybe!float.init;
        }
    }

    Maybe!float wallCrossing(size_t axis, int wall) const {
        return crossing(axis, layout.gridToKlein(wall));
    }

    Maybe!float nextWall(size_t axis, int cell, float now) const {
        if (steps[axis] == 0) {
            return Maybe!float.init;
        } else {
            int wall = cell;
            if (steps[axis] > 0) {
                wall += 1;
            }
            Maybe!float t = wallCrossing(axis, wall);
            if (t.exists && t.value >= now) {
                return t;
            } else {
                return Maybe!float.init;
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

    Maybe!ChunkRayCastHit run(ref const Voxels voxels, float limit) const {
        int dimension = layout.dimension;
        float entry = 0;
        float exit = limit;
        Maybe!uint entryAxis;
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
                    return Maybe!ChunkRayCastHit.init;
                }
            } else if (past > 0) {
                return Maybe!ChunkRayCastHit.init;
            } else {
                if (ahead > 0) {
                    Maybe!float near = wallCrossing(axis, nearWall);
                    if (!near.exists) {
                        return Maybe!ChunkRayCastHit.init;
                    } else if (near.value > entry) {
                        entry = near.value;
                        entryAxis = Maybe!uint.of(axis);
                    }
                }
                Maybe!float far = wallCrossing(axis, farWall);
                if (far.exists) {
                    exit = lowerOf(far.value, exit);
                }
            }
        }
        if (!(entry < exit)) {
            return Maybe!ChunkRayCastHit.init;
        } else {
            Vec3!int cell;
            foreach (axis; 0 .. AXIS_COUNT) {
                cell[axis] = cellAlong(axis, entry);
            }
            if (entryAxis.exists) {
                if (steps[entryAxis.value] > 0) {
                    cell[entryAxis.value] = 0;
                } else {
                    cell[entryAxis.value] = dimension - 1;
                }
                if (isFilled(voxels, cell)) {
                    return hitAt(entry, cell, entryAxis.value);
                }
            }
            return walkFrom(voxels, cell, entry, exit);
        }
    }

    Maybe!ChunkRayCastHit walkFrom(ref const Voxels voxels, Vec3!int first, float entry, float exit) const {
        Vec3!int cell = first;
        Vec3!(Maybe!float) next;
        foreach (axis; 0 .. AXIS_COUNT) {
            next[axis] = nextWall(axis, cell[axis], entry);
        }
        while (true) {
            Maybe!uint nearest = nearestOf(next);
            if (!nearest.exists) {
                return Maybe!ChunkRayCastHit.init;
            }
            uint axis = nearest.value;
            float t = next[axis].value;
            cell[axis] += steps[axis];
            if (!(t < exit) || cell[axis] < 0 || cell[axis] >= layout.dimension) {
                return Maybe!ChunkRayCastHit.init;
            } else if (isFilled(voxels, cell)) {
                return hitAt(t, cell, axis);
            } else {
                next[axis] = nextWall(axis, cell[axis], t);
            }
        }
    }

    bool isFilled(ref const Voxels voxels, Vec3!int cell) const {
        return voxels.at(cellIndex(layout.dimension, cell.x, cell.y, cell.z)) != Material.none;
    }

    Maybe!ChunkRayCastHit hitAt(float t, Vec3!int cell, size_t axis) const {
        Cell coords = cell.as!ubyte();
        Sign face = Sign.plus;
        if (steps[axis] > 0) {
            face = Sign.minus;
        }
        return Maybe!ChunkRayCastHit.of(ChunkRayCastHit(t, coords, cast(Axis) axis, face));
    }
}

Maybe!uint nearestOf(Vec3!(Maybe!float) crossings) {
    Maybe!uint nearest;
    foreach (axis; 0 .. AXIS_COUNT) {
        if (crossings[axis].exists && (!nearest.exists || crossings[axis].value < crossings[nearest.value].value)) {
            nearest = Maybe!uint.of(axis);
        }
    }
    return nearest;
}
