module common.character.controller;

import core.math : sqrt;
import core.stdc.math : asinhf, ceilf, expf;
import common.character.sweep : Sweep;
import common.collision.graph : Capsule, isRegionPopulated;
import common.graph : Graph, ROOT_NODE;
import common.math : MIsometry, MPoint, higherOf;
import common.position : Position;
import common.settings : CharacterConfig, SimConfig;
import common.vector3 : ZERO_VECTOR, cappedTo, cross, dot, magnitude, movedToward, negated, plus, projectedOntoPlane, rejectAlong, scaled;
import common.worldgen.generation : NodeState;

enum uint MAX_CONTACT_PLANES = 5;
enum uint MAX_SLIDE_PLANES = MAX_CONTACT_PLANES + 1;
enum float MIN_CREASE_SINE = 1e-3f;
enum float MAX_INPUT_LENGTH = 1.0f;
enum float UP_PROBE_DISTANCE = 0.1f;
enum float UP_PROBE_MIN_GAIN = 0.05f;
enum float TEST_TOLERANCE = 1e-5f;
enum ubyte TEST_DIMENSION = 12;

enum MovementMode : ubyte {
    walk,
    fly,
    noclip,
}

struct CharacterInput {
    float[3] movement = [0, 0, 0];
    MovementMode mode;
    bool isJumpHeld;
}

struct CharacterState {
    Position position;
    float[3] velocity = [0, 0, 0];
    float[3] groundNormal = [0, 1, 0];
    bool isOnGround;

    float runStep(ref const SimConfig simConfig, ref const Graph graph, CharacterInput input, float dtSeconds) {
        CharacterConfig cfg = simConfig.character;
        uint substeps = atLeastOne(cast(uint) ceilf(speedBound(cfg, input, dtSeconds) * dtSeconds / cfg.characterRadius));
        float dt = dtSeconds / substeps;
        float reach = cfg.characterHalfHeight + 2.0f * cfg.characterRadius + cfg.stepHeight + cfg.contactSkin;
        float traveled = 0;
        foreach (_; 0 .. substeps) {
            MIsometry!float before = position.local;
            if (input.mode == MovementMode.noclip) {
                noClipStep(cfg, input, dt);
            } else if (graph.isRegionPopulated(position, reach)) {
                Mover mover = Mover.make(cfg, graph, graph.relativeUp(position));
                if (input.mode == MovementMode.fly) {
                    flyStep(mover, input, dt);
                } else {
                    walkStep(mover, input, dt);
                }
            } else {
                velocity = ZERO_VECTOR;
            }
            position.local = position.local.renormalized();
            traveled += stepLength(before.inverse() * position.local);
            position = graph.normalized(position);
        }
        return traveled;
    }

    float speedBound(ref const CharacterConfig cfg, CharacterInput input, float dt) const {
        if (input.mode == MovementMode.fly) {
            return cfg.flyMovementSpeed;
        } else if (input.mode == MovementMode.walk && input.isJumpHeld) {
            return walkSpeedBound(cfg, dt) + cfg.jumpSpeed;
        } else if (input.mode == MovementMode.walk) {
            return walkSpeedBound(cfg, dt);
        } else {
            return cfg.noClipMovementSpeed;
        }
    }

    float walkSpeedBound(ref const CharacterConfig cfg, float dt) const {
        return velocity.magnitude + higherOf(cfg.groundAcceleration, cfg.airAcceleration + cfg.gravityAcceleration) * dt;
    }

    float takeoffSpeed(ref const CharacterConfig cfg, float verticalSpeed) const {
        if (isOnGround) {
            return cfg.jumpSpeed;
        } else {
            return verticalSpeed;
        }
    }

    void noClipStep(ref const CharacterConfig cfg, CharacterInput input, float dt) {
        velocity = input.movement.cappedTo(MAX_INPUT_LENGTH).scaled(cfg.noClipMovementSpeed);
        isOnGround = false;
        position.local = position.local * MIsometry!float.fromDisplacement(velocity.scaled(dt));
    }

    void flyStep(ref const Mover mover, CharacterInput input, float dt) {
        float[3] flyVelocity = input.movement.cappedTo(MAX_INPUT_LENGTH).scaled(mover.cfg.flyMovementSpeed);
        Slide moved = mover.slide(position, flyVelocity.scaled(dt), flyVelocity, Sliding.free, PlaneSet.init);
        position = moved.position;
        velocity = moved.velocity;
        isOnGround = false;
    }

    void walkStep(ref const Mover mover, CharacterInput input, float dt) {
        float[3] wish = input.movement.cappedTo(MAX_INPUT_LENGTH).rejectAlong(mover.up);
        float[3] targetVelocity = wish.scaled(mover.cfg.maxGroundSpeed);
        float[3] horizontalVelocity = velocity.rejectAlong(mover.up);
        float verticalSpeed = velocity.dot(mover.up);
        if (isOnGround && !input.isJumpHeld) {
            groundMove(mover, horizontalVelocity.movedToward(targetVelocity, mover.cfg.groundAcceleration * dt), dt);
        } else {
            airMove(mover, steered(horizontalVelocity, targetVelocity, wish, mover.cfg.airAcceleration * dt), takeoffSpeed(mover.cfg, verticalSpeed), dt);
        }
    }

    void groundMove(ref const Mover mover, float[3] groundVelocity, float dt) {
        float[3] displacement = groundVelocity.scaled(dt);
        PlaneSet ground;
        ground.add(ContactPlane(groundNormal, mover.up, 0));
        Slide chosen = mover.slideOrStep(position, displacement, groundVelocity, ground);
        Slide settled = mover.settle(chosen.position, mover.cfg.stepHeight);
        velocity = chosen.velocity.rejectAlong(mover.up);
        isOnGround = settled.hasLanded;
        if (settled.hasLanded) {
            position = settled.position;
            groundNormal = settled.groundNormal;
        } else {
            position = chosen.position;
        }
    }

    void airMove(ref const Mover mover, float[3] horizontalVelocity, float verticalSpeed, float dt) {
        float[3] startVelocity = horizontalVelocity.plus(mover.up.scaled(verticalSpeed));
        float[3] fallen = horizontalVelocity.plus(mover.up.scaled(verticalSpeed - mover.cfg.gravityAcceleration * dt));
        float[3] endVelocity = fallen.scaled(expf(-mover.cfg.airResistance * dt)).cappedTo(mover.cfg.speedCap);
        float[3] displacement = startVelocity.plus(endVelocity).scaled(0.5f * dt);
        Slide moved = mover.slide(position, displacement, endVelocity, Sliding.free, PlaneSet.init);
        position = moved.position;
        isOnGround = moved.hasLanded;
        if (moved.hasLanded) {
            velocity = moved.velocity.rejectAlong(mover.up);
            groundNormal = moved.groundNormal;
        } else {
            velocity = moved.velocity;
        }
    }
}

enum Sliding : ubyte {
    free,
    walking,
}

struct Mover {
    const(Graph)* graph;
    Capsule capsule;
    CharacterConfig cfg;
    float[3] up;
    float walkableUpDot;

    static Mover make(ref const CharacterConfig cfg, ref const Graph graph, float[3] up) {
        float slope = cfg.maxGroundSlope;
        return Mover(&graph, Capsule(up, cfg.characterRadius, cfg.characterHalfHeight, cfg.contactSkin), cfg, up, 1.0f / sqrt(slope * slope + 1.0f));
    }

    Slide slideOrStep(Position start, float[3] displacement, float[3] velocity, PlaneSet ground) const {
        Slide slid = slide(start, displacement, velocity, Sliding.walking, ground);
        if (slid.hasHitWall) {
            Step stepped = stepUp(start, displacement.plus(skinTowardWall(slid.wallNormal)), velocity, ground);
            if (stepped.isValid && horizontalProgress(start, stepped.slide.position, displacement) > horizontalProgress(start, slid.position, displacement)) {
                return stepped.slide;
            } else {
                return slid;
            }
        } else {
            return slid;
        }
    }

    Step stepUp(Position start, float[3] displacement, float[3] velocity, PlaneSet ground) const {
        Slide raised = slide(start, up.scaled(cfg.stepHeight), ZERO_VECTOR, Sliding.free, PlaneSet.init);
        float rise = verticalGain(start, raised.position);
        if (rise > 0) {
            Slide across = slide(raised.position, displacement, velocity, Sliding.walking, ground);
            Slide drop = settle(across.position, rise);
            if (drop.hasLanded) {
                Slide landed = across;
                landed.position = drop.position;
                landed.groundNormal = drop.groundNormal;
                return Step(landed, true);
            } else {
                return Step(Slide.init, false);
            }
        } else {
            return Step(Slide.init, false);
        }
    }

    float[3] skinTowardWall(float[3] wallNormal) const {
        float[3] inward = wallNormal.negated.rejectAlong(up);
        float length = inward.magnitude;
        if (length > 0) {
            return inward.scaled(cfg.contactSkin / length);
        } else {
            return ZERO_VECTOR;
        }
    }

    Slide settle(Position start, float distance) const {
        return slide(start, up.negated.scaled(distance), ZERO_VECTOR, Sliding.free, PlaneSet.init);
    }

    Slide slide(Position start, float[3] displacement, float[3] velocity, Sliding sliding, PlaneSet planes) const {
        return slideFrom(Slide(start, velocity), planes, clipToPlanes(planes.slice(), displacement, true), sliding, MAX_CONTACT_PLANES);
    }

    Slide slideFrom(Slide current, PlaneSet planes, float[3] remaining, Sliding sliding, uint contactsLeft) const {
        if (contactsLeft == 0) {
            return current;
        } else {
            Sweep sweep = Sweep.fromCapsule(*graph, capsule, current.position, remaining);
            Slide moved = current;
            moved.position.local = current.position.local * sweep.transform;
            if (!sweep.hasContact) {
                return moved;
            } else {
                return slideAfterContact(moved, planes, remaining, sliding, sweep, contactsLeft - 1);
            }
        }
    }

    Slide slideAfterContact(Slide current, PlaneSet planes, float[3] remaining, Sliding sliding, ref const Sweep sweep, uint contactsLeft) const {
        float[3] shortened = remaining.scaled(1.0f - sweep.displacement.magnitude / remaining.magnitude);
        bool isWalkableContact = isWalkable(sweep.normal);
        bool isDescending = shortened.dot(up) < 0;
        bool isLanding = isDescending && isSupporting(sweep);
        Slide contacted = current;
        if (isLanding) {
            contacted.hasLanded = true;
            contacted.groundNormal = supportNormal(sweep);
        }
        if (!isWalkableContact && !current.hasHitWall) {
            contacted.hasHitWall = true;
            contacted.wallNormal = sweep.normal;
        }
        PlaneSet clipping = planes;
        clipping.add(ContactPlane(sweep.normal, contactDirection(sweep.normal, isWalkableContact && (isDescending || sliding == Sliding.walking)), cfg.contactSkin - sweep.gap));
        contacted.velocity = clipToPlanes(clipping.slice(), current.velocity, false);
        return slideFrom(contacted, clipping, clipToPlanes(clipping.slice(), landedRemainder(shortened, isLanding), true), sliding, contactsLeft);
    }

    float[3] landedRemainder(float[3] remaining, bool isLanding) const {
        if (isLanding) {
            return remaining.rejectAlong(up);
        } else {
            return remaining;
        }
    }

    float[3] contactDirection(float[3] normal, bool isAlongUp) const {
        if (isAlongUp) {
            return up;
        } else {
            return normal;
        }
    }

    bool isWalkable(float[3] normal) const {
        return normal.dot(up) > walkableUpDot;
    }

    bool hasWalkableSurface(ref const Sweep sweep) const {
        uint surface = 0;
        while (surface < sweep.surfaceCount && !isWalkable(sweep.surfaces[surface])) {
            surface += 1;
        }
        return surface < sweep.surfaceCount;
    }

    bool isSupporting(ref const Sweep sweep) const {
        return sweep.isLowestSection && sweep.normal.dot(up) > 0 && hasWalkableSurface(sweep);
    }

    float[3] supportNormal(ref const Sweep sweep) const {
        float[3] result = sweep.surfaces[0];
        foreach (surface; sweep.surfaces[0 .. sweep.surfaceCount]) {
            if (surface.dot(up) > result.dot(up)) {
                result = surface;
            }
        }
        return result;
    }

    float verticalGain(Position start, Position end) const {
        MPoint!float moved = (start.local.inverse() * end.local) * MPoint!float.origin();
        return moved.vec.xyz().dot(up);
    }

    float horizontalProgress(Position start, Position end, float[3] displacement) const {
        MPoint!float moved = (start.local.inverse() * end.local) * MPoint!float.origin();
        float[3] horizontal = displacement.rejectAlong(up);
        float horizontalLength = horizontal.magnitude;
        if (horizontalLength > 0) {
            return moved.vec.xyz().rejectAlong(up).dot(horizontal) / horizontalLength;
        } else {
            return 0;
        }
    }
}

struct ContactPlane {
    float[3] normal;
    float[3] direction;
    float separation;
}

struct PlaneSet {
    ContactPlane[MAX_SLIDE_PLANES] planes;
    uint count;

    const(ContactPlane)[] slice() const {
        return planes[0 .. count];
    }

    bool isMergeable(size_t index, ContactPlane plane) const {
        return planes[index].normal.dot(plane.normal) > 0 && planes[index].normal.cross(plane.normal).magnitude < MIN_CREASE_SINE;
    }

    size_t mergeIndex(ContactPlane plane) const {
        size_t index = 0;
        while (index < count && !isMergeable(index, plane)) {
            index += 1;
        }
        return index;
    }

    void add(ContactPlane plane) {
        size_t index = mergeIndex(plane);
        if (index < count) {
            planes[index] = ContactPlane(plane.normal, plane.direction, higherOf(planes[index].separation, plane.separation));
        } else if (count < MAX_SLIDE_PLANES) {
            planes[count] = plane;
            count += 1;
        }
    }
}

struct Slide {
    Position position;
    float[3] velocity = [0, 0, 0];
    float[3] groundNormal = [0, 0, 0];
    float[3] wallNormal = [0, 0, 0];
    bool hasHitWall;
    bool hasLanded;
}

struct Step {
    Slide slide;
    bool isValid;
}

uint atLeastOne(uint count) {
    if (count < 1) {
        return 1;
    } else {
        return count;
    }
}

float[3] steered(float[3] velocity, float[3] target, float[3] wish, float maxStep) {
    if (wish.dot(wish) > 0) {
        return velocity.movedToward(target, maxStep);
    } else {
        return velocity;
    }
}

float stepLength(MIsometry!float step) {
    return asinhf((step * MPoint!float.origin()).vec.xyz().magnitude);
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
    return v.projectedOntoPlane(plane.normal, plane.direction, target(plane, isRestoringSkin));
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

float[3] clipToCrease(const(ContactPlane)[] planes, float[3] v, bool isRestoringSkin) {
    size_t n = planes.length;
    size_t pair = 0;
    while (pair < n * n && !isCreaseClip(planes, v, isRestoringSkin, pair / n, pair % n)) {
        pair += 1;
    }
    if (pair < n * n) {
        return creaseCandidate(planes, v, isRestoringSkin, pair / n, pair % n);
    } else {
        return ZERO_VECTOR;
    }
}

float[3] clipToPlane(const(ContactPlane)[] planes, float[3] v, bool isRestoringSkin) {
    size_t index = 0;
    while (index < planes.length && !isPlaneClip(planes, v, isRestoringSkin, index)) {
        index += 1;
    }
    if (index < planes.length) {
        return planeCandidate(planes[index], v, isRestoringSkin);
    } else {
        return clipToCrease(planes, v, isRestoringSkin);
    }
}

float[3] clipToPlanes(const(ContactPlane)[] planes, float[3] v, bool isRestoringSkin) {
    if (isSatisfyingPlanes(planes, v, isRestoringSkin, planes.length, planes.length)) {
        return v;
    } else {
        return clipToPlane(planes, v, isRestoringSkin);
    }
}

float[3] relativeUp(ref const Graph graph, Position position) {
    float[3] gradient = (position.local.inverse() * graph.nodeState(position.node).surface.scaledNormal).xyz();
    return gradient.scaled(1.0f / gradient.magnitude);
}

unittest {
    Graph graph = Graph.make(TEST_DIMENSION);
    graph.ensureNodeState(ROOT_NODE);
    Position start = Position.origin();
    float[3] up = graph.relativeUp(start);
    const(NodeState)* state = graph.nodeState(ROOT_NODE);
    float startDistance = state.surface.distanceTo(start.local * MPoint!float.origin());
    MIsometry!float raised = start.local * MIsometry!float.fromDisplacement(up.scaled(UP_PROBE_DISTANCE));
    float endDistance = state.surface.distanceTo(raised * MPoint!float.origin());
    assert(endDistance > startDistance + UP_PROBE_MIN_GAIN);
    graph.release();
}

unittest {
    float[3] up = [0, 1, 0];
    float[3] floorNormal = [0, 1, 0];
    float[3] wallNormal = [-1, 0, 0];
    ContactPlane[2] planes = [
        ContactPlane(floorNormal, up, 0),
        ContactPlane(wallNormal, wallNormal, 0),
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
    float[3] up = [0, 1, 0];
    ContactPlane[1] walkable = [ContactPlane(slopeNormal, up, 0)];
    float[3] uphill = [1, 0, 0];
    float[3] climbed = clipToPlanes(walkable, uphill, true);
    assert(climbed[0] == 1);
    assert(climbed[1] > 0);
    ContactPlane[1] wall = [ContactPlane(slopeNormal, slopeNormal, 0)];
    assert(clipToPlanes(wall, uphill, true).magnitude <= 1);
}

unittest {
    float[3] wallNormal = [-1, 0, 0];
    float skinDeficit = 0.25f;
    ContactPlane[1] touching = [ContactPlane(wallNormal, wallNormal, skinDeficit)];
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
        ContactPlane(a, a, 0),
        ContactPlane(b, b, 0),
        ContactPlane(c, c, 0),
    ];
    float[3] intoAll = [1, 1, 1];
    assert(clipToPlanes(boxed, intoAll, true).magnitude == 0);
}

unittest {
    float[3] first = [-1, 0, 0];
    float[3] nearlySame = [-1, 1e-5f, 0];
    PlaneSet set;
    set.add(ContactPlane(first, first, 0.5f));
    set.add(ContactPlane(nearlySame, nearlySame, 0.1f));
    assert(set.count == 1);
    assert(set.planes[0].separation == 0.5f);
}
