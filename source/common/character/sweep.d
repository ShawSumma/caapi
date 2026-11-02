module common.character.sweep;

import core.math : sqrt;
import core.stdc.math : ceilf;
import base.numbers : higherOf, isNan;
import base.vector3 : ZERO_VECTOR, cross, dot, magnitude, minus, plus, scaled;
import common.character.features : Edge, Features, Quad, unit;

enum double MIN_DISPLACEMENT_SQUARED = 1e-16;
enum float MIN_CREASE_SINE = 1e-3f;

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

enum SectionRank : ubyte {
    upper,
    lowest,
}

struct Contact {
    float[3] normal = [0, 0, 0];
    float stop = float.nan;
    float gap = 0;
    SectionRank rank;

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
    SectionRank rank;

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
                return accepted(best, Contact(quad.normal, stop, gapAt(separation, stop), rank));
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
                return accepted(best, Contact(unit(reached.minus(line.scaled(position))), stop, gapAt(offsetAcross.magnitude, stop), rank));
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
            return accepted(best, Contact(unit(center.plus(direction.scaled(stop)).minus(corner)), stop, gapAt(offset.magnitude, stop), rank));
        }
    }
}

struct Sweep {
    float[3] displacement;
    Contact contact;

    static Sweep fromCapsule(ref const Features features, Capsule capsule, float[3] start, float[3] displacement, const(ContactPlane)[] clipped) {
        float displacementSquared = displacement.dot(displacement);
        if (displacementSquared < MIN_DISPLACEMENT_SQUARED) {
            return Sweep(ZERO_VECTOR);
        } else {
            float distance = sqrt(displacementSquared);
            Contact contact = features.capsuleContact(capsule, start, displacement.scaled(1.0f / distance), distance, clipped);
            if (contact.isHit()) {
                return Sweep(displacement.scaled(contact.stop / distance), contact);
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
        SectionRank rank = SectionRank.upper;
        if (index == 0) {
            rank = SectionRank.lowest;
        }
        Section section = Section(clipped, capsule.sectionCenter(start, index, count), capsule.radius, capsule.radius + capsule.skin, rank);
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
