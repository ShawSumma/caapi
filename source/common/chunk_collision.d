module common.chunk_collision;

import common.collision_math : Ray, transformRay;
import common.math : MDirection, MIsometry, MPoint, MVector;
import common.math : ceil, cosh, floor, isNaN, sinh, sqrt, tanh;
import common.node : VoxelData, ChunkLayout;
import common.voxel_math : Coords;
import common.world : Material;

struct ChunkCollisionHit {
    float tanhDistance;
    MVector!float normal;
    // Face contacts (surface rectangles) outrank edge/corner contacts in
    // near-ties: an edge lying in a contacted face must not steal the
    // contact with its tilted radial normal.
    bool isFace;
}

/// Face contacts beat edge/corner contacts within this distance.
enum float FACE_TIE_EPS = 1e-5f;

/// A swept upright cylinder: `radius` laterally, `halfHeight` along `axis`
/// (a unit direction at the ray origin). Face rectangles are tested with the
/// cylinder's support (flat caps, straight sides); edges and corners with
/// sphere sections at the feet, waist, and head.
struct SweptShape {
    float radius;
    float halfHeight;
    MVector!float axis;

    static SweptShape sphere(float radius) {
        SweptShape s;
        s.radius = radius;
        s.halfHeight = radius;
        s.axis = MVector!float(0, 1, 0, 0);
        return s;
    }

    static SweptShape cylinder(float radius, float halfHeight, MVector!float axis) {
        SweptShape s;
        s.radius = radius;
        s.halfHeight = halfHeight;
        s.axis = axis;
        return s;
    }
}

// Grid-index window the sweep can touch; the sweep is a fraction of a voxel
// long, so this bounds the surface enumeration to a handful of cells.
struct GridRange {
    int[3] lo;
    int[3] hi;
    bool empty;
}

GridRange sweepGridRange(
    const ref ChunkLayout layout,
    const ref Ray ray,
    float tanhDistance,
    float padDistance
) {
    GridRange r;
    r.empty = false;

    float capped = tanhDistance < 0.999f ? tanhDistance : 0.999f;
    MVector!float p0 = ray.position.vec;
    MVector!float p1 = ray.rayPoint(capped);
    float pad = tanh(padDistance) * layout.dualToGridFactor + 2.0f;

    foreach (i; 0 .. 3) {
        float g0 = p0.data[i] / p0.data[3] * layout.dualToGridFactor;
        float g1 = p1.data[i] / p1.data[3] * layout.dualToGridFactor;
        float lo = (g0 < g1 ? g0 : g1) - pad;
        float hi = (g0 > g1 ? g0 : g1) + pad;
        if (lo > cast(float) layout.dimension || hi < 0) {
            r.empty = true;
            return r;
        }
        r.lo[i] = lo < 0 ? 0 : cast(int) floor(lo);
        int cellHi = hi > cast(float)(layout.dimension - 1) ? layout.dimension - 1 : cast(int) ceil(hi);
        r.hi[i] = cellHi;
    }
    return r;
}

// One exposed surface face: solid cell, empty neighbor across `axis` in
// direction `sign` — exactly the faces the renderer's extraction emits.
struct SurfaceFace {
    ubyte[3] cell;
    ubyte axis;    // t axis
    byte sign;     // +1: face on the cell's high side, -1: low side
}

ChunkCollisionHit chunkShapeCast(
    const ref SweptShape shape,
    const ref VoxelData voxelData,
    const ref ChunkLayout layout,
    const ref Ray ray,
    float tanhDistance
) {
    ChunkCollisionHit hit;
    hit.tanhDistance = float.nan;
    hit.isFace = false;

    GridRange range = sweepGridRange(layout, ray, tanhDistance, shape.radius + shape.halfHeight);
    if (range.empty) {
        return hit;
    }

    // Enumerate the surface mesh inside the window.
    enum MAX_FACES = 256;
    SurfaceFace[MAX_FACES] faces = void;
    uint faceCount = 0;

    foreach (cx; range.lo[0] .. range.hi[0] + 1) {
        foreach (cy; range.lo[1] .. range.hi[1] + 1) {
            foreach (cz; range.lo[2] .. range.hi[2] + 1) {
                ubyte[3] cell = [cast(ubyte) cx, cast(ubyte) cy, cast(ubyte) cz];
                if (!voxelIsSolid(voxelData, layout, cell)) {
                    continue;
                }
                foreach (axis; 0 .. 3) {
                    foreach (sign; [cast(byte)-1, cast(byte) 1]) {
                        int[3] nb = [cx, cy, cz];
                        nb[axis] += sign;
                        if (voxelSolidWithMargins(voxelData, layout, nb)) {
                            continue;
                        }
                        if (faceCount < MAX_FACES) {
                            faces[faceCount++] = SurfaceFace(cell, cast(ubyte) axis, sign);
                        }
                    }
                }
            }
        }
    }
    if (faceCount == 0) {
        return hit;
    }

    // Pass 1: face rectangles (cylinder support, footprint-vs-rect).
    foreach (i; 0 .. faceCount) {
        faceContact(shape, layout, ray, faces[i], hit, tanhDistance);
    }

    // Pass 2: bounded edges and corners of those faces, per sphere section.
    float capOffset = shape.halfHeight - shape.radius;
    if (capOffset < 0) {
        capOffset = 0;
    }
    int sectionCount = capOffset > 1e-9f ? 3 : 1;
    static immutable float[3] SECTION_SIGNS = [0.0f, 1.0f, -1.0f];

    foreach (si; 0 .. sectionCount) {
        Ray sectionRay = ray;
        MIsometry!float fromSection = MIsometry!float.identity();
        bool offsetSection = SECTION_SIGNS[si] != 0;
        if (offsetSection) {
            MIsometry!float toSection = axisTranslation(ray, shape.axis, SECTION_SIGNS[si] * capOffset);
            sectionRay = transformRay(toSection, ray);
            fromSection = toSection.inverse();
        }

        foreach (i; 0 .. faceCount) {
            faceBoundaryContacts(shape, layout, sectionRay, fromSection, offsetSection,
                faces[i], hit, tanhDistance);
        }
    }

    return hit;
}

MIsometry!float axisTranslation(const ref Ray ray, MVector!float axis, float offset) {
    MPoint!float target = MPoint!float(ray.position.vec * cosh(offset) + axis * sinh(offset));
    return MIsometry!float.translation(MPoint!float(ray.position.vec), target);
}

MDirection!float gridPlane(const ref ChunkLayout layout, size_t axis, int t) {
    float[4] nData = [0, 0, 0, 0];
    nData[axis] = 1.0f;
    nData[3] = layout.gridToDual(cast(ubyte) t);
    return MVector!float(nData[0], nData[1], nData[2], nData[3]).normalizedDirection();
}

void faceContact(
    const ref SweptShape shape,
    const ref ChunkLayout layout,
    const ref Ray ray,
    const ref SurfaceFace face,
    ref ChunkCollisionHit hit,
    float tanhDistance
) {
    size_t tAxis = face.axis;
    size_t uAxis = (tAxis + 1) % 3;
    size_t vAxis = (tAxis + 2) % 3;
    int t = face.cell[tAxis] + (face.sign > 0 ? 1 : 0);

    MDirection!float plane = gridPlane(layout, tAxis, t);
    MDirection!float outward = face.sign > 0 ? plane : -plane;

    // Backface: only contacts approaching the face from its outside count.
    if (ray.direction.mip(outward) >= 0) {
        return;
    }

    // Cylinder support against this plane orientation.
    float axial = shape.axis.mip(plane.vec);
    if (axial < 0) {
        axial = -axial;
    }
    if (axial > 1) {
        axial = 1;
    }
    float lateral = sqrt(1.0f - axial * axial);
    float sinhEff = sinh(shape.radius) * lateral + sinh(shape.halfHeight) * axial;

    float newDist = ray.solveSphereePlaneIntersection(outward, sinhEff);
    if (isNaN(newDist)) {
        return;
    }
    float limit = !isNaN(hit.tanhDistance) ? hit.tanhDistance : tanhDistance;
    // A face may take over an edge hit within the tie margin.
    if (!hit.isFace && !isNaN(hit.tanhDistance)) {
        limit = hit.tanhDistance + FACE_TIE_EPS;
    }
    if (newDist >= limit) {
        return;
    }

    // Contact footprint (2D capsule: axis projected into the plane, thickened
    // by the lateral radius) must overlap this face's rectangle.
    MVector!float rayEndpoint = ray.rayPoint(newDist);
    MVector!float contact = rayEndpoint - outward.vec * rayEndpoint.mip(outward.vec);
    float gridU = contact.data[uAxis] / contact.data[3] * layout.dualToGridFactor;
    float gridV = contact.data[vAxis] / contact.data[3] * layout.dualToGridFactor;

    float axU = shape.axis.data[uAxis];
    float axV = shape.axis.data[vAxis];
    float axLen = sqrt(axU * axU + axV * axV);
    float halfLen = sinh(shape.halfHeight) * axLen * layout.dualToGridFactor;
    float radius = sinh(shape.radius) * layout.dualToGridFactor;
    float dirU = 0;
    float dirV = 0;
    if (axLen > 1e-6f) {
        dirU = axU / axLen;
        dirV = axV / axLen;
    } else {
        halfLen = 0;
    }

    if (segmentRectDistance(gridU, gridV, dirU, dirV, halfLen,
            cast(float) face.cell[uAxis], cast(float) face.cell[vAxis]) > radius) {
        return;
    }

    hit.tanhDistance = newDist;
    hit.normal = outward.vec;
    hit.isFace = true;
}

void faceBoundaryContacts(
    const ref SweptShape shape,
    const ref ChunkLayout layout,
    const ref Ray sectionRay,
    const ref MIsometry!float fromSection,
    bool offsetSection,
    const ref SurfaceFace face,
    ref ChunkCollisionHit hit,
    float tanhDistance
) {
    size_t tAxis = face.axis;
    size_t uAxis = (tAxis + 1) % 3;
    size_t vAxis = (tAxis + 2) % 3;
    int t = face.cell[tAxis] + (face.sign > 0 ? 1 : 0);
    float sinhR = sinh(shape.radius);

    MDirection!float tPlane = gridPlane(layout, tAxis, t);

    float limit() {
        float l = !isNaN(hit.tanhDistance) ? hit.tanhDistance : tanhDistance;
        if (hit.isFace) {
            l -= FACE_TIE_EPS;
        }
        return l;
    }

    void takeHit(float dist, MVector!float normal) {
        if (offsetSection) {
            normal = fromSection.mat * normal;
        }
        hit.tanhDistance = dist;
        hit.normal = normal;
        hit.isFace = false;
    }

    // Four bounded edge segments of the face rectangle.
    foreach (edgeAxisPick; 0 .. 2) {
        size_t eAxis = edgeAxisPick == 0 ? uAxis : vAxis;   // fixed coordinate axis
        size_t fAxis = edgeAxisPick == 0 ? vAxis : uAxis;   // free coordinate along the edge
        foreach (side; 0 .. 2) {
            int e = face.cell[eAxis] + side;
            MDirection!float ePlaneRaw = gridPlane(layout, eAxis, e);
            MDirection!float ePlane = (ePlaneRaw.vec - tPlane.vec * tPlane.mip(ePlaneRaw.vec)).normalizedDirection();

            float newDist = sectionRay.solveSpherLineIntersection(tPlane, ePlane, sinhR);
            if (isNaN(newDist) || newDist >= limit()) {
                continue;
            }

            MVector!float rayEndpoint = sectionRay.rayPoint(newDist);
            MVector!float contact = rayEndpoint - tPlane.vec * rayEndpoint.mip(tPlane.vec)
                                       - ePlane.vec * rayEndpoint.mip(ePlane.vec);
            int freeCoord = layout.dualToVoxel(contact.data[fAxis] / contact.data[3]);
            if (freeCoord != face.cell[fAxis]) {
                continue;
            }

            takeHit(newDist, rayEndpoint - contact);
        }
    }

    // Four corners of the face rectangle.
    foreach (du; 0 .. 2) {
        foreach (dv; 0 .. 2) {
            int[3] g;
            g[tAxis] = t;
            g[uAxis] = face.cell[uAxis] + du;
            g[vAxis] = face.cell[vAxis] + dv;

            MDirection!float n0 = gridPlane(layout, 0, g[0]);
            MVector!float n1v = gridPlane(layout, 1, g[1]).vec;
            MDirection!float n1 = (n1v - n0.vec * n0.mip(n1v)).normalizedDirection();
            MVector!float n2v = gridPlane(layout, 2, g[2]).vec;
            MDirection!float n2 = (n2v - n0.vec * n0.mip(n2v) - n1.vec * n1.mip(n2v)).normalizedDirection();

            float newDist = sectionRay.solveSpherePointIntersection(n0, n1, n2, sinhR);
            if (isNaN(newDist) || newDist >= limit()) {
                continue;
            }

            MPoint!float cornerPos = MVector!float(
                layout.gridToDual(cast(ubyte) g[0]),
                layout.gridToDual(cast(ubyte) g[1]),
                layout.gridToDual(cast(ubyte) g[2]),
                1.0f
            ).normalizedPoint();

            MVector!float rayEndpoint = sectionRay.rayPoint(newDist);
            takeHit(newDist, rayEndpoint - cornerPos.vec);
        }
    }
}

// Distance from the segment (center c, direction d, half-length L) to the
// unit cell [cx, cx+1] x [cy, cy+1], by sampling the segment and taking
// point-to-rect distances (segments here are at most ~2 cells long).
float segmentRectDistance(
    float cx0, float cy0, float dirU, float dirV, float halfLen,
    float rectU, float rectV
) {
    enum int SAMPLES = 7;
    float best = float.max;
    foreach (i; 0 .. SAMPLES) {
        float s = halfLen == 0 ? 0
            : (-halfLen + 2.0f * halfLen * cast(float) i / (SAMPLES - 1));
        float px = cx0 + dirU * s;
        float py = cy0 + dirV * s;
        float dx = px < rectU ? rectU - px : (px > rectU + 1 ? px - rectU - 1 : 0);
        float dy = py < rectV ? rectV - py : (py > rectV + 1 ? py - rectV - 1 : 0);
        float d = sqrt(dx * dx + dy * dy);
        if (d < best) {
            best = d;
        }
        if (halfLen == 0) {
            break;
        }
    }
    return best;
}

/// Solidity including the margin layer: coordinates may range -1..dimension,
/// where the out-of-chunk cells read the mirrored neighbor-chunk data.
bool voxelSolidWithMargins(const ref VoxelData voxelData, const ref ChunkLayout layout, int[3] coords) {
    foreach (i; 0 .. 3) {
        if (coords[i] < -1 || coords[i] > layout.dimension) {
            return false;
        }
    }
    size_t csm = layout.dimension + 2;
    size_t idx = (coords[0] + 1) + (coords[1] + 1) * csm + (coords[2] + 1) * csm * csm;
    return voxelData.get(idx) != Material.Void;
}

bool voxelIsSolid(const ref VoxelData voxelData, const ref ChunkLayout layout, ubyte[3] coords) {
    if (coords[0] >= layout.dimension || coords[1] >= layout.dimension || coords[2] >= layout.dimension) {
        return false;
    }
    return voxelData.get(Coords(coords).toIndex(layout.dimension)) != Material.Void;
}
