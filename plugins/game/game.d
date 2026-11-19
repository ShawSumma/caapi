module plugins.game.game;

import core.stdc.math : acoshf, atan2f, atanhf, ceilf, coshf, fabs, fabsf, floorf, sinhf, sqrt, tanhf;
import base.array : Array;
import base.flags : Readiness;
import base.hashmap : FIBONACCI_MULTIPLIER, HashMap, Present;
import base.maybe : Maybe, MaybeIndex;
import base.numbers : higherOf, lowerOf;
import base.splitmix : SplitMix;
import base.units : Acceleration, Angle, AngularSpeed, Blocks, Length, Rate, Ratio, Speed, Time;
import base.vector3 : Vec3, ZERO_VECTOR, cross, dot, magnitude, minus, negated, plus, rejectAlong, scaled;
import client.arrivals : generateNow;
import client.camera : CAMERA_FORWARD, Camera;
import client.streaming : Pacing;
import client.world : LocalWorld, Placement;
import common.character.controller : CharacterInput, CharacterState, Footing, Jump, MovementMode, Mover, Slide, Stepped, movedBy, perpendicularTo, regionReach;
import common.character.features : CellOverlap, CellRange, Features, LocalFrame, MaterialOverlap, RequiredChunks, gridPoint, isInsideGrid, visitCells;
import common.character.sweep : Capsule, sectionCenters;
import common.content.content : fire, keptText, readApi;
import common.edits : BlockRecord, RecordTag;
import common.graph : Graph, NodeId;
import common.material : MaterialSet, families, fluids, has, isEmpty, isHidden, joined, materialCount, materialNames, plainSolid, within;
import common.node : ChunkId, ChunkSlot, ChunkState, cellIndex;
import common.perception : Channel, Perception, Reveal, effectiveFor, leveled, presets, viewOf;
import common.position : Position;
import common.raycast.graph : GraphCastHit;
import common.settings : CHUNK_DIMENSION, CharacterConfig;
import common.traversal : NearbyNode, NearbyScratch;
import common.worldgen.blueprint : RouteStop;
import common.worldgen.generation : NodeState, Worldgen;
import common.worldgen.horospheres : Gravity, ensureGravityAt, ensureGravityKnown, gravityAt, isBelowAbyss, isBelowUnderside, isGravityKnown;
import common.worldgen.lineage : Lineage;
import common.worldgen.spawn : collectChunksNear, findSpawnPosition;
import common.worldgen.structure : SiteFrame, columnPoint, edgeCells, edgeLength, forwarded, moveToLevel, nodeToNode, rootSite, sitePlacement, siteToNode, spawnBefore, turnSite;
import geometry.cube : Cell;
import geometry.honeycomb : CORNER_COUNT, Corner, Face, cornerToNode, cubeToNode, nodeToCorner;
import geometry.lorentz : Motion, Point, Vec4;
import plugins.api.api : Material, Turn;
import plugins.api.binding : settingsOf;
import plugins.api.content : Happening;
import plugins.api.flags : Flags;
import plugins.crafting.crafting : HAND, IdSet, Insight, Job, Product, Recipe, Shortfall, Station, Step, Taken, Trigger, Upgrade, canCraft, insights, jobFor, planRecipe, recipes, stationOf, stations, takeIngredients, upgrades;
import plugins.crafting.inventory : Inventory, SLOT_COUNT, STACK_LIMIT, Section, Stack, isAmong, isSameKind, sectionOf;
import plugins.crafting.items : Item, ItemKind, itemNamed, itemOf, placedBlock;
import plugins.game.bindings : Rules;
import plugins.game.config : ClientConfig, DEFAULT_THREAD_BEADS, THREAD_SPACING, pitchSign;
import plugins.game.mining : breakSeconds, miningTiers, toolTiers;
import plugins.game.play : BROKE, CRAFTED, PLACED, Play, WOKE;
import plugins.game.plugin : NAME;
import plugins.game.roles : beaconBlock;

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
enum size_t MOST_NOTES = 4;
enum Time NOTE_SECONDS = Time(5);
enum Time CREATIVE_BREAK = Time(0.15f);
enum Time HAND_BREAK = Time(1.5f);
enum uint MOST_FOOTHOLDS = 9;
enum size_t NOTE_CAPACITY = 128;
enum size_t MOST_GUESTS = 4;
enum uint FEW_CRAFTS = 3;
enum ulong RUMOR_SALT = 0x52_554D_4F52;
enum uint CORNER_SHIFT = 32;
enum uint MOST_CRAFTS_AT_ONCE = 81;

enum NoteKind : ubyte {
    revealed,
    faded,
    inventoryFull,
    crafted,
    upgraded,
    missingIngredients,
    needsTier,
    upgradeQueued,
    learned,
    told,
    woke,
    written,
}

struct Note {
    Time at;
    float amount = 0;
    const(char)[] label;
    Item item;
    Material material;
    uint family;
    uint code;
    NoteKind kind;
    ubyte length;
    char[NOTE_CAPACITY] text;

    const(char)[] written() const return {
        return text[0 .. length];
    }
}

struct BodySettings {
    float noclipSpeed;
    float flySpeed;
    float walkSpeed;
    float walkResponse;
    float steering;
    float gravity;
    float upTurnRate;
    float leastTurningGravity;
    float jumpHeight;
    float stepHeight;
    float footFriction;
    float skin;
    float radius;
    float height;
    float eyeHeight;
}

CharacterConfig characterOf(BodySettings body) {
    return CharacterConfig(MaterialSet.init, Speed(body.noclipSpeed), Speed(body.flySpeed), Speed(body.walkSpeed), Rate(body.walkResponse), Acceleration(body.steering), Acceleration(body.gravity), AngularSpeed(body.upTurnRate), Ratio(body.leastTurningGravity), Length(body.jumpHeight), Blocks(body.stepHeight), Ratio(body.footFriction), Length(body.skin), Length(body.radius), Length(body.height), Length(body.eyeHeight));
}

enum Length STATION_REACH = Length(0.6f);
enum float MINING_SPEEDUP = 0.4f;

enum size_t MOST_STATIONS = 32;
enum string BARE_HANDS = "bare hands";
enum string UNKNOWN_TOOL = "a tool no recipe makes";

uint requiredTierOf(Material material) {
    return miningTiers.ptr[material.id];
}

uint highestMiningTier() {
    uint highest = 0;
    foreach (tier; toolTiers.slice()) {
        highest = higherOf(highest, tier);
    }
    return highest;
}

const(char)[] toolFor(uint tier) {
    if (tier == 0) {
        return BARE_HANDS;
    } else {
        size_t index = 0;
        while (index < toolTiers.length && toolTiers.ptr[index] != tier) {
            index += 1;
        }
        if (index < toolTiers.length) {
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

enum CraftKind : ubyte {
    recipe,
    work,
}

struct Work {
    const(char)[] function(ref const Crafting crafting) name;
    Station function(ref const Crafting crafting) station;
    Time function(ref const Crafting crafting) time;
    void function(ref Game game, ref const Crafting crafting) finish;
    void function(ref Game game, ref const Crafting crafting) cancel;
    const(char)[] function(ref const Crafting crafting, char[] buffer) label;
}

struct Crafting {
    Taken taken;
    Time left;
    uint index;
    CraftKind kind;
    Readiness started;
    uint job;
    Step step;
    const(Work)* work;
    ulong[2] payload;
    Stack held;
    uint order;
}

Station stationOf(ref const Crafting crafting) {
    final switch (crafting.kind) {
        case CraftKind.recipe:
            return recipes()[crafting.index].station;
        case CraftKind.work:
            return crafting.work.station(crafting);
    }
}

Time timeOf(ref const Crafting crafting) {
    final switch (crafting.kind) {
        case CraftKind.recipe:
            return recipes()[crafting.index].time;
        case CraftKind.work:
            return crafting.work.time(crafting);
    }
}

struct Extension {
    void function(ref Game game) attach;
    void function(ref Game game) detach;
    void function(ref Game game) startOver;
    void function(ref Game game, Time dt) step;
    Perception function(ref const Game game, Perception felt) feel;
    bool function(ref Game game, ChunkId chunk, uint cell, Material broken) broke;
    void function(ref Game game, ChunkId chunk, uint cell, Stack placed) placed;
    bool function(ref Game game, Material target) use;
    void function(ref Game game, ref const GraphCastHit hit, Material target) aim;
    void function(ref Game game, ref const Stack gained) gained;
    void function(ref Game game) upgraded;
    void function(ref Game game) woke;
}

__gshared Array!Extension extensions;

uint extend(Extension extension) {
    assert(extensions.length < MOST_GUESTS);
    extensions.append(extension);
    return cast(uint) extensions.length - 1;
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
    usable,
    readable,
}

bool isReadIn(uint insight, Item item) {
    return insights()[insight].trigger == Trigger.read && item.isAmong(insights()[insight].noticed);
}

uint rumorsIn(Item item) {
    uint count = 0;
    foreach (index; 0 .. insights().length) {
        if (isReadIn(cast(uint) index, item)) {
            count += 1;
        }
    }
    return count;
}

Maybe!Insight rumorAt(Material held, ChunkId chunk, uint cell) {
    Item item = itemOf(held);
    uint count = rumorsIn(item);
    if (count == 0) {
        return Maybe!Insight.init;
    } else {
        ulong place = (cast(ulong) chunk.corner << CORNER_SHIFT) | cell;
        ulong left = SplitMix(chunk.node.spice() ^ RUMOR_SALT ^ ((place + 1) * FIBONACCI_MULTIPLIER)).next() % count;
        uint index = 0;
        while (!(isReadIn(index, item) && left == 0)) {
            if (isReadIn(index, item)) {
                left -= 1;
            }
            index += 1;
        }
        return Maybe!Insight.of(Insight(cast(ubyte) index));
    }
}

enum Screen : ubyte {
    none,
    character,
    machine,
    station,
    journal,
    menu,
    controls,
}

enum Deleting : ubyte {
    idle,
    asked,
}

enum Saving : ubyte {
    enabled,
    refused,
    scene,
}

enum PickKind : ubyte {
    world,
    scene,
}

struct WorldPick {
    uint index;
    PickKind kind;
}

struct WorldMenu {
    IdSet saved;
    Maybe!WorldPick picked;
    WorldPick current;
    Deleting deleting;
    Saving saving;
}

enum Click : ubyte {
    primary,
    secondary,
    quick,
}

uint craftsFor(Click click) {
    final switch (click) {
        case Click.primary:
            return 1;
        case Click.secondary:
            return FEW_CRAFTS;
        case Click.quick:
            return MOST_CRAFTS_AT_ONCE;
    }
}

enum UiKind : ubyte {
    slot,
    craft,
    cancelCraft,
    sheet,
    close,
    rebind,
    resetBindings,
    takeItem,
    open,
    pickWorld,
    askDelete,
    playWorld,
    deleteWorld,
    pickScene,
    playScene,
    act,
}

alias Act = void function(ref Game game, uint index);

struct UiAction {
    uint index;
    UiKind kind;
    Act act;
}

struct Mining {
    ChunkId chunk;
    Cell cell;
    Time spent;
}

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

enum RecordTag BEACON_RECORD = RecordTag(0);

struct Footholds {
    Position[MOST_FOOTHOLDS] places;
    uint count;
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

struct Aim {
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
    void*[MOST_GUESTS] guests;
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
    Array!Job jobs;
    uint lastJob;
    uint lastQueued;
    Thread thread;
    Footholds footholds;
    HashMap!(NodeId, Present) explored;
    Aim aim;
    Inventory inventory;
    Stack carried;
    Maybe!Mining mining;
    Maybe!Beacon[MOST_STATIONS] usedStations;
    ChunkId machine;
    uint machineCell;
    uint machineScreen;
    Vec3!float compass = Vec3!float(0, 0, -1);
    IdSet owned;
    IdSet noticed;
    MovementMode mode = MovementMode.walk;
    uint preset;
    Screen screen;
    uint sheet;
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
        game.character = characterOf((&readApi).settingsOf!BodySettings(NAME));
        game.camera = Camera.make(game.character.eyeOffset);
        game.character.solid = plainSolid;
        foreach (ref extension; extensions.slice()) {
            extension.attach(game);
        }
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

    Length touchReach() const {
        return Length(atanhf(world.tanhReach));
    }

    void generateWithin(Position position, Length reach) {
        generateChunksNear(position, reach);
        generateRegion(position, reach);
    }

    void generateAroundBody(Position position, Length region) {
        generateChunksNear(position, touchReach());
        generateRegion(position, region);
    }

    void generateChunksNear(Position position, Length reach) {
        Array!ChunkSlot picked = world.graph.collectChunksNear(position, reach.value);
        foreach (chunk; picked.slice()) {
            world.graph.generateNow(chunk);
        }
        picked.release();
    }

    void generateRegion(Position position, Length reach) {
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
        Footing footing = settleStep();
        while (footing == Footing.airborne) {
            footing = settleStep();
        }
    }

    Footing settleStep() {
        Length reach = regionReach(character) + bodyReach();
        generateAroundBody(characterState.position, reach);
        characterState.up = world.graph.ensureGravityAt(characterState.position).up;
        characterState.pull = characterState.up;
        Features features;
        features.collect(world.graph, characterState.position, reach, bodySolid());
        Slide drop = Mover.make(character, features, characterState.up, Length(0)).settle(ZERO_VECTOR, bodyReach());
        features.release();
        characterState.position = world.graph.movedBy(characterState.position, drop.position);
        if (drop.hasLanded) {
            characterState.groundNormal = drop.groundNormal;
            characterState.footing = Footing.grounded;
            return Footing.grounded;
        } else {
            return Footing.airborne;
        }
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
        return world.graph.stateAt(world.graph.slotOf(characterState.position.node).value).reference.value.upAt(characterState.position.local).negated;
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
        footholds = Footholds.init;
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
        jobs.clear();
        notes.clear();
        foreach (ref extension; extensions.slice()) {
            extension.startOver(this);
        }
        time = Time(0);
    }

    void release() {
        foreach (ref extension; extensions.slice()) {
            extension.detach(this);
        }
        thrown.release();
        beacons.release();
        notes.release();
        crafts.release();
        jobs.release();
        thread.beads.release();
        explored.release();
        world.release();
    }

    void store(Stack stack) {
        uint lost = inventory.gain(stack);
        if (lost > 0) {
            Note made = {kind: NoteKind.inventoryFull, item: stack.item, amount: lost};
            post(made);
        }
        foreach (ref extension; extensions.slice()) {
            extension.gained(this, stack);
        }
    }

    uint miningTier() const {
        if (rules == Rules.creative) {
            return highestMiningTier();
        } else {
            uint tier = 0;
            foreach (index, tool; toolTiers.slice()) {
                if (owned.has(cast(uint) index)) {
                    tier = higherOf(tier, tool);
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

    void learn(Insight insight) {
        if (!noticed.has(insight.id)) {
            noticed.set(insight.id);
            Note made = {kind: NoteKind.learned, label: insights()[insight.id].title};
            post(made);
        }
    }

    RecipePlan planOf(uint recipe) const {
        Inventory stock = inventory;
        Array!uint plan;
        Shortfall shortfall = planRecipe(stock, recipe, 1, plan, 0);
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

    bool craft(uint recipe) {
        Inventory stock = inventory;
        Array!uint plan;
        Shortfall shortfall = planRecipe(stock, recipe, 1, plan, 0);
        bool queued = !isRepeatedUpgrade(recipe) && shortfall.count == 0;
        if (isRepeatedUpgrade(recipe)) {
            Note made = {kind: NoteKind.upgradeQueued, label: upgrades()[recipes()[recipe].upgrade.id].title};
            post(made);
        } else if (shortfall.count > 0) {
            Note made = {kind: NoteKind.missingIngredients, label: shortfall.label, amount: shortfall.count};
            post(made);
        } else {
            enqueue(plan.slice());
        }
        plan.release();
        return queued;
    }

    bool canQueue(uint recipe) const {
        return !isRepeatedUpgrade(recipe) && planOf(recipe).shortfall.count == 0;
    }

    uint craftSeveral(uint recipe, uint wanted) {
        uint queued = 0;
        while (queued < wanted && canQueue(recipe)) {
            craft(recipe);
            queued += 1;
        }
        if (queued == 0) {
            craft(recipe);
        }
        return queued;
    }

    void enqueue(const(uint)[] plan) {
        lastJob += 1;
        jobs.append(jobFor(inventory, plan, lastJob));
        foreach (at, index; plan) {
            Step step = Step.last;
            if (at + 1 < plan.length) {
                step = Step.feeding;
            }
            queue(Crafting(Taken.init, recipes()[index].time, index, CraftKind.recipe, Readiness.pending, lastJob, step));
        }
    }

    void queue(Crafting crafting) {
        lastQueued += 1;
        Crafting made = crafting;
        made.order = lastQueued;
        crafts.append(made);
    }

    void requeue(Crafting crafting) {
        size_t at = crafts.length;
        while (at > 0 && crafts.ptr[at - 1].order > crafting.order) {
            at -= 1;
        }
        crafts.append(crafting);
        foreach_reverse (later; at + 1 .. crafts.length) {
            crafts.ptr[later] = crafts.ptr[later - 1];
        }
        crafts.ptr[at] = crafting;
    }

    uint jobIndexOf(uint id) const {
        uint index = 0;
        while (index < jobs.length && jobs.ptr[index].id != id) {
            index += 1;
        }
        assert(index < jobs.length);
        return index;
    }

    void closeJob(uint id) {
        uint index = jobIndexOf(id);
        Inventory left = jobs.ptr[index].held;
        foreach (later; index + 1 .. jobs.length) {
            jobs.ptr[later - 1] = jobs.ptr[later];
        }
        jobs.length -= 1;
        foreach (ref stack; left.slots) {
            if (!stack.isEmpty) {
                store(stack);
            }
        }
    }

    void cancelJob(uint id) {
        size_t index = crafts.length;
        while (index > 0) {
            index -= 1;
            Crafting step = crafts.ptr[index];
            if (step.kind == CraftKind.recipe && step.job == id) {
                if (step.started == Readiness.ready) {
                    giveBack(recipes()[step.index], step.taken);
                }
                removeCraft(index);
            }
        }
        closeJob(id);
    }

    void giveBack(ref const Recipe recipe, ref const Taken taken) {
        foreach (need, ref ingredient; recipe.needs[0 .. recipe.needed]) {
            foreach (option, item; ingredient.accepted) {
                if (taken.counts[need][option] > 0) {
                    store(Stack(item, taken.counts[need][option]));
                }
            }
        }
    }

    void cancelCraft(uint index) {
        if (index < crafts.length) {
            Crafting crafting = crafts.ptr[index];
            final switch (crafting.kind) {
                case CraftKind.recipe:
                    cancelJob(crafting.job);
                    break;
                case CraftKind.work:
                    crafting.work.cancel(this, crafting);
                    removeCraft(index);
                    break;
            }
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

    bool canStart(ref const Crafting crafting) const {
        final switch (crafting.kind) {
            case CraftKind.recipe:
                return jobs.ptr[jobIndexOf(crafting.job)].held.canCraft(recipes()[crafting.index]);
            case CraftKind.work:
                return true;
        }
    }

    bool isWorkable(ref const Crafting crafting) const {
        return isStationReady(stationOf(crafting)) && (crafting.started == Readiness.ready || canStart(crafting));
    }

    void start(ref Crafting crafting) {
        final switch (crafting.kind) {
            case CraftKind.recipe:
                crafting.taken = jobs.ptr[jobIndexOf(crafting.job)].held.takeIngredients(recipes()[crafting.index]).value;
                break;
            case CraftKind.work:
                break;
        }
        crafting.started = Readiness.ready;
    }

    void finish(Crafting crafting) {
        noticeWorking(stationOf(crafting));
        final switch (crafting.kind) {
            case CraftKind.recipe:
                const(Recipe)* recipe = &recipes()[crafting.index];
                final switch (crafting.step) {
                    case Step.feeding:
                        jobs.ptr[jobIndexOf(crafting.job)].held.gain(Stack(recipe.made, recipe.yield));
                        break;
                    case Step.last:
                        deliver(*recipe);
                        closeJob(crafting.job);
                        break;
                }
                happen(CRAFTED, recipe.name);
                break;
            case CraftKind.work:
                crafting.work.finish(this, crafting);
                happen(CRAFTED, crafting.work.name(crafting));
                break;
        }
    }

    void deliver(ref const Recipe recipe) {
        final switch (recipe.product) {
            case Product.item:
                store(Stack(recipe.made, recipe.yield));
                Note made = {kind: NoteKind.crafted, item: recipe.made, amount: recipe.yield};
                post(made);
                break;
            case Product.upgrade:
                owned.set(recipe.upgrade.id);
                foreach (ref extension; extensions.slice()) {
                    extension.upgraded(this);
                }
                Note granted = {kind: NoteKind.upgraded, label: upgrades()[recipe.upgrade.id].title};
                post(granted);
                break;
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
        Time unspent = dt;
        MaybeIndex!uint active = activeCraft();
        while (active.exists && unspent > Time(0)) {
            uint index = active.value;
            Crafting* crafting = &crafts.ptr[index];
            if (crafting.started == Readiness.pending) {
                start(*crafting);
            }
            Time spent = lowerOf(unspent, crafting.left);
            crafting.left = crafting.left - spent;
            unspent = unspent - spent;
            if (crafting.left <= Time(0)) {
                Crafting done = *crafting;
                removeCraft(index);
                finish(done);
            }
            active = activeCraft();
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
        sheet = 0;
        worlds.picked = Maybe!WorldPick.init;
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

    void write(uint code, const(char)[] text) {
        Note made = {kind: NoteKind.written, code: code, length: cast(ubyte) lowerOf(text.length, NOTE_CAPACITY)};
        foreach (index; 0 .. made.length) {
            made.text[index] = text[index];
        }
        post(made);
    }

    void openMachine(uint chosen) {
        openScreen(Screen.machine);
        machineScreen = chosen;
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

    Length blockLength() const {
        return Length(edgeLength(world.graph.layout).value / edgeCells(world.graph.layout.dimension));
    }

    void keepFoothold(Position at) {
        if (footholds.count == MOST_FOOTHOLDS) {
            world.graph.unreference(world.graph.slotOf(footholds.places[MOST_FOOTHOLDS - 1].node).value);
            footholds.count -= 1;
        }
        foreach_reverse (index; 0 .. footholds.count) {
            footholds.places[index + 1] = footholds.places[index];
        }
        footholds.places[0] = at;
        footholds.count += 1;
        world.graph.reference(world.graph.slotOf(at.node).value);
    }

    void dropNewestFoothold() {
        world.graph.unreference(world.graph.slotOf(footholds.places[0].node).value);
        foreach (index; 1 .. footholds.count) {
            footholds.places[index - 1] = footholds.places[index];
        }
        footholds.count -= 1;
    }

    bool isApartFromFootholds(Position at) const {
        if (footholds.count == 0) {
            return true;
        } else {
            Position newest = footholds.places[0];
            Motion!float toNewest = world.graph.ownView.nodeToNode(world.graph.slotOf(at.node).value, world.graph.slotOf(newest.node).value);
            Point!float here = toNewest * at.local * Point!float.origin();
            return here.coshDistance(newest.local * Point!float.origin()) >= coshf(blockLength().value);
        }
    }

    void markFoothold() {
        Position here = characterState.position;
        if (mode == MovementMode.walk && characterState.isOnGround && reveal.touchable.isEmpty && !world.graph.isBelowUnderside(here) && isApartFromFootholds(here)) {
            keepFoothold(here);
        }
    }

    void wake() {
        closeScreen();
        mining = Maybe!Mining.init;
        foreach (ref extension; extensions.slice()) {
            extension.woke(this);
        }
        Footing landed = Footing.airborne;
        while (landed == Footing.airborne && footholds.count > 0) {
            placeAt(footholds.places[0], Length(0));
            landed = settleStep();
            if (landed == Footing.airborne) {
                dropNewestFoothold();
            }
        }
        if (landed == Footing.airborne) {
            placeAtSpawn();
        }
        uint lost = 0;
        final switch (rules) {
            case Rules.survival:
                lost = inventory.loseShare();
                break;
            case Rules.creative:
                break;
        }
        Note made = {kind: NoteKind.woke, amount: lost};
        post(made);
        happen(WOKE, world.graph.worldgen.structureName());
        world.settleFogColor();
        updateView();
    }

    void happen(const(char)[] event, const(char)[] subject) {
        Play play = Play(&this, &readApi, &playGive, &playLearn, &playNote);
        fire(&play, Happening(subject, event));
    }

    void noticeBreaking(Material material) {
        foreach (index, ref rule; insights()) {
            if (rule.trigger == Trigger.broke && itemOf(material).isAmong(rule.noticed)) {
                learn(Insight(cast(ubyte) index));
            }
        }
    }

    void noticeWorking(Station station) {
        foreach (index, ref rule; insights()) {
            if (rule.trigger == Trigger.worked && rule.station == station) {
                learn(Insight(cast(ubyte) index));
            }
        }
    }

    void noticeRevealing(uint family) {
        foreach (index, ref rule; insights()) {
            if (rule.trigger == Trigger.revealed && rule.family == family) {
                learn(Insight(cast(ubyte) index));
            }
        }
    }

    bool breakBlock() {
        Maybe!GraphCastHit hit = world.castCenterRay();
        Maybe!Material broken = world.targetMaterial();
        bool done = world.breakBlock();
        if (done) {
            Cell coords = hit.value.voxelCoords;
            uint cell = cast(uint) cellIndex(world.graph.layout.dimension, coords.x, coords.y, coords.z);
            uint yielded = 0;
            foreach (ref extension; extensions.slice()) {
                if (extension.broke(this, hit.value.chunk, cell, broken.value)) {
                    yielded += 1;
                }
            }
            if (yielded == 0) {
                store(Stack(itemOf(broken.value), 1));
            }
            noticeBreaking(broken.value);
            happen(BROKE, materialNames.ptr[broken.value.id]);
            if (broken.value == beaconBlock) {
                removeBeacon(hit.value.chunk, cell);
            }
        }
        return done;
    }

    void updateAim() {
        Maybe!GraphCastHit hit = world.castCenterRay();
        Maybe!Material target = world.targetMaterial();
        aim = Aim.init;
        if (target.exists) {
            aim.material = target.value;
            aim.kind = AimKind.block;
            Cell coords = hit.value.voxelCoords;
            if (stationOf(target.value).exists) {
                aim.kind = AimKind.usable;
            } else if (rumorAt(target.value, hit.value.chunk, cast(uint) cellIndex(world.graph.layout.dimension, coords.x, coords.y, coords.z)).exists) {
                aim.kind = AimKind.readable;
            }
            foreach (ref extension; extensions.slice()) {
                extension.aim(this, hit.value, target.value);
            }
        }
    }

    bool interact() {
        Maybe!GraphCastHit hit = world.castCenterRay();
        Maybe!Material target = world.targetMaterial();
        uint used = 0;
        if (target.exists) {
            Cell coords = hit.value.voxelCoords;
            machine = hit.value.chunk;
            machineCell = cast(uint) cellIndex(world.graph.layout.dimension, coords.x, coords.y, coords.z);
            if (stationOf(target.value).exists) {
                workstation = stationOf(target.value).value;
                usedStations[workstation.id] = Maybe!Beacon.of(Beacon(machine, machineCell));
                openScreen(Screen.station);
                used += 1;
            }
            foreach (ref extension; extensions.slice()) {
                if (used == 0 && extension.use(this, target.value)) {
                    used += 1;
                }
            }
            if (used == 0 && read(target.value, machine, machineCell)) {
                used += 1;
            }
        }
        if (used > 0) {
            return true;
        } else {
            return placeBlock();
        }
    }

    bool read(Material held, ChunkId chunk, uint cell) {
        Maybe!Insight rumor = rumorAt(held, chunk, cell);
        if (!rumor.exists) {
            return false;
        } else if (noticed.has(rumor.value.id)) {
            Note made = {kind: NoteKind.told, label: insights()[rumor.value.id].title};
            post(made);
            return true;
        } else {
            learn(rumor.value);
            return true;
        }
    }

    void apply(UiAction action, Click click) {
        final switch (action.kind) {
            case UiKind.slot:
                clickSlot(action.index, click);
                break;
            case UiKind.craft:
                craftSeveral(action.index, craftsFor(click));
                break;
            case UiKind.cancelCraft:
                cancelCraft(action.index);
                break;
            case UiKind.sheet:
                sheet = action.index;
                break;
            case UiKind.close:
                closeScreen();
                break;
            case UiKind.act:
                action.act(this, action.index);
                break;
            case UiKind.takeItem:
                takeFromCatalog(Item(cast(ushort) action.index), click);
                break;
            case UiKind.open:
                openScreen(cast(Screen) action.index);
                break;
            case UiKind.pickWorld:
                worlds.picked = Maybe!WorldPick.of(WorldPick(action.index, PickKind.world));
                worlds.deleting = Deleting.idle;
                break;
            case UiKind.pickScene:
                worlds.picked = Maybe!WorldPick.of(WorldPick(action.index, PickKind.scene));
                worlds.deleting = Deleting.idle;
                break;
            case UiKind.askDelete:
                worlds.deleting = Deleting.asked;
                break;
            case UiKind.rebind:
            case UiKind.resetBindings:
            case UiKind.playWorld:
            case UiKind.deleteWorld:
            case UiKind.playScene:
                break;
        }
    }

    void addBeacon(ChunkId chunk, uint cell) {
        world.graph.reference(world.graph.slotOf(chunk.node).value);
        beacons.append(Beacon(chunk, cell));
        world.graph.edits.keepRecord(chunk, BlockRecord(Lineage.init, time, cell, BEACON_RECORD));
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
                if (held == beaconBlock) {
                    addBeacon(placement.value.chunk, cell);
                }
                foreach (ref extension; extensions.slice()) {
                    extension.placed(this, placement.value.chunk, cell, stack);
                }
                happen(PLACED, materialNames.ptr[held.id]);
            }
            return done;
        } else {
            return false;
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
                noticeRevealing(cast(uint) index);
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

    Perception sensed() const {
        Perception felt = presets.ptr[preset].perception;
        foreach (ref extension; extensions.slice()) {
            felt = extension.feel(this, felt);
        }
        return felt;
    }

    void perceive(uint chosen) {
        preset = chosen;
        perception = sensed();
        settleReveal();
        updateView();
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
        world.joinAhead();
        FrameInput input = given;
        if (screen != Screen.none) {
            input = FrameInput.init;
        }
        look(input.yaw, input.pitch);
        float moveX = axisValue(input.held, Key.right) - axisValue(input.held, Key.left);
        float moveY = axisValue(input.held, Key.up) - axisValue(input.held, Key.down);
        float moveZ = axisValue(input.held, Key.back) - axisValue(input.held, Key.forward);
        foreach (ref extension; extensions.slice()) {
            extension.step(this, dt);
        }
        perception = sensed();
        settleReveal();
        CharacterConfig effective = character.effectiveFor(perception);
        effective.solid = bodySolid();
        Stepped stepped = runCharacter(effective, characterInput(moveX, moveY, moveZ, jumpFrom(input.held)), dt);
        lastHeld = input.held;
        traveled = traveled + stepped.traveled;
        world.graph.ensureGravityKnown(characterState.position);
        if (mode == MovementMode.walk && world.graph.isBelowAbyss(characterState.position)) {
            wake();
        } else {
            markFoothold();
        }
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
        generateAroundBody(characterState.position, regionReach(config));
        CharacterState trial = characterState;
        Stepped stepped = trial.runStep(config, world.graph, input, dt);
        while (stepped.isStalled) {
            generateAroundBody(trial.position, regionReach(config));
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
