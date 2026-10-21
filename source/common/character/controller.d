module common.character.controller;

import core.stdc.math : acosf, atanhf, ceilf, cosf, expf, fabsf, sinf;
import base.numbers : clamped, higherOf;
import base.units : Length, Ratio, Speed, Time;
import base.vector3 : ZERO_VECTOR, cappedTo, cross, dot, magnitude, minus, negated, plus, projectedOntoPlane, rejectAlong, scaled;
import common.character.features : BlockProbe, Features, visitCells;
import common.character.sweep : Capsule, ContactPlane, MIN_CREASE_SINE, Sweep, isSameDirection;
import common.graph : Graph;
import common.position : Position;
import common.settings : CharacterConfig;
import common.worldgen.sky : Gravity, gravityAt;
import geometry.lorentz : Motion;

enum uint MAX_CONTACT_PLANES = 5;
enum uint MAX_SLIDE_PLANES = MAX_CONTACT_PLANES + 1;
enum float MAX_INPUT_LENGTH = 1.0f;
enum float TEST_TOLERANCE = 1e-5f;

enum MovementMode : ubyte {
    walk,
    fly,
    noclip,
}

struct CharacterInput {
    float[3] movement = [0, 0, 0];
    MovementMode mode;
    bool isJumping;
}

struct Stepped {
    Length traveled;
    bool isStalled;
}

Length regionReach(ref const CharacterConfig character) {
    return character.halfHeight + character.radius * 2.0f + character.skin * 2.0f;
}

struct CharacterState {
    Position position;
    float[3] velocity = [0, 0, 0];
    float[3] groundNormal = [0, 1, 0];
    float[3] up = [0, 1, 0];
    float[3] pull = [0, 1, 0];
    bool isOnGround;

    Stepped runStep(ref const CharacterConfig character, ref const Graph graph, CharacterInput input, Time step) {
        uint substeps = higherOf(cast(uint) ceilf((speedBound(character, input.mode, step) * step / character.radius).value), 1u);
        Time dt = step / cast(float) substeps;
        bool isJumpPending = input.isJumping;
        Stepped stepped;
        Features features;
        float[3] movement = input.movement;
        foreach (_; 0 .. substeps) {
            Gravity gravity = Gravity(up, 0);
            if (graph.nodeAt(graph.slotOf(position.node)).hasState) {
                gravity = graph.gravityAt(position);
            }
            float[3] turned = up;
            if (gravity.strength >= character.leastTurningGravity.value) {
                turned = turnedToward(up, gravity.up, (character.upTurnRate * dt).value);
            }
            float[3] pivot = turned.minus(up).scaled((character.halfHeight - character.radius).value);
            if (up.dot(gravity.up) < 0) {
                pivot = pivot.negated;
            }
            movement = rotatedBetween(movement, up, turned);
            float[3] halfway = turned.plus(turned.minus(up).scaled(0.5f));
            input.movement = rotatedBetween(movement, turned, halfway.scaled(1.0f / halfway.magnitude));
            up = turned;
            pull = gravity.up.scaled(gravity.strength);
            float[3] offset = ZERO_VECTOR;
            if (input.mode == MovementMode.noclip) {
                offset = noclipStep(character, input, dt);
            } else {
                features.collect(graph, position, regionReach(character));
                if (features.isLoaded) {
                    Mover mover = Mover.make(character, features, up, stepRiseAhead(character, graph, input));
                    float[3] pivoted = mover.slide(ZERO_VECTOR, pivot, ZERO_VECTOR, false, PlaneSet.init).position;
                    if (input.mode == MovementMode.fly) {
                        offset = flyStep(mover, pivoted, input, dt);
                    } else {
                        offset = walkStep(mover, pivoted, input, isJumpPending, dt);
                    }
                } else {
                    velocity = ZERO_VECTOR;
                    stepped.isStalled = true;
                }
            }
            isJumpPending = false;
            stepped.traveled = stepped.traveled + Length(offset.magnitude);
            position = graph.movedBy(position, offset);
        }
        features.release();
        return stepped;
    }

    Length stepRiseAhead(ref const CharacterConfig character, ref const Graph graph, CharacterInput input) const {
        float[3] level = input.movement.rejectAlong(up);
        float length = level.magnitude;
        if (input.mode != MovementMode.walk || length == 0) {
            return Length(0);
        } else {
            float[3] ahead = level.scaled((character.radius + character.skin).value / length).minus(up.scaled((character.halfHeight - character.radius).value));
            BlockProbe probe = BlockProbe(up);
            visitCells(graph, Position(position.node, position.local * Motion!float.shift(ahead)), Length(0), probe);
            if (probe.isFound) {
                return probe.block.heightOf(character.stepHeight) + character.skin;
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

    float[3] noclipStep(ref const CharacterConfig character, CharacterInput input, Time dt) {
        velocity = input.movement.cappedTo(MAX_INPUT_LENGTH).scaled(character.noclipSpeed.value);
        isOnGround = false;
        return velocity.scaled(dt.value);
    }

    float[3] flyStep(ref const Mover mover, float[3] at, CharacterInput input, Time dt) {
        float[3] flyVelocity = input.movement.cappedTo(MAX_INPUT_LENGTH).scaled(mover.character.flySpeed.value);
        Slide moved = mover.slide(at, flyVelocity.scaled(dt.value), flyVelocity, false, PlaneSet.init);
        velocity = moved.velocity;
        isOnGround = false;
        return moved.position;
    }

    float[3] walkStep(ref const Mover mover, float[3] at, CharacterInput input, bool isJumping, Time dt) {
        float[3] wish = input.movement.cappedTo(MAX_INPUT_LENGTH).rejectAlong(mover.up);
        if (isOnGround && isJumping) {
            velocity = alongGround(velocity, groundNormal).plus(mover.up.scaled(mover.character.jumpSpeed.value));
            isOnGround = false;
            return unsupportedMove(mover, at, wish, dt);
        } else if (isOnGround) {
            return groundMove(mover, at, alongGround(wish.scaled(mover.character.walkSpeed.value), groundNormal), dt);
        } else {
            return unsupportedMove(mover, at, wish, dt);
        }
    }

    float[3] steered(ref const Mover mover, float[3] wish, Time dt) const {
        float[3] across = velocity.rejectAlong(mover.up);
        float[3] pushed = across.plus(wish.scaled((mover.character.steering * dt).value));
        return velocity.minus(across).plus(pushed.cappedTo(higherOf(across.magnitude, mover.character.walkSpeed.value)));
    }

    float[3] groundMove(ref const Mover mover, float[3] at, float[3] walking, Time dt) {
        float decay = expf(-(mover.character.walkResponse * dt).value);
        float[3] lag = alongGround(velocity, groundNormal).minus(walking);
        float[3] reached = walking.plus(lag.scaled(decay));
        float[3] displacement = walking.scaled(dt.value).plus(lag.scaled((Ratio(1.0f - decay) / mover.character.walkResponse).value));
        PlaneSet ground;
        ground.add(ContactPlane(groundNormal, 0));
        Slide moved = mover.steppedOver(at, displacement, reached, mover.slide(at, displacement, reached, false, ground));
        velocity = moved.velocity;
        if (moved.isClimbing) {
            return moved.position;
        } else {
            Slide probe = mover.settle(moved.position, mover.character.skin);
            isOnGround = probe.hasLanded;
            if (probe.hasLanded) {
                groundNormal = probe.groundNormal;
                return probe.position;
            } else {
                return moved.position;
            }
        }
    }

    float[3] unsupportedMove(ref const Mover mover, float[3] at, float[3] wish, Time dt) {
        velocity = steered(mover, wish, dt);
        float[3] fallen = velocity.minus(pull.scaled((mover.character.gravity * dt).value));
        float[3] displacement = velocity.plus(fallen).scaled(0.5f * dt.value);
        Slide moved = mover.slide(at, displacement, fallen, false, PlaneSet.init);
        velocity = moved.velocity;
        isOnGround = moved.hasLanded;
        if (moved.hasLanded) {
            groundNormal = moved.groundNormal;
        }
        return moved.position;
    }
}

Position movedBy(ref const Graph graph, Position start, float[3] klein) {
    float length = klein.magnitude;
    if (length == 0) {
        return start;
    } else {
        Motion!float step = Motion!float.shift(klein.scaled(atanhf(length) / length));
        return graph.normalized(Position(start.node, (start.local * step).orthonormalized()));
    }
}

float[3] turnedToward(float[3] from, float[3] to, float most) {
    float angle = acosf(clamped(from.dot(to), -1.0f, 1.0f));
    if (angle <= most) {
        return to;
    } else {
        float[3] axis = from.cross(to);
        if (axis.magnitude == 0) {
            axis = from.cross(perpendicularTo(from));
        }
        float[3] side = axis.scaled(1.0f / axis.magnitude).cross(from);
        float[3] rotated = from.scaled(cosf(most)).plus(side.scaled(sinf(most)));
        return rotated.scaled(1.0f / rotated.magnitude);
    }
}

float[3] rotatedBetween(float[3] v, float[3] from, float[3] to) {
    float[3] axis = from.cross(to);
    float sine = axis.magnitude;
    if (sine == 0) {
        return v;
    } else {
        float[3] unitAxis = axis.scaled(1.0f / sine);
        float cosine = from.dot(to);
        return v.scaled(cosine).plus(unitAxis.cross(v).scaled(sine)).plus(unitAxis.scaled(unitAxis.dot(v) * (1.0f - cosine)));
    }
}

float[3] perpendicularTo(float[3] direction) {
    float[3] xAxis = [1, 0, 0];
    float[3] yAxis = [0, 1, 0];
    if (fabsf(direction[0]) < fabsf(direction[1])) {
        return xAxis;
    } else {
        return yAxis;
    }
}

float[3] alongGround(float[3] wish, float[3] normal) {
    return wish.minus(normal.scaled(wish.dot(normal)));
}

struct Mover {
    const(Features)* features;
    Capsule capsule;
    CharacterConfig character;
    float[3] up;
    Length stepRise;

    static Mover make(ref const CharacterConfig character, ref const Features features, float[3] up, Length stepRise) {
        return Mover(&features, Capsule(up, character.radius.value, character.halfHeight.value, character.skin.value), character, up, stepRise);
    }

    Slide settle(float[3] start, Length distance) const {
        return slide(start, up.negated.scaled(distance.value), ZERO_VECTOR, true, PlaneSet.init);
    }

    Slide steppedOver(float[3] start, float[3] displacement, float[3] velocity, Slide walked) const {
        float length = displacement.magnitude;
        if (!walked.isObstructed || stepRise.value == 0 || length == 0 || !isStepClear(start, displacement, walked)) {
            return walked;
        } else {
            Slide raised = slide(start, up.scaled(length), ZERO_VECTOR, false, PlaneSet.init);
            Slide across = slide(raised.position, displacement, velocity, false, PlaneSet.init);
            Slide lowered = settle(across.position, Length(raised.position.minus(start).dot(up)) + character.skin);
            if (lowered.hasLanded && lowered.position.minus(walked.position).dot(up) > character.skin.value) {
                return Slide(lowered.position, across.velocity, lowered.groundNormal, true, false, false);
            } else {
                return Slide(across.position, velocity, ZERO_VECTOR, false, false, true);
            }
        }
    }

    bool isStepClear(float[3] start, float[3] displacement, ref const Slide walked) const {
        float length = displacement.magnitude;
        float[3] reach = displacement.scaled(higherOf(length, (character.radius + character.skin).value) / length);
        Slide raised = slide(start, up.scaled(stepRise.value), ZERO_VECTOR, false, PlaneSet.init);
        Slide across = slide(raised.position, reach, ZERO_VECTOR, false, PlaneSet.init);
        Slide lowered = settle(across.position, Length(raised.position.minus(start).dot(up)) + character.skin);
        bool hasRisen = lowered.position.minus(walked.position).dot(up) > character.skin.value;
        return lowered.hasLanded && hasRisen && lowered.position.minus(start).dot(reach) > walked.position.minus(start).dot(reach);
    }

    Slide slide(float[3] start, float[3] displacement, float[3] velocity, bool isSettling, PlaneSet planes) const {
        return slideFrom(Slide(start, velocity), planes, clipToPlanes(planes.slice(), displacement, true), isSettling, MAX_CONTACT_PLANES);
    }

    Slide slideFrom(Slide current, PlaneSet planes, float[3] remaining, bool isSettling, uint contactsLeft) const {
        if (contactsLeft == 0) {
            return current;
        } else {
            Sweep sweep = Sweep.fromCapsule(*features, capsule, current.position, remaining, planes.slice());
            Slide moved = current;
            moved.position = current.position.plus(sweep.displacement);
            if (!sweep.hasContact) {
                return moved;
            } else {
                return slideAfterContact(moved, planes, remaining, isSettling, sweep, contactsLeft - 1);
            }
        }
    }

    Slide slideAfterContact(Slide current, PlaneSet planes, float[3] remaining, bool isSettling, ref const Sweep sweep, uint contactsLeft) const {
        float[3] shortened = remaining.scaled(1.0f - sweep.displacement.magnitude / remaining.magnitude);
        bool isLanding = shortened.dot(up) < 0 && sweep.isLowestSection && sweep.normal.dot(up) >= character.minSupportCosine;
        Slide contacted = current;
        PlaneSet clipping = planes;
        clipping.add(ContactPlane(sweep.normal, character.skin.value - sweep.gap));
        if (isLanding) {
            contacted.hasLanded = true;
            contacted.groundNormal = sweep.normal;
            contacted.velocity = clipToPlanes(clipping.slice(), current.velocity.rejectAlong(up), false);
        } else {
            contacted.isObstructed = contacted.isObstructed || sweep.normal.dot(up) < character.minSupportCosine;
            contacted.velocity = clipToPlanes(clipping.slice(), current.velocity, false);
        }
        return slideFrom(contacted, clipping, clipToPlanes(clipping.slice(), landedRemainder(shortened, isLanding, isSettling), true), isSettling, contactsLeft);
    }

    float[3] landedRemainder(float[3] remaining, bool isLanding, bool isSettling) const {
        if (isLanding && isSettling) {
            return ZERO_VECTOR;
        } else if (isLanding) {
            return remaining.rejectAlong(up);
        } else {
            return remaining;
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

struct Clip {
    float[3] motion;
    bool isFound;
}

struct Slide {
    float[3] position = [0, 0, 0];
    float[3] velocity = [0, 0, 0];
    float[3] groundNormal = [0, 0, 0];
    bool hasLanded;
    bool isObstructed;
    bool isClimbing;
}

float target(ContactPlane plane, bool isRestoringSkin) {
    if (isRestoringSkin) {
        return plane.separation;
    } else {
        return 0;
    }
}

bool isSatisfyingPlanes(const(ContactPlane)[] planes, float[3] v, bool isRestoringSkin, size_t skipA, size_t skipB) {
    size_t k = 0;
    while (k < planes.length && (k == skipA || k == skipB || !(v.dot(planes[k].normal) < target(planes[k], isRestoringSkin)))) {
        k += 1;
    }
    return k == planes.length;
}

float[3] planeCandidate(ContactPlane plane, float[3] v, bool isRestoringSkin) {
    return v.projectedOntoPlane(plane.normal, plane.normal, target(plane, isRestoringSkin));
}

bool isPlaneClip(const(ContactPlane)[] planes, float[3] v, bool isRestoringSkin, size_t i) {
    return v.dot(planes[i].normal) < target(planes[i], isRestoringSkin) && isSatisfyingPlanes(planes, planeCandidate(planes[i], v, isRestoringSkin), isRestoringSkin, i, i);
}

float creaseSine(const(ContactPlane)[] planes, size_t i, size_t j) {
    return planes[i].normal.cross(planes[j].normal).magnitude;
}

float[3] creaseCandidate(const(ContactPlane)[] planes, float[3] v, bool isRestoringSkin, size_t i, size_t j) {
    float[3] crease = planes[i].normal.cross(planes[j].normal);
    float sine = crease.magnitude;
    float[3] line = crease.scaled(1.0f / sine);
    float cosine = planes[i].normal.dot(planes[j].normal);
    float determinant = sine * sine;
    float targetI = target(planes[i], isRestoringSkin);
    float targetJ = target(planes[j], isRestoringSkin);
    float alongI = (targetI - cosine * targetJ) / determinant;
    float alongJ = (targetJ - cosine * targetI) / determinant;
    return line.scaled(v.dot(line)).plus(planes[i].normal.scaled(alongI).plus(planes[j].normal.scaled(alongJ)));
}

bool isCreaseClip(const(ContactPlane)[] planes, float[3] v, bool isRestoringSkin, size_t i, size_t j) {
    return j > i && creaseSine(planes, i, j) >= MIN_CREASE_SINE && isSatisfyingPlanes(planes, creaseCandidate(planes, v, isRestoringSkin, i, j), isRestoringSkin, i, j);
}

Clip clipToCrease(const(ContactPlane)[] planes, float[3] v, bool isRestoringSkin) {
    size_t n = planes.length;
    size_t pair = 0;
    while (pair < n * n && !isCreaseClip(planes, v, isRestoringSkin, pair / n, pair % n)) {
        pair += 1;
    }
    if (pair < n * n) {
        return Clip(creaseCandidate(planes, v, isRestoringSkin, pair / n, pair % n), true);
    } else {
        return Clip(ZERO_VECTOR, false);
    }
}

Clip clipToPlane(const(ContactPlane)[] planes, float[3] v, bool isRestoringSkin) {
    size_t index = 0;
    while (index < planes.length && !isPlaneClip(planes, v, isRestoringSkin, index)) {
        index += 1;
    }
    if (index < planes.length) {
        return Clip(planeCandidate(planes[index], v, isRestoringSkin), true);
    } else {
        return clipToCrease(planes, v, isRestoringSkin);
    }
}

float[3] clipToPlanes(const(ContactPlane)[] planes, float[3] v, bool isRestoringSkin) {
    if (isSatisfyingPlanes(planes, v, isRestoringSkin, planes.length, planes.length)) {
        return v;
    } else {
        Clip clip = clipToPlane(planes, v, isRestoringSkin);
        if (clip.isFound || !isRestoringSkin) {
            return clip.motion;
        } else {
            return clipToPlanes(planes, v, false);
        }
    }
}

unittest {
    float[3] floorNormal = [0, 1, 0];
    float[3] wallNormal = [-1, 0, 0];
    ContactPlane[2] planes = [
        ContactPlane(floorNormal, 0),
        ContactPlane(wallNormal, 0),
    ];
    float[3] intoCorner = [1, -0.5f, 1];
    float[3] clipped = clipToPlanes(planes, intoCorner, true);
    assert(clipped[0] > -TEST_TOLERANCE && clipped[0] < TEST_TOLERANCE);
    assert(clipped[1] > -TEST_TOLERANCE && clipped[1] < TEST_TOLERANCE);
    assert(clipped[2] > 1 - TEST_TOLERANCE);
    assert(clipped.magnitude <= intoCorner.magnitude);
}

unittest {
    float[3] slopeNormal = [-0.5f, 0.8660254f, 0];
    float[3] uphill = [1, 0, 0];
    float[3] downhill = [-1, 0, 0];
    float[3] across = [0, 0, 1];
    float cosine = slopeNormal[1];
    assert(alongGround(uphill, slopeNormal).magnitude > cosine - TEST_TOLERANCE && alongGround(uphill, slopeNormal).magnitude < cosine + TEST_TOLERANCE);
    assert(alongGround(uphill, slopeNormal)[1] > 0);
    assert(alongGround(downhill, slopeNormal).magnitude > cosine - TEST_TOLERANCE && alongGround(downhill, slopeNormal).magnitude < cosine + TEST_TOLERANCE);
    assert(alongGround(downhill, slopeNormal)[1] < 0);
    assert(alongGround(across, slopeNormal).magnitude > 1 - TEST_TOLERANCE);
}

unittest {
    float[3] wallNormal = [-1, 0, 0];
    float skinDeficit = 0.25f;
    ContactPlane[1] touching = [ContactPlane(wallNormal, skinDeficit)];
    float[3] along = [0, 0, 1];
    float[3] restored = clipToPlanes(touching, along, true);
    assert(restored.dot(wallNormal) >= skinDeficit);
    float[3] clippedVelocity = clipToPlanes(touching, along, false);
    assert(clippedVelocity[0] == along[0] && clippedVelocity[1] == along[1] && clippedVelocity[2] == along[2]);
}

unittest {
    float[3] a = [-1, 0, 0];
    float[3] b = [0, 0, -1];
    float[3] c = [0, -1, 0];
    ContactPlane[3] boxed = [
        ContactPlane(a, 0),
        ContactPlane(b, 0),
        ContactPlane(c, 0),
    ];
    float[3] intoAll = [1, 1, 1];
    assert(clipToPlanes(boxed, intoAll, true).magnitude == 0);
}

unittest {
    float[3] floorNormal = [0, 1, 0];
    float[3] ceilingNormal = [0, -1, 0];
    ContactPlane[2] squeezed = [
        ContactPlane(floorNormal, 0.01f),
        ContactPlane(ceilingNormal, 0.02f),
    ];
    float[3] alongSlot = [1, -0.1f, 0];
    float[3] clipped = clipToPlanes(squeezed, alongSlot, true);
    assert(clipped[0] > 1 - TEST_TOLERANCE);
    assert(clipped[1] > -TEST_TOLERANCE && clipped[1] < TEST_TOLERANCE);
}

unittest {
    float[3] first = [-1, 0, 0];
    float[3] nearlySame = [-1, 1e-5f, 0];
    PlaneSet set;
    set.add(ContactPlane(first, 0.5f));
    set.add(ContactPlane(nearlySame, 0.1f));
    assert(set.count == 1);
    assert(set.planes[0].separation == 0.5f);
}
