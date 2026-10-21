module common.character.sweep;

import core.math : sqrt;
import core.stdc.math : ceilf, fabsf;
import base.numbers : higherOf, isNan;
import base.vector3 : ZERO_VECTOR, cross, dot, magnitude, minus, plus, scaled;
import common.character.features : Edge, Features, Quad, unit;

enum double MIN_DISPLACEMENT_SQUARED = 1e-16;
enum float MIN_CREASE_SINE = 1e-3f;
enum float TEST_TOLERANCE = 1e-5f;

struct Capsule {
    float[3] axis;
    float radius;
    float halfHeight;
    float skin;

    float capOffset() const {
        return higherOf(halfHeight - radius, 0.0f);
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

    float[3] sectionCenter(float[3] center, uint sectionIndex, uint count) const {
        return center.plus(axis.scaled(sectionOffset(sectionIndex, count)));
    }
}

struct Contact {
    float[3] normal = [0, 0, 0];
    float stop = float.nan;
    float gap = 0;
    bool isLowestSection;

    bool isHit() const {
        return !isNan(stop);
    }

    bool isImprovedBy(float candidate) const {
        return isNan(stop) || candidate < stop;
    }
}

struct ContactPlane {
    float[3] normal;
    float separation;
}

bool isSameDirection(float[3] a, float[3] b) {
    return a.dot(b) > 0 && a.cross(b).magnitude < MIN_CREASE_SINE;
}

struct Section {
    const(ContactPlane)[] clipped;
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

    Contact accepted(Contact best, Contact candidate) const {
        size_t index = 0;
        while (index < clipped.length && !isSameDirection(clipped[index].normal, candidate.normal)) {
            index += 1;
        }
        if (index < clipped.length) {
            return best;
        } else {
            return candidate;
        }
    }

    Contact quadContact(ref const Quad quad, float[3] direction, float distance, Contact best) const {
        float separation = quad.separation(center);
        float rate = quad.normal.dot(direction);
        float stop = contactTime(separation * separation, separation * rate, rate * rate, stopRadius);
        if (rate >= 0 || !isTouchWithin(stop, distance) || !best.isImprovedBy(stop)) {
            return best;
        } else {
            float[3] at = center.plus(direction.scaled(stop));
            if (quad.isAbove(at.minus(quad.normal.scaled(quad.separation(at))))) {
                return accepted(best, Contact(quad.normal, stop, gapAt(separation, stop), isLowest));
            } else {
                return best;
            }
        }
    }

    Contact edgeContact(ref const Edge edge, float[3] direction, float distance, Contact best) const {
        float[3] along = edge.end.minus(edge.start);
        float length = along.magnitude;
        float[3] line = along.scaled(1.0f / length);
        float[3] offset = center.minus(edge.start);
        float[3] offsetAcross = offset.minus(line.scaled(offset.dot(line)));
        float[3] rateAcross = direction.minus(line.scaled(direction.dot(line)));
        float stop = contactTime(offsetAcross.dot(offsetAcross), offsetAcross.dot(rateAcross), rateAcross.dot(rateAcross), stopRadius);
        if (!isTouchWithin(stop, distance) || !best.isImprovedBy(stop)) {
            return best;
        } else {
            float[3] reached = center.plus(direction.scaled(stop)).minus(edge.start);
            float position = reached.dot(line);
            if (position >= 0 && position <= length) {
                return accepted(best, Contact(unit(reached.minus(line.scaled(position))), stop, gapAt(offsetAcross.magnitude, stop), isLowest));
            } else {
                return best;
            }
        }
    }

    Contact cornerContact(float[3] corner, float[3] direction, float distance, Contact best) const {
        float[3] offset = center.minus(corner);
        float stop = contactTime(offset.dot(offset), offset.dot(direction), direction.dot(direction), stopRadius);
        if (!isTouchWithin(stop, distance) || !best.isImprovedBy(stop)) {
            return best;
        } else {
            return accepted(best, Contact(unit(center.plus(direction.scaled(stop)).minus(corner)), stop, gapAt(offset.magnitude, stop), isLowest));
        }
    }
}

struct Sweep {
    float[3] displacement;
    float[3] normal = [0, 0, 0];
    float gap = 0;
    bool hasContact;
    bool isLowestSection;

    static Sweep fromCapsule(ref const Features features, Capsule capsule, float[3] start, float[3] displacement, const(ContactPlane)[] clipped) {
        float displacementSquared = displacement.dot(displacement);
        if (displacementSquared < MIN_DISPLACEMENT_SQUARED) {
            return Sweep(ZERO_VECTOR);
        } else {
            float distance = sqrt(displacementSquared);
            Contact contact = features.capsuleContact(capsule, start, displacement.scaled(1.0f / distance), distance, clipped);
            if (contact.isHit()) {
                return Sweep(displacement.scaled(contact.stop / distance), contact.normal, contact.gap, true, contact.isLowestSection);
            } else {
                return Sweep(displacement);
            }
        }
    }
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

Contact capsuleContact(ref const Features features, Capsule capsule, float[3] start, float[3] direction, float distance, const(ContactPlane)[] clipped) {
    uint count = capsule.sectionCount();
    Contact best;
    foreach (index; 0 .. count) {
        Section section = Section(clipped, capsule.sectionCenter(start, index, count), capsule.radius, capsule.radius + capsule.skin, index == 0);
        foreach (ref quad; features.quads.slice()) {
            best = section.quadContact(quad, direction, distance, best);
        }
        foreach (ref edge; features.edges.slice()) {
            best = section.edgeContact(edge, direction, distance, best);
        }
        foreach (corner; features.corners.slice()) {
            best = section.cornerContact(corner, direction, distance, best);
        }
    }
    return best;
}

float[3][] sectionCenters(Capsule capsule, float[3] center, float[3][] storage) {
    uint count = capsule.sectionCount();
    foreach (index; 0 .. count) {
        storage[index] = capsule.sectionCenter(center, index, count);
    }
    return storage[0 .. count];
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
    Quad floor = Quad([[0, 1, 0], [0, 1, 1], [1, 1, 1], [1, 1, 0]], [0, 1, 0]);
    Section section = Section(null, [0.5f, 2.0f, 0.5f], 0.4f, 0.41f, true);
    float[3] down = [0, -1, 0];
    Contact landing = section.quadContact(floor, down, 2.0f, Contact.init);
    assert(landing.isHit() && fabsf(landing.stop - 0.59f) < TEST_TOLERANCE);
    float[3] along = [1, 0, 0];
    assert(!section.quadContact(floor, along, 2.0f, Contact.init).isHit());
    Section resting = Section(null, [0.5f, 1.405f, 0.5f], 0.4f, 0.41f, true);
    Contact touching = resting.quadContact(floor, down, 1.0f, Contact.init);
    assert(touching.stop == 0 && touching.gap > 0.004f && touching.gap < 0.006f);
    Edge rim = Edge([1, 1, 0], [1, 1, 1]);
    Section beside = Section(null, [1.6f, 1.2f, 0.5f], 0.4f, 0.41f, true);
    float[3] toward = [-1, 0, 0];
    Contact edgeHit = beside.edgeContact(rim, toward, 1.0f, Contact.init);
    assert(edgeHit.isHit() && edgeHit.normal[0] > 0 && edgeHit.normal[1] > 0);
}
