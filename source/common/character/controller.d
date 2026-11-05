module common.character.controller;

import core.stdc.math : acosf, atanhf, ceilf, cosf, expf, fabsf, sinf;
import base.maybe : Maybe;
import base.numbers : clamped, higherOf;
import base.units : Length, Ratio, Speed, Time;
import base.vector3 : Vec3, ZERO_VECTOR, cappedTo, cross, dot, magnitude, minus, negated, plus, projectedOntoPlane, rejectAlong, scaled;
import common.character.features : BlockProbe, Features, visitCells;
import common.character.sweep : Capsule, Contact, ContactPlane, MIN_CREASE_SINE, SectionRank, Sweep, isSameDirection;
import common.graph : Graph;
import common.position : Position;
import common.settings : CharacterConfig;
import common.worldgen.horospheres : Gravity, gravityAt, isGravityKnown;
import geometry.lorentz : Motion;
import plugins.api.flags : Flags;

enum uint MAX_CONTACT_PLANES = 5;
enum uint MAX_SLIDE_PLANES = MAX_CONTACT_PLANES + 1;
enum float MAX_INPUT_LENGTH = 1.0f;

enum MovementMode : ubyte {
    walk,
    fly,
    noclip,
}

enum Jump : ubyte {
    none,
    pressed,
}

enum Footing : ubyte {
    airborne,
    grounded,
}

enum SlideKind : ubyte {
    move,
    settle,
}

enum SkinRule : ubyte {
    ignore,
    restore,
}

enum SlideMark : ubyte {
    landed,
    obstructed,
    climbing,
}

struct CharacterInput {
    Vec3!float movement = Vec3!float(0, 0, 0);
    MovementMode mode;
    Jump jump;
}

struct Stepped {
    Length traveled;
    uint stalls;

    bool isStalled() const {
        return stalls > 0;
    }
}

Length regionReach(ref const CharacterConfig character) {
    return character.halfHeight + character.radius * 2.0f + character.skin * 2.0f;
}

struct CharacterState {
    Position position;
    Vec3!float velocity = Vec3!float(0, 0, 0);
    Vec3!float groundNormal = Vec3!float(0, 1, 0);
    Vec3!float up = Vec3!float(0, 1, 0);
    Vec3!float pull = Vec3!float(0, 1, 0);
    Footing footing;

    bool isOnGround() const {
        return footing == Footing.grounded;
    }

    Stepped runStep(ref const CharacterConfig character, ref const Graph graph, CharacterInput input, Time step) {
        uint substeps = higherOf(cast(uint) ceilf((speedBound(character, input.mode, step) * step / character.radius).value), 1u);
        Time dt = step / cast(float) substeps;
        Stepped stepped;
        Features features;
        Vec3!float movement = input.movement;
        foreach (_; 0 .. substeps) {
            Gravity gravity = Gravity(up, 0);
            if (graph.isGravityKnown(graph.slotOf(position.node).value)) {
                gravity = graph.gravityAt(position);
            }
            Vec3!float turned = up;
            if (gravity.strength >= character.leastTurningGravity.value) {
                turned = turnedToward(up, gravity.up, (character.upTurnRate * dt).value);
            }
            Vec3!float pivot = turned.minus(up).scaled((character.halfHeight - character.radius).value);
            if (up.dot(gravity.up) < 0) {
                pivot = pivot.negated;
            }
            movement = rotatedBetween(movement, up, turned);
            Vec3!float halfway = turned.plus(turned.minus(up).scaled(0.5f));
            input.movement = rotatedBetween(movement, turned, halfway.scaled(1.0f / halfway.magnitude));
            up = turned;
            pull = gravity.up.scaled(gravity.strength);
            Vec3!float offset = ZERO_VECTOR;
            if (input.mode == MovementMode.noclip) {
                offset = noclipStep(character, input, dt);
            } else {
                features.collect(graph, position, regionReach(character));
                if (features.isLoaded) {
                    Mover mover = Mover.make(character, features, up, stepRiseAhead(character, graph, input));
                    Vec3!float pivoted = mover.slide(ZERO_VECTOR, pivot, ZERO_VECTOR, SlideKind.move, PlaneSet.init).position;
                    if (input.mode == MovementMode.fly) {
                        offset = flyStep(mover, pivoted, input, dt);
                    } else {
                        offset = walkStep(mover, pivoted, input, dt);
                    }
                } else {
                    velocity = ZERO_VECTOR;
                    stepped.stalls += 1;
                }
            }
            input.jump = Jump.none;
            stepped.traveled = stepped.traveled + Length(offset.magnitude);
            position = graph.movedBy(position, offset);
        }
        features.release();
        return stepped;
    }

    Length stepRiseAhead(ref const CharacterConfig character, ref const Graph graph, CharacterInput input) const {
        Vec3!float level = input.movement.rejectAlong(up);
        float length = level.magnitude;
        if (input.mode != MovementMode.walk || length == 0) {
            return Length(0);
        } else {
            Vec3!float ahead = level.scaled((character.radius + character.skin).value / length).minus(up.scaled((character.halfHeight - character.radius).value));
            BlockProbe probe = BlockProbe(up);
            visitCells(graph, Position(position.node, position.local * Motion!float.shift(ahead)), Length(0), probe);
            if (probe.block.exists) {
                return probe.block.value.heightOf(character.stepHeight) + character.skin;
            } else {
                return Length(0);
            }
        }
    }

    Speed speedBound(ref const CharacterConfig character, MovementMode mode, Time dt) const {
        if (mode == MovementMode.fly) {
            return character.flySpeed;
        } else if (mode == MovementMode.walk) {
            return Speed(velocity.magnitude) + character.walkSpeed + character.jumpSpeed + character.gravity * dt;
        } else {
            return character.noclipSpeed;
        }
    }

    Vec3!float noclipStep(ref const CharacterConfig character, CharacterInput input, Time dt) {
        velocity = input.movement.cappedTo(MAX_INPUT_LENGTH).scaled(character.noclipSpeed.value);
        footing = Footing.airborne;
        return velocity.scaled(dt.value);
    }

    Vec3!float flyStep(ref const Mover mover, Vec3!float at, CharacterInput input, Time dt) {
        Vec3!float flyVelocity = input.movement.cappedTo(MAX_INPUT_LENGTH).scaled(mover.character.flySpeed.value);
        Slide moved = mover.slide(at, flyVelocity.scaled(dt.value), flyVelocity, SlideKind.move, PlaneSet.init);
        velocity = moved.velocity;
        footing = Footing.airborne;
        return moved.position;
    }

    Vec3!float walkStep(ref const Mover mover, Vec3!float at, CharacterInput input, Time dt) {
        Vec3!float wish = input.movement.cappedTo(MAX_INPUT_LENGTH).rejectAlong(mover.up);
        if (isOnGround && input.jump == Jump.pressed) {
            velocity = alongGround(velocity, groundNormal).plus(mover.up.scaled(mover.character.jumpSpeed.value));
            footing = Footing.airborne;
            return unsupportedMove(mover, at, wish, dt);
        } else if (isOnGround) {
            return groundMove(mover, at, alongGround(wish.scaled(mover.character.walkSpeed.value), groundNormal), dt);
        } else {
            return unsupportedMove(mover, at, wish, dt);
        }
    }

    Vec3!float steered(ref const Mover mover, Vec3!float wish, Time dt) const {
        Vec3!float across = velocity.rejectAlong(mover.up);
        Vec3!float pushed = across.plus(wish.scaled((mover.character.steering * dt).value));
        return velocity.minus(across).plus(pushed.cappedTo(higherOf(across.magnitude, mover.character.walkSpeed.value)));
    }

    Vec3!float groundMove(ref const Mover mover, Vec3!float at, Vec3!float walking, Time dt) {
        float decay = expf(-(mover.character.walkResponse * dt).value);
        Vec3!float lag = alongGround(velocity, groundNormal).minus(walking);
        Vec3!float reached = walking.plus(lag.scaled(decay));
        Vec3!float displacement = walking.scaled(dt.value).plus(lag.scaled((Ratio(1.0f - decay) / mover.character.walkResponse).value));
        PlaneSet ground;
        ground.add(ContactPlane(groundNormal, 0));
        Slide moved = mover.steppedOver(at, displacement, reached, mover.slide(at, displacement, reached, SlideKind.move, ground));
        velocity = moved.velocity;
        if (moved.isClimbing) {
            return moved.position;
        } else {
            Slide probe = mover.settle(moved.position, mover.character.skin);
            if (probe.hasLanded) {
                footing = Footing.grounded;
                groundNormal = probe.groundNormal;
                return probe.position;
            } else {
                footing = Footing.airborne;
                return moved.position;
            }
        }
    }

    Vec3!float unsupportedMove(ref const Mover mover, Vec3!float at, Vec3!float wish, Time dt) {
        velocity = steered(mover, wish, dt);
        Vec3!float fallen = velocity.minus(pull.scaled((mover.character.gravity * dt).value));
        Vec3!float displacement = velocity.plus(fallen).scaled(0.5f * dt.value);
        Slide moved = mover.slide(at, displacement, fallen, SlideKind.move, PlaneSet.init);
        velocity = moved.velocity;
        footing = Footing.airborne;
        if (moved.hasLanded) {
            footing = Footing.grounded;
            groundNormal = moved.groundNormal;
        }
        return moved.position;
    }
}

Position movedBy(ref const Graph graph, Position start, Vec3!float klein) {
    float length = klein.magnitude;
    if (length == 0) {
        return start;
    } else {
        Motion!float step = Motion!float.shift(klein.scaled(atanhf(length) / length));
        return graph.normalized(Position(start.node, (start.local * step).orthonormalized()));
    }
}

Vec3!float turnedToward(Vec3!float from, Vec3!float to, float most) {
    float angle = acosf(clamped(from.dot(to), -1.0f, 1.0f));
    if (angle <= most) {
        return to;
    } else {
        Vec3!float axis = from.cross(to);
        if (axis.magnitude == 0) {
            axis = from.cross(perpendicularTo(from));
        }
        Vec3!float side = axis.scaled(1.0f / axis.magnitude).cross(from);
        Vec3!float rotated = from.scaled(cosf(most)).plus(side.scaled(sinf(most)));
        return rotated.scaled(1.0f / rotated.magnitude);
    }
}

Vec3!float rotatedBetween(Vec3!float v, Vec3!float from, Vec3!float to) {
    Vec3!float axis = from.cross(to);
    float sine = axis.magnitude;
    if (sine == 0) {
        return v;
    } else {
        Vec3!float unitAxis = axis.scaled(1.0f / sine);
        float cosine = from.dot(to);
        return v.scaled(cosine).plus(unitAxis.cross(v).scaled(sine)).plus(unitAxis.scaled(unitAxis.dot(v) * (1.0f - cosine)));
    }
}

Vec3!float perpendicularTo(Vec3!float direction) {
    if (fabsf(direction.x) < fabsf(direction.y)) {
        return Vec3!float(1, 0, 0);
    } else {
        return Vec3!float(0, 1, 0);
    }
}

Vec3!float alongGround(Vec3!float wish, Vec3!float normal) {
    return wish.minus(normal.scaled(wish.dot(normal)));
}

struct Mover {
    const(Features)* features;
    Capsule capsule;
    CharacterConfig character;
    Vec3!float up;
    Length stepRise;

    static Mover make(ref const CharacterConfig character, ref const Features features, Vec3!float up, Length stepRise) {
        return Mover(&features, Capsule(up, character.radius.value, character.halfHeight.value, character.skin.value), character, up, stepRise);
    }

    Slide settle(Vec3!float start, Length distance) const {
        return slide(start, up.negated.scaled(distance.value), ZERO_VECTOR, SlideKind.settle, PlaneSet.init);
    }

    Slide steppedOver(Vec3!float start, Vec3!float displacement, Vec3!float velocity, Slide walked) const {
        float length = displacement.magnitude;
        if (!walked.isObstructed || stepRise.value == 0 || length == 0 || !isStepClear(start, displacement, walked)) {
            return walked;
        } else {
            Slide raised = slide(start, up.scaled(length), ZERO_VECTOR, SlideKind.move, PlaneSet.init);
            Slide across = slide(raised.position, displacement, velocity, SlideKind.move, PlaneSet.init);
            Slide lowered = settle(across.position, Length(raised.position.minus(start).dot(up)) + character.skin);
            if (lowered.hasLanded && lowered.position.minus(walked.position).dot(up) > character.skin.value) {
                return Slide(lowered.position, across.velocity, lowered.groundNormal, Flags!SlideMark.of(SlideMark.landed));
            } else {
                return Slide(across.position, velocity, ZERO_VECTOR, Flags!SlideMark.of(SlideMark.climbing));
            }
        }
    }

    bool isStepClear(Vec3!float start, Vec3!float displacement, ref const Slide walked) const {
        float length = displacement.magnitude;
        Vec3!float reach = displacement.scaled(higherOf(length, (character.radius + character.skin).value) / length);
        Slide raised = slide(start, up.scaled(stepRise.value), ZERO_VECTOR, SlideKind.move, PlaneSet.init);
        Slide across = slide(raised.position, reach, ZERO_VECTOR, SlideKind.move, PlaneSet.init);
        Slide lowered = settle(across.position, Length(raised.position.minus(start).dot(up)) + character.skin);
        return lowered.hasLanded && lowered.position.minus(walked.position).dot(up) > character.skin.value && lowered.position.minus(start).dot(reach) > walked.position.minus(start).dot(reach);
    }

    Slide slide(Vec3!float start, Vec3!float displacement, Vec3!float velocity, SlideKind kind, PlaneSet planes) const {
        return slideFrom(Slide(start, velocity), planes, clipToPlanes(planes.slice(), displacement, SkinRule.restore), kind, MAX_CONTACT_PLANES);
    }

    Slide slideFrom(Slide current, PlaneSet planes, Vec3!float remaining, SlideKind kind, uint contactsLeft) const {
        if (contactsLeft == 0) {
            return current;
        } else {
            Sweep sweep = Sweep.fromCapsule(*features, capsule, current.position, remaining, planes.slice());
            Slide moved = current;
            moved.position = current.position.plus(sweep.displacement);
            if (sweep.contact.exists) {
                return slideAfterContact(moved, planes, remaining, kind, sweep, contactsLeft - 1);
            } else {
                return moved;
            }
        }
    }

    Slide slideAfterContact(Slide current, PlaneSet planes, Vec3!float remaining, SlideKind kind, ref const Sweep sweep, uint contactsLeft) const {
        Vec3!float shortened = remaining.scaled(1.0f - sweep.displacement.magnitude / remaining.magnitude);
        Slide contacted = current;
        PlaneSet clipping = planes;
        Contact contact = sweep.contact.value;
        clipping.add(ContactPlane(contact.normal, character.skin.value - contact.gap));
        Vec3!float rest = shortened;
        if (shortened.dot(up) < 0 && contact.rank == SectionRank.lowest && contact.normal.dot(up) >= character.minSupportCosine) {
            contacted.marks.set(SlideMark.landed);
            contacted.groundNormal = contact.normal;
            contacted.velocity = clipToPlanes(clipping.slice(), current.velocity.rejectAlong(up), SkinRule.ignore);
            rest = landedRemainder(shortened, kind);
        } else {
            if (contact.normal.dot(up) < character.minSupportCosine) {
                contacted.marks.set(SlideMark.obstructed);
            }
            contacted.velocity = clipToPlanes(clipping.slice(), current.velocity, SkinRule.ignore);
        }
        return slideFrom(contacted, clipping, clipToPlanes(clipping.slice(), rest, SkinRule.restore), kind, contactsLeft);
    }

    Vec3!float landedRemainder(Vec3!float remaining, SlideKind kind) const {
        if (kind == SlideKind.settle) {
            return ZERO_VECTOR;
        } else {
            return remaining.rejectAlong(up);
        }
    }
}

struct PlaneSet {
    ContactPlane[MAX_SLIDE_PLANES] planes;
    uint count;

    const(ContactPlane)[] slice() const {
        return planes[0 .. count];
    }

    size_t mergeIndex(ContactPlane plane) const {
        size_t index = 0;
        while (index < count && !isSameDirection(planes[index].normal, plane.normal)) {
            index += 1;
        }
        return index;
    }

    void add(ContactPlane plane) {
        size_t index = mergeIndex(plane);
        if (index < count) {
            planes[index] = ContactPlane(plane.normal, higherOf(planes[index].separation, plane.separation));
        } else if (count < MAX_SLIDE_PLANES) {
            planes[count] = plane;
            count += 1;
        }
    }
}

struct Slide {
    Vec3!float position = Vec3!float(0, 0, 0);
    Vec3!float velocity = Vec3!float(0, 0, 0);
    Vec3!float groundNormal = Vec3!float(0, 0, 0);
    Flags!SlideMark marks;

    bool hasLanded() const {
        return marks.has(SlideMark.landed);
    }

    bool isObstructed() const {
        return marks.has(SlideMark.obstructed);
    }

    bool isClimbing() const {
        return marks.has(SlideMark.climbing);
    }
}

float target(ContactPlane plane, SkinRule skin) {
    if (skin == SkinRule.restore) {
        return plane.separation;
    } else {
        return 0;
    }
}

bool isSatisfyingPlanes(const(ContactPlane)[] planes, Vec3!float v, SkinRule skin, size_t skipA, size_t skipB) {
    size_t k = 0;
    while (k < planes.length && (k == skipA || k == skipB || !(v.dot(planes[k].normal) < target(planes[k], skin)))) {
        k += 1;
    }
    return k == planes.length;
}

Vec3!float planeCandidate(ContactPlane plane, Vec3!float v, SkinRule skin) {
    return v.projectedOntoPlane(plane.normal, plane.normal, target(plane, skin));
}

bool isPlaneClip(const(ContactPlane)[] planes, Vec3!float v, SkinRule skin, size_t i) {
    return v.dot(planes[i].normal) < target(planes[i], skin) && isSatisfyingPlanes(planes, planeCandidate(planes[i], v, skin), skin, i, i);
}

float creaseSine(const(ContactPlane)[] planes, size_t i, size_t j) {
    return planes[i].normal.cross(planes[j].normal).magnitude;
}

Vec3!float creaseCandidate(const(ContactPlane)[] planes, Vec3!float v, SkinRule skin, size_t i, size_t j) {
    Vec3!float crease = planes[i].normal.cross(planes[j].normal);
    float sine = crease.magnitude;
    Vec3!float line = crease.scaled(1.0f / sine);
    float cosine = planes[i].normal.dot(planes[j].normal);
    float determinant = sine * sine;
    float targetI = target(planes[i], skin);
    float targetJ = target(planes[j], skin);
    float alongI = (targetI - cosine * targetJ) / determinant;
    float alongJ = (targetJ - cosine * targetI) / determinant;
    return line.scaled(v.dot(line)).plus(planes[i].normal.scaled(alongI).plus(planes[j].normal.scaled(alongJ)));
}

bool isCreaseClip(const(ContactPlane)[] planes, Vec3!float v, SkinRule skin, size_t i, size_t j) {
    return j > i && creaseSine(planes, i, j) >= MIN_CREASE_SINE && isSatisfyingPlanes(planes, creaseCandidate(planes, v, skin, i, j), skin, i, j);
}

Maybe!(Vec3!float) clipToCrease(const(ContactPlane)[] planes, Vec3!float v, SkinRule skin) {
    size_t n = planes.length;
    size_t pair = 0;
    while (pair < n * n && !isCreaseClip(planes, v, skin, pair / n, pair % n)) {
        pair += 1;
    }
    if (pair < n * n) {
        return Maybe!(Vec3!float).of(creaseCandidate(planes, v, skin, pair / n, pair % n));
    } else {
        return Maybe!(Vec3!float).init;
    }
}

Maybe!(Vec3!float) clipToPlane(const(ContactPlane)[] planes, Vec3!float v, SkinRule skin) {
    size_t index = 0;
    while (index < planes.length && !isPlaneClip(planes, v, skin, index)) {
        index += 1;
    }
    if (index < planes.length) {
        return Maybe!(Vec3!float).of(planeCandidate(planes[index], v, skin));
    } else {
        return clipToCrease(planes, v, skin);
    }
}

Vec3!float clipToPlanes(const(ContactPlane)[] planes, Vec3!float v, SkinRule skin) {
    if (isSatisfyingPlanes(planes, v, skin, planes.length, planes.length)) {
        return v;
    } else {
        Maybe!(Vec3!float) clip = clipToPlane(planes, v, skin);
        if (clip.exists) {
            return clip.value;
        } else if (skin == SkinRule.restore) {
            return clipToPlanes(planes, v, SkinRule.ignore);
        } else {
            return ZERO_VECTOR;
        }
    }
}
