module client.game;

import core.stdc.math : acoshf, atan2f, atanhf, ceilf, coshf, fabs, fabsf, floorf, roundf, sinhf, sqrt, tanhf;
import base.array : Array;
import base.clock : MILLISECONDS_PER_SECOND;
import base.flags : Readiness;
import base.hashmap : HashMap, Present;
import base.maybe : Maybe, MaybeIndex;
import base.numbers : higherOf, lowerOf;
import base.units : Acceleration, Angle, AngularSpeed, Length, Rate, Ratio, Speed, Time;
import base.vector3 : Vec3, ZERO_VECTOR, cross, dot, magnitude, minus, negated, plus, rejectAlong, scaled;
import client.arrivals : generateNow;
import client.bindings : Rules;
import client.camera : CAMERA_FORWARD, Camera;
import client.config : ClientConfig, DEFAULT_THREAD_BEADS, THREAD_SPACING, pitchSign;
import client.streaming : Pacing;
import client.world : LocalWorld, Placement;
import common.biology.air : ASH_GAS, AirMix, GAS_COUNT, GAS_MOLECULES, airOf;
import common.biology.breeding : crossed, expressionIn, productOf;
import common.biology.genome : Genome, MOST_GENES, enzymeGene;
import common.biology.kinetics : Body, Route;
import common.biology.metabolism : Enzyme, Operation;
import common.biology.molecule : Molecule;
import common.biology.organism : Dose, Organism, starterDoses, starterGenome;
import common.biology.pocket : Binding;
import common.biology.signaling : Signaling;
import common.biology.wild : FIRST_ENZYME_GENE, WildGenes, cellGenes, enzymeFromSeed, speciesGenes;
import common.character.controller : CharacterInput, CharacterState, Footing, Jump, MovementMode, Mover, Slide, Stepped, movedBy, perpendicularTo, regionReach;
import common.character.features : CellOverlap, CellRange, Features, LocalFrame, MaterialOverlap, RequiredChunks, gridPoint, isInsideGrid, visitCells;
import common.character.sweep : Capsule, sectionCenters;
import common.content.content : fire, keptText, readApi;
import common.content.roles : Role, roleBlock, roleItem;
import common.crafting : CraftKind, Crafting, DoseRoute, Effect, HAND, IdSet, Insight, Product, Reaction, Recipe, Shortfall, Station, Synthesis, SynthesisRule, Taken, Trigger, Upgrade, canCraft, doseRoutes, insights, isKnown, planRecipe, projected, recipes, returnIngredients, stationOf, stations, syntheses, synthesized, takeIngredients, upgrades;
import common.edits : BlockRecord, RecordKind;
import common.graph : Graph, NodeId;
import common.inventory : Inventory, SLOT_COUNT, STACK_LIMIT, Section, Sorting, Stack, isAmong, isSameKind, sectionOf;
import common.items : Item, ItemKind, itemNamed, itemOf, materialNames, placedBlock;
import common.material : MaterialSet, breakSeconds, families, fluids, has, isEmpty, isHidden, isLiving, isPlant, joined, materialCount, miningTiers, nameHashOf, plainSolid, within;
import common.node : ChunkId, ChunkSlot, ChunkState, cellIndex;
import common.perception : Channel, Perception, Reveal, effectiveFor, felt, leveled, presets, viewOf;
import common.position : Position;
import common.raycast.graph : GraphCastHit;
import common.settings : CHUNK_DIMENSION, CharacterConfig;
import common.traversal : NearbyNode, NearbyScratch;
import common.worldgen.blueprint : RouteStop;
import common.worldgen.generation : NodeState, Worldgen;
import common.worldgen.horospheres : Gravity, ensureGravityAt, gravityAt, isGravityKnown;
import common.worldgen.spawn : collectChunksNear, findSpawnPosition;
import common.worldgen.structure : SiteFrame, columnPoint, edgeLength, forwarded, moveToLevel, nodeToNode, rootSite, sitePlacement, siteToNode, spawnBefore, turnSite;
import geometry.cube : Cell;
import geometry.honeycomb : CORNER_COUNT, Corner, Face, cornerToNode, cubeToNode, nodeToCorner;
import geometry.lorentz : Motion, Point, Vec4;
import plugins.api.api : Material, Turn;
import plugins.api.content : Event, Happening, Play;
import plugins.api.flags : Flags;

enum uint MOST_BODY_SECTIONS = 64;
enum float SUN_ELEVATION_COSINE = 0.82f;
enum float SUN_ELEVATION_SINE = 0.57f;
enum size_t MOST_THROWN = 8;
enum uint TRAIL_POINTS = 48;
enum Time TRAIL_EVERY_SECONDS = Time(0.05f);
enum Speed THROW_SPEED = Speed(1.4f);
enum Speed THROW_LIFT = Speed(0.5f);
enum Time THROWN_SECONDS = Time(20);
enum Length THROWN_STEP = Length(0.02f);
enum float LEAST_COMPASS_LENGTH = 1e-3f;
enum double MOST_STEP_SECONDS = 0.1;
enum uint MOST_SCANNED_RECEPTORS = 16;
enum Ratio PLANT_DOSE = Ratio(1);
enum uint CELL_HASH_SHIFT = 40;
enum Time MOST_COLLECTED_SECONDS = Time(120);
enum Rate COLLECTION_RATE = Rate(0.02f);
enum Time GROWN_SECONDS = Time(60);
enum float MOST_EXTRA_YIELD = 2;
enum Time EAT_TIME = Time(1.5f);
enum float BASE_BREEDING_MUTATION = 0.05f;
enum float ASH_BREEDING_MUTATION = 0.3f;
enum float MUTAGEN_BREEDING_MUTATION = 0.3f;
enum ulong BREEDING_SALT = 0xB4EED;
enum size_t MOST_NOTES = 4;
enum Time NOTE_SECONDS = Time(5);
enum Time CREATIVE_BREAK = Time(0.15f);
enum Time HAND_BREAK = Time(1.5f);

enum NoteKind : ubyte {
    planted,
    plantedWild,
    ate,
    ateUnknown,
    nothingToEat,
    noGenes,
    spliced,
    genomeFull,
    noPlant,
    needPlants,
    crossed,
    crossedWithMutagen,
    breathed,
    dosed,
    revealed,
    faded,
    inventoryFull,
    crafted,
    upgraded,
    missingIngredients,
    harvested,
    extracted,
    needsTier,
    synthesized,
    unchanged,
    noDose,
    noTestDose,
    needsDevice,
    bodyFull,
    upgradeQueued,
    queueFull,
    learned,
    unripeHarvest,
    told,
}

struct Note {
    Molecule molecule;
    Time at;
    float amount = 0;
    const(char)[] label;
    Item item;
    Material material;
    Operation operation;
    uint family;
    Route route;
    NoteKind kind;
}

enum Length STATION_REACH = Length(0.6f);
enum float MINING_SPEEDUP = 0.4f;
enum float HARVEST_RAW = 1;
enum float RAW_PER_DOSE = 4;
enum Ratio DOSE_SIZE = Ratio(1);
enum size_t MOST_COMPOUNDS = 24;

enum size_t MOST_STATIONS = 32;
enum string BARE_HANDS = "bare hands";
enum string UNKNOWN_TOOL = "a tool no recipe makes";

uint requiredTierOf(Material material) {
    return miningTiers.ptr[material.id];
}

uint highestMiningTier() {
    uint highest = 0;
    foreach (ref upgrade; upgrades()) {
        if (upgrade.effect == Effect.mining) {
            highest = higherOf(highest, upgrade.tier);
        }
    }
    return highest;
}

const(char)[] toolFor(uint tier) {
    if (tier == 0) {
        return BARE_HANDS;
    } else {
        size_t index = 0;
        while (index < upgrades().length && !(upgrades()[index].effect == Effect.mining && upgrades()[index].tier == tier)) {
            index += 1;
        }
        if (index < upgrades().length) {
            return upgrades()[index].title;
        } else {
            return UNKNOWN_TOOL;
        }
    }
}

void playGive(const(Play)* play, const(char)[] item, uint count) {
    Maybe!Item found = itemNamed(item);
    if (found.exists) {
        (cast(Game*) play.host).store(Stack(found.value, count));
    }
}

void playLearn(const(Play)* play, const(char)[] insight) {
    size_t index = 0;
    while (index < insights().length && insights()[index].name != insight) {
        index += 1;
    }
    if (index < insights().length) {
        (cast(Game*) play.host).learn(Insight(cast(ubyte) index));
    }
}

void playNote(const(Play)* play, const(char)[] text) {
    Note made = {kind: NoteKind.told, label: keptText(text)};
    (cast(Game*) play.host).post(made);
}

struct Compound {
    Molecule molecule;
    Ratio[MOST_SCANNED_RECEPTORS] affinity;
    Ratio[MOST_SCANNED_RECEPTORS] efficacy;
    float raw = 0;
    float doses = 0;
    uint receptors;
}

uint slotFor(ref Array!Compound compounds, Molecule molecule) {
    uint index = 0;
    while (index < compounds.length && compounds.ptr[index].molecule != molecule) {
        index += 1;
    }
    if (index == compounds.length) {
        if (compounds.length == MOST_COMPOUNDS) {
            foreach (later; 1 .. compounds.length) {
                compounds.ptr[later - 1] = compounds.ptr[later];
            }
            compounds.length -= 1;
        }
        Compound made;
        made.molecule = molecule;
        compounds.append(made);
        index = cast(uint)(compounds.length - 1);
    }
    return index;
}


bool isCatalogued(Item item) {
    final switch (item.kind) {
        case ItemKind.nothing:
            return false;
        case ItemKind.block:
            return !isHidden(item.block) && !fluids.has(item.block);
        case ItemKind.ware:
            return true;
    }
}

Inventory creativeInventory() {
    Inventory inventory;
    uint slot = 0;
    foreach (id; 1 .. materialCount()) {
        Item item = Item(cast(ushort) id);
        if (slot < SLOT_COUNT && isCatalogued(item)) {
            inventory.slots[slot] = Stack(item, STACK_LIMIT);
            slot += 1;
        }
    }
    return inventory;
}

enum AimKind : ubyte {
    nothing,
    block,
    living,
    collector,
    bench,
    station,
}

enum Screen : ubyte {
    none,
    character,
    bench,
    collector,
    station,
    journal,
    menu,
    controls,
}

enum Sheet : ubyte {
    items,
    body,
    chemistry,
    surroundings,
    catalog,
}

enum Deleting : ubyte {
    idle,
    asked,
}

enum Saving : ubyte {
    enabled,
    refused,
}

struct WorldMenu {
    IdSet saved;
    MaybeIndex!uint picked;
    uint current;
    Deleting deleting;
    Saving saving;
}

enum Ripeness : ubyte {
    wild,
    growing,
    ripe,
}

enum uint SHEET_COUNT = Sheet.max + 1;

uint sheetsFor(Rules rules) {
    final switch (rules) {
        case Rules.survival:
            return Sheet.catalog;
        case Rules.creative:
            return SHEET_COUNT;
    }
}

enum Click : ubyte {
    primary,
    secondary,
    quick,
}

enum UiKind : ubyte {
    slot,
    craft,
    cancelCraft,
    sheet,
    choosePlant,
    pressLiving,
    cross,
    splice,
    breathe,
    close,
    rebind,
    resetBindings,
    chooseCompound,
    synthesize,
    takeDose,
    takeItem,
    open,
    pickWorld,
    askDelete,
    playWorld,
    deleteWorld,
}

struct UiAction {
    uint index;
    UiKind kind;
}

struct Mining {
    ChunkId chunk;
    Cell cell;
    Time spent;
}

enum uint CHOSEN_PLANTS = 2;
enum size_t MOST_CRAFTS = 16;

enum Key : ubyte {
    forward,
    back,
    left,
    right,
    up,
    down,
    yawLeft,
    yawRight,
    pitchUp,
    pitchDown,
    mine,
    eat,
}

enum uint KEY_COUNT = Key.max + 1;

enum KeyStroke : ubyte {
    first,
    repeated,
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
    Time untilTrail;
    Time age;
    ThrownMotion motion;

    void remember() {
        trail[trailCount % TRAIL_POINTS] = position;
        trailCount += 1;
        untilTrail = TRAIL_EVERY_SECONDS;
    }

    void advance(ref const Graph graph, Acceleration gravity, Time dt) {
        age = age + dt;
        if (age > THROWN_SECONDS || !graph.slotOf(position.node).exists) {
            motion = ThrownMotion.gone;
        } else if (motion == ThrownMotion.flying) {
            untilTrail = untilTrail - dt;
            if (untilTrail <= Time(0)) {
                remember();
            }
            fly(graph, gravity, dt);
        }
    }

    void fly(ref const Graph graph, Acceleration gravity, Time dt) {
        uint substeps = higherOf(cast(uint) ceilf(velocity.magnitude * dt.value / THROWN_STEP.value), 1u);
        float each = dt.value / substeps;
        foreach (_; 0 .. substeps) {
            MaybeIndex!uint slot = graph.slotOf(position.node);
            if (!slot.exists) {
                motion = ThrownMotion.gone;
                return;
            } else if (graph.isGravityKnown(slot.value)) {
                Gravity pull = graph.gravityAt(position);
                velocity = velocity.minus(pull.up.scaled(pull.strength * gravity.value * each));
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

struct Thread {
    Array!Position beads;
    Length spacing = THREAD_SPACING;
    Length due;
    uint most = DEFAULT_THREAD_BEADS;

    void lay(Position at, Length traveled) {
        if (most > 0 && !(traveled < due)) {
            MaybeIndex!uint back = rewoundTo(at);
            if (back.exists) {
                beads.length = back.value + 1;
            } else {
                if (beads.length >= most) {
                    thin();
                }
                if (beads.length < most) {
                    beads.append(at);
                }
            }
            due = traveled + spacing;
        }
    }

    MaybeIndex!uint rewoundTo(Position at) const {
        Point!float here = at.local * Point!float.origin();
        float coshReach = coshf(spacing.value);
        uint index = 0;
        while (index + 1 < beads.length && !(beads.ptr[index].node == at.node && !(here.coshDistance(beads.ptr[index].local * Point!float.origin()) > coshReach))) {
            index += 1;
        }
        if (index + 1 < beads.length) {
            return MaybeIndex!uint.of(index);
        } else {
            return MaybeIndex!uint.init;
        }
    }

    void thin() {
        size_t kept = (beads.length + 1) / 2;
        foreach (index; 0 .. kept) {
            beads.ptr[index] = beads.ptr[2 * index];
        }
        beads.length = kept;
    }

    void restart(Length traveled) {
        beads.clear();
        due = traveled;
    }
}

struct LivingGenes {
    WildGenes genes;
    Time left;
    Material species;
    Ripeness growth;
}

struct Eating {
    Stack food;
    Time spent;
    uint slot;
}

bool isLivingItem(Item item) {
    return item.kind == ItemKind.block && isLiving(item.block);
}

bool isPlantItem(Item item) {
    return item.kind == ItemKind.block && isPlant(item.block);
}

struct LivingReading {
    Molecule product;
    Ratio[MOST_SCANNED_RECEPTORS] affinity;
    Ratio[MOST_SCANNED_RECEPTORS] efficacy;
    Time left;
    Ratio fit;
    uint receptors;
    Material species;
    Ripeness growth;
}

struct Aim {
    LivingReading living;
    Ratio[GAS_COUNT] gathered;
    Ratio mutation;
    Material material;
    AimKind kind;
}

struct RecipePlan {
    Shortfall shortfall;
    uint steps;
}

enum Mineable : ubyte {
    yes,
    tooHard,
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
    Array!Note notes;
    Array!Crafting crafts;
    Array!Compound compounds;
    Thread thread;
    HashMap!(NodeId, Present) explored;
    Aim aim;
    Ratio[GAS_COUNT] machineAir;
    Ratio machineFill;
    Inventory inventory;
    Stack carried;
    Maybe!Mining mining;
    Maybe!Eating eating;
    Maybe!Beacon[MOST_STATIONS] usedStations;
    ChunkId machine;
    uint machineCell;
    Vec3!float compass = Vec3!float(0, 0, -1);
    MaybeIndex!uint[CHOSEN_PLANTS] chosen;
    MaybeIndex!uint chosenCompound;
    uint doses;
    IdSet owned;
    IdSet noticed;
    MovementMode mode = MovementMode.walk;
    uint preset;
    Screen screen;
    Sheet sheet;
    WorldMenu worlds;
    Station workstation;
    Rules rules;
    ChunkSupply supply;
    Readiness cameraVelocity;
    Flags!Key lastHeld;

    static Game make(Worldgen worldgen, Length reach) {
        Game game;
        game.world = LocalWorld.make(CHUNK_DIMENSION, worldgen, tanhf(reach.value));
        game.world.graph.bindView();
        game.camera = Camera.make(game.character.eyeOffset);
        game.organism = Organism.make(starterGenome());
        game.character.solid = plainSolid;
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
        Readiness covered = generateRequired(position, reach, required);
        while (covered == Readiness.pending) {
            covered = generateRequired(position, reach, required);
        }
        required.release();
    }

    Readiness generateRequired(Position position, Length reach, ref RequiredChunks required) {
        required.clear();
        visitCells(world.graph, position, reach, required);
        foreach (missing; required.missing.slice()) {
            world.graph.ensureNeighborSlot(missing.slot, missing.side);
        }
        foreach (chunk; required.chunks.slice()) {
            world.graph.generateNow(chunk);
        }
        if (required.missing.length > 0) {
            return Readiness.pending;
        } else {
            return Readiness.ready;
        }
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
        made.velocity = CAMERA_FORWARD.scaled(THROW_SPEED.value).plus(Vec3!float(0, THROW_LIFT.value, 0));
        made.remember();
        thrown.append(made);
    }

    void stepThrown(Time dt) {
        size_t index = 0;
        while (index < thrown.length) {
            thrown.ptr[index].advance(world.graph, character.gravity, dt);
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
        thread.restart(traveled);
        explored.clear();
        usedStations[] = Maybe!Beacon.init;
        closeScreen();
        mining = Maybe!Mining.init;
        reveal.touchable = MaterialSet.init;
        world.release();
        world = LocalWorld.make(dimension, worldgen, tanhReach);
        world.graph.bindView();
        world.renderRadius = renderRadius;
        world.epoch = epoch + 1;
    }

    void startOver() {
        inventory = Inventory.init;
        carried = Stack.init;
        owned = IdSet.init;
        noticed = IdSet.init;
        crafts.clear();
        compounds.clear();
        notes.clear();
        chosenCompound = MaybeIndex!uint.init;
        chosen[] = MaybeIndex!uint.init;
        eating = Maybe!Eating.init;
        organism.release();
        organism = Organism.make(starterGenome());
        doses = 0;
        time = Time(0);
    }

    void release() {
        thrown.release();
        beacons.release();
        notes.release();
        crafts.release();
        compounds.release();
        thread.beads.release();
        explored.release();
        organism.release();
        world.release();
    }

    void store(Stack stack) {
        uint lost = inventory.gain(stack);
        if (lost > 0) {
            Note made = {kind: NoteKind.inventoryFull, item: stack.item, amount: lost};
            post(made);
        }
        if (stack.strainCount > 0) {
            sortLiving();
        }
    }

    bool isKnownStrain(Item item, WildGenes genes) const {
        return isKnownProduct(productOf(item.block, genes));
    }

    bool hasKnownStrain(ref const Stack stack) const {
        uint index = 0;
        while (index < stack.strainCount && !(stack.sorting == Sorting.unsorted && isKnownStrain(stack.item, stack.strains[index].genes))) {
            index += 1;
        }
        return index < stack.strainCount;
    }

    void sortLiving() {
        foreach (slot; 0 .. SLOT_COUNT) {
            if (hasKnownStrain(inventory.slots[slot])) {
                Inventory before = inventory;
                uint stranded = sortStack(slot);
                if (stranded > 0) {
                    inventory = before;
                }
            }
        }
    }

    uint sortStack(uint slot) {
        Stack mixed = inventory.slots[slot];
        inventory.slots[slot] = Stack.init;
        uint stranded = 0;
        foreach (ref run; mixed.strains[0 .. mixed.strainCount]) {
            if (!isKnownStrain(mixed.item, run.genes)) {
                Stack unknown = Stack.ofLiving(mixed.item, run.count, run.genes, Sorting.unsorted);
                unknown.pourInto(inventory.slots[slot]);
            }
        }
        foreach (ref run; mixed.strains[0 .. mixed.strainCount]) {
            if (isKnownStrain(mixed.item, run.genes)) {
                Stack known = Stack.ofLiving(mixed.item, run.count, run.genes, Sorting.sorted);
                inventory.joinWithin(0, SLOT_COUNT, known);
                if (inventory.slots[slot].isEmpty) {
                    known.pourInto(inventory.slots[slot]);
                }
                stranded += inventory.gain(known);
            }
        }
        return stranded;
    }

    uint miningTier() const {
        if (rules == Rules.creative) {
            return highestMiningTier();
        } else {
            uint tier = 0;
            foreach (index, ref upgrade; upgrades()) {
                if (upgrade.effect == Effect.mining && owned.has(cast(uint) index)) {
                    tier = higherOf(tier, upgrade.tier);
                }
            }
            return tier;
        }
    }

    Mineable mineableOf(Material material) const {
        if (requiredTierOf(material) <= miningTier()) {
            return Mineable.yes;
        } else {
            return Mineable.tooHard;
        }
    }

    Time breakTimeOf(Material material) const {
        if (rules == Rules.creative) {
            return CREATIVE_BREAK;
        } else {
            return Time(breakSeconds.ptr[material.id]) / (1 + MINING_SPEEDUP * miningTier());
        }
    }

    Ratio miningShare() const {
        if (!mining.exists) {
            return Ratio(0);
        } else {
            return Ratio(lowerOf((mining.value.spent / breakTimeOf(aim.material)).value, 1.0f));
        }
    }

    void mine(Time dt) {
        Maybe!GraphCastHit hit = world.castCenterRay();
        Maybe!Material target = world.targetMaterial();
        if (!hit.exists || !target.exists) {
            mining = Maybe!Mining.init;
        } else if (mining.exists && mining.value.chunk == hit.value.chunk && mining.value.cell == hit.value.voxelCoords) {
            if (mineableOf(target.value) == Mineable.yes) {
                mining.value.spent = mining.value.spent + dt;
            }
            if (mining.value.spent >= breakTimeOf(target.value)) {
                breakBlock();
                mining = Maybe!Mining.init;
            }
        } else {
            mining = Maybe!Mining.of(Mining(hit.value.chunk, hit.value.voxelCoords, Time(0)));
            if (mineableOf(target.value) == Mineable.tooHard) {
                Note made = {kind: NoteKind.needsTier, material: target.value, label: toolFor(requiredTierOf(target.value))};
                post(made);
            }
        }
    }

    IdSet knowledge() const {
        IdSet known = noticed;
        if (rules == Rules.creative) {
            foreach (insight; 0 .. insights().length) {
                known.set(cast(uint) insight);
            }
        }
        return known;
    }

    bool isKnownRecipe(uint recipe) const {
        IdSet known = knowledge();
        return known.isKnown(recipes()[recipe].insight);
    }

    void learn(Insight insight) {
        if (!noticed.has(insight.id)) {
            noticed.set(insight.id);
            Note made = {kind: NoteKind.learned, label: insights()[insight.id].title};
            post(made);
        }
    }

    void learnFromBreaking(Material material) {
        foreach (index, ref rule; insights()) {
            if (rule.trigger == Trigger.broke && itemOf(material).isAmong(rule.noticed)) {
                learn(Insight(cast(ubyte) index));
            }
        }
    }

    void learnFromWorking(Station station) {
        foreach (index, ref rule; insights()) {
            if (rule.trigger == Trigger.worked && rule.station == station) {
                learn(Insight(cast(ubyte) index));
            }
        }
    }

    RecipePlan planOf(uint recipe) const {
        Inventory stock = projected(inventory, crafts.slice());
        Array!uint plan;
        Shortfall shortfall = planRecipe(stock, recipe, 1, plan, 0, knowledge());
        RecipePlan made = RecipePlan(shortfall, cast(uint) plan.length);
        plan.release();
        return made;
    }

    bool hasOrQueued(Upgrade upgrade) const {
        uint index = 0;
        while (index < crafts.length && !(crafts.ptr[index].kind == CraftKind.recipe && recipes()[crafts.ptr[index].index].product == Product.upgrade && recipes()[crafts.ptr[index].index].upgrade == upgrade)) {
            index += 1;
        }
        return owned.has(upgrade.id) || index < crafts.length;
    }

    bool isRepeatedUpgrade(uint recipe) const {
        return recipes()[recipe].product == Product.upgrade && hasOrQueued(recipes()[recipe].upgrade);
    }

    bool isPressing(uint synthesis) const {
        return syntheses()[synthesis].reaction == Reaction.press;
    }

    bool isExtracting(uint synthesis) const {
        return syntheses()[synthesis].reaction == Reaction.extract;
    }

    MaybeIndex!uint extractionAt(Station station) const {
        uint index = 0;
        while (index < syntheses().length && !(isExtracting(index) && syntheses()[index].station == station)) {
            index += 1;
        }
        if (index < syntheses().length) {
            return MaybeIndex!uint.of(index);
        } else {
            return MaybeIndex!uint.init;
        }
    }

    bool isPressable(uint slot) const {
        Stack stack = inventory.slots[slot];
        return !stack.isEmpty && isLivingItem(stack.item) && stack.genes.exists;
    }

    bool pressLiving(uint slot) {
        MaybeIndex!uint rule = extractionAt(workstation);
        if (!rule.exists || slot >= SLOT_COUNT) {
            return false;
        } else if (!isPressable(slot)) {
            Note made = {kind: NoteKind.noGenes, item: inventory.slots[slot].item};
            post(made);
            return false;
        } else if (crafts.length == MOST_CRAFTS) {
            post(NoteKind.queueFull);
            return false;
        } else {
            Stack pressed = inventory.slots[slot].front();
            crafts.append(Crafting(Taken.init, productOf(pressed.item.block, pressed.genes.value), syntheses()[rule.value].time, rule.value, CraftKind.synthesis, Readiness.pending, pressed));
            return true;
        }
    }

    bool craft(uint recipe) {
        Inventory stock = projected(inventory, crafts.slice());
        Array!uint plan;
        Shortfall shortfall = planRecipe(stock, recipe, 1, plan, 0, knowledge());
        bool queued = !isRepeatedUpgrade(recipe) && shortfall.count == 0 && crafts.length + plan.length <= MOST_CRAFTS;
        if (isRepeatedUpgrade(recipe)) {
            Note made = {kind: NoteKind.upgradeQueued, label: upgrades()[recipes()[recipe].upgrade.id].title};
            post(made);
        } else if (shortfall.count > 0) {
            Note made = {kind: NoteKind.missingIngredients, label: shortfall.label, amount: shortfall.count};
            post(made);
        } else if (!queued) {
            post(NoteKind.queueFull);
        } else {
            foreach (index; plan.slice()) {
                crafts.append(Crafting(Taken.init, Molecule.init, recipes()[index].time, index, CraftKind.recipe, Readiness.pending));
            }
        }
        plan.release();
        return queued;
    }

    bool synthesize(Synthesis synthesis) {
        if (!chosenCompound.exists) {
            return false;
        } else if (crafts.length == MOST_CRAFTS) {
            post(NoteKind.queueFull);
            return false;
        } else {
            Molecule molecule = compounds.ptr[chosenCompound.value].molecule;
            Maybe!Molecule product = synthesized(molecule, synthesis);
            if (!product.exists || (!isPressing(synthesis.id) && product.value == molecule)) {
                Note made = {kind: NoteKind.unchanged, molecule: molecule};
                post(made);
                return false;
            } else {
                crafts.append(Crafting(Taken.init, molecule, syntheses()[synthesis.id].time, synthesis.id, CraftKind.synthesis, Readiness.pending));
                return true;
            }
        }
    }

    void cancelCraft(uint index) {
        if (index < crafts.length) {
            Crafting crafting = crafts.ptr[index];
            if (crafting.started == Readiness.ready) {
                final switch (crafting.kind) {
                    case CraftKind.recipe:
                        inventory.returnIngredients(recipes()[crafting.index], crafting.taken);
                        break;
                    case CraftKind.synthesis:
                        refundSynthesis(crafting);
                        break;
                }
            }
            removeCraft(index);
        }
    }

    Maybe!Material materialAt(ChunkId chunk, uint cell) const {
        MaybeIndex!uint slot = world.graph.slotOf(chunk.node);
        if (!slot.exists || world.graph.chunks.at(ChunkSlot(slot.value, chunk.corner)).state != ChunkState.populated) {
            return Maybe!Material.init;
        } else {
            return Maybe!Material.of(world.graph.chunks.at(ChunkSlot(slot.value, chunk.corner)).voxels.at(cell));
        }
    }

    bool isNearStation(Station station) const {
        if (!usedStations[station.id].exists) {
            return false;
        } else {
            Beacon spot = usedStations[station.id].value;
            Maybe!Material there = materialAt(spot.chunk, spot.cell);
            return there.exists && there.value == stations()[station.id].block && !(sightingOf(spot).distance > STATION_REACH);
        }
    }

    bool isStationReady(Station station) const {
        return station == HAND || rules == Rules.creative || isNearStation(station);
    }

    bool hasEffect(Effect effect) const {
        size_t index = 0;
        while (index < upgrades().length && !(upgrades()[index].effect == effect && owned.has(cast(uint) index))) {
            index += 1;
        }
        return index < upgrades().length;
    }

    bool hasAssay() const {
        return rules == Rules.creative || hasEffect(Effect.assay);
    }

    bool isKnownProduct(Molecule molecule) const {
        return hasAssay() || compoundIndexOf(molecule).exists;
    }

    MaybeIndex!uint compoundIndexOf(Molecule molecule) const {
        uint index = 0;
        while (index < compounds.length && compounds.ptr[index].molecule != molecule) {
            index += 1;
        }
        if (index < compounds.length) {
            return MaybeIndex!uint.of(index);
        } else {
            return MaybeIndex!uint.init;
        }
    }

    bool canStart(ref const Crafting crafting) const {
        final switch (crafting.kind) {
            case CraftKind.recipe:
                return inventory.canCraft(recipes()[crafting.index]);
            case CraftKind.synthesis:
                MaybeIndex!uint found = compoundIndexOf(crafting.molecule);
                const(SynthesisRule)* rule = &syntheses()[crafting.index];
                bool hasReagent = rule.reagent.kind == ItemKind.nothing || inventory.countOf(rule.reagent) > 0;
                if (isExtracting(crafting.index)) {
                    return inventory.countOfKind(crafting.pressed) > 0;
                } else if (!found.exists || !hasReagent) {
                    return false;
                } else if (isPressing(crafting.index)) {
                    return compounds.ptr[found.value].raw >= RAW_PER_DOSE;
                } else {
                    return compounds.ptr[found.value].doses >= 1;
                }
        }
    }

    bool isWorkable(ref const Crafting crafting) const {
        return isStationReady(stationOf(crafting)) && (crafting.started == Readiness.ready || canStart(crafting));
    }

    void start(ref Crafting crafting) {
        final switch (crafting.kind) {
            case CraftKind.recipe:
                crafting.taken = inventory.takeIngredients(recipes()[crafting.index]).value;
                break;
            case CraftKind.synthesis:
                startSynthesis(crafting);
                break;
        }
        crafting.started = Readiness.ready;
    }

    void startSynthesis(ref const Crafting crafting) {
        const(SynthesisRule)* rule = &syntheses()[crafting.index];
        if (rule.reagent.kind != ItemKind.nothing) {
            inventory.spend(rule.reagent, 1);
        }
        if (isExtracting(crafting.index)) {
            inventory.spendKind(crafting.pressed);
        } else if (isPressing(crafting.index)) {
            compounds.ptr[compoundIndexOf(crafting.molecule).value].raw -= RAW_PER_DOSE;
        } else {
            compounds.ptr[compoundIndexOf(crafting.molecule).value].doses -= 1;
        }
    }

    void refundSynthesis(Crafting crafting) {
        const(SynthesisRule)* rule = &syntheses()[crafting.index];
        if (rule.reagent.kind != ItemKind.nothing) {
            store(Stack(rule.reagent, 1));
        }
        if (isExtracting(crafting.index)) {
            store(crafting.pressed);
        } else if (isPressing(crafting.index)) {
            keepCompound(crafting.molecule, RAW_PER_DOSE, 0);
        } else {
            keepCompound(crafting.molecule, 0, 1);
        }
    }

    void finish(Crafting crafting) {
        learnFromWorking(stationOf(crafting));
        final switch (crafting.kind) {
            case CraftKind.recipe:
                const(Recipe)* recipe = &recipes()[crafting.index];
                final switch (recipe.product) {
                    case Product.item:
                        store(Stack(recipe.made, recipe.yield));
                        Note made = {kind: NoteKind.crafted, item: recipe.made, amount: recipe.yield};
                        post(made);
                        break;
                    case Product.upgrade:
                        owned.set(recipe.upgrade.id);
                        assayAll();
                        sortLiving();
                        Note granted = {kind: NoteKind.upgraded, label: upgrades()[recipe.upgrade.id].title};
                        post(granted);
                        break;
                }
                happen(Event.crafted, recipe.name);
                break;
            case CraftKind.synthesis:
                finishSynthesis(crafting);
                happen(Event.crafted, syntheses()[crafting.index].name);
                break;
        }
    }

    void finishSynthesis(ref const Crafting crafting) {
        if (isExtracting(crafting.index)) {
            keepCompound(crafting.molecule, HARVEST_RAW, 0);
            Note made = {kind: NoteKind.extracted, item: crafting.pressed.item, molecule: crafting.molecule, amount: HARVEST_RAW};
            post(made);
        } else {
            Molecule product = synthesized(crafting.molecule, Synthesis(cast(ubyte) crafting.index)).value;
            keepCompound(product, 0, 1);
            Note made = {kind: NoteKind.synthesized, molecule: product};
            post(made);
        }
    }

    MaybeIndex!uint activeCraft() const {
        uint index = 0;
        while (index < crafts.length && !isWorkable(crafts.ptr[index])) {
            index += 1;
        }
        if (index < crafts.length) {
            return MaybeIndex!uint.of(index);
        } else {
            return MaybeIndex!uint.init;
        }
    }

    void advanceCrafting(Time dt) {
        MaybeIndex!uint active = activeCraft();
        if (active.exists) {
            uint index = active.value;
            Crafting* crafting = &crafts.ptr[index];
            if (crafting.started == Readiness.pending) {
                start(*crafting);
            }
            crafting.left = crafting.left - dt;
            if (crafting.left <= Time(0)) {
                Crafting done = *crafting;
                removeCraft(index);
                finish(done);
            }
        }
    }

    void keepCompound(Molecule molecule, float raw, float doses) {
        MaybeIndex!uint found = compoundIndexOf(molecule);
        if (!found.exists && compounds.length == MOST_COMPOUNDS) {
            chosenCompound = MaybeIndex!uint.init;
        }
        uint index = compounds.slotFor(molecule);
        compounds.ptr[index].raw += raw;
        compounds.ptr[index].doses += doses;
        if (!found.exists) {
            assay(compounds.ptr[index]);
            sortLiving();
        }
    }

    void assay(ref Compound compound) {
        compound.receptors = 0;
        if (hasAssay()) {
            compound.receptors = cast(uint) lowerOf(organism.receptors.length, cast(size_t) MOST_SCANNED_RECEPTORS);
            foreach (index; 0 .. compound.receptors) {
                Binding binding = organism.cache.bindingOf(organism.receptors.ptr[index].pocket, compound.molecule);
                compound.affinity[index] = binding.affinity;
                float efficacy = 0;
                foreach (transducer; binding.efficacy) {
                    efficacy += transducer.value;
                }
                compound.efficacy[index] = Ratio(efficacy);
            }
        }
    }

    void assayAll() {
        foreach (ref compound; compounds.slice()) {
            assay(compound);
        }
    }

    bool takeDose(uint routeIndex) {
        const(DoseRoute)* chosen = &doseRoutes()[routeIndex];
        if (!chosenCompound.exists || compounds.ptr[chosenCompound.value].doses < 1) {
            post(NoteKind.noDose);
            return false;
        } else if (!organism.body.hasRoomFor(compounds.ptr[chosenCompound.value].molecule)) {
            post(NoteKind.bodyFull);
            return false;
        } else if (chosen.device.kind != ItemKind.nothing && inventory.countOf(chosen.device) < higherOf(chosen.uses, 1u)) {
            Note made = {kind: NoteKind.needsDevice, item: chosen.device};
            post(made);
            return false;
        } else {
            if (chosen.device.kind != ItemKind.nothing && chosen.uses > 0) {
                inventory.spend(chosen.device, chosen.uses);
            }
            Compound* compound = &compounds.ptr[chosenCompound.value];
            organism.dose(Dose(compound.molecule, DOSE_SIZE, chosen.route));
            compound.doses -= 1;
            Note made = {kind: NoteKind.dosed, molecule: compound.molecule, route: chosen.route};
            post(made);
            happen(Event.dosed, chosen.name);
            return true;
        }
    }

    void removeCraft(size_t index) {
        foreach (later; index + 1 .. crafts.length) {
            crafts.ptr[later - 1] = crafts.ptr[later];
        }
        crafts.length -= 1;
    }

    void clickSlot(uint slot, Click click) {
        Stack* stack = &inventory.slots[slot];
        final switch (click) {
            case Click.primary:
                uint held = carried.count;
                if (!carried.isEmpty && !stack.isEmpty) {
                    carried.pourInto(*stack);
                }
                if (carried.count == held) {
                    Stack swapped = *stack;
                    *stack = carried;
                    carried = swapped;
                }
                break;
            case Click.secondary:
                if (carried.isEmpty && !stack.isEmpty) {
                    carried = stack.draw((stack.count + 1) / 2);
                } else if (!carried.isEmpty) {
                    Stack one = carried.draw(1);
                    one.pourInto(*stack);
                    one.pourInto(carried);
                }
                break;
            case Click.quick:
                if (!stack.isEmpty) {
                    Section other = Section.hotbar;
                    if (sectionOf(slot) == Section.hotbar) {
                        other = Section.pack;
                    }
                    Stack moving = *stack;
                    *stack = Stack.init;
                    inventory.pour(other, moving);
                    *stack = moving;
                }
                break;
        }
    }

    void takeFromCatalog(Item item, Click click) {
        uint count = STACK_LIMIT;
        if (click == Click.secondary) {
            count = 1;
        }
        if (!carried.isEmpty && !carried.isSameKind(Stack(item, count))) {
            store(carried);
        }
        carried = Stack(item, count);
    }

    void openScreen(Screen chosen) {
        closeScreen();
        screen = chosen;
        sheet = Sheet.items;
        worlds.picked = MaybeIndex!uint.init;
        worlds.deleting = Deleting.idle;
        mining = Maybe!Mining.init;
    }

    void toggle(Screen chosen) {
        if (screen == Screen.none) {
            openScreen(chosen);
        } else {
            closeScreen();
        }
    }

    void closeScreen() {
        if (!carried.isEmpty) {
            store(carried);
            carried = Stack.init;
        }
        screen = Screen.none;
    }

    void post(Note made) {
        if (notes.length == MOST_NOTES) {
            foreach (index; 1 .. notes.length) {
                notes.ptr[index - 1] = notes.ptr[index];
            }
            notes.length -= 1;
        }
        Note stamped = made;
        stamped.at = time;
        notes.append(stamped);
    }

    void post(NoteKind kind) {
        Note made = {kind: kind};
        post(made);
    }

    void layThread() {
        thread.lay(characterState.position, traveled);
        if (explored.find(characterState.position.node) is null) {
            explored.insert(characterState.position.node, Present.init);
        }
    }

    bool isExplored(NodeId node) const {
        return explored.find(node) !is null;
    }

    void happen(Event event, const(char)[] subject) {
        Play play = Play(&this, &readApi, &playGive, &playLearn, &playNote);
        fire(&play, Happening(subject, event));
    }

    bool breakBlock() {
        Maybe!GraphCastHit hit = world.castCenterRay();
        Maybe!Material broken = world.targetMaterial();
        Maybe!LivingGenes genes = livingGenesAt(hit);
        bool done = world.breakBlock();
        if (done) {
            if (genes.exists) {
                harvest(genes.value, world.graph.slotOf(hit.value.chunk.node).value);
            } else {
                store(Stack(itemOf(broken.value), 1));
            }
            learnFromBreaking(broken.value);
            happen(Event.broke, materialNames.ptr[broken.value.id]);
            Cell coords = hit.value.voxelCoords;
            uint cell = cast(uint) cellIndex(world.graph.layout.dimension, coords.x, coords.y, coords.z);
            if (broken.value == roleBlock(Role.beacon)) {
                removeBeacon(hit.value.chunk, cell);
            } else if (broken.value == roleBlock(Role.collector) || isLiving(broken.value)) {
                world.graph.edits.dropRecord(hit.value.chunk, cell);
            }
        }
        return done;
    }

    void harvest(LivingGenes genes, uint slot) {
        uint count = 1;
        final switch (genes.growth) {
            case Ripeness.wild:
                break;
            case Ripeness.growing:
                Note unripe = {kind: NoteKind.unripeHarvest, material: genes.species};
                post(unripe);
                break;
            case Ripeness.ripe:
                count += cast(uint) roundf(MOST_EXTRA_YIELD * expressionIn(genes.species, world.graph.stateAt(slot).climate.climate()));
                Note made = {kind: NoteKind.harvested, material: genes.species, amount: count};
                post(made);
                break;
        }
        store(Stack.ofLiving(itemOf(genes.species), count, genes.genes, Sorting.unsorted));
    }

    Maybe!LivingGenes livingGenesAt(Maybe!GraphCastHit hit) {
        if (!hit.exists) {
            return Maybe!LivingGenes.init;
        } else {
            Cell coords = hit.value.voxelCoords;
            uint cell = cast(uint) cellIndex(world.graph.layout.dimension, coords.x, coords.y, coords.z);
            ChunkSlot slot = ChunkSlot(world.graph.slotOf(hit.value.chunk.node).value, hit.value.chunk.corner);
            Material species = world.graph.chunks.at(slot).voxels.at(cell);
            BlockRecord* record = world.graph.edits.recordAt(hit.value.chunk, cell);
            if (!isLiving(species) || !world.graph.nodeAt(slot.slot).hasState) {
                return Maybe!LivingGenes.init;
            } else if (record !is null && record.kind == RecordKind.planted) {
                Time left = GROWN_SECONDS - (time - record.placed);
                Ripeness growth = Ripeness.growing;
                if (left <= Time(0)) {
                    growth = Ripeness.ripe;
                    left = Time(0);
                }
                return Maybe!LivingGenes.of(LivingGenes(record.genes, left, species, growth));
            } else if (record !is null && record.kind == RecordKind.placedLiving) {
                return Maybe!LivingGenes.of(LivingGenes(record.genes, Time(0), species, Ripeness.wild));
            } else {
                return Maybe!LivingGenes.of(LivingGenes(wildGenesAt(hit.value.chunk, cell, species), Time(0), species, Ripeness.wild));
            }
        }
    }

    WildGenes wildGenesAt(ChunkId chunk, uint cell, Material species) const {
        WildGenes genes = speciesGenes(world.graph.stateAt(world.graph.slotOf(chunk.node).value).wild, nameHashOf(species));
        if (isPlant(species)) {
            return cellGenes(genes, chunk.node.spice() ^ (cast(ulong) chunk.corner << CELL_HASH_SHIFT) ^ cell);
        } else {
            return genes;
        }
    }

    Maybe!LivingReading livingReadingAt(Maybe!GraphCastHit hit) {
        Maybe!LivingGenes genes = livingGenesAt(hit);
        if (!genes.exists) {
            return Maybe!LivingReading.init;
        } else {
            uint slot = world.graph.slotOf(hit.value.chunk.node).value;
            LivingReading reading;
            reading.product = productOf(genes.value.species, genes.value.genes);
            reading.left = genes.value.left;
            reading.fit = Ratio(expressionIn(genes.value.species, world.graph.stateAt(slot).climate.climate()));
            reading.species = genes.value.species;
            reading.growth = genes.value.growth;
            if (hasAssay()) {
                reading.receptors = cast(uint) lowerOf(organism.receptors.length, cast(size_t) MOST_SCANNED_RECEPTORS);
            }
            foreach (index; 0 .. reading.receptors) {
                Binding binding = organism.cache.bindingOf(organism.receptors.ptr[index].pocket, reading.product);
                reading.affinity[index] = binding.affinity;
                float efficacy = 0;
                foreach (transducer; binding.efficacy) {
                    efficacy += transducer.value;
                }
                reading.efficacy[index] = Ratio(efficacy);
            }
            return Maybe!LivingReading.of(reading);
        }
    }

    Ratio mutationOddsAt(uint slot) const {
        float odds = BASE_BREEDING_MUTATION;
        if (world.graph.nodeAt(slot).hasState) {
            odds += ASH_BREEDING_MUTATION * airOf(world.graph.stateAt(slot).climate.climate()).fractions[ASH_GAS].value;
        }
        if (inventory.countOf(roleItem(Role.mutagen)) > 0) {
            odds += MUTAGEN_BREEDING_MUTATION;
        }
        return Ratio(odds);
    }

    Ratio[GAS_COUNT] gatheredBy(ref const BlockRecord record, uint slot) const {
        Ratio[GAS_COUNT] gathered;
        if (world.graph.nodeAt(slot).hasState) {
            float elapsed = lowerOf((time - record.placed).value, MOST_COLLECTED_SECONDS.value);
            AirMix air = airOf(world.graph.stateAt(slot).climate.climate());
            foreach (gas; 0 .. GAS_COUNT) {
                gathered[gas] = Ratio(air.fractions[gas].value * COLLECTION_RATE.value * elapsed);
            }
        }
        return gathered;
    }

    void updateAim() {
        Maybe!GraphCastHit hit = world.castCenterRay();
        Maybe!Material target = world.targetMaterial();
        aim = Aim.init;
        if (target.exists) {
            aim.material = target.value;
            aim.kind = AimKind.block;
            uint slot = world.graph.slotOf(hit.value.chunk.node).value;
            Cell coords = hit.value.voxelCoords;
            BlockRecord* record = world.graph.edits.recordAt(hit.value.chunk, cast(uint) cellIndex(world.graph.layout.dimension, coords.x, coords.y, coords.z));
            Maybe!LivingReading reading = livingReadingAt(hit);
            if (reading.exists) {
                aim.living = reading.value;
                aim.kind = AimKind.living;
            } else if (stationOf(target.value).exists) {
                aim.kind = AimKind.station;
            } else if (target.value == roleBlock(Role.collector) && record !is null) {
                aim.gathered = gatheredBy(*record, slot);
                aim.kind = AimKind.collector;
            } else if (target.value == roleBlock(Role.bench)) {
                aim.mutation = mutationOddsAt(slot);
                aim.kind = AimKind.bench;
            }
        }
    }

    bool isBreedable(uint slot) const {
        Stack stack = inventory.slots[slot];
        return !stack.isEmpty && isPlantItem(stack.item) && stack.genes.exists;
    }

    bool isChosenBreedable(uint index) const {
        return chosen[index].exists && isBreedable(chosen[index].value);
    }

    void chooseFirstPlants() {
        chosen[] = MaybeIndex!uint.init;
        uint marked = 0;
        foreach (slot; 0 .. SLOT_COUNT) {
            if (marked < CHOSEN_PLANTS && isBreedable(slot)) {
                chosen[marked] = MaybeIndex!uint.of(slot);
                marked += 1;
            }
        }
    }

    void choose(uint slot) {
        MaybeIndex!uint picked = MaybeIndex!uint.of(slot);
        if (slot < SLOT_COUNT && isBreedable(slot)) {
            if (chosen[0] == picked) {
                chosen[0] = chosen[1];
                chosen[1] = MaybeIndex!uint.init;
            } else if (chosen[1] == picked) {
                chosen[1] = MaybeIndex!uint.init;
            } else if (!chosen[0].exists) {
                chosen[0] = picked;
            } else {
                chosen[1] = picked;
            }
        }
    }

    bool crossChosen() {
        MaybeIndex!uint bench = world.graph.slotOf(machine.node);
        if (!isChosenBreedable(0) || !isChosenBreedable(1) || !bench.exists) {
            post(NoteKind.needPlants);
            return false;
        } else {
            Ratio odds = mutationOddsAt(bench.value);
            NoteKind kind = NoteKind.crossed;
            if (inventory.spend(roleItem(Role.mutagen), 1)) {
                kind = NoteKind.crossedWithMutagen;
            }
            Stack first = inventory.slots[chosen[0].value];
            Stack second = inventory.slots[chosen[1].value];
            ulong salt = BREEDING_SALT ^ (cast(ulong)(time.value * MILLISECONDS_PER_SECOND) << 8) ^ first.count;
            inventory.spendFrom(chosen[0].value);
            store(Stack.ofLiving(first.item, 1, crossed(first.genes.value, second.genes.value, salt, odds.value), Sorting.unsorted));
            Note made = {kind: kind, material: first.item.block, amount: odds.value, item: roleItem(Role.mutagen)};
            post(made);
            return true;
        }
    }

    bool spliceChosen() {
        if (!isChosenBreedable(0)) {
            post(NoteKind.noPlant);
            return false;
        } else if (organism.genome.count == MOST_GENES) {
            post(NoteKind.genomeFull);
            return false;
        } else {
            Stack source = inventory.slots[chosen[0].value];
            inventory.spendFrom(chosen[0].value);
            Genome genome = organism.genome;
            Enzyme enzyme = enzymeFromSeed(source.genes.value.seeds[FIRST_ENZYME_GENE]);
            genome.add(enzymeGene(enzyme, Ratio(1)));
            Note made = {kind: NoteKind.spliced, material: source.item.block, operation: enzyme.operation};
            post(made);
            Body body = organism.body;
            Signaling signaling = organism.signaling;
            organism.release();
            organism = Organism.make(genome);
            organism.body = body;
            organism.signaling = signaling;
            assayAll();
            return true;
        }
    }

    bool interact() {
        Maybe!GraphCastHit hit = world.castCenterRay();
        Maybe!Material target = world.targetMaterial();
        if (target.exists && (target.value == roleBlock(Role.bench) || target.value == roleBlock(Role.collector) || stationOf(target.value).exists)) {
            Cell coords = hit.value.voxelCoords;
            machine = hit.value.chunk;
            machineCell = cast(uint) cellIndex(world.graph.layout.dimension, coords.x, coords.y, coords.z);
            if (target.value == roleBlock(Role.bench)) {
                chooseFirstPlants();
                openScreen(Screen.bench);
            } else if (target.value == roleBlock(Role.collector)) {
                openScreen(Screen.collector);
            } else {
                workstation = stationOf(target.value).value;
                usedStations[workstation.id] = Maybe!Beacon.of(Beacon(machine, machineCell));
                openScreen(Screen.station);
            }
            return true;
        } else {
            return placeBlock();
        }
    }

    void apply(UiAction action, Click click) {
        final switch (action.kind) {
            case UiKind.slot:
                clickSlot(action.index, click);
                break;
            case UiKind.craft:
                craft(action.index);
                break;
            case UiKind.cancelCraft:
                cancelCraft(action.index);
                break;
            case UiKind.sheet:
                sheet = cast(Sheet) action.index;
                break;
            case UiKind.choosePlant:
                choose(action.index);
                break;
            case UiKind.pressLiving:
                pressLiving(action.index);
                break;
            case UiKind.cross:
                crossChosen();
                break;
            case UiKind.splice:
                spliceChosen();
                break;
            case UiKind.breathe:
                breatheMachine();
                break;
            case UiKind.close:
                closeScreen();
                break;
            case UiKind.chooseCompound:
                if (action.index < compounds.length) {
                    chosenCompound = MaybeIndex!uint.of(action.index);
                }
                break;
            case UiKind.synthesize:
                synthesize(Synthesis(cast(ubyte) action.index));
                break;
            case UiKind.takeDose:
                takeDose(action.index);
                break;
            case UiKind.takeItem:
                takeFromCatalog(Item(cast(ushort) action.index), click);
                break;
            case UiKind.open:
                openScreen(cast(Screen) action.index);
                break;
            case UiKind.pickWorld:
                worlds.picked = MaybeIndex!uint.of(action.index);
                worlds.deleting = Deleting.idle;
                break;
            case UiKind.askDelete:
                worlds.deleting = Deleting.asked;
                break;
            case UiKind.rebind:
            case UiKind.resetBindings:
            case UiKind.playWorld:
            case UiKind.deleteWorld:
                break;
        }
    }

    bool breatheMachine() {
        BlockRecord* record = world.graph.edits.recordAt(machine, machineCell);
        MaybeIndex!uint slot = world.graph.slotOf(machine.node);
        if (record is null || !slot.exists || !world.graph.nodeAt(slot.value).hasState) {
            return false;
        } else {
            Ratio[GAS_COUNT] gathered = gatheredBy(*record, slot.value);
            float total = 0;
            foreach (gas; 0 .. GAS_COUNT) {
                organism.dose(Dose(GAS_MOLECULES[gas], gathered[gas], Route.inhaled));
                total += gathered[gas].value;
            }
            record.placed = time;
            Note made = {kind: NoteKind.breathed, amount: total, route: Route.inhaled};
            post(made);
            return true;
        }
    }

    Ratio machineFilled() {
        BlockRecord* record = world.graph.edits.recordAt(machine, machineCell);
        if (record is null) {
            return Ratio(0);
        } else {
            return Ratio(lowerOf((time - record.placed).value, MOST_COLLECTED_SECONDS.value) / MOST_COLLECTED_SECONDS.value);
        }
    }

    Ratio[GAS_COUNT] machineGathered() {
        BlockRecord* record = world.graph.edits.recordAt(machine, machineCell);
        MaybeIndex!uint slot = world.graph.slotOf(machine.node);
        if (record is null || !slot.exists) {
            Ratio[GAS_COUNT] nothing;
            return nothing;
        } else {
            return gatheredBy(*record, slot.value);
        }
    }

    Maybe!Eating startEating(Stack food) {
        if (food.isEmpty || !isLivingItem(food.item)) {
            post(NoteKind.nothingToEat);
            return Maybe!Eating.init;
        } else if (!food.genes.exists) {
            Note made = {kind: NoteKind.noGenes, item: food.item};
            post(made);
            return Maybe!Eating.init;
        } else if (!organism.body.hasRoomFor(productOf(food.item.block, food.genes.value))) {
            post(NoteKind.bodyFull);
            return Maybe!Eating.init;
        } else {
            return Maybe!Eating.of(Eating(food, Time(0), inventory.selected));
        }
    }

    void chew(Time dt, KeyStroke press) {
        Stack food = inventory.slots[inventory.selected];
        if (eating.exists && eating.value.slot == inventory.selected && !food.isEmpty && food.isSameKind(eating.value.food)) {
            eating.value.spent = eating.value.spent + dt;
            if (eating.value.spent >= EAT_TIME) {
                swallow(food);
                eating = Maybe!Eating.init;
            }
        } else if (press == KeyStroke.first) {
            eating = startEating(food);
        } else {
            eating = Maybe!Eating.init;
        }
    }

    void swallow(Stack food) {
        inventory.spendFrom(inventory.selected);
        Molecule product = productOf(food.item.block, food.genes.value);
        NoteKind kind = NoteKind.ateUnknown;
        if (isKnownProduct(product)) {
            kind = NoteKind.ate;
        }
        organism.dose(Dose(product, PLANT_DOSE, Route.ingested));
        Note made = {kind: kind, item: food.item, amount: PLANT_DOSE.value, route: Route.ingested, molecule: product};
        post(made);
    }

    Ratio eatingShare() const {
        if (!eating.exists) {
            return Ratio(0);
        } else {
            return Ratio(lowerOf((eating.value.spent / EAT_TIME).value, 1.0f));
        }
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
        Stack stack = inventory.slots[inventory.selected];
        Material held = placedBlock(stack.item);
        if (placement.exists && held != Material.none && world.isEmptyAt(placement.value) && !isBodyOverlapping(ChunkSlot(world.graph.slotOf(placement.value.chunk.node).value, placement.value.chunk.corner), placement.value)) {
            bool done = world.setVoxel(placement.value.chunk, placement.value.coords, held);
            if (done) {
                inventory.spendHeld();
                Cell coords = placement.value.coords;
                uint cell = cast(uint) cellIndex(world.graph.layout.dimension, coords.x, coords.y, coords.z);
                if (held == roleBlock(Role.beacon)) {
                    addBeacon(placement.value.chunk, cell);
                } else if (held == roleBlock(Role.collector)) {
                    world.graph.edits.keepRecord(placement.value.chunk, BlockRecord(WildGenes.init, time, cell, RecordKind.collector));
                } else if (isLiving(held)) {
                    placeLiving(placement.value.chunk, cell, stack);
                }
                happen(Event.placed, materialNames.ptr[held.id]);
            }
            return done;
        } else {
            return false;
        }
    }

    void placeLiving(ChunkId chunk, uint cell, Stack stack) {
        Material block = stack.item.block;
        NoteKind kind = NoteKind.plantedWild;
        WildGenes genes = wildGenesAt(chunk, cell, block);
        if (stack.genes.exists) {
            genes = stack.genes.value;
            kind = NoteKind.planted;
        }
        if (isPlant(block)) {
            world.graph.edits.keepRecord(chunk, BlockRecord(genes, time, cell, RecordKind.planted));
            Note made = {kind: kind, material: block, amount: GROWN_SECONDS.value};
            post(made);
        } else {
            world.graph.edits.keepRecord(chunk, BlockRecord(genes, time, cell, RecordKind.placedLiving));
        }
    }

    bool isBodyOverlapping(ChunkSlot slot, Placement placement) const {
        Vec3!float[MOST_BODY_SECTIONS] storage;
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
        MaterialSet before = reveal.revealed;
        reveal.update(perception);
        foreach (index, ref family; families.slice()) {
            bool was = !family.members.within(before).isEmpty;
            bool now = !family.members.within(reveal.revealed).isEmpty;
            if (now && !was) {
                Note made = {kind: NoteKind.revealed, family: cast(uint) index};
                post(made);
            } else if (was && !now) {
                Note made = {kind: NoteKind.faded, family: cast(uint) index};
                post(made);
            }
        }
        foreach (ref family; families.slice()) {
            if (!family.members.within(reveal.revealed).isEmpty && family.members.within(reveal.touchable).isEmpty && !isBodyInside(family.members)) {
                reveal.touchable = reveal.touchable.joined(family.members);
            }
        }
    }

    bool isBodyInside(MaterialSet materials) const {
        Vec3!float[MOST_BODY_SECTIONS] storage;
        MaterialOverlap overlap = MaterialOverlap(sectionCenters(bodyCapsule(), ZERO_VECTOR, storage[]), materials, character.radius.value);
        visitCells(world.graph, characterState.position, regionReach(character), overlap);
        return overlap.overlaps > 0;
    }

    void perceive(uint chosen) {
        preset = chosen;
        perception = felt(presets.ptr[chosen].perception, organism.signaling.signals[]);
        settleReveal();
        updateView();
    }

    void doseNext() {
        if (starterDoses.length == 0) {
            Note none = {kind: NoteKind.noTestDose};
            post(none);
        } else {
            Dose given = starterDoses.ptr[doses % starterDoses.length];
            organism.dose(given);
            doses += 1;
            Note made = {kind: NoteKind.dosed, amount: given.amount.value, route: given.route, molecule: given.molecule};
            post(made);
        }
    }

    void nextPreset() {
        perceive(cast(uint)((preset + 1) % presets.length));
    }

    Vec3!float sunInBody() const {
        Vec3!float up = characterState.up;
        Vec3!float side = perpendicularTo(up).rejectAlong(up);
        return up.scaled(SUN_ELEVATION_COSINE).plus(side.scaled(SUN_ELEVATION_SINE / side.magnitude));
    }

    void step(FrameInput given, Time dt) {
        FrameInput input = given;
        if (screen != Screen.none) {
            input = FrameInput.init;
        }
        look(input.yaw, input.pitch);
        float moveX = axisValue(input.held, Key.right) - axisValue(input.held, Key.left);
        float moveY = axisValue(input.held, Key.up) - axisValue(input.held, Key.down);
        float moveZ = axisValue(input.held, Key.back) - axisValue(input.held, Key.forward);
        organism.advance(dt);
        if (input.held.has(Key.eat)) {
            chew(dt, strokeOf(input.held, Key.eat));
        } else {
            eating = Maybe!Eating.init;
        }
        perception = felt(presets.ptr[preset].perception, organism.signaling.signals[]);
        settleReveal();
        CharacterConfig effective = character.effectiveFor(perception);
        effective.solid = bodySolid();
        Stepped stepped = runCharacter(effective, characterInput(moveX, moveY, moveZ, jumpFrom(input.held)), dt);
        lastHeld = input.held;
        traveled = traveled + stepped.traveled;
        layThread();
        altitude = ensureAltitude();
        followBody();
        levelCompass();
        updateView();
        stepThrown(dt);
        updateAim();
        if (input.held.has(Key.mine)) {
            mine(dt);
        } else {
            mining = Maybe!Mining.init;
        }
        if (screen == Screen.collector) {
            machineAir = machineGathered();
            machineFill = machineFilled();
        }
        advanceCrafting(dt);
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

    KeyStroke strokeOf(Flags!Key held, Key key) const {
        if (held.has(key) && lastHeld.has(key)) {
            return KeyStroke.repeated;
        } else {
            return KeyStroke.first;
        }
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
