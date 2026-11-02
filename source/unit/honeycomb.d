module unit.honeycomb;

import core.stdc.math : acosh;
import geometry.honeycomb : CORNER_COUNT, CUBE_RADIUS, Corner, FACE_COUNT, FACE_DISTANCE, Face, NODE_RADIUS, across, axisMaps, cornerToNode, cubeCenter, cubeScale, cubeToNode, faces, isAdjacentTo, isBeyond, mirror, nodeToCorner, normal, opposite;
import geometry.lorentz : Point, Vec4;

enum float TOLERANCE = 1e-5f;

unittest {
    foreach (index; 0 .. FACE_COUNT) {
        Face face = cast(Face) index;
        assert(face.opposite != face && !face.isAdjacentTo(face.opposite) && face.opposite.opposite == face);
        uint neighbors = 0;
        foreach (other; 0 .. FACE_COUNT) {
            if (face.isAdjacentTo(cast(Face) other)) {
                neighbors += 1;
            }
        }
        assert(neighbors == 5);
        Point!float mirrored = face.mirror * Point!float.origin();
        assert(face.isBeyond(mirrored) && !face.isBeyond(Point!float.origin()));
        assert(acosh(mirrored.coshDistance(Point!float.origin())) - 2 * FACE_DISTANCE < TOLERANCE);
    }
    foreach (index; 0 .. CORNER_COUNT) {
        Corner corner = cast(Corner) index;
        Point!float point = corner.cornerToNode * Point!float.origin();
        assert(point.distance(Point!float.origin()) - NODE_RADIUS < TOLERANCE);
        foreach (face; corner.faces) {
            assert(face.normal.minkowski(point.v) * face.normal.minkowski(point.v) < TOLERANCE);
        }
        Vec4!float center = corner.nodeToCorner * Vec4!float.origin();
        foreach (axis; 0 .. 3) {
            assert(center.c[axis] / center.c[3] / cubeScale() - 1 < TOLERANCE);
            Corner next = corner.across[axis];
            assert(next != corner && next.across[corner.axisMaps[axis].to[axis]] == corner);
        }
        foreach (cubeCorner; 0 .. 8) {
            Vec4!float at = Vec4!float([cubeCorner & 1, (cubeCorner >> 1) & 1, (cubeCorner >> 2) & 1, 1]);
            Point!float cornerOfCube = (corner.cubeToNode * at).toPoint();
            assert(corner.cubeCenter.distance(cornerOfCube) < CUBE_RADIUS + TOLERANCE);
        }
    }
}
