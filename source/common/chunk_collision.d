module common.chunk_collision;

import core.stdc.math : ceilf, coshf, floorf, sinhf, tanhf;
import common.collision_math : MAX_TANH_DISTANCE, Ray, transformRay;
import common.math : MDirection, MIsometry, MPoint, MVector, isNan;
import common.node : ChunkLayout, VoxelData;
import common.voxel_math : Coords;
import common.world : Material;

enum float FACE_TIE_EPS = 1e-5f;
enum float GRID_PADDING_CELLS = 2.0f;
enum uint MAX_FACES = 256;
enum float SECTION_SPACING_RADII = 0.4f;
enum float FACE_BORDER_TOLERANCE_CELLS = 1e-4f;
enum float MIN_CAP_OFFSET = 1e-9f;

immutable byte[2] FACE_SIGNS = [-1, 1];

struct ChunkCollisionHit {
    MVector!float normal;
    float tanhDistance;
    bool isFace;
}

struct SweptShape {
    MVector!float axis;
    float radius;
    float halfHeight;
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
    float sinhRadius;
    bool offset;
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
    hit.tanhDistance = float.nan;
    hit.isFace = false;
    GridRange range = sweepGridRange(layout, ray, tanhDistance, shape.radius + shape.halfHeight);
    if (!range.empty) {
        SurfaceFace[MAX_FACES] faces = void;
        uint faceCount = collectSurfaceFaces(voxelData, layout, range, faces.ptr);
        float capOffset = 0;
        if (shape.halfHeight > shape.radius) {
            capOffset = shape.halfHeight - shape.radius;
        }
        uint sectionCount = capsuleSectionCount(capOffset, shape.radius);
        foreach (sectionIndex; 0 .. sectionCount) {
            Section section = capsuleSection(shape, ray, sectionOffset(sectionIndex, sectionCount, capOffset));
            foreach (i; 0 .. faceCount) {
                faceContact(&section, layout, faces[i], &hit, tanhDistance);
                faceBoundaryContacts(&section, voxelData, layout, faces[i], &hit, tanhDistance);
            }
        }
    }
    return hit;
}

uint capsuleSectionCount(float capOffset, float radius) {
    uint result = 1;
    if (capOffset > MIN_CAP_OFFSET) {
        result = cast(uint) ceilf(2.0f * capOffset / (radius * SECTION_SPACING_RADII)) + 1;
    }
    return result;
}

float sectionOffset(uint sectionIndex, uint sectionCount, float capOffset) {
    float result = 0;
    if (sectionCount > 1) {
        result = capOffset * (2.0f * cast(float) sectionIndex / cast(float)(sectionCount - 1) - 1.0f);
    }
    return result;
}

Section capsuleSection(SweptShape shape, Ray ray, float offset) {
    Section section;
    section.ray = ray;
    section.fromSection = MIsometry!float.identity();
    section.sinhRadius = sinhf(shape.radius);
    section.offset = offset != 0;
    if (section.offset) {
        MIsometry!float toSection = axisTranslation(ray, shape.axis, offset);
        section.ray = transformRay(toSection, ray);
        section.fromSection = toSection.inverse();
    }
    return section;
}

MIsometry!float axisTranslation(Ray ray, MVector!float axis, float offset) {
    MPoint!float target = MPoint!float(ray.position.vec * coshf(offset) + axis * sinhf(offset));
    return MIsometry!float.translation(MPoint!float(ray.position.vec), target);
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

bool withinCell(float grid, ubyte cell) {
    return grid >= cast(float) cell - FACE_BORDER_TOLERANCE_CELLS && grid <= cast(float) cell + 1.0f + FACE_BORDER_TOLERANCE_CELLS;
}

float faceLimit(const(ChunkCollisionHit)* hit, float tanhDistance) {
    float limit = tanhDistance;
    if (!isNan(hit.tanhDistance)) {
        limit = hit.tanhDistance;
    }
    if (!hit.isFace && !isNan(hit.tanhDistance)) {
        limit = hit.tanhDistance + FACE_TIE_EPS;
    }
    return limit;
}

float boundaryLimit(const(ChunkCollisionHit)* hit, float tanhDistance) {
    float limit = tanhDistance;
    if (!isNan(hit.tanhDistance)) {
        limit = hit.tanhDistance;
    }
    if (hit.isFace) {
        limit -= FACE_TIE_EPS;
    }
    return limit;
}

void takeHit(ChunkCollisionHit* hit, const(Section)* section, float distance, MVector!float normal, bool isFace) {
    MVector!float bodyNormal = normal;
    if (section.offset) {
        bodyNormal = section.fromSection.mat * normal;
    }
    hit.tanhDistance = distance;
    hit.normal = bodyNormal;
    hit.isFace = isFace;
}

void faceContact(const(Section)* section, ChunkLayout layout, SurfaceFace face, ChunkCollisionHit* hit, float tanhDistance) {
    size_t tAxis = face.axis;
    size_t uAxis = (tAxis + 1) % 3;
    size_t vAxis = (tAxis + 2) % 3;
    MDirection!float plane = gridPlane(layout, tAxis, facePlaneIndex(face));
    MDirection!float outward = plane;
    if (!(face.sign > 0)) {
        outward = -plane;
    }
    if (!(section.ray.direction.mip(outward.vec) >= 0)) {
        float newDistance = section.ray.solveSpherePlaneIntersection(outward, section.sinhRadius);
        if (!isNan(newDistance) && !(newDistance >= faceLimit(hit, tanhDistance))) {
            MVector!float rayEndpoint = section.ray.rayPoint(newDistance);
            MVector!float contact = rayEndpoint - outward.vec * rayEndpoint.mip(outward.vec);
            float gridU = contact.data[uAxis] / contact.data[3] * layout.dualToGridFactor;
            float gridV = contact.data[vAxis] / contact.data[3] * layout.dualToGridFactor;
            if (withinCell(gridU, face.cell[uAxis]) && withinCell(gridV, face.cell[vAxis])) {
                takeHit(hit, section, newDistance, outward.vec, true);
            }
        }
    }
}

bool inPlaneNeighborSolid(const(VoxelData)* voxelData, ChunkLayout layout, SurfaceFace face, size_t axis, int side) {
    int[3] neighbor = [face.cell[0], face.cell[1], face.cell[2]];
    neighbor[axis] += 2 * side - 1;
    return voxelSolidWithMargins(voxelData, layout, neighbor);
}

void faceBoundaryContacts(const(Section)* section, const(VoxelData)* voxelData, ChunkLayout layout, SurfaceFace face, ChunkCollisionHit* hit, float tanhDistance) {
    size_t uAxis = (face.axis + 1) % 3;
    size_t vAxis = (face.axis + 2) % 3;
    foreach (side; 0 .. 2) {
        if (!inPlaneNeighborSolid(voxelData, layout, face, uAxis, side)) {
            edgeContact(section, layout, face, uAxis, vAxis, side, hit, tanhDistance);
        }
        if (!inPlaneNeighborSolid(voxelData, layout, face, vAxis, side)) {
            edgeContact(section, layout, face, vAxis, uAxis, side, hit, tanhDistance);
        }
    }
    foreach (du; 0 .. 2) {
        foreach (dv; 0 .. 2) {
            if (!inPlaneNeighborSolid(voxelData, layout, face, uAxis, du) && !inPlaneNeighborSolid(voxelData, layout, face, vAxis, dv)) {
                cornerContact(section, layout, face, du, dv, hit, tanhDistance);
            }
        }
    }
}

void edgeContact(const(Section)* section, ChunkLayout layout, SurfaceFace face, size_t edgeAxis, size_t freeAxis, int side, ChunkCollisionHit* hit, float tanhDistance) {
    MDirection!float tPlane = gridPlane(layout, face.axis, facePlaneIndex(face));
    MDirection!float edgePlaneRaw = gridPlane(layout, edgeAxis, face.cell[edgeAxis] + side);
    MDirection!float edgePlane = (edgePlaneRaw.vec - tPlane.vec * tPlane.mip(edgePlaneRaw.vec)).normalizedDirection();
    float newDistance = section.ray.solveSphereLineIntersection(tPlane, edgePlane, section.sinhRadius);
    if (!isNan(newDistance) && !(newDistance >= boundaryLimit(hit, tanhDistance))) {
        MVector!float rayEndpoint = section.ray.rayPoint(newDistance);
        MVector!float contact = rayEndpoint - tPlane.vec * rayEndpoint.mip(tPlane.vec) - edgePlane.vec * rayEndpoint.mip(edgePlane.vec);
        if (layout.dualToVoxel(contact.data[freeAxis] / contact.data[3]) == face.cell[freeAxis]) {
            takeHit(hit, section, newDistance, rayEndpoint - contact, false);
        }
    }
}

void cornerContact(const(Section)* section, ChunkLayout layout, SurfaceFace face, int du, int dv, ChunkCollisionHit* hit, float tanhDistance) {
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
    float newDistance = section.ray.solveSpherePointIntersection(n0, n1, n2, section.sinhRadius);
    if (!isNan(newDistance) && !(newDistance >= boundaryLimit(hit, tanhDistance))) {
        MVector!float cornerDual = MVector!float(layout.gridToDual(cast(ubyte) grid[0]), layout.gridToDual(cast(ubyte) grid[1]), layout.gridToDual(cast(ubyte) grid[2]), 1.0f);
        MVector!float rayEndpoint = section.ray.rayPoint(newDistance);
        takeHit(hit, section, newDistance, rayEndpoint - cornerDual.normalizedPoint().vec, false);
    }
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
    assert(capsuleSectionCount(0, 1) == 1);
    float radius = 0.4f;
    float capOffset = 0.5f;
    uint count = capsuleSectionCount(capOffset, radius);
    assert(sectionOffset(0, count, capOffset) == -capOffset);
    assert(sectionOffset(count - 1, count, capOffset) == capOffset);
    float spacing = sectionOffset(1, count, capOffset) - sectionOffset(0, count, capOffset);
    assert(spacing <= radius * SECTION_SPACING_RADII);
}
