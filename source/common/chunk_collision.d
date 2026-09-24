module common.chunk_collision;

import core.math : sqrt;
import core.stdc.math : ceilf, coshf, floorf, sinhf, tanhf;
import common.collision_math : MAX_TANH_DISTANCE, Ray, transformRay;
import common.math : MDirection, MIsometry, MPoint, MVector, isNan;
import common.node : ChunkLayout, VoxelData;
import common.voxel_math : Coords;
import common.world : Material;

enum float FACE_TIE_EPS = 1e-5f;
enum float GRID_PADDING_CELLS = 2.0f;
enum uint MAX_FACES = 256;
enum int SEGMENT_SAMPLES = 7;
enum float MIN_AXIS_LENGTH = 1e-6f;
enum float MIN_CAP_OFFSET = 1e-9f;

immutable byte[2] FACE_SIGNS = [-1, 1];
immutable float[3] SECTION_SIGNS = [0.0f, 1.0f, -1.0f];

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
        foreach (i; 0 .. faceCount) {
            faceContact(shape, layout, ray, faces[i], &hit, tanhDistance);
        }
        float capOffset = shape.halfHeight - shape.radius;
        if (capOffset < 0) {
            capOffset = 0;
        }
        uint sectionCount = 1;
        if (capOffset > MIN_CAP_OFFSET) {
            sectionCount = 3;
        }
        foreach (section; 0 .. sectionCount) {
            Ray sectionRay = ray;
            MIsometry!float fromSection = MIsometry!float.identity();
            bool offsetSection = SECTION_SIGNS[section] != 0;
            if (offsetSection) {
                MIsometry!float toSection = axisTranslation(ray, shape.axis, SECTION_SIGNS[section] * capOffset);
                sectionRay = transformRay(toSection, ray);
                fromSection = toSection.inverse();
            }
            foreach (i; 0 .. faceCount) {
                faceBoundaryContacts(shape, layout, sectionRay, fromSection, offsetSection, faces[i], &hit, tanhDistance);
            }
        }
    }
    return hit;
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

void faceContact(SweptShape shape, ChunkLayout layout, Ray ray, SurfaceFace face, ChunkCollisionHit* hit, float tanhDistance) {
    size_t tAxis = face.axis;
    size_t uAxis = (tAxis + 1) % 3;
    size_t vAxis = (tAxis + 2) % 3;
    MDirection!float plane = gridPlane(layout, tAxis, facePlaneIndex(face));
    MDirection!float outward = plane;
    if (!(face.sign > 0)) {
        outward = -plane;
    }
    if (!(ray.direction.mip(outward.vec) >= 0)) {
        float axial = shape.axis.mip(plane.vec);
        if (axial < 0) {
            axial = -axial;
        }
        if (axial > 1) {
            axial = 1;
        }
        float lateral = sqrt(1.0f - axial * axial);
        float sinhEffective = sinhf(shape.radius) * lateral + sinhf(shape.halfHeight) * axial;
        float newDistance = ray.solveSpherePlaneIntersection(outward, sinhEffective);
        float limit = tanhDistance;
        if (!isNan(hit.tanhDistance)) {
            limit = hit.tanhDistance;
        }
        if (!hit.isFace && !isNan(hit.tanhDistance)) {
            limit = hit.tanhDistance + FACE_TIE_EPS;
        }
        if (!isNan(newDistance) && !(newDistance >= limit)) {
            MVector!float rayEndpoint = ray.rayPoint(newDistance);
            MVector!float contact = rayEndpoint - outward.vec * rayEndpoint.mip(outward.vec);
            float gridU = contact.data[uAxis] / contact.data[3] * layout.dualToGridFactor;
            float gridV = contact.data[vAxis] / contact.data[3] * layout.dualToGridFactor;
            float axisU = shape.axis.data[uAxis];
            float axisV = shape.axis.data[vAxis];
            float axisLength = sqrt(axisU * axisU + axisV * axisV);
            float halfLength = sinhf(shape.halfHeight) * axisLength * layout.dualToGridFactor;
            float radius = sinhf(shape.radius) * layout.dualToGridFactor;
            float directionU = 0;
            float directionV = 0;
            if (axisLength > MIN_AXIS_LENGTH) {
                directionU = axisU / axisLength;
                directionV = axisV / axisLength;
            } else {
                halfLength = 0;
            }
            if (!(segmentRectDistance(gridU, gridV, directionU, directionV, halfLength, cast(float) face.cell[uAxis], cast(float) face.cell[vAxis]) > radius)) {
                hit.tanhDistance = newDistance;
                hit.normal = outward.vec;
                hit.isFace = true;
            }
        }
    }
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

void takeBoundaryHit(ChunkCollisionHit* hit, float distance, MVector!float normal, MIsometry!float fromSection, bool offsetSection) {
    MVector!float sectionNormal = normal;
    if (offsetSection) {
        sectionNormal = fromSection.mat * normal;
    }
    hit.tanhDistance = distance;
    hit.normal = sectionNormal;
    hit.isFace = false;
}

void faceBoundaryContacts(SweptShape shape, ChunkLayout layout, Ray sectionRay, MIsometry!float fromSection, bool offsetSection, SurfaceFace face, ChunkCollisionHit* hit, float tanhDistance) {
    size_t tAxis = face.axis;
    size_t uAxis = (tAxis + 1) % 3;
    size_t vAxis = (tAxis + 2) % 3;
    int t = facePlaneIndex(face);
    float sinhRadius = sinhf(shape.radius);
    MDirection!float tPlane = gridPlane(layout, tAxis, t);

    foreach (edgeAxisPick; 0 .. 2) {
        size_t edgeAxis = uAxis;
        size_t freeAxis = vAxis;
        if (edgeAxisPick == 1) {
            edgeAxis = vAxis;
            freeAxis = uAxis;
        }
        foreach (side; 0 .. 2) {
            MDirection!float edgePlaneRaw = gridPlane(layout, edgeAxis, face.cell[edgeAxis] + side);
            MDirection!float edgePlane = (edgePlaneRaw.vec - tPlane.vec * tPlane.mip(edgePlaneRaw.vec)).normalizedDirection();
            float newDistance = sectionRay.solveSphereLineIntersection(tPlane, edgePlane, sinhRadius);
            if (!isNan(newDistance) && !(newDistance >= boundaryLimit(hit, tanhDistance))) {
                MVector!float rayEndpoint = sectionRay.rayPoint(newDistance);
                MVector!float contact = rayEndpoint - tPlane.vec * rayEndpoint.mip(tPlane.vec) - edgePlane.vec * rayEndpoint.mip(edgePlane.vec);
                if (layout.dualToVoxel(contact.data[freeAxis] / contact.data[3]) == face.cell[freeAxis]) {
                    takeBoundaryHit(hit, newDistance, rayEndpoint - contact, fromSection, offsetSection);
                }
            }
        }
    }

    foreach (du; 0 .. 2) {
        foreach (dv; 0 .. 2) {
            int[3] grid;
            grid[tAxis] = t;
            grid[uAxis] = face.cell[uAxis] + du;
            grid[vAxis] = face.cell[vAxis] + dv;
            MDirection!float n0 = gridPlane(layout, 0, grid[0]);
            MVector!float n1Raw = gridPlane(layout, 1, grid[1]).vec;
            MDirection!float n1 = (n1Raw - n0.vec * n0.mip(n1Raw)).normalizedDirection();
            MVector!float n2Raw = gridPlane(layout, 2, grid[2]).vec;
            MDirection!float n2 = (n2Raw - n0.vec * n0.mip(n2Raw) - n1.vec * n1.mip(n2Raw)).normalizedDirection();
            float newDistance = sectionRay.solveSpherePointIntersection(n0, n1, n2, sinhRadius);
            if (!isNan(newDistance) && !(newDistance >= boundaryLimit(hit, tanhDistance))) {
                MVector!float cornerDual = MVector!float(layout.gridToDual(cast(ubyte) grid[0]), layout.gridToDual(cast(ubyte) grid[1]), layout.gridToDual(cast(ubyte) grid[2]), 1.0f);
                MVector!float rayEndpoint = sectionRay.rayPoint(newDistance);
                takeBoundaryHit(hit, newDistance, rayEndpoint - cornerDual.normalizedPoint().vec, fromSection, offsetSection);
            }
        }
    }
}

float distanceOutside(float position, float low) {
    float result = 0;
    if (position < low) {
        result = low - position;
    } else if (position > low + 1) {
        result = position - low - 1;
    }
    return result;
}

float segmentRectDistance(float centerU, float centerV, float directionU, float directionV, float halfLength, float rectU, float rectV) {
    float best = float.max;
    int sampleCount = SEGMENT_SAMPLES;
    if (halfLength == 0) {
        sampleCount = 1;
    }
    foreach (i; 0 .. sampleCount) {
        float s = 0;
        if (halfLength != 0) {
            s = -halfLength + 2.0f * halfLength * cast(float) i / (SEGMENT_SAMPLES - 1);
        }
        float dx = distanceOutside(centerU + directionU * s, rectU);
        float dy = distanceOutside(centerV + directionV * s, rectV);
        float d = sqrt(dx * dx + dy * dy);
        if (d < best) {
            best = d;
        }
    }
    return best;
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
