module geometry.honeycomb;

import core.math : sqrt;
import core.stdc.math : acosh;
import base.numbers : acoshAtCompileTime, asinhAtCompileTime;
import geometry.cube : AxisMap;
import geometry.lorentz : Mat4, Motion, Normal, Point, Vec4;

enum Face : ubyte {
    f0,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
}

enum Corner : ubyte {
    c0,
    c1,
    c2,
    c3,
    c4,
    c5,
    c6,
    c7,
    c8,
    c9,
    c10,
    c11,
    c12,
    c13,
    c14,
    c15,
    c16,
    c17,
    c18,
    c19,
}

enum uint FACE_COUNT = 12;
enum uint CORNER_COUNT = 20;
enum ubyte NO_CORNER = ubyte.max;

struct Honeycomb {
    Normal!float[FACE_COUNT] normals;
    Motion!float[FACE_COUNT] mirrors;
    float[3][FACE_COUNT] directions;
    float[3][FACE_COUNT] references;
    Face[FACE_COUNT] opposites;
    ushort[FACE_COUNT] adjacent;
    Face[3][CORNER_COUNT] cornerFaces;
    Corner[3][CORNER_COUNT] across;
    AxisMap[3][CORNER_COUNT] axisMaps;
    Motion!float[CORNER_COUNT] cornerToNode;
    Motion!float[CORNER_COUNT] nodeToCorner;
    Point!float[CORNER_COUNT] cubeCenters;
    float cubeScale;
    float coshNodeRadius;
    float coshCubeRadius;
    float coshCubeGridRadius;
    float sinhFaceDistance;

    static Honeycomb make() {
        Honeycomb h;
        Normal!double[FACE_COUNT] normals = faceNormals();
        foreach (face; 0 .. FACE_COUNT) {
            h.normals[face] = normals[face].as!float();
            h.mirrors[face] = Motion!double.reflection(normals[face]).as!float();
            double[3] spatial = normals[face].v.spatial();
            double length = sqrt(spatial[0] * spatial[0] + spatial[1] * spatial[1] + spatial[2] * spatial[2]);
            foreach (axis; 0 .. 3) {
                h.directions[face][axis] = cast(float)(spatial[axis] / length);
            }
            h.sinhFaceDistance = cast(float)(normals[face].v.c[3]);
            foreach (other; 0 .. FACE_COUNT) {
                double product = normals[face].minkowski(normals[other].v);
                if (product * product < ORTHOGONAL_TOLERANCE) {
                    h.adjacent[face] |= cast(ushort)(1u << other);
                }
            }
            h.opposites[face] = mostAntiparallel(normals, face);
        }
        uint corners = 0;
        foreach (a; 0 .. FACE_COUNT) {
            foreach (b; a + 1 .. FACE_COUNT) {
                foreach (c; b + 1 .. FACE_COUNT) {
                    if (h.isAdjacent(a, b) && h.isAdjacent(b, c) && h.isAdjacent(a, c)) {
                        h.cornerFaces[corners] = [cast(Face) a, cast(Face) b, cast(Face) c];
                        corners += 1;
                    }
                }
            }
        }
        assert(corners == CORNER_COUNT);
        Point!double[CORNER_COUNT] cornerPoints;
        Motion!double[CORNER_COUNT] frames;
        foreach (corner; 0 .. CORNER_COUNT) {
            Face[3] faces = h.cornerFaces[corner];
            frames[corner] = cornerFrame(normals[faces[0]], normals[faces[1]], normals[faces[2]]);
            cornerPoints[corner] = frames[corner] * Point!double.origin();
            h.cornerToNode[corner] = frames[corner].as!float();
            h.nodeToCorner[corner] = frames[corner].inverse().as!float();
            h.cubeCenters[corner] = cornerPoints[corner].midpoint(Point!double.origin()).as!float();
            foreach (axis; 0 .. 3) {
                h.across[corner][axis] = h.cornerAcross(faces, axis);
                h.axisMaps[corner][axis] = AxisMap.between(h.acrossFaces(faces, axis), h.cornerFaces[h.across[corner][axis]]);
            }
        }
        foreach (face; 0 .. FACE_COUNT) {
            h.references[face] = referenceIn(h.directions[face], cornerPoints[h.firstCornerOn(cast(Face) face)]);
        }
        Vec4!double centerInCorner = frames[0].inverse() * Vec4!double.origin();
        double toCube = centerInCorner.c[0] / centerInCorner.c[3];
        h.cubeScale = cast(float) toCube;
        h.coshNodeRadius = cast(float) -cornerPoints[0].minkowski(Vec4!double.origin());
        Point!double center = cornerPoints[0].midpoint(Point!double.origin());
        Point!double gridCenter = (frames[0] * Vec4!double([0.5 * toCube, 0.5 * toCube, 0.5 * toCube, 1])).toPoint();
        double farthest = 1;
        double farthestFromGrid = 1;
        foreach (cubeCorner; 0 .. 8) {
            double[3] at = [(cubeCorner & 1) * toCube, ((cubeCorner >> 1) & 1) * toCube, ((cubeCorner >> 2) & 1) * toCube];
            Point!double point = (frames[0] * Vec4!double([at[0], at[1], at[2], 1])).toPoint();
            farthest = higher(farthest, center.coshDistance(point));
            farthestFromGrid = higher(farthestFromGrid, gridCenter.coshDistance(point));
        }
        h.coshCubeRadius = cast(float) farthest;
        h.coshCubeGridRadius = cast(float) farthestFromGrid;
        return h;
    }

    bool isAdjacent(size_t a, size_t b) const {
        return (adjacent[a] & (1u << b)) != 0;
    }

    Corner cornerAcross(Face[3] faces, size_t axis) const {
        Face[3] swapped = acrossFaces(faces, axis);
        uint corner = 0;
        while (corner < CORNER_COUNT && !isSameFaceSet(cornerFaces[corner], swapped)) {
            corner += 1;
        }
        assert(corner < CORNER_COUNT);
        return cast(Corner) corner;
    }

    Face[3] acrossFaces(Face[3] faces, size_t axis) const {
        uint candidate = 0;
        while (candidate < FACE_COUNT && !(candidate != faces[axis] && isAdjacent(candidate, faces[(axis + 1) % 3]) && isAdjacent(candidate, faces[(axis + 2) % 3]))) {
            candidate += 1;
        }
        assert(candidate < FACE_COUNT);
        Face[3] swapped;
        foreach (i; 0 .. 3) {
            swapped[i] = i == axis ? cast(Face) candidate : faces[i];
        }
        return swapped;
    }

    uint firstCornerOn(Face face) const {
        uint corner = 0;
        while (cornerFaces[corner][0] != face && cornerFaces[corner][1] != face && cornerFaces[corner][2] != face) {
            corner += 1;
        }
        return corner;
    }
}

enum double ORTHOGONAL_TOLERANCE = 1e-12;
enum double GOLDEN = 1.6180339887498948482;

Normal!double[FACE_COUNT] faceNormals() {
    double rootFive = sqrt(5.0);
    double a = sqrt(1 / (1 - 1 / rootFive));
    double b = a / sqrt(rootFive);
    double length = sqrt(1 + GOLDEN * GOLDEN);
    Normal!double[FACE_COUNT] normals;
    foreach (face; 0 .. FACE_COUNT) {
        size_t placement = (5 - face % 3) % 3;
        size_t signs = face / 3;
        double first = signs & 1 ? -1 : 1;
        double second = signs & 2 ? -GOLDEN : GOLDEN;
        double[3] direction = [0, 0, 0];
        direction[(placement + 1) % 3] = first / length;
        direction[(placement + 2) % 3] = second / length;
        normals[face] = Normal!double(Vec4!double([a * direction[0], a * direction[1], a * direction[2], b]));
    }
    return normals;
}

Face mostAntiparallel(ref const Normal!double[FACE_COUNT] normals, size_t face) {
    size_t opposite = face;
    double lowest = 0;
    foreach (other; 0 .. FACE_COUNT) {
        double product = normals[face].minkowski(normals[other].v);
        if (product < lowest) {
            lowest = product;
            opposite = other;
        }
    }
    return cast(Face) opposite;
}

Motion!double cornerFrame(Normal!double a, Normal!double b, Normal!double c) {
    double distance = a.v.c[3];
    Point!double corner = (Vec4!double.origin() + (a.v + b.v + c.v) * distance).toPoint();
    return Motion!double.fromFrame([-a, -b, -c], corner);
}

float[3] referenceIn(float[3] direction, Point!double corner) {
    double[3] point = corner.v.spatial();
    double along = point[0] * direction[0] + point[1] * direction[1] + point[2] * direction[2];
    double[3] reference = [point[0] - along * direction[0], point[1] - along * direction[1], point[2] - along * direction[2]];
    double length = sqrt(reference[0] * reference[0] + reference[1] * reference[1] + reference[2] * reference[2]);
    return [cast(float)(reference[0] / length), cast(float)(reference[1] / length), cast(float)(reference[2] / length)];
}

bool isSameFaceSet(Face[3] a, Face[3] b) {
    uint matched = 0;
    foreach (face; a) {
        if (face == b[0] || face == b[1] || face == b[2]) {
            matched += 1;
        }
    }
    return matched == 3;
}

double higher(double a, double b) {
    return a > b ? a : b;
}

immutable Honeycomb HONEYCOMB = Honeycomb.make();

enum float NODE_VOLUME = 4.3062076f;

Normal!float normal(Face face) {
    return HONEYCOMB.normals[face];
}

Motion!float mirror(Face face) {
    return HONEYCOMB.mirrors[face];
}

bool isAdjacentTo(Face a, Face b) {
    return HONEYCOMB.isAdjacent(a, b);
}

ushort adjacentFaces(Face face) {
    return HONEYCOMB.adjacent[face];
}

ushort faceBit(Face face) {
    return cast(ushort)(1u << face);
}

Face opposite(Face face) {
    return HONEYCOMB.opposites[face];
}

float[3] direction(Face face) {
    return HONEYCOMB.directions[face];
}

float[3] reference(Face face) {
    return HONEYCOMB.references[face];
}

bool isBeyond(Face face, Point!float point) {
    return HONEYCOMB.normals[face].minkowski(point.v) > BEYOND_TOLERANCE * point.v.c[3];
}

enum float BEYOND_TOLERANCE = 1e-6f;

Face[3] faces(Corner corner) {
    return HONEYCOMB.cornerFaces[corner];
}

Corner[3] across(Corner corner) {
    return HONEYCOMB.across[corner];
}

AxisMap[3] axisMaps(Corner corner) {
    return HONEYCOMB.axisMaps[corner];
}

Motion!float cornerToNode(Corner corner) {
    return HONEYCOMB.cornerToNode[corner];
}

Motion!float nodeToCorner(Corner corner) {
    return HONEYCOMB.nodeToCorner[corner];
}

Mat4!float cubeToNode(Corner corner) {
    return HONEYCOMB.cornerToNode[corner].m * Mat4!float.scaling(HONEYCOMB.cubeScale);
}

float cubeScale() {
    return HONEYCOMB.cubeScale;
}

Point!float cubeCenter(Corner corner) {
    return HONEYCOMB.cubeCenters[corner];
}

enum float NODE_RADIUS = cast(float) acoshAtCompileTime(HONEYCOMB.coshNodeRadius);
enum float CUBE_RADIUS = cast(float) acoshAtCompileTime(HONEYCOMB.coshCubeRadius);
enum float CUBE_GRID_RADIUS = cast(float) acoshAtCompileTime(HONEYCOMB.coshCubeGridRadius);
enum float FACE_DISTANCE = cast(float) asinhAtCompileTime(HONEYCOMB.sinhFaceDistance);

enum float TABLE_TOLERANCE = 1e-5f;

unittest {
    foreach (index; 0 .. FACE_COUNT) {
        Face face = cast(Face) index;
        assert(face.opposite != face && !face.isAdjacentTo(face.opposite) && face.opposite.opposite == face);
        uint neighbors = 0;
        foreach (other; 0 .. FACE_COUNT) {
            neighbors += face.isAdjacentTo(cast(Face) other);
        }
        assert(neighbors == 5);
        Point!float mirrored = face.mirror * Point!float.origin();
        assert(face.isBeyond(mirrored) && !face.isBeyond(Point!float.origin()));
        assert(acosh(mirrored.coshDistance(Point!float.origin())) - 2 * FACE_DISTANCE < TABLE_TOLERANCE);
    }
    foreach (index; 0 .. CORNER_COUNT) {
        Corner corner = cast(Corner) index;
        Point!float point = corner.cornerToNode * Point!float.origin();
        assert(point.distance(Point!float.origin()) - NODE_RADIUS < TABLE_TOLERANCE);
        foreach (face; corner.faces) {
            assert(face.normal.minkowski(point.v) * face.normal.minkowski(point.v) < TABLE_TOLERANCE);
        }
        Vec4!float center = corner.nodeToCorner * Vec4!float.origin();
        foreach (axis; 0 .. 3) {
            assert(center.c[axis] / center.c[3] / cubeScale() - 1 < TABLE_TOLERANCE);
            Corner next = corner.across[axis];
            assert(next != corner && next.across[corner.axisMaps[axis].to[axis]] == corner);
        }
        foreach (cubeCorner; 0 .. 8) {
            Vec4!float at = Vec4!float([cubeCorner & 1, (cubeCorner >> 1) & 1, (cubeCorner >> 2) & 1, 1]);
            Point!float cornerOfCube = (corner.cubeToNode * at).toPoint();
            assert(corner.cubeCenter.distance(cornerOfCube) < CUBE_RADIUS + TABLE_TOLERANCE);
        }
    }
}
