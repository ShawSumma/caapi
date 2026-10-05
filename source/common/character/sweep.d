module common.character.sweep;

import core.math : sqrt;
import core.stdc.math : ceilf, floorf;
import common.character.place : Place, SameCell, isCellBlocked, isOnAnyPath;
import common.coords : Coords;
import common.graph : Graph;
import common.math : higherOf, isNan, lowerOf;
import common.node : ChunkSlot;
import common.vector3 : ZERO_VECTOR, dot, magnitude, minus, plus, scaled;

enum uint MAX_FEATURE_SURFACES = 3;
enum int MAX_BOX_EDGE = 12;
enum int BOX_MARGIN_CELLS = 1;
enum double MIN_DISPLACEMENT_SQUARED = 1e-16;
enum float TEST_TOLERANCE = 1e-5f;

immutable int[2] FACE_SIGNS = [-1, 1];

struct Capsule {
    float[3] axis;
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

struct Contact {
    float[3][MAX_FEATURE_SURFACES] surfaces;
    float[3] normal = [0, 0, 0];
    float stop = float.nan;
    float gap = 0;
    uint surfaceCount;
    bool isLowestSection;

    bool isHit() const {
        return !isNan(stop);
    }

    bool isImprovedBy(float candidate) const {
        return isNan(stop) || candidate < stop;
    }
}

struct Section {
    float[3] center;
    float radius;
    float stopRadius;
    bool isLowest;

    float gapAt(float separation, float stop) const {
        if (stop == 0) {
            return separation - radius;
        } else {
            return stopRadius - radius;
        }
    }
}

struct Bounds {
    float[3] low;
    float[3] high;

    static Bounds fromCapsule(float[3] center, float[3] tip, float reach) {
        Bounds bounds;
        foreach (axis; 0 .. 3) {
            bounds.low[axis] = center[axis] - absolute(tip[axis]) - reach;
            bounds.high[axis] = center[axis] + absolute(tip[axis]) + reach;
        }
        return bounds;
    }

    Bounds merged(Bounds other) const {
        Bounds result;
        foreach (axis; 0 .. 3) {
            result.low[axis] = lowerOf(low[axis], other.low[axis]);
            result.high[axis] = higherOf(high[axis], other.high[axis]);
        }
        return result;
    }
}

struct CellRange {
    int[3] low;
    int[3] size;

    static CellRange fromBounds(Bounds bounds, int margin) {
        CellRange range;
        foreach (axis; 0 .. 3) {
            range.low[axis] = cast(int) floorf(bounds.low[axis]) - margin;
            range.size[axis] = cast(int) floorf(bounds.high[axis]) + margin - range.low[axis] + 1;
        }
        return range;
    }

    uint count() const {
        return size[0] * size[1] * size[2];
    }

    int[3] cellAt(uint index) const {
        return [low[0] + cast(int)(index % size[0]), low[1] + cast(int)(index / size[0] % size[1]), low[2] + cast(int)(index / (size[0] * size[1]))];
    }

    uint indexOf(int[3] cell) const {
        return (cell[0] - low[0]) + size[0] * ((cell[1] - low[1]) + size[1] * (cell[2] - low[2]));
    }

    bool isInterior(int[3] cell, int margin) const {
        uint axis = 0;
        while (axis < 3 && cell[axis] >= low[axis] + margin && cell[axis] < low[axis] + size[axis] - margin) {
            axis += 1;
        }
        return axis == 3;
    }
}

struct CellBox {
    bool[MAX_BOX_EDGE * MAX_BOX_EDGE * MAX_BOX_EDGE] isBlocked;
    CellRange range;

    static CellBox fromBounds(ref const Graph graph, ChunkSlot chunk, Bounds bounds) {
        CellBox box;
        box.range = CellRange.fromBounds(bounds, BOX_MARGIN_CELLS);
        assert(box.range.size[0] <= MAX_BOX_EDGE && box.range.size[1] <= MAX_BOX_EDGE && box.range.size[2] <= MAX_BOX_EDGE);
        foreach (index; 0 .. box.range.count()) {
            box.isBlocked[index] = graph.isCellBlocked(chunk, box.range.cellAt(index));
        }
        return box;
    }

    bool isSolid(int[3] cell) const {
        return isBlocked[range.indexOf(cell)];
    }

    bool isSolidBeside(int[3] cell, size_t axis, int sign) const {
        int[3] neighbor = cell;
        neighbor[axis] += sign;
        return isSolid(neighbor);
    }
}

struct Sweep {
    float[3][MAX_FEATURE_SURFACES] surfaces;
    float[3] displacement;
    float[3] normal = [0, 0, 0];
    float gap = 0;
    uint surfaceCount;
    bool hasContact;
    bool isLowestSection;

    static Sweep fromCapsule(ref const Graph graph, Capsule capsule, Place place, float[3] displacement) {
        float displacementSquared = displacement.dot(displacement);
        if (displacementSquared < MIN_DISPLACEMENT_SQUARED) {
            return Sweep.fromFreeMove(ZERO_VECTOR);
        } else {
            float distance = sqrt(displacementSquared);
            float[3] direction = place.frame.toGrid(displacement.scaled(1.0f / distance));
            Contact contact = graph.capsuleContact(capsule, place, direction, distance);
            if (contact.isHit()) {
                return Sweep.fromContact(contact, place, displacement.scaled(contact.stop / distance));
            } else {
                return Sweep.fromFreeMove(displacement);
            }
        }
    }

    static Sweep fromFreeMove(float[3] displacement) {
        Sweep sweep;
        sweep.displacement = displacement;
        return sweep;
    }

    static Sweep fromContact(Contact contact, Place place, float[3] displacement) {
        float[3][MAX_FEATURE_SURFACES] surfaces;
        foreach (i; 0 .. contact.surfaceCount) {
            surfaces[i] = place.frame.toBody(contact.surfaces[i]);
        }
        return Sweep(surfaces, displacement, place.frame.toBody(contact.normal), contact.gap, contact.surfaceCount, true, contact.isLowestSection);
    }
}

float absolute(float value) {
    if (value < 0) {
        return -value;
    } else {
        return value;
    }
}

float[3] axisVector(size_t axis, float sign) {
    float[3] result = [0, 0, 0];
    result[axis] = sign;
    return result;
}

float[3] unit(float[3] v) {
    return v.scaled(1.0f / v.magnitude);
}

int sideSign(int side) {
    if (side == 1) {
        return 1;
    } else {
        return -1;
    }
}

float planeCoord(int cell, int sign) {
    if (sign > 0) {
        return cell + 1;
    } else {
        return cell;
    }
}

bool isOwned(float coord, int cell) {
    return floorf(coord) == cell;
}

bool isTouchWithin(float stop, float distance) {
    return !isNan(stop) && !(stop > distance);
}

float contactTime(float separationSquared, float approach, float directionSquared, float stopRadius) {
    float constantTerm = separationSquared - stopRadius * stopRadius;
    float discriminant = approach * approach - directionSquared * constantTerm;
    if (approach >= 0.0f) {
        return float.nan;
    } else if (constantTerm <= 0.0f && separationSquared - approach * approach / directionSquared < separationSquared) {
        return 0.0f;
    } else if (constantTerm <= 0.0f) {
        return float.nan;
    } else if (discriminant > 0.0f) {
        return constantTerm / (-approach + sqrt(discriminant));
    } else {
        return float.nan;
    }
}

Section sectionOf(Capsule capsule, float[3] center, float[3] axis, uint index, uint count) {
    return Section(center.plus(axis.scaled(capsule.sectionOffset(index, count))), capsule.radius, capsule.radius + capsule.skin, index == 0);
}

Bounds sweptBounds(Capsule capsule, float[3] start, float[3] axis, float[3] end) {
    float[3] tip = axis.scaled(capsule.capOffset());
    float reach = capsule.radius + capsule.skin;
    return Bounds.fromCapsule(start, tip, reach).merged(Bounds.fromCapsule(end, tip, reach));
}

Contact capsuleContact(ref const Graph graph, Capsule capsule, Place place, float[3] direction, float distance) {
    float[3] axis = place.frame.toGrid(capsule.axis);
    CellBox box = CellBox.fromBounds(graph, place.chunk, sweptBounds(capsule, place.grid, axis, place.grid.plus(direction.scaled(distance))));
    uint count = capsule.sectionCount();
    Contact best;
    foreach (index; 0 .. box.range.count()) {
        int[3] cell = box.range.cellAt(index);
        if (box.range.isInterior(cell, BOX_MARGIN_CELLS) && box.isSolid(cell)) {
            foreach (faceAxis; 0 .. 3) {
                foreach (sign; FACE_SIGNS) {
                    if (!box.isSolidBeside(cell, faceAxis, sign)) {
                        foreach (sectionIndex; 0 .. count) {
                            Section section = sectionOf(capsule, place.grid, axis, sectionIndex, count);
                            best = section.faceContact(direction, distance, cell, faceAxis, sign, best);
                            best = section.faceBoundaryContacts(box, direction, distance, cell, faceAxis, sign, best);
                        }
                    }
                }
            }
        }
    }
    return best;
}

Contact faceContact(Section section, float[3] direction, float distance, int[3] cell, size_t axis, int sign, Contact best) {
    size_t uAxis = (axis + 1) % 3;
    size_t vAxis = (axis + 2) % 3;
    float separation = sign * (section.center[axis] - planeCoord(cell[axis], sign));
    float rate = sign * direction[axis];
    float stop = contactTime(separation * separation, separation * rate, rate * rate, section.stopRadius);
    if (rate >= 0 || !isTouchWithin(stop, distance)) {
        return best;
    } else {
        float[3] at = section.center.plus(direction.scaled(stop));
        if (isOwned(at[uAxis], cell[uAxis]) && isOwned(at[vAxis], cell[vAxis]) && best.isImprovedBy(stop)) {
            float[3] normal = axisVector(axis, sign);
            return Contact([normal, ZERO_VECTOR, ZERO_VECTOR], normal, stop, section.gapAt(separation, stop), 1, section.isLowest);
        } else {
            return best;
        }
    }
}

Contact faceBoundaryContacts(Section section, ref const CellBox box, float[3] direction, float distance, int[3] cell, size_t axis, int sign, Contact best) {
    size_t uAxis = (axis + 1) % 3;
    size_t vAxis = (axis + 2) % 3;
    Contact hit = best;
    foreach (side; 0 .. 2) {
        if (!box.isSolidBeside(cell, uAxis, sideSign(side))) {
            hit = section.edgeContact(direction, distance, cell, axis, sign, uAxis, side, hit);
        }
        if (!box.isSolidBeside(cell, vAxis, sideSign(side))) {
            hit = section.edgeContact(direction, distance, cell, axis, sign, vAxis, side, hit);
        }
    }
    foreach (du; 0 .. 2) {
        foreach (dv; 0 .. 2) {
            if (!box.isSolidBeside(cell, uAxis, sideSign(du)) && !box.isSolidBeside(cell, vAxis, sideSign(dv))) {
                hit = section.cornerContact(direction, distance, cell, axis, sign, du, dv, hit);
            }
        }
    }
    return hit;
}

Contact edgeContact(Section section, float[3] direction, float distance, int[3] cell, size_t axis, int sign, size_t edgeAxis, int side, Contact best) {
    size_t freeAxis = 3 - axis - edgeAxis;
    float[3] point = [0, 0, 0];
    point[axis] = planeCoord(cell[axis], sign);
    point[edgeAxis] = cell[edgeAxis] + side;
    float[3] offset = section.center.minus(point);
    offset[freeAxis] = 0;
    float[3] rate = direction;
    rate[freeAxis] = 0;
    float stop = contactTime(offset.dot(offset), offset.dot(rate), rate.dot(rate), section.stopRadius);
    if (!isTouchWithin(stop, distance)) {
        return best;
    } else {
        float[3] at = section.center.plus(direction.scaled(stop));
        if (isOwned(at[freeAxis], cell[freeAxis]) && best.isImprovedBy(stop)) {
            float[3] normal = at.minus(point);
            normal[freeAxis] = 0;
            return Contact([axisVector(axis, sign), axisVector(edgeAxis, sideSign(side)), ZERO_VECTOR], unit(normal), stop, section.gapAt(offset.magnitude, stop), 2, section.isLowest);
        } else {
            return best;
        }
    }
}

Contact cornerContact(Section section, float[3] direction, float distance, int[3] cell, size_t axis, int sign, int du, int dv, Contact best) {
    size_t uAxis = (axis + 1) % 3;
    size_t vAxis = (axis + 2) % 3;
    float[3] point = [0, 0, 0];
    point[axis] = planeCoord(cell[axis], sign);
    point[uAxis] = cell[uAxis] + du;
    point[vAxis] = cell[vAxis] + dv;
    float[3] offset = section.center.minus(point);
    float stop = contactTime(offset.dot(offset), offset.dot(direction), direction.dot(direction), section.stopRadius);
    if (!isTouchWithin(stop, distance) || !best.isImprovedBy(stop)) {
        return best;
    } else {
        float[3] normal = section.center.plus(direction.scaled(stop)).minus(point);
        return Contact([axisVector(axis, sign), axisVector(uAxis, sideSign(du)), axisVector(vAxis, sideSign(dv))], unit(normal), stop, section.gapAt(offset.magnitude, stop), 3, section.isLowest);
    }
}

float squaredDistanceToCell(float[3] point, int[3] cell) {
    float total = 0;
    foreach (axis; 0 .. 3) {
        float below = cell[axis] - point[axis];
        float above = point[axis] - (cell[axis] + 1);
        float outside = higherOf(higherOf(below, above), 0);
        total += outside * outside;
    }
    return total;
}

bool isCapsuleTouchingCell(Capsule capsule, float[3] center, float[3] axis, int[3] cell) {
    uint count = capsule.sectionCount();
    uint section = 0;
    while (section < count && !(squaredDistanceToCell(center.plus(axis.scaled(capsule.sectionOffset(section, count))), cell) < capsule.radius * capsule.radius)) {
        section += 1;
    }
    return section < count;
}

bool isCapsuleOverlappingCell(ref const Graph graph, Capsule capsule, Place place, ChunkSlot target, Coords coords) {
    float[3] axis = place.frame.toGrid(capsule.axis);
    CellRange range = CellRange.fromBounds(sweptBounds(capsule, place.grid, axis, place.grid), 0);
    SameCell sameCell = SameCell(target, coords);
    uint index = 0;
    while (index < range.count() && !(isCapsuleTouchingCell(capsule, place.grid, axis, range.cellAt(index)) && graph.isOnAnyPath(sameCell, place.chunk, range.cellAt(index)))) {
        index += 1;
    }
    return index < range.count();
}

bool isCapsuleBlocked(ref const Graph graph, Capsule capsule, Place place) {
    float[3] axis = place.frame.toGrid(capsule.axis);
    CellRange range = CellRange.fromBounds(sweptBounds(capsule, place.grid, axis, place.grid), 0);
    uint index = 0;
    while (index < range.count() && !(isCapsuleTouchingCell(capsule, place.grid, axis, range.cellAt(index)) && graph.isCellBlocked(place.chunk, range.cellAt(index)))) {
        index += 1;
    }
    return index < range.count();
}

unittest {
    Capsule capsule = Capsule([0, 1, 0], 0.4f, 0.9f, 0.01f);
    uint count = capsule.sectionCount();
    assert(capsule.sectionOffset(0, count) == -capsule.capOffset());
    assert(capsule.sectionOffset(count - 1, count) == capsule.capOffset());
    float spacing = capsule.sectionOffset(1, count) - capsule.sectionOffset(0, count);
    float half = spacing / 2;
    assert(capsule.radius - sqrt(capsule.radius * capsule.radius - half * half) <= capsule.skin);
    Capsule sphere = Capsule([0, 1, 0], 0.4f, 0.4f, 0.01f);
    assert(sphere.sectionCount() == 1);
}

unittest {
    Section section = Section([0.5f, 2.0f, 0.5f], 0.4f, 0.41f, true);
    float[3] down = [0, -1, 0];
    int[3] floor = [0, 0, 0];
    Contact landing = section.faceContact(down, 2.0f, floor, 1, 1, Contact.init);
    assert(landing.isHit() && landing.stop > 0.59f - TEST_TOLERANCE && landing.stop < 0.59f + TEST_TOLERANCE);
    float[3] along = [1, 0, 0];
    assert(!section.faceContact(along, 2.0f, floor, 1, 1, Contact.init).isHit());
    Section resting = Section([0.5f, 1.405f, 0.5f], 0.4f, 0.41f, true);
    Contact touching = resting.faceContact(down, 1.0f, floor, 1, 1, Contact.init);
    assert(touching.stop == 0 && touching.gap > 0.004f && touching.gap < 0.006f);
}
