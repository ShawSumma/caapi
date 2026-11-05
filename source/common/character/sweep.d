module common.character.sweep;

import core.math : sqrt;
import core.stdc.math : ceilf;
import base.maybe : Maybe;
import base.numbers : higherOf;
import base.vector3 : Vec3, ZERO_VECTOR, cross, dot, magnitude, minus, plus, scaled;
import common.character.features : Edge, Features, Quad, unit;

enum double MIN_DISPLACEMENT_SQUARED = 1e-16;
enum float MIN_CREASE_SINE = 1e-3f;

struct Capsule {
    Vec3!float axis;
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

    Vec3!float sectionCenter(Vec3!float center, uint sectionIndex, uint count) const {
        return center.plus(axis.scaled(sectionOffset(sectionIndex, count)));
    }
}

enum SectionRank : ubyte {
    upper,
    lowest,
}

struct Contact {
    Vec3!float normal = Vec3!float(0, 0, 0);
    float stop = 0;
    float gap = 0;
    SectionRank rank;
}

bool isImprovedBy(Maybe!Contact best, float candidate) {
    return !best.exists || candidate < best.value.stop;
}

struct ContactPlane {
    Vec3!float normal;
    float separation;
}

bool isSameDirection(Vec3!float a, Vec3!float b) {
    return a.dot(b) > 0 && a.cross(b).magnitude < MIN_CREASE_SINE;
}

struct Section {
    const(ContactPlane)[] clipped;
    Vec3!float center;
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

    Maybe!Contact accepted(Maybe!Contact best, Contact candidate) const {
        size_t index = 0;
        while (index < clipped.length && !isSameDirection(clipped[index].normal, candidate.normal)) {
            index += 1;
        }
        if (index < clipped.length) {
            return best;
        } else {
            return Maybe!Contact.of(candidate);
        }
    }

    Maybe!Contact quadContact(ref const Quad quad, Vec3!float direction, float distance, Maybe!Contact best) const {
        float separation = quad.separation(center);
        float rate = quad.normal.dot(direction);
        Maybe!float stop = contactTime(separation * separation, separation * rate, rate * rate, stopRadius);
        if (rate >= 0 || !isTouchWithin(stop, distance) || !best.isImprovedBy(stop.value)) {
            return best;
        } else {
            Vec3!float at = center.plus(direction.scaled(stop.value));
            if (quad.isAbove(at.minus(quad.normal.scaled(quad.separation(at))))) {
                return accepted(best, Contact(quad.normal, stop.value, gapAt(separation, stop.value), rank));
            } else {
                return best;
            }
        }
    }

    Maybe!Contact edgeContact(ref const Edge edge, Vec3!float direction, float distance, Maybe!Contact best) const {
        Vec3!float along = edge.end.minus(edge.start);
        float length = along.magnitude;
        Vec3!float line = along.scaled(1.0f / length);
        Vec3!float offset = center.minus(edge.start);
        Vec3!float offsetAcross = offset.minus(line.scaled(offset.dot(line)));
        Vec3!float rateAcross = direction.minus(line.scaled(direction.dot(line)));
        Maybe!float stop = contactTime(offsetAcross.dot(offsetAcross), offsetAcross.dot(rateAcross), rateAcross.dot(rateAcross), stopRadius);
        if (!isTouchWithin(stop, distance) || !best.isImprovedBy(stop.value)) {
            return best;
        } else {
            Vec3!float reached = center.plus(direction.scaled(stop.value)).minus(edge.start);
            float position = reached.dot(line);
            if (position >= 0 && position <= length) {
                return accepted(best, Contact(unit(reached.minus(line.scaled(position))), stop.value, gapAt(offsetAcross.magnitude, stop.value), rank));
            } else {
                return best;
            }
        }
    }

    Maybe!Contact cornerContact(Vec3!float corner, Vec3!float direction, float distance, Maybe!Contact best) const {
        Vec3!float offset = center.minus(corner);
        Maybe!float stop = contactTime(offset.dot(offset), offset.dot(direction), direction.dot(direction), stopRadius);
        if (!isTouchWithin(stop, distance) || !best.isImprovedBy(stop.value)) {
            return best;
        } else {
            return accepted(best, Contact(unit(center.plus(direction.scaled(stop.value)).minus(corner)), stop.value, gapAt(offset.magnitude, stop.value), rank));
        }
    }
}

struct Sweep {
    Vec3!float displacement;
    Maybe!Contact contact;

    static Sweep fromCapsule(ref const Features features, Capsule capsule, Vec3!float start, Vec3!float displacement, const(ContactPlane)[] clipped) {
        float displacementSquared = displacement.dot(displacement);
        if (displacementSquared < MIN_DISPLACEMENT_SQUARED) {
            return Sweep(ZERO_VECTOR);
        } else {
            float distance = sqrt(displacementSquared);
            Maybe!Contact contact = features.capsuleContact(capsule, start, displacement.scaled(1.0f / distance), distance, clipped);
            if (contact.exists) {
                return Sweep(displacement.scaled(contact.value.stop / distance), contact);
            } else {
                return Sweep(displacement);
            }
        }
    }
}

bool isTouchWithin(Maybe!float stop, float distance) {
    return stop.exists && !(stop.value > distance);
}

Maybe!float contactTime(float separationSquared, float approach, float directionSquared, float stopRadius) {
    float constantTerm = separationSquared - stopRadius * stopRadius;
    float discriminant = approach * approach - directionSquared * constantTerm;
    if (approach >= 0.0f) {
        return Maybe!float.init;
    } else if (constantTerm <= 0.0f && separationSquared - approach * approach / directionSquared < separationSquared) {
        return Maybe!float.of(0.0f);
    } else if (constantTerm <= 0.0f) {
        return Maybe!float.init;
    } else if (discriminant > 0.0f) {
        return Maybe!float.of(constantTerm / (-approach + sqrt(discriminant)));
    } else {
        return Maybe!float.init;
    }
}

Maybe!Contact capsuleContact(ref const Features features, Capsule capsule, Vec3!float start, Vec3!float direction, float distance, const(ContactPlane)[] clipped) {
    uint count = capsule.sectionCount();
    Maybe!Contact best;
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

Vec3!float[] sectionCenters(Capsule capsule, Vec3!float center, Vec3!float[] storage) {
    uint count = capsule.sectionCount();
    foreach (index; 0 .. count) {
        storage[index] = capsule.sectionCenter(center, index, count);
    }
    return storage[0 .. count];
}
