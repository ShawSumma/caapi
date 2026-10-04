module common.character_controller.controller;

import core.math : sqrt;
import core.stdc.math : asinhf, ceilf, expf;
import common.character_controller.collision : CollisionCheckingResult, CollisionContext;
import common.graph : Graph, ROOT_NODE;
import common.graph_collision : Capsule, isRegionPopulated;
import common.math : MIsometry, MPoint, limitToUnitLength, projectToPlane;
import common.proto : CharacterInput, MovementMode, Position;
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
    bool isOnGround;

    float runStep(const(SimConfig)* simConfig, const(Graph)* graph, CharacterInput input, float dtSeconds) {
        const(CharacterConfig)* cfg = &simConfig.character;
        immutable uint substeps = atLeastOne(cast(uint) ceilf(speedBound(cfg, input, dtSeconds) * dtSeconds / cfg.characterRadius));
        float dt = dtSeconds / substeps;
        float reach = cfg.characterHalfHeight + 2.0f * cfg.characterRadius + cfg.stepHeight + cfg.contactSkin;
        float traveled = 0;
        foreach (substep; 0 .. substeps) {
            MIsometry!float before = position.local;
            if (input.mode == MovementMode.noclip) {
                noClipStep(cfg, input, dt);
            } else if (isRegionPopulated(graph, position, reach)) {
                Mover mover = Mover.make(cfg, graph, graph.relativeUp(position));
                if (input.mode == MovementMode.fly) {
                    flyStep(&mover, input, dt);
                } else {
                    walkStep(&mover, input, dt);
                }
            } else {
                velocity = zero3();
            }
            position.local = position.local.renormalized();
            traveled += stepLength(before.inverse() * position.local);
            position = graph.normalized(position);
        }
        return traveled;
    }

    float speedBound(const(CharacterConfig)* cfg, CharacterInput input, float dt) const {
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

    float walkSpeedBound(const(CharacterConfig)* cfg, float dt) const {
        return velocity.magnitude3 + higherOf(cfg.groundAcceleration, cfg.airAcceleration + cfg.gravityAcceleration) * dt;
    }

    float takeoffSpeed(const(CharacterConfig)* cfg, float verticalSpeed) const {
        if (isOnGround) {
            return cfg.jumpSpeed;
        } else {
            return verticalSpeed;
        }
    }

    void noClipStep(const(CharacterConfig)* cfg, CharacterInput input, float dt) {
        velocity = limitToUnitLength(input.movement).scale3(cfg.noClipMovementSpeed);
        isOnGround = false;
        position.local = position.local * MIsometry!float.translationAlong(velocity.scale3(dt));
    }

    void flyStep(const(Mover)* mover, CharacterInput input, float dt) {
        float[3] flyVelocity = limitToUnitLength(input.movement).scale3(mover.cfg.flyMovementSpeed);
        PlaneSet none;
        Slide moved = mover.slide(position, flyVelocity.scale3(dt), flyVelocity, Sliding.free, none);
        position = moved.position;
        velocity = moved.velocity;
        isOnGround = false;
    }

    void walkStep(const(Mover)* mover, CharacterInput input, float dt) {
        const(CharacterConfig)* cfg = mover.cfg;
        float[3] wish = limitToUnitLength(input.movement).rejectAlong(mover.up);
        float[3] targetVelocity = wish.scale3(cfg.maxGroundSpeed);
        float[3] horizontalVelocity = velocity.rejectAlong(mover.up);
        float verticalSpeed = velocity.dot3(mover.up);
        if (isOnGround && !input.isJumpHeld) {
            groundMove(mover, horizontalVelocity.moveToward3(targetVelocity, cfg.groundAcceleration * dt), dt);
        } else {
            airMove(mover, steered(horizontalVelocity, targetVelocity, wish, cfg.airAcceleration * dt), takeoffSpeed(cfg, verticalSpeed), dt);
        }
    }

    void groundMove(const(Mover)* mover, float[3] groundVelocity, float dt) {
        float[3] displacement = groundVelocity.scale3(dt);
        Position start = position;
        PlaneSet ground;
        ground.add(ContactPlane(groundNormal, mover.up, 0));
        Slide chosen = mover.slideOrStep(start, displacement, groundVelocity, ground);
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

    void airMove(const(Mover)* mover, float[3] horizontalVelocity, float verticalSpeed, float dt) {
        const(CharacterConfig)* cfg = mover.cfg;
        float[3] startVelocity = horizontalVelocity.add3(mover.up.scale3(verticalSpeed));
        float[3] fallen = horizontalVelocity.add3(mover.up.scale3(verticalSpeed - cfg.gravityAcceleration * dt));
        float[3] endVelocity = fallen.scale3(expf(-cfg.airResistance * dt)).capMagnitude3(cfg.speedCap);
        float[3] displacement = startVelocity.add3(endVelocity).scale3(0.5f * dt);
        PlaneSet none;
        Slide moved = mover.slide(position, displacement, endVelocity, Sliding.free, none);
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
    CollisionContext collision;
    const(CharacterConfig)* cfg;
    float[3] up;
    float walkableUpDot;

    static Mover make(const(CharacterConfig)* cfg, const(Graph)* graph, float[3] up) {
        float slope = cfg.maxGroundSlope;
        Capsule capsule = Capsule(up, cfg.characterRadius, cfg.characterHalfHeight, cfg.contactSkin);
        return Mover(CollisionContext(graph, capsule), cfg, up, 1.0f / sqrt(slope * slope + 1.0f));
    }

    Slide slideOrStep(Position start, float[3] displacement, float[3] velocity, PlaneSet ground) const {
        Slide slid = slide(start, displacement, velocity, Sliding.walking, ground);
        if (slid.hasHitWall) {
            Step stepped = stepUp(start, displacement.add3(skinTowardWall(slid.wallNormal)), velocity, ground);
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
        PlaneSet none;
        Slide raised = slide(start, up.scale3(cfg.stepHeight), zero3(), Sliding.free, none);
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
        float[3] inward = wallNormal.neg3.rejectAlong(up);
        float length = inward.magnitude3;
        if (length > 0) {
            return inward.scale3(cfg.contactSkin / length);
        } else {
            return zero3();
        }
    }

    Slide settle(Position start, float distance) const {
        PlaneSet none;
        return slide(start, up.neg3.scale3(distance), zero3(), Sliding.free, none);
    }

    Slide slide(Position start, float[3] displacement, float[3] velocity, Sliding sliding, PlaneSet initialPlanes) const {
        Slide result;
        result.position = start;
        result.velocity = velocity;
        PlaneSet planes = initialPlanes;
        float[3] remaining = clipToPlanes(planes.slice(), displacement, true);
        foreach (contact; 0 .. MAX_CONTACT_PLANES) {
            CollisionCheckingResult hit = collision.check(result.position, remaining);
            result.position.local = result.position.local * hit.displacementTransform;
            if (!hit.hasCollision) {
                return result;
            } else {
                float length = remaining.magnitude3;
                remaining = remaining.scale3(1.0f - hit.displacementVector.magnitude3 / length);
                immutable bool isWalkableContact = isWalkable(hit.normal);
                immutable bool isDescending = remaining.dot3(up) < 0;
                if (isDescending && isSupporting(&hit)) {
                    result.hasLanded = true;
                    result.groundNormal = supportNormal(&hit);
                    remaining = remaining.rejectAlong(up);
                }
                if (!isWalkableContact && !result.hasHitWall) {
                    result.hasHitWall = true;
                    result.wallNormal = hit.normal;
                }
                planes.add(ContactPlane(hit.normal, contactDirection(hit.normal, isWalkableContact && (isDescending || sliding == Sliding.walking)), cfg.contactSkin - hit.gap));
                remaining = clipToPlanes(planes.slice(), remaining, true);
                result.velocity = clipToPlanes(planes.slice(), result.velocity, false);
            }
        }
        return result;
    }

    float[3] contactDirection(float[3] normal, bool isAlongUp) const {
        if (isAlongUp) {
            return up;
        } else {
            return normal;
        }
    }

    bool isWalkable(float[3] normal) const {
        return normal.dot3(up) > walkableUpDot;
    }

    bool hasWalkableSurface(const(CollisionCheckingResult)* hit) const {
        foreach (surface; hit.surfaces[0 .. hit.surfaceCount]) {
            if (isWalkable(surface)) {
                return true;
            }
        }
        return false;
    }

    bool isSupporting(const(CollisionCheckingResult)* hit) const {
        return hit.isLowestSection && hit.normal.dot3(up) > 0 && hasWalkableSurface(hit);
    }

    float[3] supportNormal(const(CollisionCheckingResult)* hit) const {
        float[3] result = hit.surfaces[0];
        foreach (surface; hit.surfaces[0 .. hit.surfaceCount]) {
            if (surface.dot3(up) > result.dot3(up)) {
                result = surface;
            }
        }
        return result;
    }

    float verticalGain(Position start, Position end) const {
        MPoint!float moved = (start.local.inverse() * end.local) * MPoint!float.origin();
        return moved.vec.xyz().dot3(up);
    }

    float horizontalProgress(Position start, Position end, float[3] displacement) const {
        MPoint!float moved = (start.local.inverse() * end.local) * MPoint!float.origin();
        float[3] horizontal = displacement.rejectAlong(up);
        float horizontalLength = horizontal.magnitude3;
        if (horizontalLength > 0) {
            return moved.vec.xyz().rejectAlong(up).dot3(horizontal) / horizontalLength;
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

    size_t mergeIndex(ContactPlane plane) const {
        foreach (i; 0 .. count) {
            if (planes[i].normal.dot3(plane.normal) > 0 && planes[i].normal.cross3(plane.normal).magnitude3 < MIN_CREASE_SINE) {
                return i;
            }
        }
        return count;
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

float higherOf(float kept, float candidate) {
    if (kept > candidate) {
        return kept;
    } else {
        return candidate;
    }
}

float[3] steered(float[3] velocity, float[3] target, float[3] wish, float maxStep) {
    if (wish.dot3(wish) > 0) {
        return velocity.moveToward3(target, maxStep);
    } else {
        return velocity;
    }
}

float stepLength(MIsometry!float step) {
    return asinhf((step * MPoint!float.origin()).vec.xyz().magnitude3);
}

float target(ContactPlane plane, bool isRestoringSkin) {
    if (isRestoringSkin) {
        return plane.separation;
    } else {
        return 0;
    }
}

bool isSatisfyingPlanes(const(ContactPlane)[] planes, float[3] v, bool isRestoringSkin, size_t skipA, size_t skipB) {
    foreach (k, plane; planes) {
        if (k != skipA && k != skipB && v.dot3(plane.normal) < target(plane, isRestoringSkin)) {
            return false;
        }
    }
    return true;
}

float[3] clipToPlanes(const(ContactPlane)[] planes, float[3] v, bool isRestoringSkin) {
    if (isSatisfyingPlanes(planes, v, isRestoringSkin, planes.length, planes.length)) {
        return v;
    } else {
        foreach (i, plane; planes) {
            if (v.dot3(plane.normal) < target(plane, isRestoringSkin)) {
                float[3] candidate = projectToPlane(v, plane.normal, plane.direction, target(plane, isRestoringSkin));
                if (isSatisfyingPlanes(planes, candidate, isRestoringSkin, i, i)) {
                    return candidate;
                }
            }
        }
        foreach (i; 0 .. planes.length) {
            foreach (j; i + 1 .. planes.length) {
                float[3] crease = planes[i].normal.cross3(planes[j].normal);
                float creaseSine = crease.magnitude3;
                if (creaseSine >= MIN_CREASE_SINE) {
                    float[3] line = crease.scale3(1.0f / creaseSine);
                    float cosine = planes[i].normal.dot3(planes[j].normal);
                    float determinant = creaseSine * creaseSine;
                    float targetI = target(planes[i], isRestoringSkin);
                    float targetJ = target(planes[j], isRestoringSkin);
                    float alongI = (targetI - cosine * targetJ) / determinant;
                    float alongJ = (targetJ - cosine * targetI) / determinant;
                    float[3] candidate = line.scale3(v.dot3(line)).add3(planes[i].normal.scale3(alongI).add3(planes[j].normal.scale3(alongJ)));
                    if (isSatisfyingPlanes(planes, candidate, isRestoringSkin, i, j)) {
                        return candidate;
                    }
                }
            }
        }
        return zero3();
    }
}

float[3] relativeUp(const(Graph)* graph, Position position) {
    float[3] gradient = (position.local.inverse() * graph.nodeState(position.node).surface.scaledNormal).xyz();
    return gradient.scale3(1.0f / gradient.magnitude3);
}

unittest {
    Graph graph = Graph.make(12);
    graph.ensureNodeState(ROOT_NODE);
    Position position = Position.origin();
    float[3] up = relativeUp(&graph, position);
    const(NodeState)* state = graph.nodeState(ROOT_NODE);
    float startDistance = state.surface.distanceTo(position.local * MPoint!float.origin());
    position.local = position.local * MIsometry!float.translationAlong(up.scale3(UP_PROBE_DISTANCE));
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
    assert(clipped.magnitude3 <= intoCorner.magnitude3);
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
    assert(clipToPlanes(wall, uphill, true).magnitude3 <= 1);
}

unittest {
    float[3] wallNormal = [-1, 0, 0];
    float skinDeficit = 0.25f;
    ContactPlane[1] touching = [ContactPlane(wallNormal, wallNormal, skinDeficit)];
    float[3] along = [0, 0, 1];
    float[3] restored = clipToPlanes(touching, along, true);
    assert(restored.dot3(wallNormal) >= skinDeficit);
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
    assert(clipToPlanes(boxed, intoAll, true).magnitude3 == 0);
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
