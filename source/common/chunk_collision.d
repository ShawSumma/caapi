module common.chunk_collision;

import core.math : sqrt;
import core.stdc.math : ceilf, coshf, floorf, sinhf, tanhf;
import core.stdc.stdlib : alloca;
import common.collision_math : ContactTerms, MAX_TANH_DISTANCE, Ray;
import common.math : MDirection, MIsometry, MPoint, MVector, isNan;
import common.node : ChunkLayout, VoxelData;
import common.voxel_math : Coords;
import common.world : Material;

enum float GRID_PADDING_CELLS = 2.0f;
enum uint MAX_FEATURE_SURFACES = 3;

immutable byte[2] FACE_SIGNS = [-1, 1];

struct ChunkCollisionHit {
    MVector!float normal;
    MVector!float[MAX_FEATURE_SURFACES] surfaces;
    float stopDistance = float.nan;
    float gap;
    uint surfaceCount;
    bool isLowestSection;

    bool isHit() const {
        return !isNan(stopDistance);
    }

    bool isImprovedBy(float stop) const {
        return isNan(stopDistance) || stop < stopDistance;
    }
}

struct SweptShape {
    MVector!float axis;
    float radius;
    float halfHeight;
    float skin;

    float capOffset() const {
        if (halfHeight > radius) {
            return halfHeight - radius;
        } else {
            return 0;
        }
    }

    float sectionSpacing() const {
        return 2.0f * sqrt(skin * (2.0f * radius - skin));
    }

    uint sectionCount() const {
        float length = 2.0f * capOffset();
        if (length > 0) {
            return cast(uint) ceilf(length / sectionSpacing()) + 1;
        } else {
            return 1;
        }
    }

    float sectionOffset(uint sectionIndex, uint count) const {
        if (count > 1) {
            return capOffset() * (2.0f * cast(float) sectionIndex / cast(float)(count - 1) - 1.0f);
        } else {
            return 0;
        }
    }
}

struct GridRange {
    int[3] lo;
    int[3] hi;
    bool isEmpty;
}

struct SurfaceFace {
    ubyte[3] cell;
    ubyte axis;
    byte sign;

    int planeIndex() const {
        if (sign > 0) {
            return cell[axis] + 1;
        } else {
            return cell[axis];
        }
    }

    MDirection!float outward(ChunkLayout layout) const {
        MDirection!float plane = gridPlane(layout, axis, planeIndex());
        if (sign > 0) {
            return plane;
        } else {
            return -plane;
        }
    }

    SurfaceFace adjacent(size_t adjacentAxis, int side) const {
        return SurfaceFace(cell, cast(ubyte) adjacentAxis, sideSign(side));
    }
}

struct Section {
    Ray ray;
    MIsometry!float fromSection;
    float radius;
    float skin;
    float sinhRadius;
    float sinhStopRadius;
    bool isOffset;
    bool isLowest;

    static Section make(SweptShape shape, Ray ray, uint sectionIndex, uint sectionCount) {
        float offset = shape.sectionOffset(sectionIndex, sectionCount);
        if (offset == 0) {
            return Section(ray, MIsometry!float.identity(), shape.radius, shape.skin, sinhf(shape.radius), sinhf(shape.radius + shape.skin), false, sectionIndex == 0);
        } else {
            MIsometry!float toSection = axisTranslation(ray.position, shape.axis, offset);
            return Section(ray.transformedBy(toSection), toSection.inverse(), shape.radius, shape.skin, sinhf(shape.radius), sinhf(shape.radius + shape.skin), true, sectionIndex == 0);
        }
    }

    float stopDistance(ContactTerms terms, float touch) const {
        float stop = terms.contactTime(sinhStopRadius);
        if (isNan(stop)) {
            return touch;
        } else {
            return stop;
        }
    }

    float gapAt(ContactTerms terms, float stop) const {
        if (stop == 0) {
            return terms.separationDistance() - radius;
        } else {
            return skin;
        }
    }

    ChunkCollisionHit hit(float stop, float gap, MVector!float normal, Feature feature) const {
        ChunkCollisionHit result;
        result.stopDistance = stop;
        result.gap = gap;
        result.surfaceCount = feature.surfaceCount;
        result.isLowestSection = isLowest;
        if (isOffset) {
            result.normal = fromSection.mat * normal;
            foreach (i; 0 .. feature.surfaceCount) {
                result.surfaces[i] = fromSection.mat * feature.surfaces[i];
            }
        } else {
            result.normal = normal;
            result.surfaces = feature.surfaces;
        }
        return result;
    }
}

struct EdgeLine {
    MDirection!float facePlane;
    MDirection!float edgePlane;

    MVector!float foot(MVector!float point) const {
        return point - facePlane.vec * point.mip(facePlane.vec) - edgePlane.vec * point.mip(edgePlane.vec);
    }
}

struct CornerFrame {
    MDirection!float[3] planes;
    MVector!float point;
}

struct Feature {
    MVector!float[MAX_FEATURE_SURFACES] surfaces;
    uint surfaceCount;
}

byte sideSign(int side) {
    if (side == 1) {
        return 1;
    } else {
        return -1;
    }
}

float lowerOf(float a, float b) {
    if (a < b) {
        return a;
    } else {
        return b;
    }
}

float higherOf(float a, float b) {
    if (a > b) {
        return a;
    } else {
        return b;
    }
}

int gridLow(float low) {
    if (low < 0) {
        return 0;
    } else {
        return cast(int) floorf(low);
    }
}

int gridHigh(float high, ubyte dimension) {
    if (high > cast(float)(dimension - 1)) {
        return dimension - 1;
    } else {
        return cast(int) ceilf(high);
    }
}

GridRange sweepGridRange(ChunkLayout layout, Ray ray, float tanhDistance, float padDistance) {
    GridRange range;
    MVector!float p0 = ray.position.vec;
    MVector!float p1 = ray.rayPoint(lowerOf(tanhDistance, MAX_TANH_DISTANCE));
    float pad = tanhf(padDistance) * layout.dualToGridFactor + GRID_PADDING_CELLS;
    foreach (i; 0 .. 3) {
        float g0 = p0.data[i] / p0.data[3] * layout.dualToGridFactor;
        float g1 = p1.data[i] / p1.data[3] * layout.dualToGridFactor;
        float low = lowerOf(g0, g1) - pad;
        float high = higherOf(g0, g1) + pad;
        if (low > cast(float) layout.dimension || high < 0) {
            range.isEmpty = true;
            return range;
        } else {
            range.lo[i] = gridLow(low);
            range.hi[i] = gridHigh(high, layout.dimension);
        }
    }
    return range;
}

ChunkCollisionHit chunkShapeCast(SweptShape shape, const(VoxelData)* voxelData, ChunkLayout layout, Ray ray, float tanhDistance) {
    GridRange range = sweepGridRange(layout, ray, tanhDistance, shape.radius + shape.halfHeight);
    ChunkCollisionHit hit;
    if (!range.isEmpty) {
        uint sectionCount = shape.sectionCount();
        Section* sections = cast(Section*) alloca(sectionCount * Section.sizeof);
        foreach (sectionIndex; 0 .. sectionCount) {
            sections[sectionIndex] = Section.make(shape, ray, sectionIndex, sectionCount);
        }
        foreach (cx; range.lo[0] .. range.hi[0] + 1) {
            foreach (cy; range.lo[1] .. range.hi[1] + 1) {
                foreach (cz; range.lo[2] .. range.hi[2] + 1) {
                    ubyte[3] cell = [cast(ubyte) cx, cast(ubyte) cy, cast(ubyte) cz];
                    if (voxelData.isVoxelSolid(layout, cell)) {
                        foreach (axis; 0 .. 3) {
                            foreach (sign; FACE_SIGNS) {
                                int[3] neighbor = [cx, cy, cz];
                                neighbor[axis] += sign;
                                if (!voxelData.isVoxelSolidWithMargins(layout, neighbor)) {
                                    SurfaceFace face = SurfaceFace(cell, cast(ubyte) axis, sign);
                                    foreach (section; sections[0 .. sectionCount]) {
                                        hit = faceContact(&section, layout, face, hit, tanhDistance);
                                        hit = faceBoundaryContacts(&section, voxelData, layout, face, hit, tanhDistance);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return hit;
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

EdgeLine edgeLine(ChunkLayout layout, SurfaceFace face, size_t edgeAxis, int side) {
    MDirection!float facePlane = gridPlane(layout, face.axis, face.planeIndex());
    MDirection!float edgePlaneRaw = gridPlane(layout, edgeAxis, face.cell[edgeAxis] + side);
    MDirection!float edgePlane = (edgePlaneRaw.vec - facePlane.vec * facePlane.mip(edgePlaneRaw.vec)).normalizedDirection();
    return EdgeLine(facePlane, edgePlane);
}

CornerFrame cornerFrame(ChunkLayout layout, SurfaceFace face, int du, int dv) {
    size_t uAxis = (face.axis + 1) % 3;
    size_t vAxis = (face.axis + 2) % 3;
    int[3] grid;
    grid[face.axis] = face.planeIndex();
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

bool isOwnedByCell(ChunkLayout layout, MVector!float point, size_t axis, ubyte cell) {
    return layout.dualToVoxel(point.data[axis] / point.data[3]) == cell;
}

bool isBoundarySideTested(const(VoxelData)* voxelData, ChunkLayout layout, SurfaceFace face, size_t axis, int side) {
    int[3] neighbor = [face.cell[0], face.cell[1], face.cell[2]];
    neighbor[axis] += 2 * side - 1;
    return neighbor[axis] < 0 || neighbor[axis] >= layout.dimension || !voxelData.isVoxelSolidWithMargins(layout, neighbor);
}

Feature faceFeature(ChunkLayout layout, SurfaceFace face) {
    Feature feature;
    feature.surfaces[0] = face.outward(layout).vec;
    feature.surfaceCount = 1;
    return feature;
}

Feature edgeFeature(ChunkLayout layout, SurfaceFace face, size_t edgeAxis, int side) {
    Feature feature = faceFeature(layout, face);
    feature.surfaces[1] = face.adjacent(edgeAxis, side).outward(layout).vec;
    feature.surfaceCount = 2;
    return feature;
}

Feature cornerFeature(ChunkLayout layout, SurfaceFace face, int du, int dv) {
    Feature feature = faceFeature(layout, face);
    feature.surfaces[1] = face.adjacent((face.axis + 1) % 3, du).outward(layout).vec;
    feature.surfaces[2] = face.adjacent((face.axis + 2) % 3, dv).outward(layout).vec;
    feature.surfaceCount = 3;
    return feature;
}

bool isTouchWithin(float touch, float tanhDistance) {
    return !isNan(touch) && !(touch > tanhDistance);
}

ChunkCollisionHit faceContact(const(Section)* section, ChunkLayout layout, SurfaceFace face, ChunkCollisionHit best, float tanhDistance) {
    size_t uAxis = (face.axis + 1) % 3;
    size_t vAxis = (face.axis + 2) % 3;
    MDirection!float outward = face.outward(layout);
    ContactTerms terms = section.ray.planeTerms(outward);
    float touch = terms.contactTime(section.sinhRadius);
    if (section.ray.direction.mip(outward.vec) >= 0 || !isTouchWithin(touch, tanhDistance)) {
        return best;
    } else {
        MVector!float center = section.ray.rayPoint(touch);
        MVector!float foot = center - outward.vec * center.mip(outward.vec);
        float stop = section.stopDistance(terms, touch);
        if (isOwnedByCell(layout, foot, uAxis, face.cell[uAxis]) && isOwnedByCell(layout, foot, vAxis, face.cell[vAxis]) && best.isImprovedBy(stop)) {
            return section.hit(stop, section.gapAt(terms, stop), outward.vec, faceFeature(layout, face));
        } else {
            return best;
        }
    }
}

ChunkCollisionHit faceBoundaryContacts(const(Section)* section, const(VoxelData)* voxelData, ChunkLayout layout, SurfaceFace face, ChunkCollisionHit best, float tanhDistance) {
    size_t uAxis = (face.axis + 1) % 3;
    size_t vAxis = (face.axis + 2) % 3;
    ChunkCollisionHit hit = best;
    foreach (side; 0 .. 2) {
        if (isBoundarySideTested(voxelData, layout, face, uAxis, side)) {
            hit = edgeContact(section, layout, face, uAxis, vAxis, side, hit, tanhDistance);
        }
        if (isBoundarySideTested(voxelData, layout, face, vAxis, side)) {
            hit = edgeContact(section, layout, face, vAxis, uAxis, side, hit, tanhDistance);
        }
    }
    foreach (du; 0 .. 2) {
        foreach (dv; 0 .. 2) {
            if (isBoundarySideTested(voxelData, layout, face, uAxis, du) && isBoundarySideTested(voxelData, layout, face, vAxis, dv)) {
                hit = cornerContact(section, layout, face, du, dv, hit, tanhDistance);
            }
        }
    }
    return hit;
}

ChunkCollisionHit edgeContact(const(Section)* section, ChunkLayout layout, SurfaceFace face, size_t edgeAxis, size_t freeAxis, int side, ChunkCollisionHit best, float tanhDistance) {
    EdgeLine line = edgeLine(layout, face, edgeAxis, side);
    ContactTerms terms = section.ray.lineTerms(line.facePlane, line.edgePlane);
    float touch = terms.contactTime(section.sinhRadius);
    if (!isTouchWithin(touch, tanhDistance)) {
        return best;
    } else {
        float stop = section.stopDistance(terms, touch);
        if (isOwnedByCell(layout, line.foot(section.ray.rayPoint(touch)), freeAxis, face.cell[freeAxis]) && best.isImprovedBy(stop)) {
            MVector!float center = section.ray.rayPoint(stop);
            return section.hit(stop, section.gapAt(terms, stop), center - line.foot(center), edgeFeature(layout, face, edgeAxis, side));
        } else {
            return best;
        }
    }
}

ChunkCollisionHit cornerContact(const(Section)* section, ChunkLayout layout, SurfaceFace face, int du, int dv, ChunkCollisionHit best, float tanhDistance) {
    CornerFrame corner = cornerFrame(layout, face, du, dv);
    ContactTerms terms = section.ray.pointTerms(corner.planes[0], corner.planes[1], corner.planes[2]);
    float touch = terms.contactTime(section.sinhRadius);
    if (!isTouchWithin(touch, tanhDistance)) {
        return best;
    } else {
        float stop = section.stopDistance(terms, touch);
        if (best.isImprovedBy(stop)) {
            return section.hit(stop, section.gapAt(terms, stop), section.ray.rayPoint(stop) - corner.point, cornerFeature(layout, face, du, dv));
        } else {
            return best;
        }
    }
}

bool isCapsuleIntersectingVoxel(SweptShape shape, ChunkLayout layout, ubyte[3] cell, MPoint!float center) {
    uint sectionCount = shape.sectionCount();
    float sinhRadius = sinhf(shape.radius);
    foreach (sectionIndex; 0 .. sectionCount) {
        if (isSphereIntersectingVoxel(layout, cell, axisPoint(center, shape.axis, shape.sectionOffset(sectionIndex, sectionCount)), sinhRadius)) {
            return true;
        }
    }
    return false;
}

bool isInsideVoxel(ChunkLayout layout, ubyte[3] cell, MPoint!float center) {
    foreach (axis; 0 .. 3) {
        foreach (sign; FACE_SIGNS) {
            if (center.mip(SurfaceFace(cell, cast(ubyte) axis, sign).outward(layout).vec) >= 0) {
                return false;
            }
        }
    }
    return true;
}

bool isSphereTouchingVoxel(ChunkLayout layout, ubyte[3] cell, MPoint!float center, float sinhRadius) {
    Ray probe = Ray(center, MDirection!float.x());
    float limit = sinhRadius * sinhRadius;
    foreach (axis; 0 .. 3) {
        size_t uAxis = (axis + 1) % 3;
        size_t vAxis = (axis + 2) % 3;
        foreach (sign; FACE_SIGNS) {
            SurfaceFace face = SurfaceFace(cell, cast(ubyte) axis, sign);
            MDirection!float outward = face.outward(layout);
            float signedSinh = center.mip(outward.vec);
            MVector!float foot = center.vec - outward.vec * signedSinh;
            if (signedSinh >= 0 && signedSinh * signedSinh < limit && isOwnedByCell(layout, foot, uAxis, cell[uAxis]) && isOwnedByCell(layout, foot, vAxis, cell[vAxis])) {
                return true;
            }
            foreach (side; 0 .. 2) {
                EdgeLine uLine = edgeLine(layout, face, uAxis, side);
                if (probe.lineTerms(uLine.facePlane, uLine.edgePlane).separationSquared < limit && isOwnedByCell(layout, uLine.foot(center.vec), vAxis, cell[vAxis])) {
                    return true;
                }
                foreach (dv; 0 .. 2) {
                    CornerFrame corner = cornerFrame(layout, face, side, dv);
                    if (probe.pointTerms(corner.planes[0], corner.planes[1], corner.planes[2]).separationSquared < limit) {
                        return true;
                    }
                }
            }
        }
    }
    return false;
}

bool isSphereIntersectingVoxel(ChunkLayout layout, ubyte[3] cell, MPoint!float center, float sinhRadius) {
    return isInsideVoxel(layout, cell, center) || isSphereTouchingVoxel(layout, cell, center, sinhRadius);
}

bool isVoxelSolidWithMargins(const(VoxelData)* voxelData, ChunkLayout layout, int[3] coords) {
    foreach (i; 0 .. 3) {
        if (coords[i] < -1 || coords[i] > layout.dimension) {
            return false;
        }
    }
    size_t stride = layout.dimension + 2;
    size_t index = (coords[0] + 1) + (coords[1] + 1) * stride + (coords[2] + 1) * stride * stride;
    return voxelData.get(index) != Material.Void;
}

bool isVoxelSolid(const(VoxelData)* voxelData, ChunkLayout layout, ubyte[3] coords) {
    return coords[0] < layout.dimension && coords[1] < layout.dimension && coords[2] < layout.dimension && voxelData.get(Coords(coords).toIndex(layout.dimension)) != Material.Void;
}

unittest {
    SweptShape shape = SweptShape(MVector!float(0, 1, 0, 0), 0.4f, 0.9f, 0.01f);
    uint count = shape.sectionCount();
    assert(shape.sectionOffset(0, count) == -shape.capOffset());
    assert(shape.sectionOffset(count - 1, count) == shape.capOffset());
    float spacing = shape.sectionOffset(1, count) - shape.sectionOffset(0, count);
    float half = spacing / 2;
    float ripple = shape.radius - sqrt(shape.radius * shape.radius - half * half);
    assert(ripple <= shape.skin);
    SweptShape sphere = SweptShape(MVector!float(0, 1, 0, 0), 0.4f, 0.4f, 0.01f);
    assert(sphere.sectionCount() == 1);
}

unittest {
    ChunkLayout layout = ChunkLayout(12);
    MPoint!float gridPoint(float[3] grid) {
        return MVector!float(grid[0] / layout.dualToGridFactor, grid[1] / layout.dualToGridFactor, grid[2] / layout.dualToGridFactor, 1.0f).normalizedPoint();
    }
    ubyte[3] cell = [5, 5, 5];
    MPoint!float center = gridPoint([5.5f, 5.5f, 5.5f]);
    MPoint!float outside = gridPoint([7.5f, 5.5f, 5.5f]);
    float sinhFaceDistance = outside.mip(SurfaceFace(cell, 0, 1).outward(layout).vec);
    assert(sinhFaceDistance > 0);
    assert(isSphereIntersectingVoxel(layout, cell, center, sinhf(0.001f)));
    assert(isSphereIntersectingVoxel(layout, cell, outside, sinhFaceDistance * 1.01f));
    assert(!isSphereIntersectingVoxel(layout, cell, outside, sinhFaceDistance * 0.99f));
}
