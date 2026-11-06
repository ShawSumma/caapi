module client.game;

import core.stdc.math : acoshf, atan2f, atanhf, ceilf, coshf, fabs, fabsf, floorf, sinhf, sqrt, tanhf;
import base.array : Array;
import base.flags : Readiness;
import base.maybe : Maybe, MaybeIndex;
import base.numbers : higherOf, lowerOf;
import base.units : Acceleration, Angle, AngularSpeed, Length, Rate, Ratio, Speed, Time;
import base.vector3 : Vec3, ZERO_VECTOR, cross, dot, magnitude, minus, negated, plus, rejectAlong, scaled;
import client.arrivals : generateNow;
import client.camera : CAMERA_FORWARD, Camera;
import client.config : ClientConfig, pitchSign;
import client.streaming : Pacing;
import client.world : LocalWorld, Placement;
import common.character.controller : CharacterInput, CharacterState, Footing, Jump, MovementMode, Mover, Slide, Stepped, movedBy, perpendicularTo, regionReach;
import common.character.features : CellOverlap, CellRange, Features, LocalFrame, MaterialOverlap, RequiredChunks, gridPoint, isInsideGrid, visitCells;
import common.character.sweep : Capsule, sectionCenters;
import common.graph : Graph, NodeId;
import common.node : ChunkId, ChunkSlot, ChunkState, cellIndex;
import common.edits : BlockRecord, RecordKind;
import common.inventory : Inventory;
import common.raycast.graph : GraphCastHit;
import geometry.cube : Cell;
import common.material : FAMILY_SETS, MaterialSet, has, isEmpty, isPlant, joined, within;
import common.biology.air : ASH_GAS, AirMix, GAS_COUNT, GAS_MOLECULES, airOf;
import common.biology.kinetics : Route;
import common.biology.molecule : Molecule;
import common.biology.organism : Dose, Organism, STARTER_DOSES, starterGenome;
import common.biology.pocket : Binding;
import common.biology.breeding : crossed, expressionIn;
import common.biology.genome : Genome, MOST_GENES, enzymeGene;
import common.biology.kinetics : Body;
import common.biology.signaling : Signaling;
import common.biology.wild : FIRST_ENZYME_GENE, WildGenes, cellGenes, enzymeFromSeed, productOfGenes;
import base.clock : MILLISECONDS_PER_SECOND;
import common.perception : Channel, Perception, Reveal, effectiveFor, felt, leveled, viewOf;
import common.position : Position;
import common.settings : CHUNK_DIMENSION, CharacterConfig;
import common.traversal : NearbyNode, NearbyScratch;
import common.worldgen.blueprint : RouteStop;
import common.worldgen.generation : NodeState, Worldgen;
import common.worldgen.horospheres : Gravity, ensureGravityAt, gravityAt, isGravityKnown;
import common.worldgen.spawn : collectChunksNear, findSpawnPosition;
import common.worldgen.structure : SiteFrame, columnPoint, edgeLength, forwarded, moveToLevel, nodeToNode, rootSite, sitePlacement, siteToNode, spawnBefore, turnSite;
import geometry.honeycomb : CORNER_COUNT, Corner, Face, cornerToNode, cubeToNode, nodeToCorner;
import geometry.lorentz : Motion, Point, Vec4;
import plugins.api.api : Material, Turn;
import plugins.api.flags : Flags;

enum uint MAX_BODY_SECTIONS = 64;
enum float SUN_ELEVATION_COSINE = 0.82f;
enum float SUN_ELEVATION_SINE = 0.57f;
enum size_t MOST_THROWN = 8;
enum uint TRAIL_POINTS = 48;
enum float TRAIL_EVERY_SECONDS = 0.05f;
enum float THROW_SPEED = 1.4f;
enum float THROW_LIFT = 0.5f;
enum float THROWN_SECONDS = 20;
enum float THROWN_STEP = 0.02f;
enum float LEAST_COMPASS_LENGTH = 1e-3f;
enum double MAX_STEP_SECONDS = 0.1;
enum uint MOST_SCANNED_RECEPTORS = 16;
enum Time SCAN_SECONDS = Time(12);
enum Ratio PLANT_DOSE = Ratio(1);
enum uint CELL_HASH_SHIFT = 40;
enum Time MOST_COLLECTED_SECONDS = Time(120);
enum Rate COLLECTION_RATE = Rate(0.02f);
enum uint MOST_SEEDS = 32;
enum Time GROWN_SECONDS = Time(60);
enum float BASE_BREEDING_MUTATION = 0.05f;
enum float ASH_BREEDING_MUTATION = 0.3f;
enum float SULFUR_BREEDING_MUTATION = 0.3f;
enum ulong BREEDING_SALT = 0xB4EED;

enum Preset : ubyte {
    plain,
    heavy,
    light,
    wide,
    narrow,
    behind,
    swaying,
    turned,
    mist,
    afterimage,
    sharp,
    soft,
}

enum uint PRESET_COUNT = Preset.max + 1;

immutable Perception[PRESET_COUNT] PRESETS = [
    Preset.plain: Perception.init,
    Preset.heavy: Perception.init.leveled(Channel.walkSpeed, Ratio(-0.4f)).leveled(Channel.gravity, Ratio(0.7f)).leveled(Channel.jumpHeight, Ratio(-0.7f)),
    Preset.light: Perception.init.leveled(Channel.gravity, Ratio(-0.9f)).leveled(Channel.jumpHeight, Ratio(0.9f)),
    Preset.wide: Perception.init.leveled(Channel.fieldOfView, Ratio(0.9f)),
    Preset.narrow: Perception.init.leveled(Channel.fieldOfView, Ratio(-0.6f)).leveled(Channel.fog, Ratio(1.2f)),
    Preset.behind: Perception.init.leveled(Channel.eyeOffset, Ratio(0.4f)),
    Preset.swaying: Perception.init.leveled(Channel.warp, Ratio(0.1f)),
    Preset.turned: Perception.init.leveled(Channel.colorTurn0, Ratio(1.2f)).leveled(Channel.colorTurn3, Ratio(0.8f)),
    Preset.mist: Perception.init.leveled(Channel.revealMist, Ratio(1)),
    Preset.afterimage: Perception.init.leveled(Channel.afterimage, Ratio(1)),
    Preset.sharp: Perception.init.leveled(Channel.fineDetail, Ratio(0.9f)),
    Preset.soft: Perception.init.leveled(Channel.fineDetail, Ratio(-2.5f)).leveled(Channel.coarseDetail, Ratio(-1)),
];

enum Key : ubyte {
    fwd,
    back,
    left,
    right,
    up,
    down,
    yawLeft,
    yawRight,
    pitchUp,
    pitchDown,
}

enum uint KEY_COUNT = Key.max + 1;

enum KeyStroke : ubyte {
    first,
    repeated,
}

enum Command : ubyte {
    walkMode,
    noclipMode,
    previousWorld,
    nextWorld,
    throwBlock,
    nextPreset,
    dose,
    use,
    eat,
}

struct KeyBinding(Symbol) {
    Symbol symbol;
    Key key;
}

struct CommandBinding(Symbol) {
    Symbol symbol;
    Command command;
}

Maybe!Command commandOf(Symbol)(const(CommandBinding!Symbol)[] bindings, Symbol symbol, KeyStroke press) {
    Maybe!Command found;
    if (press == KeyStroke.first) {
        foreach (binding; bindings) {
            if (binding.symbol == symbol) {
                found = Maybe!Command.of(binding.command);
            }
        }
    }
    return found;
}

void holdBound(Symbol)(ref Flags!Key held, const(KeyBinding!Symbol)[] bindings, Symbol symbol) {
    foreach (binding; bindings) {
        if (binding.symbol == symbol) {
            held.set(binding.key);
        }
    }
}

void letGoBound(Symbol)(ref Flags!Key held, const(KeyBinding!Symbol)[] bindings, Symbol symbol) {
    foreach (binding; bindings) {
        if (binding.symbol == symbol) {
            held.clear(binding.key);
        }
    }
}

enum ChunkSupply : ubyte {
    streamed,
    onDemand,
}

struct FrameInput {
    Angle yaw;
    Angle pitch;
    Flags!Key held;
}

float axisValue(Flags!Key held, Key key) {
    if (held.has(key)) {
        return 1.0f;
    } else {
        return 0.0f;
    }
}

FrameInput frameInputOf(ref const ClientConfig config, Flags!Key held, double mouseDx, double mouseDy, Time dt) {
    AngularSpeed yawRate = config.keyTurnRate * (axisValue(held, Key.yawRight) - axisValue(held, Key.yawLeft));
    AngularSpeed pitchRate = config.keyTurnRate * (axisValue(held, Key.pitchDown) - axisValue(held, Key.pitchUp));
    Angle yaw = yawRate * dt + config.mouseTurnPerCount * cast(float) mouseDx;
    Angle pitch = pitchRate * dt + config.mouseTurnPerCount * cast(float) mouseDy * pitchSign(config.pitchAxis);
    return FrameInput(yaw, pitch, held);
}

struct UnloadedCount {
    uint fresh;
    uint generating;
    uint dropped;
    uint missingNodes;
    uint awaitingBuilding;

    void visitMissingNode(uint, Face) {
        missingNodes += 1;
    }

    void visitChunk(ref const Graph graph, LocalFrame, ChunkSlot slot, CellRange) {
        final switch (graph.chunks.at(slot).state) {
            case ChunkState.fresh:
                if (graph.structures.at(slot.slot).isBuildingQueued) {
                    awaitingBuilding += 1;
                } else {
                    fresh += 1;
                }
                break;
            case ChunkState.generating:
                generating += 1;
                break;
            case ChunkState.dropped:
                dropped += 1;
                break;
            case ChunkState.populated:
                break;
        }
    }
}

struct SolidProbe {
    MaterialSet solid;
    uint solidCells;

    void visitMissingNode(uint, Face) {
    }

    void visitChunk(ref const Graph graph, LocalFrame frame, ChunkSlot slot, CellRange) {
        Vec3!float grid = gridPoint(graph.layout, slot.corner.nodeToCorner * frame.toBody.inverse());
        if (isInsideGrid(grid, graph.layout.dimension) && graph.chunks.at(slot).state == ChunkState.populated) {
            size_t cell = cellIndex(graph.layout.dimension, cast(int) floorf(grid.x), cast(int) floorf(grid.y), cast(int) floorf(grid.z));
            if (solid.has(graph.chunks.at(slot).voxels.at(cell))) {
                solidCells += 1;
            }
        }
    }
}

enum ThrownMotion : ubyte {
    flying,
    resting,
    gone,
}

struct Thrown {
    Position position;
    Vec3!float velocity;
    MaterialSet solid;
    Position[TRAIL_POINTS] trail;
    uint trailCount;
    float untilTrail = 0;
    float age = 0;
    ThrownMotion motion;

    void remember() {
        trail[trailCount % TRAIL_POINTS] = position;
        trailCount += 1;
        untilTrail = TRAIL_EVERY_SECONDS;
    }

    void advance(ref const Graph graph, float gravity, Time dt) {
        age += dt.value;
        if (age > THROWN_SECONDS || !graph.slotOf(position.node).exists) {
            motion = ThrownMotion.gone;
        } else if (motion == ThrownMotion.flying) {
            untilTrail -= dt.value;
            if (untilTrail <= 0) {
                remember();
            }
            fly(graph, gravity, dt);
        }
    }

    void fly(ref const Graph graph, float gravity, Time dt) {
        uint substeps = higherOf(cast(uint) ceilf(velocity.magnitude * dt.value / THROWN_STEP), 1u);
        float each = dt.value / substeps;
        foreach (_; 0 .. substeps) {
            MaybeIndex!uint slot = graph.slotOf(position.node);
            if (!slot.exists) {
                motion = ThrownMotion.gone;
                return;
            } else if (graph.isGravityKnown(slot.value)) {
                Gravity pull = graph.gravityAt(position);
                velocity = velocity.minus(pull.up.scaled(pull.strength * gravity * each));
            }
            Position next = graph.movedBy(position, velocity.scaled(each));
            SolidProbe probe = SolidProbe(solid);
            visitCells(graph, next, Length(0), probe);
            if (probe.solidCells > 0) {
                motion = ThrownMotion.resting;
                return;
            }
            position = next;
        }
    }
}

struct Beacon {
    ChunkId chunk;
    uint cell;
}

struct Seed {
    WildGenes genes;
    Material plant;
}

struct PlantGenes {
    WildGenes genes;
    Material plant;
    Readiness growth;
}

struct Scan {
    Molecule product;
    Ratio[MOST_SCANNED_RECEPTORS] affinity;
    Ratio[MOST_SCANNED_RECEPTORS] efficacy;
    Time seenAt;
    uint receptors;
    Material plant;
}

struct BeaconSighting {
    Vec3!float direction;
    Length distance;
}

struct RouteWaypoint {
    Angle yaw;
    Length horizontal;
    Length rise;
}

struct Game {
    LocalWorld world;
    Camera camera;
    CharacterState characterState;
    CharacterConfig character;
    Perception perception;
    Reveal reveal;
    Organism organism;
    Time time;
    Length traveled;
    Length altitude;
    Ratio comfort = Ratio(1);
    Acceleration cameraVerticalAcceleration;
    Length cameraAltitude;
    Speed cameraVerticalVelocity;
    Array!Thrown thrown;
    Array!Beacon beacons;
    Array!Seed seeds;
    Maybe!Scan scan;
    Vec3!float compass = Vec3!float(0, 0, -1);
    Inventory inventory = Inventory.starter();
    uint doses;
    MovementMode mode = MovementMode.walk;
    Preset preset;
    ChunkSupply supply;
    Readiness cameraVelocity;
    Flags!Key lastHeld;

    static Game make(Worldgen worldgen, Length reach) {
        Game game;
        game.world = LocalWorld.make(CHUNK_DIMENSION, worldgen, tanhf(reach.value));
        game.world.graph.bindView();
        game.camera = Camera.make(game.character.eyeOffset);
        game.organism = Organism.make(starterGenome());
        return game;
    }

    Length bodyExtent() const {
        return character.halfHeight + character.skin;
    }

    Length bodyReach() const {
        return bodyExtent() + character.radius;
    }

    Capsule bodyCapsule() const {
        return Capsule(characterState.up, character.radius.value, character.halfHeight.value, character.skin.value);
    }

    void generateAround(Position position, Length reach) {
        Array!ChunkSlot picked = world.graph.collectChunksNear(position, atanhf(world.tanhReach));
        foreach (chunk; picked.slice()) {
            world.graph.generateNow(chunk);
        }
        picked.release();
        RequiredChunks required;
        do {
            required.clear();
            visitCells(world.graph, position, reach, required);
            foreach (missing; required.missing.slice()) {
                world.graph.ensureNeighborSlot(missing.slot, missing.side);
            }
            foreach (chunk; required.chunks.slice()) {
                world.graph.generateNow(chunk);
            }
        } while (required.missing.length > 0);
        required.release();
    }

    void placeAtSpawn() {
        Maybe!RouteStop entrance = world.graph.structures.blueprint.entrance;
        if (entrance.exists) {
            placeAt(ensureSitePosition(entrance.value.site, spawnBefore(world.graph.layout, entrance.value.spot)), bodyExtent() + character.skin);
        } else {
            Position spawn = world.graph.findSpawnPosition(bodyReach().value);
            Vec3!float up = world.graph.ensureGravityAt(spawn).up;
            characterState = CharacterState(spawn, ZERO_VECTOR, Vec3!float(0, 1, 0), up, up);
        }
        settleToGround();
        resetView();
        if (world.graph.structures.blueprint.entrance.exists) {
            camera.turn(yawToward(directionToDoor()), Angle(0));
        } else if (world.graph.worldgen.groundTiltRadians() != 0) {
            camera.turn(yawToward(uphillDirection()), Angle(0));
        }
        updateView();
        resetCompass();
        world.settleFogColor();
    }

    void resetCompass() {
        Vec3!float level = camera.heading.rotate(CAMERA_FORWARD).rejectAlong(characterState.up);
        compass = level.scaled(1.0f / level.magnitude);
    }

    void levelCompass() {
        Vec3!float level = compass.rejectAlong(characterState.up);
        float length = level.magnitude;
        if (length > LEAST_COMPASS_LENGTH) {
            compass = level.scaled(1.0f / length);
        }
    }

    Angle compassOff() const {
        return yawToward(compass);
    }

    void throwBlock() {
        if (thrown.length == MOST_THROWN) {
            foreach (index; 1 .. thrown.length) {
                thrown.ptr[index - 1] = thrown.ptr[index];
            }
            thrown.length -= 1;
        }
        Thrown made;
        made.solid = bodySolid();
        made.position = world.cameraPosition;
        made.velocity = CAMERA_FORWARD.scaled(THROW_SPEED).plus(Vec3!float(0, THROW_LIFT, 0));
        made.remember();
        thrown.append(made);
    }

    void stepThrown(Time dt) {
        size_t index = 0;
        while (index < thrown.length) {
            thrown.ptr[index].advance(world.graph, character.gravity.value, dt);
            if (thrown.ptr[index].motion == ThrownMotion.gone) {
                foreach (later; index + 1 .. thrown.length) {
                    thrown.ptr[later - 1] = thrown.ptr[later];
                }
                thrown.length -= 1;
            } else {
                index += 1;
            }
        }
    }

    void settleToGround() {
        Length reach = regionReach(character) + bodyReach();
        Features features;
        Slide drop;
        while (!drop.hasLanded) {
            generateAround(characterState.position, reach);
            characterState.up = world.graph.ensureGravityAt(characterState.position).up;
            characterState.pull = characterState.up;
            features.collect(world.graph, characterState.position, reach, bodySolid());
            drop = Mover.make(character, features, characterState.up, Length(0)).settle(ZERO_VECTOR, bodyReach());
            characterState.position = world.graph.movedBy(characterState.position, drop.position);
        }
        features.release();
        characterState.groundNormal = drop.groundNormal;
        characterState.footing = Footing.grounded;
    }

    void resetView() {
        camera = Camera.make(character.eyeOffset);
        altitude = ensureAltitude();
        followBody();
        updateView();
        cameraAltitude = altitude + camera.eyeOffset;
        cameraVelocity = Readiness.pending;
    }

    Length ensureAltitude() {
        Position position = characterState.position;
        return Length(world.graph.horospheres.gravitySign() * world.graph.ensureState(world.graph.slotOf(position.node).value).surface.distanceTo(position.local * Point!float.origin()));
    }

    Vec3!float directionToDoor() const {
        RouteStop entrance = world.graph.structures.blueprint.entrance.value;
        Motion!float siteToBody = characterState.position.local.inverse() * world.graph.ownView.siteToNode(entrance.site, world.graph.slotOf(characterState.position.node).value);
        return (siteToBody * columnPoint(world.graph.layout, entrance.spot)).v.spatial();
    }

    Vec3!float uphillDirection() const {
        return world.graph.stateAt(world.graph.slotOf(characterState.position.node).value).reference.upAt(characterState.position.local).negated;
    }

    Angle yawToward(Vec3!float direction) const {
        Vec3!float forward = camera.heading.rotate(CAMERA_FORWARD);
        Vec3!float level = direction.rejectAlong(camera.viewUp);
        return Angle(atan2f(camera.viewUp.dot(forward.cross(level)), forward.dot(level)));
    }

    void enterStructure(Length height) {
        float edge = edgeLength(world.graph.layout).value;
        float edges = floorf(height.value / edge);
        float rest = height.value - edges * edge;
        SiteFrame tower = world.graph.view.turnSite(rootSite(world.graph.anchorSlot), Turn.pitchUp);
        SiteFrame at = world.graph.view.moveToLevel(forwarded(tower, cast(int) edges), 0);
        placeAt(ensureSitePosition(at, Point!float(Vec4!float([0, 0, sinhf(rest), coshf(rest)]))), Length(0));
    }

    Position ensureSitePosition(SiteFrame site, Point!float inSite) {
        Point!float point = sitePlacement(site, world.graph.layout) * inSite;
        return world.graph.ensureNormalized(Position(world.graph.idAt(site.node), Motion!float.shiftTo(point)));
    }

    void enterRoute(size_t index) {
        RouteStop stop = world.graph.structures.blueprint.route.ptr[index];
        placeAt(ensureSitePosition(stop.site, columnPoint(world.graph.layout, stop.spot)), bodyExtent() + character.skin);
    }

    Maybe!RouteWaypoint routeWaypoint(size_t index) const {
        if (index >= world.graph.structures.blueprint.route.length) {
            return Maybe!RouteWaypoint.init;
        } else {
            RouteStop stop = world.graph.structures.blueprint.route.ptr[index];
            Motion!float siteToBody = world.graph.ownView.siteToNode(stop.site, world.graph.slotOf(characterState.position.node).value);
            return Maybe!RouteWaypoint.of(waypointAt(siteToBody * columnPoint(world.graph.layout, stop.spot)));
        }
    }

    RouteWaypoint waypointAt(Point!float floor) const {
        Vec4!float local = (characterState.position.local.inverse() * floor).v;
        Vec3!float direction = local.spatial();
        float length = direction.magnitude;
        Vec3!float toFloor = direction.scaled(acoshf(local.c[3]) / length);
        Vec3!float fromFeet = toFloor.plus(characterState.up.scaled(bodyExtent().value));
        return RouteWaypoint(yawToward(toFloor), Length(fromFeet.rejectAlong(characterState.up).magnitude), Length(fromFeet.dot(characterState.up)));
    }

    void placeAt(Position target, Length lift) {
        Vec3!float up = world.graph.ensureGravityAt(target).up;
        Position lifted = world.graph.ensureNormalized(Position(target.node, (target.local * Motion!float.shift(up.scaled(lift.value))).orthonormalized()));
        Vec3!float liftedUp = world.graph.ensureGravityAt(lifted).up;
        characterState = CharacterState(lifted, ZERO_VECTOR, characterState.groundNormal, liftedUp, liftedUp);
        resetView();
        resetCompass();
    }

    void rebuildWorld(Worldgen worldgen) {
        ubyte dimension = world.graph.layout.dimension;
        float tanhReach = world.tanhReach;
        float renderRadius = world.renderRadius;
        uint epoch = world.epoch;
        thrown.clear();
        beacons.clear();
        reveal.touchable = MaterialSet.init;
        world.release();
        world = LocalWorld.make(dimension, worldgen, tanhReach);
        world.graph.bindView();
        world.renderRadius = renderRadius;
        world.epoch = epoch + 1;
    }

    void release() {
        thrown.release();
        beacons.release();
        seeds.release();
        organism.release();
        world.release();
    }

    bool breakBlock() {
        Maybe!GraphCastHit hit = world.castCenterRay();
        Maybe!Material broken = world.targetMaterial();
        Maybe!PlantGenes genes = plantGenesAt(hit);
        if (genes.exists) {
            keepSeed(Seed(genes.value.genes, genes.value.plant));
        }
        bool done = world.breakBlock();
        if (done) {
            inventory.gain(broken.value);
            Cell coords = hit.value.voxelCoords;
            uint cell = cast(uint) cellIndex(world.graph.layout.dimension, coords.x, coords.y, coords.z);
            if (broken.value == Material.beacon) {
                removeBeacon(hit.value.chunk, cell);
            } else if (broken.value == Material.collector || isPlant(broken.value)) {
                world.graph.edits.dropRecord(hit.value.chunk, cell);
            }
        }
        return done;
    }

    Maybe!PlantGenes plantGenesAt(Maybe!GraphCastHit hit) {
        if (!hit.exists) {
            return Maybe!PlantGenes.init;
        } else {
            Cell coords = hit.value.voxelCoords;
            uint cell = cast(uint) cellIndex(world.graph.layout.dimension, coords.x, coords.y, coords.z);
            ChunkSlot slot = ChunkSlot(world.graph.slotOf(hit.value.chunk.node).value, hit.value.chunk.corner);
            Material plant = world.graph.chunks.at(slot).voxels.at(cell);
            BlockRecord* record = world.graph.edits.recordAt(hit.value.chunk, cell);
            if (!isPlant(plant) || !world.graph.nodeAt(slot.slot).hasState) {
                return Maybe!PlantGenes.init;
            } else if (record !is null && record.kind == RecordKind.planted) {
                Readiness growth = Readiness.pending;
                if (time - record.placed >= GROWN_SECONDS) {
                    growth = Readiness.ready;
                }
                return Maybe!PlantGenes.of(PlantGenes(record.genes, plant, growth));
            } else {
                ulong cellHash = hit.value.chunk.node.spice() ^ (cast(ulong) slot.corner << CELL_HASH_SHIFT) ^ cell;
                return Maybe!PlantGenes.of(PlantGenes(cellGenes(world.graph.stateAt(slot.slot).wild, cellHash), plant, Readiness.ready));
            }
        }
    }

    Maybe!Molecule plantProductAt(Maybe!GraphCastHit hit) {
        Maybe!PlantGenes genes = plantGenesAt(hit);
        if (genes.exists && genes.value.growth == Readiness.ready) {
            return Maybe!Molecule.of(productOfGenes(genes.value.genes));
        } else {
            return Maybe!Molecule.init;
        }
    }

    void keepSeed(Seed seed) {
        if (seeds.length == MOST_SEEDS) {
            foreach (index; 1 .. seeds.length) {
                seeds.ptr[index - 1] = seeds.ptr[index];
            }
            seeds.length -= 1;
        }
        seeds.append(seed);
    }

    Maybe!Seed takeSeedFor(Material plant) {
        size_t index = seeds.length;
        while (index > 0 && seeds.ptr[index - 1].plant != plant) {
            index -= 1;
        }
        if (index == 0) {
            return Maybe!Seed.init;
        } else {
            Seed taken = seeds.ptr[index - 1];
            foreach (later; index .. seeds.length) {
                seeds.ptr[later - 1] = seeds.ptr[later];
            }
            seeds.length -= 1;
            return Maybe!Seed.of(taken);
        }
    }

    bool breedAt(uint slot) {
        if (seeds.length < 2) {
            return false;
        } else {
            float odds = BASE_BREEDING_MUTATION;
            if (world.graph.nodeAt(slot).hasState) {
                odds += ASH_BREEDING_MUTATION * airOf(world.graph.stateAt(slot).climate.climate()).fractions[ASH_GAS].value;
            }
            if (inventory.spend(Material.sulfur)) {
                odds += SULFUR_BREEDING_MUTATION;
            }
            Seed first = seeds.ptr[seeds.length - 1];
            Seed second = seeds.ptr[seeds.length - 2];
            ulong salt = BREEDING_SALT ^ (cast(ulong)(time.value * MILLISECONDS_PER_SECOND) << 8) ^ seeds.length;
            keepSeed(Seed(crossed(first.genes, second.genes, salt, odds), first.plant));
            return true;
        }
    }

    bool splice() {
        if (seeds.length == 0 || organism.genome.count == MOST_GENES) {
            return false;
        } else {
            Seed source = seeds.ptr[seeds.length - 1];
            seeds.length -= 1;
            Genome genome = organism.genome;
            genome.add(enzymeGene(enzymeFromSeed(source.genes.seeds[FIRST_ENZYME_GENE]), Ratio(1)));
            Body body = organism.body;
            Signaling signaling = organism.signaling;
            organism.release();
            organism = Organism.make(genome);
            organism.body = body;
            organism.signaling = signaling;
            return true;
        }
    }

    void use() {
        Maybe!GraphCastHit hit = world.castCenterRay();
        Maybe!Material target = world.targetMaterial();
        if (target.exists && target.value == Material.collector) {
            collectAt(hit.value);
        } else if (target.exists && target.value == Material.bench) {
            breedAt(world.graph.slotOf(hit.value.chunk.node).value);
        } else {
            scanAt(hit);
        }
    }

    void collectAt(GraphCastHit hit) {
        Cell coords = hit.voxelCoords;
        BlockRecord* record = world.graph.edits.recordAt(hit.chunk, cast(uint) cellIndex(world.graph.layout.dimension, coords.x, coords.y, coords.z));
        uint slot = world.graph.slotOf(hit.chunk.node).value;
        if (record !is null && world.graph.nodeAt(slot).hasState) {
            float elapsed = lowerOf((time - record.placed).value, MOST_COLLECTED_SECONDS.value);
            AirMix air = airOf(world.graph.stateAt(slot).climate.climate());
            foreach (gas; 0 .. GAS_COUNT) {
                organism.dose(Dose(GAS_MOLECULES[gas], Ratio(air.fractions[gas].value * COLLECTION_RATE.value * elapsed), Route.inhaled));
            }
            record.placed = time;
        }
    }

    void scanAt(Maybe!GraphCastHit hit) {
        Maybe!Molecule product = plantProductAt(hit);
        if (product.exists) {
            Scan made;
            made.product = product.value;
            made.seenAt = time;
            made.plant = world.targetMaterial().value;
            made.receptors = cast(uint) lowerOf(organism.receptors.length, cast(size_t) MOST_SCANNED_RECEPTORS);
            foreach (index; 0 .. made.receptors) {
                Binding binding = organism.cache.bindingOf(organism.receptors.ptr[index].pocket, product.value);
                made.affinity[index] = binding.affinity;
                float efficacy = 0;
                foreach (transducer; binding.efficacy) {
                    efficacy += transducer.value;
                }
                made.efficacy[index] = Ratio(efficacy);
            }
            scan = Maybe!Scan.of(made);
        }
    }

    bool eat() {
        Maybe!GraphCastHit hit = world.castCenterRay();
        Maybe!Material target = world.targetMaterial();
        if (target.exists && target.value == Material.bench) {
            return splice();
        } else {
            Maybe!PlantGenes genes = plantGenesAt(hit);
            if (genes.exists && genes.value.growth == Readiness.ready && world.setVoxel(hit.value.chunk, hit.value.voxelCoords, Material.none)) {
                uint slot = world.graph.slotOf(hit.value.chunk.node).value;
                float expression = expressionIn(genes.value.plant, world.graph.stateAt(slot).climate.climate());
                Cell coords = hit.value.voxelCoords;
                world.graph.edits.dropRecord(hit.value.chunk, cast(uint) cellIndex(world.graph.layout.dimension, coords.x, coords.y, coords.z));
                organism.dose(Dose(productOfGenes(genes.value.genes), PLANT_DOSE * expression, Route.ingested));
                return true;
            } else {
                return false;
            }
        }
    }

    bool isScanShown() const {
        return scan.exists && time - scan.value.seenAt < SCAN_SECONDS;
    }

    void addBeacon(ChunkId chunk, uint cell) {
        world.graph.reference(world.graph.slotOf(chunk.node).value);
        beacons.append(Beacon(chunk, cell));
        world.graph.edits.keepRecord(chunk, BlockRecord(WildGenes.init, time, cell, RecordKind.beacon));
    }

    void removeBeacon(ChunkId chunk, uint cell) {
        size_t index = 0;
        while (index < beacons.length && !(beacons.ptr[index].chunk == chunk && beacons.ptr[index].cell == cell)) {
            index += 1;
        }
        if (index < beacons.length) {
            world.graph.unreference(world.graph.slotOf(chunk.node).value);
            beacons.ptr[index] = beacons.ptr[beacons.length - 1];
            beacons.length -= 1;
            world.graph.edits.dropRecord(chunk, cell);
        }
    }

    BeaconSighting sightingOf(Beacon beacon) const {
        ubyte dimension = world.graph.layout.dimension;
        uint slot = world.graph.slotOf(beacon.chunk.node).value;
        uint bodySlot = world.graph.slotOf(characterState.position.node).value;
        Vec3!float cube = world.graph.layout.cellCenter(Vec3!int(beacon.cell % dimension, beacon.cell / dimension % dimension, beacon.cell / (dimension * dimension)));
        Point!float inNode = (beacon.chunk.corner.cubeToNode * Vec4!float([cube.x, cube.y, cube.z, 1])).toPoint();
        Vec4!float inBody = (characterState.position.local.inverse() * world.graph.ownView.nodeToNode(slot, bodySlot) * inNode).v;
        return BeaconSighting(inBody.spatial(), Length(acoshf(inBody.c[3])));
    }

    bool placeBlock() {
        Maybe!Placement placement = world.placementTarget();
        Material held = inventory.held();
        if (placement.exists && inventory.counts[held] > 0 && world.isEmptyAt(placement.value) && !isBodyOverlapping(ChunkSlot(world.graph.slotOf(placement.value.chunk.node).value, placement.value.chunk.corner), placement.value)) {
            bool done = world.setVoxel(placement.value.chunk, placement.value.coords, held);
            if (done) {
                inventory.spend(held);
                Cell coords = placement.value.coords;
                uint cell = cast(uint) cellIndex(world.graph.layout.dimension, coords.x, coords.y, coords.z);
                if (held == Material.beacon) {
                    addBeacon(placement.value.chunk, cell);
                } else if (held == Material.collector) {
                    world.graph.edits.keepRecord(placement.value.chunk, BlockRecord(WildGenes.init, time, cell, RecordKind.collector));
                } else if (isPlant(held)) {
                    Maybe!Seed seed = takeSeedFor(held);
                    if (seed.exists) {
                        world.graph.edits.keepRecord(placement.value.chunk, BlockRecord(seed.value.genes, time, cell, RecordKind.planted));
                    }
                }
            }
            return done;
        } else {
            return false;
        }
    }

    bool isBodyOverlapping(ChunkSlot slot, Placement placement) const {
        Vec3!float[MAX_BODY_SECTIONS] storage;
        CellOverlap overlap = CellOverlap(sectionCenters(bodyCapsule(), ZERO_VECTOR, storage[]), slot, placement.coords, character.radius.value);
        visitCells(world.graph, characterState.position, regionReach(character), overlap);
        return overlap.overlaps > 0;
    }

    void look(Angle yaw, Angle pitch) {
        camera.turn(-yaw, -pitch);
        updateView();
    }

    void followBody() {
        Motion!float eye = Motion!float.shift(characterState.up.scaled(camera.eyeOffset.value));
        camera.follow(characterState.position, eye, characterState.up);
    }

    void updateView() {
        world.cameraPosition = camera.orientedPosition();
        world.sunward = camera.orientation.inverted().rotate(sunInBody());
        world.view = viewOf(perception, time, reveal.revealed, comfort);
    }

    MaterialSet bodySolid() const {
        return character.solid.joined(reveal.touchable);
    }

    void settleReveal() {
        reveal.update(perception);
        foreach (family; FAMILY_SETS) {
            if (!family.within(reveal.revealed).isEmpty && family.within(reveal.touchable).isEmpty && !isBodyInside(family)) {
                reveal.touchable = reveal.touchable.joined(family);
            }
        }
    }

    bool isBodyInside(MaterialSet materials) const {
        Vec3!float[MAX_BODY_SECTIONS] storage;
        MaterialOverlap overlap = MaterialOverlap(sectionCenters(bodyCapsule(), ZERO_VECTOR, storage[]), materials, character.radius.value);
        visitCells(world.graph, characterState.position, regionReach(character), overlap);
        return overlap.overlaps > 0;
    }

    void perceive(Preset chosen) {
        preset = chosen;
        perception = felt(PRESETS[chosen], organism.signaling.signals[]);
        settleReveal();
        updateView();
    }

    void doseNext() {
        organism.dose(STARTER_DOSES[doses % STARTER_DOSES.length]);
        doses += 1;
    }

    void nextPreset() {
        perceive(cast(Preset)((preset + 1) % PRESET_COUNT));
    }

    Vec3!float sunInBody() const {
        Vec3!float up = characterState.up;
        Vec3!float side = perpendicularTo(up).rejectAlong(up);
        return up.scaled(SUN_ELEVATION_COSINE).plus(side.scaled(SUN_ELEVATION_SINE / side.magnitude));
    }

    void step(FrameInput input, Time dt) {
        look(input.yaw, input.pitch);
        float moveX = axisValue(input.held, Key.right) - axisValue(input.held, Key.left);
        float moveY = axisValue(input.held, Key.up) - axisValue(input.held, Key.down);
        float moveZ = axisValue(input.held, Key.back) - axisValue(input.held, Key.fwd);
        organism.advance(dt);
        perception = felt(PRESETS[preset], organism.signaling.signals[]);
        settleReveal();
        CharacterConfig effective = character.effectiveFor(perception);
        effective.solid = bodySolid();
        Stepped stepped = runCharacter(effective, characterInput(moveX, moveY, moveZ, jumpFrom(input.held)), dt);
        lastHeld = input.held;
        traveled = traveled + stepped.traveled;
        altitude = ensureAltitude();
        followBody();
        levelCompass();
        updateView();
        stepThrown(dt);
        world.approachFogColor(dt.value);
        trackCameraAcceleration(altitude + camera.eyeOffset, dt);
        if (supply == ChunkSupply.streamed) {
            world.update(Pacing.budgeted);
        }
        time = time + dt;
    }

    Length probeFrameDrift(Length radius) {
        NearbyScratch scratch;
        NearbyNode[] fresh = scratch.collectAll(world.graph, world.cameraPosition, radius.value);
        const(NearbyScratch)* drawn = &world.nearby[world.published];
        Motion!float fromFrame = world.cameraInNearbyFrame().inverse();
        Motion!float fromNode = world.cameraPosition.local.inverse();
        double most = 0;
        foreach (node; fresh) {
            MaybeIndex!uint index = drawn.indexOf(node.slot);
            if (index.exists) {
                Motion!float drawnToCamera = fromFrame * drawn.nodes.ptr[index.value].transform;
                Motion!float freshToCamera = fromNode * node.transform;
                foreach (corner; 0 .. CORNER_COUNT) {
                    Motion!float toNode = (cast(Corner) corner).cornerToNode;
                    Vec4!double apart = (drawnToCamera * toNode * Point!float.origin()).v.as!double() - (freshToCamera * toNode * Point!float.origin()).v.as!double();
                    most = higherOf(sqrt(fabs(apart.minkowski(apart))), most);
                }
            }
        }
        scratch.release();
        return Length(cast(float) most);
    }

    UnloadedCount unloadedWithin(Length radius) const {
        UnloadedCount counted;
        visitCells(world.graph, characterState.position, radius, counted);
        return counted;
    }

    bool isLoadedAround() const {
        Features features;
        features.collect(world.graph, characterState.position, regionReach(character), bodySolid());
        uint unloaded = features.unloaded;
        features.release();
        return unloaded == 0;
    }

    Stepped runCharacter(ref const CharacterConfig config, CharacterInput input, Time dt) {
        if (supply == ChunkSupply.onDemand) {
            return runGenerating(config, input, dt);
        } else {
            return characterState.runStep(config, world.graph, input, dt);
        }
    }

    Stepped runGenerating(ref const CharacterConfig config, CharacterInput input, Time dt) {
        generateAround(characterState.position, regionReach(config));
        CharacterState trial = characterState;
        Stepped stepped = trial.runStep(config, world.graph, input, dt);
        while (stepped.isStalled) {
            generateAround(trial.position, regionReach(config));
            trial = characterState;
            stepped = trial.runStep(config, world.graph, input, dt);
        }
        characterState = trial;
        return stepped;
    }

    Jump jumpFrom(Flags!Key held) const {
        if (held.has(Key.up) && !lastHeld.has(Key.up)) {
            return Jump.pressed;
        } else {
            return Jump.none;
        }
    }

    CharacterInput characterInput(float moveX, float moveY, float moveZ, Jump jump) const {
        if (mode == MovementMode.noclip) {
            return CharacterInput(camera.orientation.rotate(Vec3!float(moveX, moveY, moveZ)), mode);
        } else if (mode == MovementMode.fly) {
            return CharacterInput(levelMove(moveX, moveZ).plus(characterState.up.scaled(moveY)), mode);
        } else {
            return CharacterInput(levelMove(moveX, moveZ), mode, jump);
        }
    }

    Vec3!float levelMove(float moveX, float moveZ) const {
        return camera.heading.rotate(Vec3!float(1, 0, 0)).scaled(moveX).plus(camera.heading.rotate(Vec3!float(0, 0, 1)).scaled(moveZ));
    }

    void trackCameraAcceleration(Length newCameraAltitude, Time dt) {
        Speed verticalVelocity = (newCameraAltitude - cameraAltitude) / dt;
        if (cameraVelocity == Readiness.ready) {
            cameraVerticalAcceleration = Acceleration(fabsf(((verticalVelocity - cameraVerticalVelocity) / dt).value));
        } else {
            cameraVerticalAcceleration = Acceleration(0);
        }
        cameraAltitude = newCameraAltitude;
        cameraVerticalVelocity = verticalVelocity;
        cameraVelocity = Readiness.ready;
    }

    void toggleMode(MovementMode toggled) {
        if (mode == toggled) {
            mode = MovementMode.fly;
        } else {
            mode = toggled;
        }
    }
}
