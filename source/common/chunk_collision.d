module common.chunk_collision;

import core.math : sqrt;
import core.stdc.math : ceilf, coshf, floorf, sinhf, tanhf;
import common.collision_math : ContactTerms, MAX_TANH_DISTANCE, Ray, contactTime, separationDistance, transformRay;
import common.math : MDirection, MIsometry, MPoint, MVector, isNan;
import common.node : ChunkLayout, VoxelData;
import common.voxel_math : Coords;
import common.world : Material;

enum float GRID_PADDING_CELLS = 2.0f;
enum uint MAX_FACES = 256;
enum uint MAX_FEATURE_SURFACES = 3;

immutable byte[2] FACE_SIGNS = [-1, 1];

struct ChunkCollisionHit {
    MVector!float normal;
    MVector!float[MAX_FEATURE_SURFACES] surfaces;
    float stopDistance;
    float gap;
    uint surfaceCount;
    bool lowestSection;
}

struct SweptShape {
    MVector!float axis;
    float radius;
    float halfHeight;
    float skin;
}

struct GridRange {
    int[3] lo;
    int[3] hi;
    bool empty;
}

struct SurfaceFace {
    ubyte[3] cell;
    ubyte axis;
    byte sign;
}

struct Section {
    Ray ray;
    MIsometry!float fromSection;
    float radius;
    float skin;
    float sinhRadius;
    float sinhStopRadius;
    bool offset;
    bool lowest;
}

struct EdgeLine {
    MDirection!float facePlane;
    MDirection!float edgePlane;
}

struct CornerFrame {
    MDirection!float[3] planes;
    MVector!float point;
}

struct Feature {
    MVector!float[MAX_FEATURE_SURFACES] surfaces;
    uint surfaceCount;
}

GridRange sweepGridRange(ChunkLayout layout, Ray ray, float tanhDistance, float padDistance) {
    GridRange range;
    float capped = MAX_TANH_DISTANCE;
    if (tanhDistance < MAX_TANH_DISTANCE) {
        capped = tanhDistance;
    }
    MVector!float p0 = ray.position.vec;
    MVector!float p1 = ray.rayPoint(capped);
    float pad = tanhf(padDistance) * layout.dualToGridFactor + GRID_PADDING_CELLS;
    foreach (i; 0 .. 3) {
        if (!range.empty) {
            float g0 = p0.data[i] / p0.data[3] * layout.dualToGridFactor;
            float g1 = p1.data[i] / p1.data[3] * layout.dualToGridFactor;
            float low = g1;
            float high = g1;
            if (g0 < g1) {
                low = g0;
            }
            if (g0 > g1) {
                high = g0;
            }
            low -= pad;
            high += pad;
            if (low > cast(float) layout.dimension || high < 0) {
                range.empty = true;
            } else {
                range.lo[i] = 0;
                if (!(low < 0)) {
                    range.lo[i] = cast(int) floorf(low);
                }
                range.hi[i] = layout.dimension - 1;
                if (!(high > cast(float)(layout.dimension - 1))) {
                    range.hi[i] = cast(int) ceilf(high);
                }
            }
        }
    }
    return range;
}

uint collectSurfaceFaces(const(VoxelData)* voxelData, ChunkLayout layout, GridRange range, SurfaceFace* faces) {
    uint faceCount = 0;
    foreach (cx; range.lo[0] .. range.hi[0] + 1) {
        foreach (cy; range.lo[1] .. range.hi[1] + 1) {
            foreach (cz; range.lo[2] .. range.hi[2] + 1) {
                ubyte[3] cell = [cast(ubyte) cx, cast(ubyte) cy, cast(ubyte) cz];
                if (voxelIsSolid(voxelData, layout, cell)) {
                    foreach (axis; 0 .. 3) {
                        foreach (sign; FACE_SIGNS) {
                            int[3] neighbor = [cx, cy, cz];
                            neighbor[axis] += sign;
                            if (!voxelSolidWithMargins(voxelData, layout, neighbor) && faceCount < MAX_FACES) {
                                faces[faceCount] = SurfaceFace(cell, cast(ubyte) axis, sign);
                                faceCount += 1;
                            }
                        }
                    }
                }
            }
        }
    }
    return faceCount;
}

ChunkCollisionHit chunkShapeCast(SweptShape shape, const(VoxelData)* voxelData, ChunkLayout layout, Ray ray, float tanhDistance) {
    ChunkCollisionHit hit;
    hit.stopDistance = float.nan;
    GridRange range = sweepGridRange(layout, ray, tanhDistance, shape.radius + shape.halfHeight);
    if (!range.empty) {
        SurfaceFace[MAX_FACES] faces = void;
        uint faceCount = collectSurfaceFaces(voxelData, layout, range, faces.ptr);
        uint sectionCount = capsuleSectionCount(shape);
        foreach (sectionIndex; 0 .. sectionCount) {
            Section section = capsuleSection(shape, ray, sectionIndex, sectionCount);
            foreach (i; 0 .. faceCount) {
                faceContact(&section, layout, faces[i], &hit, tanhDistance);
                faceBoundaryContacts(&section, voxelData, layout, faces[i], &hit, tanhDistance);
            }
        }
    }
    return hit;
}

float capOffset(SweptShape shape) {
    float result = 0;
    if (shape.halfHeight > shape.radius) {
        result = shape.halfHeight - shape.radius;
    }
    return result;
}

float sectionSpacing(SweptShape shape) {
    return 2.0f * sqrt(shape.skin * (2.0f * shape.radius - shape.skin));
}

uint capsuleSectionCount(SweptShape shape) {
    float length = 2.0f * capOffset(shape);
    uint result = 1;
    if (length > 0) {
        result = cast(uint) ceilf(length / sectionSpacing(shape)) + 1;
    }
    return result;
}

float sectionOffset(SweptShape shape, uint sectionIndex, uint sectionCount) {
    float result = 0;
    if (sectionCount > 1) {
        result = capOffset(shape) * (2.0f * cast(float) sectionIndex / cast(float)(sectionCount - 1) - 1.0f);
    }
    return result;
}

Section capsuleSection(SweptShape shape, Ray ray, uint sectionIndex, uint sectionCount) {
    Section section;
    float offset = sectionOffset(shape, sectionIndex, sectionCount);
    section.ray = ray;
    section.fromSection = MIsometry!float.identity();
    section.radius = shape.radius;
    section.skin = shape.skin;
    section.sinhRadius = sinhf(shape.radius);
    section.sinhStopRadius = sinhf(shape.radius + shape.skin);
    section.offset = offset != 0;
    section.lowest = sectionIndex == 0;
    if (section.offset) {
        MIsometry!float toSection = axisTranslation(ray.position, shape.axis, offset);
        section.ray = transformRay(toSection, ray);
        section.fromSection = toSection.inverse();
    }
    return section;
}

MPoint!float axisPoint(MPoint!float center, MVector!float axis, float offset) {
    return MPoint!float(center.vec * coshf(offset) + axis * sinhf(offset));
}

MIsometry!float axisTranslation(MPoint!float center, MVector!float axis, float offset) {
    return MIsometry!float.translation(center, axisPoint(center, axis, offset));
}

MDirection!float gridPlane(ChunkLayout layout, size_t axis, int t) {
    float[4] normal = [0, 0, 0, 0];
    normal[axis] = 1.0f;
    normal[3] = layout.gridToDual(cast(ubyte) t);
    return MVector!float(normal[0], normal[1], normal[2], normal[3]).normalizedDirection();
}

int facePlaneIndex(SurfaceFace face) {
    int result = face.cell[face.axis];
    if (face.sign > 0) {
        result += 1;
    }
    return result;
}

MDirection!float faceOutward(ChunkLayout layout, SurfaceFace face) {
    MDirection!float result = gridPlane(layout, face.axis, facePlaneIndex(face));
    if (!(face.sign > 0)) {
        result = -result;
    }
    return result;
}

SurfaceFace adjacentFace(SurfaceFace face, size_t axis, int side) {
    byte sign = -1;
    if (side == 1) {
        sign = 1;
    }
    return SurfaceFace(face.cell, cast(ubyte) axis, sign);
}

EdgeLine edgeLine(ChunkLayout layout, SurfaceFace face, size_t edgeAxis, int side) {
    MDirection!float facePlane = gridPlane(layout, face.axis, facePlaneIndex(face));
    MDirection!float edgePlaneRaw = gridPlane(layout, edgeAxis, face.cell[edgeAxis] + side);
    MDirection!float edgePlane = (edgePlaneRaw.vec - facePlane.vec * facePlane.mip(edgePlaneRaw.vec)).normalizedDirection();
    return EdgeLine(facePlane, edgePlane);
}

MVector!float edgeFoot(EdgeLine line, MVector!float point) {
    return point - line.facePlane.vec * point.mip(line.facePlane.vec) - line.edgePlane.vec * point.mip(line.edgePlane.vec);
}

CornerFrame cornerFrame(ChunkLayout layout, SurfaceFace face, int du, int dv) {
    size_t uAxis = (face.axis + 1) % 3;
    size_t vAxis = (face.axis + 2) % 3;
    int[3] grid;
    grid[face.axis] = facePlaneIndex(face);
    grid[uAxis] = face.cell[uAxis] + du;
    grid[vAxis] = face.cell[vAxis] + dv;
    MDirection!float n0 = gridPlane(layout, 0, grid[0]);
    MVector!float n1Raw = gridPlane(layout, 1, grid[1]).vec;
    MDirection!float n1 = (n1Raw - n0.vec * n0.mip(n1Raw)).normalizedDirection();
    MVector!float n2Raw = gridPlane(layout, 2, grid[2]).vec;
    MDirection!float n2 = (n2Raw - n0.vec * n0.mip(n2Raw) - n1.vec * n1.mip(n2Raw)).normalizedDirection();
    MVector!float point = MVector!float(layout.gridToDual(cast(ubyte) grid[0]), layout.gridToDual(cast(ubyte) grid[1]), layout.gridToDual(cast(ubyte) grid[2]), 1.0f).normalizedPoint().vec;
    return CornerFrame([n0, n1, n2], point);
}

bool cellOwns(ChunkLayout layout, MVector!float point, size_t axis, ubyte cell) {
    return layout.dualToVoxel(point.data[axis] / point.data[3]) == cell;
}

bool boundarySideTested(const(VoxelData)* voxelData, ChunkLayout layout, SurfaceFace face, size_t axis, int side) {
    int[3] neighbor = [face.cell[0], face.cell[1], face.cell[2]];
    neighbor[axis] += 2 * side - 1;
    return neighbor[axis] < 0 || neighbor[axis] >= layout.dimension || !voxelSolidWithMargins(voxelData, layout, neighbor);
}

Feature faceFeature(ChunkLayout layout, SurfaceFace face) {
    Feature feature;
    feature.surfaces[0] = faceOutward(layout, face).vec;
    feature.surfaceCount = 1;
    return feature;
}

Feature edgeFeature(ChunkLayout layout, SurfaceFace face, size_t edgeAxis, int side) {
    Feature feature = faceFeature(layout, face);
    feature.surfaces[1] = faceOutward(layout, adjacentFace(face, edgeAxis, side)).vec;
    feature.surfaceCount = 2;
    return feature;
}

Feature cornerFeature(ChunkLayout layout, SurfaceFace face, int du, int dv) {
    Feature feature = faceFeature(layout, face);
    feature.surfaces[1] = faceOutward(layout, adjacentFace(face, (face.axis + 1) % 3, du)).vec;
    feature.surfaces[2] = faceOutward(layout, adjacentFace(face, (face.axis + 2) % 3, dv)).vec;
    feature.surfaceCount = 3;
    return feature;
}

float stopDistance(const(Section)* section, ContactTerms terms, float touch) {
    float result = contactTime(terms, section.sinhStopRadius);
    if (isNan(result)) {
        result = touch;
    }
    return result;
}

float gapAt(const(Section)* section, ContactTerms terms, float stop) {
    float result = section.skin;
    if (stop == 0) {
        result = separationDistance(terms) - section.radius;
    }
    return result;
}

bool improves(const(ChunkCollisionHit)* hit, float stop) {
    return isNan(hit.stopDistance) || stop < hit.stopDistance;
}

void takeHit(ChunkCollisionHit* hit, const(Section)* section, float stop, float gap, MVector!float normal, Feature feature) {
    hit.stopDistance = stop;
    hit.gap = gap;
    hit.normal = normal;
    hit.surfaces = feature.surfaces;
    hit.surfaceCount = feature.surfaceCount;
    hit.lowestSection = section.lowest;
    if (section.offset) {
        hit.normal = section.fromSection.mat * normal;
        foreach (i; 0 .. feature.surfaceCount) {
            hit.surfaces[i] = section.fromSection.mat * feature.surfaces[i];
        }
    }
}

void faceContact(const(Section)* section, ChunkLayout layout, SurfaceFace face, ChunkCollisionHit* hit, float tanhDistance) {
    size_t uAxis = (face.axis + 1) % 3;
    size_t vAxis = (face.axis + 2) % 3;
    MDirection!float outward = faceOutward(layout, face);
    if (section.ray.direction.mip(outward.vec) < 0) {
        ContactTerms terms = section.ray.planeTerms(outward);
        float touch = contactTime(terms, section.sinhRadius);
        if (!isNan(touch) && !(touch > tanhDistance)) {
            MVector!float center = section.ray.rayPoint(touch);
            MVector!float foot = center - outward.vec * center.mip(outward.vec);
            float stop = stopDistance(section, terms, touch);
            if (cellOwns(layout, foot, uAxis, face.cell[uAxis]) && cellOwns(layout, foot, vAxis, face.cell[vAxis]) && improves(hit, stop)) {
                takeHit(hit, section, stop, gapAt(section, terms, stop), outward.vec, faceFeature(layout, face));
            }
        }
    }
}

void faceBoundaryContacts(const(Section)* section, const(VoxelData)* voxelData, ChunkLayout layout, SurfaceFace face, ChunkCollisionHit* hit, float tanhDistance) {
    size_t uAxis = (face.axis + 1) % 3;
    size_t vAxis = (face.axis + 2) % 3;
    foreach (side; 0 .. 2) {
        if (boundarySideTested(voxelData, layout, face, uAxis, side)) {
            edgeContact(section, layout, face, uAxis, vAxis, side, hit, tanhDistance);
        }
        if (boundarySideTested(voxelData, layout, face, vAxis, side)) {
            edgeContact(section, layout, face, vAxis, uAxis, side, hit, tanhDistance);
        }
    }
    foreach (du; 0 .. 2) {
        foreach (dv; 0 .. 2) {
            if (boundarySideTested(voxelData, layout, face, uAxis, du) && boundarySideTested(voxelData, layout, face, vAxis, dv)) {
                cornerContact(section, layout, face, du, dv, hit, tanhDistance);
            }
        }
    }
}

void edgeContact(const(Section)* section, ChunkLayout layout, SurfaceFace face, size_t edgeAxis, size_t freeAxis, int side, ChunkCollisionHit* hit, float tanhDistance) {
    EdgeLine line = edgeLine(layout, face, edgeAxis, side);
    ContactTerms terms = section.ray.lineTerms(line.facePlane, line.edgePlane);
    float touch = contactTime(terms, section.sinhRadius);
    if (!isNan(touch) && !(touch > tanhDistance)) {
        float stop = stopDistance(section, terms, touch);
        if (cellOwns(layout, edgeFoot(line, section.ray.rayPoint(touch)), freeAxis, face.cell[freeAxis]) && improves(hit, stop)) {
            MVector!float center = section.ray.rayPoint(stop);
            takeHit(hit, section, stop, gapAt(section, terms, stop), center - edgeFoot(line, center), edgeFeature(layout, face, edgeAxis, side));
        }
    }
}

void cornerContact(const(Section)* section, ChunkLayout layout, SurfaceFace face, int du, int dv, ChunkCollisionHit* hit, float tanhDistance) {
    CornerFrame corner = cornerFrame(layout, face, du, dv);
    ContactTerms terms = section.ray.pointTerms(corner.planes[0], corner.planes[1], corner.planes[2]);
    float touch = contactTime(terms, section.sinhRadius);
    if (!isNan(touch) && !(touch > tanhDistance)) {
        float stop = stopDistance(section, terms, touch);
        if (improves(hit, stop)) {
            takeHit(hit, section, stop, gapAt(section, terms, stop), section.ray.rayPoint(stop) - corner.point, cornerFeature(layout, face, du, dv));
        }
    }
}

bool capsuleIntersectsVoxel(SweptShape shape, ChunkLayout layout, ubyte[3] cell, MPoint!float center) {
    uint sectionCount = capsuleSectionCount(shape);
    float sinhRadius = sinhf(shape.radius);
    bool result = false;
    foreach (sectionIndex; 0 .. sectionCount) {
        if (!result) {
            result = sphereIntersectsVoxel(layout, cell, axisPoint(center, shape.axis, sectionOffset(shape, sectionIndex, sectionCount)), sinhRadius);
        }
    }
    return result;
}

bool sphereIntersectsVoxel(ChunkLayout layout, ubyte[3] cell, MPoint!float center, float sinhRadius) {
    Ray probe = Ray(center, MDirection!float.x());
    float limit = sinhRadius * sinhRadius;
    bool inside = true;
    bool touching = false;
    foreach (axis; 0 .. 3) {
        foreach (sign; FACE_SIGNS) {
            SurfaceFace face = SurfaceFace(cell, cast(ubyte) axis, sign);
            MDirection!float outward = faceOutward(layout, face);
            float signedSinh = center.mip(outward.vec);
            size_t uAxis = (axis + 1) % 3;
            size_t vAxis = (axis + 2) % 3;
            if (signedSinh >= 0) {
                inside = false;
                MVector!float foot = center.vec - outward.vec * signedSinh;
                if (signedSinh * signedSinh < limit && cellOwns(layout, foot, uAxis, cell[uAxis]) && cellOwns(layout, foot, vAxis, cell[vAxis])) {
                    touching = true;
                }
            }
            foreach (side; 0 .. 2) {
                EdgeLine uLine = edgeLine(layout, face, uAxis, side);
                if (probe.lineTerms(uLine.facePlane, uLine.edgePlane).separationSquared < limit && cellOwns(layout, edgeFoot(uLine, center.vec), vAxis, cell[vAxis])) {
                    touching = true;
                }
                foreach (dv; 0 .. 2) {
                    CornerFrame corner = cornerFrame(layout, face, side, dv);
                    if (probe.pointTerms(corner.planes[0], corner.planes[1], corner.planes[2]).separationSquared < limit) {
                        touching = true;
                    }
                }
            }
        }
    }
    return inside || touching;
}

bool voxelSolidWithMargins(const(VoxelData)* voxelData, ChunkLayout layout, int[3] coords) {
    bool inRange = true;
    foreach (i; 0 .. 3) {
        if (coords[i] < -1 || coords[i] > layout.dimension) {
            inRange = false;
        }
    }
    bool result = false;
    if (inRange) {
        size_t stride = layout.dimension + 2;
        size_t index = (coords[0] + 1) + (coords[1] + 1) * stride + (coords[2] + 1) * stride * stride;
        result = voxelData.get(index) != Material.Void;
    }
    return result;
}

bool voxelIsSolid(const(VoxelData)* voxelData, ChunkLayout layout, ubyte[3] coords) {
    bool result = false;
    if (coords[0] < layout.dimension && coords[1] < layout.dimension && coords[2] < layout.dimension) {
        result = voxelData.get(Coords(coords).toIndex(layout.dimension)) != Material.Void;
    }
    return result;
}

unittest {
    SweptShape shape = SweptShape(MVector!float(0, 1, 0, 0), 0.4f, 0.9f, 0.01f);
    uint count = capsuleSectionCount(shape);
    assert(sectionOffset(shape, 0, count) == -capOffset(shape));
    assert(sectionOffset(shape, count - 1, count) == capOffset(shape));
    float spacing = sectionOffset(shape, 1, count) - sectionOffset(shape, 0, count);
    float half = spacing / 2;
    float ripple = shape.radius - sqrt(shape.radius * shape.radius - half * half);
    assert(ripple <= shape.skin);
    SweptShape sphere = SweptShape(MVector!float(0, 1, 0, 0), 0.4f, 0.4f, 0.01f);
    assert(capsuleSectionCount(sphere) == 1);
}

unittest {
    ChunkLayout layout = ChunkLayout(12);
    MPoint!float gridPoint(float[3] grid) {
        return MVector!float(grid[0] / layout.dualToGridFactor, grid[1] / layout.dualToGridFactor, grid[2] / layout.dualToGridFactor, 1.0f).normalizedPoint();
    }
    ubyte[3] cell = [5, 5, 5];
    MPoint!float center = gridPoint([5.5f, 5.5f, 5.5f]);
    MPoint!float outside = gridPoint([7.5f, 5.5f, 5.5f]);
    float sinhFaceDistance = outside.mip(faceOutward(layout, SurfaceFace(cell, 0, 1)).vec);
    assert(sinhFaceDistance > 0);
    assert(sphereIntersectsVoxel(layout, cell, center, sinhf(0.001f)));
    assert(sphereIntersectsVoxel(layout, cell, outside, sinhFaceDistance * 1.01f));
    assert(!sphereIntersectsVoxel(layout, cell, outside, sinhFaceDistance * 0.99f));
}
