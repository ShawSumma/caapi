module common.character_controller.controller;

import core.math : sqrt;
import core.stdc.math : asinhf, ceilf, expf;
import common.character_controller.collision : CollisionCheckingResult, CollisionContext, checkCollision;
import common.graph : Graph, ROOT_NODE, createGraph;
import common.graph_collision : Capsule, regionPopulated;
import common.math : MIsometry, MPoint, limitToUnitLength, projectToPlane;
import common.proto : CharacterInput, MovementMode, Position, originPosition;
import common.sim_config : CharacterConfig, SimConfig;
import common.vector3 : add3, capMagnitude3, cross3, dot3, magnitude3, moveToward3, neg3, rejectAlong, scale3, zero3;
import common.worldgen.generation : NodeState;

enum uint MAX_CONTACT_PLANES = 5;
enum uint MAX_SLIDE_PLANES = MAX_CONTACT_PLANES + 1;
enum float MIN_CREASE_SINE = 1e-3f;
enum float UP_PROBE_DISTANCE = 0.1f;
enum float UP_PROBE_MIN_GAIN = 0.05f;
enum float TEST_TOLERANCE = 1e-5f;

struct CharacterState {
    Position position;
    float[3] velocity = [0, 0, 0];
    float[3] groundNormal = [0, 1, 0];
    bool onGround;
}

enum Sliding : ubyte {
    free,
    walking,
}

struct Mover {
    CollisionContext collision;
    const(CharacterConfig)* cfg;
    float[3] up;
    float walkableUpDot;
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

    void add(ContactPlane plane) {
        bool merged = false;
        foreach (i; 0 .. count) {
            if (!merged && dot3(planes[i].normal, plane.normal) > 0 && magnitude3(cross3(planes[i].normal, plane.normal)) < MIN_CREASE_SINE) {
                if (planes[i].separation > plane.separation) {
                    plane.separation = planes[i].separation;
                }
                planes[i] = plane;
                merged = true;
            }
        }
        if (!merged && count < MAX_SLIDE_PLANES) {
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
    bool hitWall;
    bool landed;
}

struct Step {
    Slide slide;
    bool valid;
}

float runCharacterStep(const(SimConfig)* simConfig, const(Graph)* graph, CharacterState* state, CharacterInput input, float dtSeconds) {
    const(CharacterConfig)* cfg = &simConfig.character;
    uint substeps = cast(uint) ceilf(speedBound(cfg, state, input, dtSeconds) * dtSeconds / cfg.characterRadius);
    if (substeps < 1) {
        substeps = 1;
    }
    float dt = dtSeconds / substeps;
    float reach = cfg.characterHalfHeight + 2.0f * cfg.characterRadius + cfg.stepHeight + cfg.contactSkin;
    float traveled = 0;
    foreach (substep; 0 .. substeps) {
        MIsometry!float before = state.position.local;
        if (input.mode == MovementMode.noclip) {
            noClipStep(cfg, state, input, dt);
        } else if (regionPopulated(graph, state.position.node, state.position.local, reach)) {
            Mover mover = createMover(cfg, graph, getRelativeUp(graph, state.position));
            if (input.mode == MovementMode.fly) {
                flyStep(&mover, state, input, dt);
            } else {
                walkStep(&mover, state, input, dt);
            }
        } else {
            state.velocity = zero3();
        }
        state.position.local = state.position.local.renormalized();
        traveled += stepLength(before.inverse() * state.position.local);
        state.position.node = graph.normalizeTransform(state.position.node, &state.position.local);
    }
    return traveled;
}

float speedBound(const(CharacterConfig)* cfg, const(CharacterState)* state, CharacterInput input, float dt) {
    float result = cfg.noClipMovementSpeed;
    if (input.mode == MovementMode.fly) {
        result = cfg.flyMovementSpeed;
    } else if (input.mode == MovementMode.walk) {
        float steering = cfg.groundAcceleration;
        if (cfg.airAcceleration + cfg.gravityAcceleration > steering) {
            steering = cfg.airAcceleration + cfg.gravityAcceleration;
        }
        result = magnitude3(state.velocity) + steering * dt;
        if (input.jump) {
            result += cfg.jumpSpeed;
        }
    }
    return result;
}

float stepLength(MIsometry!float step) {
    return asinhf(magnitude3((step * MPoint!float.origin()).vec.xyz()));
}

Mover createMover(const(CharacterConfig)* cfg, const(Graph)* graph, float[3] up) {
    float slope = cfg.maxGroundSlope;
    Capsule capsule = Capsule(up, cfg.characterRadius, cfg.characterHalfHeight, cfg.contactSkin);
    return Mover(CollisionContext(graph, capsule), cfg, up, 1.0f / sqrt(slope * slope + 1.0f));
}

void noClipStep(const(CharacterConfig)* cfg, CharacterState* state, CharacterInput input, float dt) {
    state.velocity = scale3(limitToUnitLength(input.movement), cfg.noClipMovementSpeed);
    state.onGround = false;
    state.position.local = state.position.local * MIsometry!float.translationAlong(scale3(state.velocity, dt));
}

void flyStep(const(Mover)* mover, CharacterState* state, CharacterInput input, float dt) {
    float[3] velocity = scale3(limitToUnitLength(input.movement), mover.cfg.flyMovementSpeed);
    PlaneSet none;
    Slide moved = slide(mover, state.position, scale3(velocity, dt), velocity, Sliding.free, none);
    state.position = moved.position;
    state.velocity = moved.velocity;
    state.onGround = false;
}

void walkStep(const(Mover)* mover, CharacterState* state, CharacterInput input, float dt) {
    const(CharacterConfig)* cfg = mover.cfg;
    float[3] wish = rejectAlong(limitToUnitLength(input.movement), mover.up);
    float[3] targetVelocity = scale3(wish, cfg.maxGroundSpeed);
    float[3] horizontalVelocity = rejectAlong(state.velocity, mover.up);
    float verticalSpeed = dot3(state.velocity, mover.up);
    if (state.onGround && !input.jump) {
        groundMove(mover, state, moveToward3(horizontalVelocity, targetVelocity, cfg.groundAcceleration * dt), dt);
    } else {
        if (state.onGround) {
            verticalSpeed = cfg.jumpSpeed;
        }
        if (dot3(wish, wish) > 0) {
            horizontalVelocity = moveToward3(horizontalVelocity, targetVelocity, cfg.airAcceleration * dt);
        }
        airMove(mover, state, horizontalVelocity, verticalSpeed, dt);
    }
}

void groundMove(const(Mover)* mover, CharacterState* state, float[3] velocity, float dt) {
    float[3] displacement = scale3(velocity, dt);
    Position start = state.position;
    PlaneSet ground;
    ground.add(ContactPlane(state.groundNormal, mover.up, 0));
    Slide chosen = slide(mover, start, displacement, velocity, Sliding.walking, ground);
    if (chosen.hitWall) {
        Step stepped = stepUp(mover, start, add3(displacement, skinTowardWall(mover, chosen.wallNormal)), velocity, ground);
        if (stepped.valid && horizontalProgress(mover, start, stepped.slide.position, displacement) > horizontalProgress(mover, start, chosen.position, displacement)) {
            chosen = stepped.slide;
        }
    }
    Slide settled = settle(mover, chosen.position, mover.cfg.stepHeight);
    state.position = chosen.position;
    state.velocity = rejectAlong(chosen.velocity, mover.up);
    state.onGround = settled.landed;
    if (settled.landed) {
        state.position = settled.position;
        state.groundNormal = settled.groundNormal;
    }
}

void airMove(const(Mover)* mover, CharacterState* state, float[3] horizontalVelocity, float verticalSpeed, float dt) {
    const(CharacterConfig)* cfg = mover.cfg;
    float[3] startVelocity = add3(horizontalVelocity, scale3(mover.up, verticalSpeed));
    float[3] fallen = add3(horizontalVelocity, scale3(mover.up, verticalSpeed - cfg.gravityAcceleration * dt));
    float[3] endVelocity = capMagnitude3(scale3(fallen, expf(-cfg.airResistance * dt)), cfg.speedCap);
    float[3] displacement = scale3(add3(startVelocity, endVelocity), 0.5f * dt);
    PlaneSet none;
    Slide moved = slide(mover, state.position, displacement, endVelocity, Sliding.free, none);
    state.position = moved.position;
    state.velocity = moved.velocity;
    state.onGround = moved.landed;
    if (moved.landed) {
        state.velocity = rejectAlong(moved.velocity, mover.up);
        state.groundNormal = moved.groundNormal;
    }
}

Step stepUp(const(Mover)* mover, Position start, float[3] displacement, float[3] velocity, PlaneSet ground) {
    Step result;
    PlaneSet none;
    Slide raised = slide(mover, start, scale3(mover.up, mover.cfg.stepHeight), zero3(), Sliding.free, none);
    float rise = verticalGain(mover, start, raised.position);
    if (rise > 0) {
        Slide across = slide(mover, raised.position, displacement, velocity, Sliding.walking, ground);
        Slide drop = settle(mover, across.position, rise);
        if (drop.landed) {
            result.slide = across;
            result.slide.position = drop.position;
            result.slide.groundNormal = drop.groundNormal;
            result.valid = true;
        }
    }
    return result;
}

float[3] skinTowardWall(const(Mover)* mover, float[3] wallNormal) {
    float[3] inward = rejectAlong(neg3(wallNormal), mover.up);
    float length = magnitude3(inward);
    float[3] result = zero3();
    if (length > 0) {
        result = scale3(inward, mover.cfg.contactSkin / length);
    }
    return result;
}

Slide settle(const(Mover)* mover, Position start, float distance) {
    PlaneSet none;
    return slide(mover, start, scale3(neg3(mover.up), distance), zero3(), Sliding.free, none);
}

Slide slide(const(Mover)* mover, Position start, float[3] displacement, float[3] velocity, Sliding sliding, PlaneSet planes) {
    Slide result;
    result.position = start;
    result.velocity = velocity;
    float[3] remaining = clipToPlanes(planes.slice(), displacement, true);
    uint contacts = 0;
    bool moving = true;
    while (moving && contacts < MAX_CONTACT_PLANES) {
        CollisionCheckingResult collision = checkCollision(&mover.collision, result.position, remaining);
        result.position.local = result.position.local * collision.displacementTransform;
        if (!collision.hasCollision) {
            moving = false;
        } else {
            float length = magnitude3(remaining);
            remaining = scale3(remaining, 1.0f - magnitude3(collision.displacementVector) / length);
            bool walkable = isWalkable(mover, collision.normal);
            bool descending = dot3(remaining, mover.up) < 0;
            if (descending && supports(mover, &collision)) {
                result.landed = true;
                result.groundNormal = supportNormal(mover, &collision);
                remaining = rejectAlong(remaining, mover.up);
            }
            if (!walkable && !result.hitWall) {
                result.hitWall = true;
                result.wallNormal = collision.normal;
            }
            float[3] direction = collision.normal;
            if (walkable && (descending || sliding == Sliding.walking)) {
                direction = mover.up;
            }
            planes.add(ContactPlane(collision.normal, direction, mover.cfg.contactSkin - collision.gap));
            contacts += 1;
            remaining = clipToPlanes(planes.slice(), remaining, true);
            result.velocity = clipToPlanes(planes.slice(), result.velocity, false);
        }
    }
    return result;
}

bool isWalkable(const(Mover)* mover, float[3] normal) {
    return dot3(normal, mover.up) > mover.walkableUpDot;
}

bool supports(const(Mover)* mover, const(CollisionCheckingResult)* collision) {
    bool walkableSurface = false;
    foreach (surface; collision.surfaces[0 .. collision.surfaceCount]) {
        if (isWalkable(mover, surface)) {
            walkableSurface = true;
        }
    }
    return collision.lowestSection && dot3(collision.normal, mover.up) > 0 && walkableSurface;
}

float[3] supportNormal(const(Mover)* mover, const(CollisionCheckingResult)* collision) {
    float[3] result = collision.surfaces[0];
    foreach (surface; collision.surfaces[0 .. collision.surfaceCount]) {
        if (dot3(surface, mover.up) > dot3(result, mover.up)) {
            result = surface;
        }
    }
    return result;
}

float target(ContactPlane plane, bool restoreSkin) {
    float result = 0;
    if (restoreSkin) {
        result = plane.separation;
    }
    return result;
}

bool satisfiesPlanes(const(ContactPlane)[] planes, float[3] v, bool restoreSkin, size_t skipA, size_t skipB) {
    bool result = true;
    foreach (k, plane; planes) {
        if (k != skipA && k != skipB && dot3(v, plane.normal) < target(plane, restoreSkin)) {
            result = false;
        }
    }
    return result;
}

float[3] clipToPlanes(const(ContactPlane)[] planes, float[3] v, bool restoreSkin) {
    float[3] result = v;
    bool found = satisfiesPlanes(planes, v, restoreSkin, planes.length, planes.length);
    foreach (i, plane; planes) {
        if (!found && dot3(v, plane.normal) < target(plane, restoreSkin)) {
            float[3] candidate = projectToPlane(v, plane.normal, plane.direction, target(plane, restoreSkin));
            if (satisfiesPlanes(planes, candidate, restoreSkin, i, i)) {
                result = candidate;
                found = true;
            }
        }
    }
    foreach (i; 0 .. planes.length) {
        foreach (j; i + 1 .. planes.length) {
            float[3] crease = cross3(planes[i].normal, planes[j].normal);
            float creaseSine = magnitude3(crease);
            if (!found && creaseSine >= MIN_CREASE_SINE) {
                float[3] line = scale3(crease, 1.0f / creaseSine);
                float cosine = dot3(planes[i].normal, planes[j].normal);
                float determinant = creaseSine * creaseSine;
                float targetI = target(planes[i], restoreSkin);
                float targetJ = target(planes[j], restoreSkin);
                float alongI = (targetI - cosine * targetJ) / determinant;
                float alongJ = (targetJ - cosine * targetI) / determinant;
                float[3] candidate = add3(scale3(line, dot3(v, line)), add3(scale3(planes[i].normal, alongI), scale3(planes[j].normal, alongJ)));
                if (satisfiesPlanes(planes, candidate, restoreSkin, i, j)) {
                    result = candidate;
                    found = true;
                }
            }
        }
    }
    if (!found) {
        result = zero3();
    }
    return result;
}

float verticalGain(const(Mover)* mover, Position start, Position end) {
    MPoint!float moved = (start.local.inverse() * end.local) * MPoint!float.origin();
    return dot3(moved.vec.xyz(), mover.up);
}

float horizontalProgress(const(Mover)* mover, Position start, Position end, float[3] displacement) {
    MPoint!float moved = (start.local.inverse() * end.local) * MPoint!float.origin();
    float[3] horizontal = rejectAlong(displacement, mover.up);
    float horizontalLength = magnitude3(horizontal);
    float result = 0;
    if (horizontalLength > 0) {
        result = dot3(rejectAlong(moved.vec.xyz(), mover.up), horizontal) / horizontalLength;
    }
    return result;
}

float[3] getRelativeUp(const(Graph)* graph, Position position) {
    float[3] gradient = (position.local.inverse() * graph.nodeState(position.node).surface.scaledNormal).xyz();
    return scale3(gradient, 1.0f / magnitude3(gradient));
}

unittest {
    Graph graph = createGraph(12);
    graph.ensureNodeState(ROOT_NODE);
    Position position = originPosition();
    float[3] up = getRelativeUp(&graph, position);
    const(NodeState)* state = graph.nodeState(ROOT_NODE);
    float startDistance = state.surface.distanceTo(position.local * MPoint!float.origin());
    position.local = position.local * MIsometry!float.translationAlong(scale3(up, UP_PROBE_DISTANCE));
    float endDistance = state.surface.distanceTo(position.local * MPoint!float.origin());
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
    assert(magnitude3(clipped) <= magnitude3(intoCorner));
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
    assert(magnitude3(clipToPlanes(wall, uphill, true)) <= 1);
}

unittest {
    float[3] wallNormal = [-1, 0, 0];
    float skinDeficit = 0.25f;
    ContactPlane[1] touching = [ContactPlane(wallNormal, wallNormal, skinDeficit)];
    float[3] along = [0, 0, 1];
    float[3] restored = clipToPlanes(touching, along, true);
    assert(dot3(restored, wallNormal) >= skinDeficit);
    float[3] velocity = clipToPlanes(touching, along, false);
    assert(velocity[0] == along[0] && velocity[1] == along[1] && velocity[2] == along[2]);
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
    assert(magnitude3(clipToPlanes(boxed, intoAll, true)) == 0);
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
