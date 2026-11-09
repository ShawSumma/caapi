module scripts.tests;

import core.math : sqrt;
import core.stdc.math : atan2, exp, fabs, roundf, sin;
import base.flags : Readiness;
import base.maybe : Maybe, MaybeIndex;
import base.names : textFor;
import base.numbers : RADIANS_PER_DEGREE, higherOf, lowerOf;
import base.units : AngularSpeed, Length, Time;
import base.vector3 : Vec3, ZERO_VECTOR, magnitude, minus;
import client.bindings : Rules;
import client.config : ClientConfig;
import client.game : AimKind, BeaconSighting, COLLECTION_RATE, ChunkSupply, Click, GROWN_SECONDS, Game, HARVEST_RAW, Key, MOST_EXTRA_YIELD, Mineable, NoteKind, PLANT_DOSE, RAW_PER_DOSE, RouteWaypoint, Screen, Sheet, UiAction, UiKind, UnloadedCount;
import client.hud : Growth;
import client.save : SaveData, Writer, applyEdits, applyState, readGame, writeGame;
import client.script : NamedScript, ONE_SECOND, Script, StepHook, degrees, insightNamed, materialNamed, named, recipeNamed, stationNamed, synthesisNamed, upgradeNamed;
import client.structures : StructureProblem, placeStructure;
import client.world : Placement;
import common.biology.air : AirMix, GAS_COUNT, airOf;
import common.biology.breeding : expressionIn, productOf;
import common.biology.kinetics : Body, Route;
import common.biology.molecule : Molecule;
import common.biology.organism : starterDoses;
import common.biology.wild : WILD_GENES, WildGenes;
import common.character.controller : MovementMode;
import common.content.content : hooks;
import common.crafting : Insight, Reaction, Station, Synthesis, Upgrade, doseRoutes, recipes, syntheses, synthesized;
import common.graph : Graph, NodeId;
import common.inventory : HOTBAR_SLOTS, Inventory, SLOT_COUNT, STACK_LIMIT, Stack, isSameKind, taken;
import common.items : Item, itemOf;
import common.material : has;
import common.node : ChunkSlot, ChunkState, cellIndex;
import common.perception : effectiveFor;
import common.position : Position;
import common.settings : CharacterConfig;
import common.worldgen.generation : Worldgen;
import geometry.lorentz : Point;
import plugins.api.api : Material;
import plugins.api.content : Event, Happening, Play;
import scripts.claims : Measure, Topic, claim, link;
import climb = scripts.climb;
import walk = scripts.walk : Across, ClimbGoal, Motion;

immutable NamedScript[] TESTS = [
    NamedScript("api", &api),
    NamedScript("demo/growth", &demoGrowth),
    NamedScript("demo/holonomy", &demoHolonomy),
    NamedScript("demo/throw", &demoThrow),
    NamedScript("flat/corner", &flatCorner),
    NamedScript("flat/curve", &flatCurve),
    NamedScript("flat/hole", &flatHole),
    NamedScript("flat/items", &flatItems),
    NamedScript("flat/mining", &flatMining),
    NamedScript("flat/crafting", &flatCrafting),
    NamedScript("flat/tiers", &flatTiers),
    NamedScript("flat/jump", &flatJump),
    NamedScript("flat/place", &flatPlace),
    NamedScript("flat/stair", &flatStair),
    NamedScript("flat/stepover", &flatStepover),
    NamedScript("flat/timestep", &flatTimestep),
    NamedScript("flat/walk", &flatWalk),
    NamedScript("flat/wall", &flatWall),
    NamedScript("beacon/home", &beaconHome),
    NamedScript("biology/dosed-climb", &biologyDosedClimb),
    NamedScript("biology/sober", &biologySober),
    NamedScript("gene/breed-splice", &geneBreedSplice),
    NamedScript("gene/grow", &geneGrow),
    NamedScript("gene/harvest", &geneHarvest),
    NamedScript("gene/kept", &geneKept),
    NamedScript("gene/ripening", &geneRipening),
    NamedScript("flat/learning", &flatLearning),
    NamedScript("gene/synthesis", &geneSynthesis),
    NamedScript("hidden/climb", &hiddenClimb),
    NamedScript("hidden/reveal-inside", &hiddenRevealInside),
    NamedScript("hidden/unrevealed", &hiddenUnrevealed),
    NamedScript("live/drift", &liveDrift),
    NamedScript("live/edit-kept", &liveEditKept),
    NamedScript("live/far", &liveFar),
    NamedScript("live/fly", &liveFly),
    NamedScript("save/round-trip", &saveRoundTrip),
    NamedScript("save/refunds", &saveRefunds),
    NamedScript("perception/body", &perceptionBody),
    NamedScript("plant/collector", &plantCollector),
    NamedScript("plant/eat", &plantEat),
    NamedScript("slope/across", &slopeAcross),
    NamedScript("slope/downhill", &slopeDownhill),
    NamedScript("slope/hopping", &slopeHopping),
    NamedScript("slope/steep", &slopeSteep),
    NamedScript("slope/turning", &slopeTurning),
    NamedScript("slope/uphill", &slopeUphill),
    NamedScript("slope/wall", &slopeWall),
    NamedScript("ui/screen-holds", &uiScreenHolds),
    NamedScript("ui/catalog", &uiCatalog),
    NamedScript("structure/arbor", &climbing!("arbor", 2.5f, SpawnCheck.checked)),
    NamedScript("structure/arborendless", &structureArborEndless),
    NamedScript("structure/arch", &climbing!("crown", 1.8f, SpawnCheck.skipped)),
    NamedScript("structure/axis", &structureAxis),
    NamedScript("structure/babel", &climbing!("babel", 1.2f, SpawnCheck.checked)),
    NamedScript("structure/backrooms", &structureBackrooms),
    NamedScript("structure/backroomsbasement", &climbing!("basement", 0.2f, SpawnCheck.skipped)),
    NamedScript("structure/backroomsstairs", &climbing!("backroomsstairs", 0.25f, SpawnCheck.skipped)),
    NamedScript("structure/backroomsworld", &structureBackroomsWorld),
    NamedScript("structure/chain", &structureChain),
    NamedScript("structure/city", &structureCity),
    NamedScript("structure/crown", &structureCrown),
    NamedScript("structure/endless", &structureEndless),
    NamedScript("structure/hamlet", &structureHamlet),
    NamedScript("structure/lattice", &structureLattice),
    NamedScript("structure/library", &structureLibrary),
    NamedScript("structure/libraryendless", &structureLibraryEndless),
    NamedScript("structure/librarylive", &structureLibraryLive),
    NamedScript("structure/libraryflight", &structureLibraryFlight),
    NamedScript("structure/librarynohole", &structureLibraryNoHole),
    NamedScript("structure/palace", &climbing!("palace", 0.35f, SpawnCheck.checked)),
    NamedScript("structure/risen", &risen!("risencity", 1.5f, "base:concrete", "the risen city's paved lot")),
    NamedScript("structure/road", &structureRoad),
    NamedScript("structure/spiral", &risen!("spiralcity", 1.5f, "base:concrete", "the spiral's landing")),
    NamedScript("structure/drift", &risen!("driftcity", 1.5f, "base:concrete", "the drift's landing")),
    NamedScript("structure/lantern", &risen!("lanterncity", 1.5f, "base:concrete", "the lantern's landing")),
    NamedScript("structure/stacked", &risen!("stacked", 1.5f, "base:concrete", "the connector's landing")),
    NamedScript("structure/stackedrooms", &risen!("stackedrooms", 1.5f, "base:concrete", "the connector's landing")),
    NamedScript("structure/stairs", &climbing!("tower", 2.5f, SpawnCheck.skipped)),
    NamedScript("structure/tower", &structureTower),
    NamedScript("structure/trail", &structureTrail),
    NamedScript("structure/tripcity", &roundTrip!("tripcity")),
    NamedScript("structure/tripwild", &roundTrip!("tripwild")),
    NamedScript("structure/triprooms", &roundTrip!("triprooms")),
    NamedScript("structure/tripstacked", &roundTrip!("tripstacked")),
    NamedScript("structure/tripcities", &roundTrip!("tripcities")),
    NamedScript("structure/tripwildwild", &roundTrip!("tripwildwild")),
    NamedScript("structure/tripspiral", &roundTrip!("tripspiral")),
    NamedScript("structure/tripdrift", &roundTrip!("tripdrift")),
    NamedScript("structure/triplantern", &roundTrip!("triplantern")),
    NamedScript("structure/treetrunk", &structureTreetrunk),
    NamedScript("structure/wild", &risen!("risenwild", 2.0f, "base:concrete", "the connector's landing")),
    NamedScript("structure/caves", &structureCaves),
    NamedScript("structure/vaults", &climbing!("vaults", 0.35f, SpawnCheck.checked)),
    NamedScript("content/hooks", &contentHooks),
    NamedScript("lost/thread-off", &lostThreadOff),
    NamedScript("lost/thread", &lostThread),
    NamedScript("lost/thread-full", &lostThreadFull),
];

enum double THREAD_WALK_SECONDS = 4;
enum uint FEW_BEADS = 8;
enum uint MANY_BEADS = 1024;
enum size_t REWOUND_SLACK = 2;

void lostThreadOff(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.press(THREAD_WALK_SECONDS, Key.forward);
    world.claim(Topic.navigation, "The thread lays nothing unless it is turned on.", world.game.thread.beads.length == 0, Measure.of("beads laid", world.game.thread.beads.length));
}

void lostThread(ref Script world) {
    world.plane(degrees(0));
    world.game.thread.most = MANY_BEADS;
    walk.spawn(world);
    float spacing = world.game.thread.spacing.value;
    world.press(THREAD_WALK_SECONDS, Key.forward);
    float walked = world.traveled().value;
    size_t laid = world.game.thread.beads.length;
    size_t expected = cast(size_t)(walked / spacing) + 1;
    world.claim(Topic.navigation, "With the thread on, a bead is laid for every spacing walked.", laid + 1 >= expected && laid <= expected + 1, Measure.of("walked", walked), Measure.of("spacing", spacing), Measure.of("beads laid", laid), Measure.of("predicted", expected));
    world.check(world.game.isExplored(world.game.characterState.position.node), "the node underfoot is not marked explored");
    world.turn(degrees(180), degrees(0), walk.TURN_SECONDS);
    world.press(THREAD_WALK_SECONDS, Key.forward);
    float back = world.traveled().value - walked;
    size_t left = world.game.thread.beads.length;
    size_t rewound = cast(size_t)(fabs(walked - back) / spacing) + REWOUND_SLACK;
    world.claim(Topic.navigation, "Walking back along the thread winds it up again.", left <= rewound, Measure.of("walked out", walked), Measure.of("walked back", back), Measure.of("beads left", left));
}

void lostThreadFull(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.thread.most = FEW_BEADS;
    world.step();
    world.check(world.game.thread.beads.length == 1, "standing still laid %zu thread beads, not one", world.game.thread.beads.length);
    Position first = world.game.thread.beads.ptr[0];
    world.press(THREAD_WALK_SECONDS, Key.forward);
    size_t held = world.game.thread.beads.length;
    Position kept = world.game.thread.beads.ptr[0];
    world.check(held <= FEW_BEADS && held > FEW_BEADS / 2, "a thread of at most %u beads holds %zu after walking %.3f", FEW_BEADS, held, world.traveled().value);
    float apart = (kept.local * Point!float.origin()).distance(first.local * Point!float.origin());
    world.check(kept.node == first.node && apart < SAVE_PLACE_TOLERANCE, "the full thread's first bead moved %.5f, so it no longer leads back to where it began", apart);
}

enum string HOOK_GIFT = "base:charcoal";
enum string HOOK_NOTE = "a mod heard the block break";
enum double GROUND_PITCH = 60;

void hearBreaks(const(Play)* play, Happening happening) {
    if (happening.event == Event.broke) {
        play.give(play, HOOK_GIFT, 1);
        play.learn(play, CHARRING);
        play.note(play, HOOK_NOTE);
    }
}

void contentHooks(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    hooks.append(&hearBreaks);
    world.look(degrees(0), degrees(GROUND_PITCH));
    bool broke = world.breakBlock();
    hooks.length -= 1;
    world.check(broke, "broke the ground underfoot");
    uint gifts = world.game.inventory.countOf(named(HOOK_GIFT));
    world.claim(Topic.mods, "A mod can hear a block break and give the player an item in answer.", gifts == 1, Measure.of("given", gifts), Measure.of("item", HOOK_GIFT));
    world.check(world.game.noticed.has(insightNamed(CHARRING).id), "the hook taught charring, which breaking ground does not");
    size_t index = 0;
    while (index < world.game.notes.length && !(world.game.notes.ptr[index].kind == NoteKind.told && world.game.notes.ptr[index].label == HOOK_NOTE)) {
        index += 1;
    }
    world.check(index < world.game.notes.length, "the hook's note was not posted");
}

enum Time DEFAULT_TIMESTEP = Time(0.016f);
enum Time CHOSEN_TIMESTEP = Time(0.02f);
enum float TIMESTEP_TOLERANCE = 1e-6f;
enum float CLOCK_TOLERANCE = 1e-4f;
enum float REST_TOLERANCE = 5e-5f;

enum SpawnCheck : ubyte {
    skipped,
    checked,
}

enum Launch : ubyte {
    still,
    moving,
}

struct HookCount {
    uint steps;
    uint allowed;
}

void countHook(ref Script world, void* context) {
    HookCount* count = cast(HookCount*) context;
    count.steps += 1;
    world.wait(1);
    bool refused = world.takeFailure();
    if (!refused) {
        count.allowed += 1;
    }
}

void api(ref Script world) {
    world.material(HOTBAR_SLOTS + 1);
    bool refused = world.takeFailure();
    world.check(refused, "material slots past the hotbar are an error");
    world.check(fabs(world.timestep.value - DEFAULT_TIMESTEP.value) < TIMESTEP_TOLERANCE, "default timestep is 0.016 s");
    world.setTimestep(CHOSEN_TIMESTEP);
    world.plane(degrees(0));
    world.check(world.mode() == MovementMode.walk && world.isOnGround(), "the player starts walking, standing on the ground");
    world.wait(1);
    world.check(fabs(world.time().value - 1) < CLOCK_TOLERANCE, "waited 1 s, clock reads %.4f s", world.time().value);
    world.step(Time(CHOSEN_TIMESTEP.value / 2));
    world.check(fabs(world.time().value - 1 - CHOSEN_TIMESTEP.value / 2) < CLOCK_TOLERANCE, "one half step, clock reads %.4f s", world.time().value);
    if (!world.isFailed) {
        world.terrain();
        refused = world.takeFailure();
        world.check(refused, "worldgen cannot change after the first step");
    }
    if (!world.isFailed) {
        world.wait(1, Time(0));
        refused = world.takeFailure();
        world.check(refused, "a zero timestep is an error");
    }

    HookCount count;
    world.onStep(StepHook(&countHook, &count));
    world.wait(0.1);
    world.check(count.steps == 5, "the step hook ran %u times in 5 steps", count.steps);
    world.check(count.allowed == 0, "a step hook cannot advance time");
    world.onStep(StepHook.init);
    world.wait(0.1);
    world.check(count.steps == 5, "a removed step hook does not run");

    world.check(world.yawRate.value == 0 && world.pitchRate.value == 0, "turn rate starts at rest");
    world.turn(degrees(90), degrees(0), 0.5);
    world.check(world.yawRate.value == 0 && world.pitchRate.value == 0, "turn restores the previous turn rate");

    world.wait(3);
    world.check(world.isOnGround(), "standing after turning");
    world.check(fabs(world.speed().value) < REST_TOLERANCE && fabs(world.verticalSpeed().value) < REST_TOLERANCE, "at rest when no key is held");

    world.hold(Key.forward);
    world.look(degrees(0.25), degrees(-0.5));
    world.wait(0.48, DEFAULT_TIMESTEP);
    world.release(Key.forward);
    world.wait(0.48, DEFAULT_TIMESTEP);
    world.check(world.traveled().value > 0, "holding fwd moves the player");
    world.material(3);
    world.check(world.material() == 3, "material slot is set and read back");
}

enum float PENTAGON_SIDE = 1.0613f;
enum uint PENTAGON_SIDES = 5;
enum double QUARTER_TURN = 90;
enum double QUARTER_TOLERANCE = 3;
enum double STRAIGHT_TOLERANCE = 0.5;
enum float CLOSED_SHARE = 0.25f;

float pentagonLap(ref Script world) {
    world.look(degrees(0), degrees(0));
    world.resetCompass();
    float before = world.compassOff().value;
    foreach (_; 0 .. PENTAGON_SIDES) {
        world.press(PENTAGON_SIDE / walk.NOCLIP_SPEED, Key.forward);
        world.look(degrees(QUARTER_TURN), degrees(0));
    }
    world.step();
    return world.compassOff().value - before;
}

void demoHolonomy(ref Script world) {
    world.plane(degrees(0));
    world.mode(MovementMode.noclip);
    world.resetCompass();
    world.press(0.2f / walk.NOCLIP_SPEED, Key.forward);
    double straight = world.compassOff().value / RADIANS_PER_DEGREE;
    world.claim(Topic.navigation, "Going straight ahead does not turn the compass.", fabs(straight) < STRAIGHT_TOLERANCE, Measure.of("compass turned by (degrees)",straight));
    Position start = world.game.characterState.position;
    double off = pentagonLap(world) / RADIANS_PER_DEGREE;
    Position end = world.game.characterState.position;
    float apart = (end.local * Point!float.origin()).distance(start.local * Point!float.origin());
    world.claim(Topic.space, "A walk of five equal legs with a right turn after each ends where it began. In flat space it would take four.", end.node == start.node && apart < CLOSED_SHARE * PENTAGON_SIDE, Measure.of("leg length", PENTAGON_SIDE), Measure.of("ended this far from its start", apart));
    world.claim(Topic.navigation, "The compass holds the direction it was set to while the player turns: after five right turns it reads a quarter turn off.", fabs(fabs(off) - QUARTER_TURN) < QUARTER_TOLERANCE, Measure.of("compass turned by (degrees)",off));
}

void demoThrow(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.throwBlock();
    world.check(world.thrownCount() == 1, "a thrown block is flying");
    world.check(!world.isThrownResting(0), "a thrown block starts in the air");
    world.wait(4);
    world.check(world.thrownCount() == 1, "the block is still there after it lands");
    world.claim(Topic.gravity, "A thrown block falls and comes to rest where it hits something solid.", world.isThrownResting(0));
}

enum double GROWTH_SECONDS = 3;
enum uint GROWTH_FIRST_STEP = 2;
enum uint GROWTH_LAST_STEP = 5;
enum double LEAST_GROWTH = 2;

void demoGrowth(ref Script world) {
    world.structure("city");
    world.live();
    world.wait(GROWTH_SECONDS);
    Growth growth;
    growth.update(world.game.world);
    foreach (step; GROWTH_FIRST_STEP .. GROWTH_LAST_STEP + 1) {
        double rate = cast(double) growth.within[step] / growth.within[step - 1];
        world.claim(Topic.space, "Each further step through the honeycomb more than doubles the number of cells within reach.", rate > LEAST_GROWTH, Measure.of("steps", step), Measure.of("cells within them", growth.within[step]), Measure.of("cells within one step fewer", growth.within[step - 1]), Measure.of("growth", rate));
    }
    growth.release();
}

enum uint CORNER_BLOCKS = 2;
enum double ARRIVAL_MARGIN_SECONDS = 0.5;
enum double PUSH_SECONDS = 2;
enum float MOST_PUSH_TRAVEL = 0.0025f;
enum float MOST_CAMERA_ACCELERATION = 0.05f;

void shakeHook(ref Script world, void* context) {
    float* shake = cast(float*) context;
    *shake = higherOf(*shake, world.cameraVerticalAcceleration());
}

void flatCorner(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    walk.buildCorner(world, CORNER_BLOCKS);
    walk.checkStanding(world, "back on the floor");
    double cornerYaw = atan2(walk.WALL_HALF_WIDTH, walk.WALL_DISTANCE) / RADIANS_PER_DEGREE;
    world.look(degrees(cornerYaw), degrees(0));
    world.hold(Key.forward);
    world.wait(sqrt(walk.WALL_DISTANCE * walk.WALL_DISTANCE + walk.WALL_HALF_WIDTH * walk.WALL_HALF_WIDTH) / walk.SPEED + ARRIVAL_MARGIN_SECONDS);
    float start = world.traveled().value;
    float shake = 0;
    world.onStep(StepHook(&shakeHook, &shake));
    world.wait(PUSH_SECONDS);
    world.release(Key.forward);
    world.onStep(StepHook.init);
    float pushed = world.traveled().value - start;
    world.claim(Topic.movement, "Pushing into a corner does not move the body.", pushed <= MOST_PUSH_TRAVEL, Measure.of("moved", pushed), Measure.of("seconds pushing", PUSH_SECONDS));
    world.check(shake <= MOST_CAMERA_ACCELERATION, "camera shook at %.4f/s^2 in the corner", shake);
    walk.checkStanding(world, "in the corner");
}

enum float CURVE_ALTITUDE = 1;
enum double FALL_SECONDS = 0.25;
enum double LEAST_CURVE_FRACTION = 0.75;
enum double MOST_CURVE_FRACTION = 1.25;

struct Fall {
    float vertical = 0;
    float speed = 0;
    float altitude = 0;
}

void riseTo(ref Script world, float altitude) {
    world.mode(MovementMode.fly);
    world.press((altitude - world.altitude().value) / walk.FLY_SPEED, Key.up);
    world.step();
}

Fall fall(ref Script world, Launch launch) {
    if (launch == Launch.moving) {
        world.hold(Key.forward);
        world.step();
    }
    world.mode(MovementMode.walk);
    if (launch == Launch.moving) {
        world.release(Key.forward);
    }
    float altitude = world.altitude().value;
    float speed = world.horizontalSpeed().value;
    world.wait(FALL_SECONDS);
    return Fall(world.verticalSpeed().value, speed, altitude);
}

void flatCurve(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    riseTo(world, CURVE_ALTITUDE);
    Fall still = fall(world, Launch.still);
    riseTo(world, CURVE_ALTITUDE);
    Fall moving = fall(world, Launch.moving);
    double doubled = exp(2.0 * moving.altitude);
    double predicted = moving.speed * moving.speed * (doubled - 1) / (doubled + 1) * FALL_SECONDS;
    double gained = moving.vertical - still.vertical;
    world.link(Topic.space, Topic.movement, "A body launched level at speed v at height h over flat ground falls slower than one dropped from rest: after a time t its downward speed is less by v^2 tanh(h) t.", gained >= LEAST_CURVE_FRACTION * predicted && gained <= MOST_CURVE_FRACTION * predicted, Measure.of("speed", moving.speed), Measure.of("height", moving.altitude), Measure.of("seconds", FALL_SECONDS), Measure.of("fell slower by", gained), Measure.of("predicted", predicted));
}

enum uint HOLE_BLOCKS = 2;
enum double LOWER_BLOCK_DEGREES = 18;
enum uint MOST_BREAKS = 4;
enum double APPROACH_SECONDS = 1;
enum double SEARCH_SECONDS = 0.5;
enum double THROUGH_SECONDS = 2;
enum double FREE_SECONDS = 1;
enum float LEAST_FREE_FRACTION = 0.8f;

bool isWall(Maybe!Material target) {
    return walk.isMaterial(target, walk.BUILD_LAYERS[0].material) || walk.isMaterial(target, walk.BUILD_LAYERS[1].material);
}

void clearAhead(ref Script world, double pitch, const(char)* what) {
    world.look(degrees(0), degrees(pitch));
    uint breaks = 0;
    while (!world.isFailed && isWall(world.targetMaterial()) && breaks < MOST_BREAKS) {
        bool broke = world.breakBlock();
        world.check(broke, "broke the %s block of the hole", what);
        breaks += 1;
    }
    const(char)[] facing = walk.nameOf(world.targetMaterial());
    world.check(breaks > 0 && !isWall(world.targetMaterial()), "cleared the %s of the hole in %u breaks, facing %.*s", what, breaks, cast(int) facing.length, facing.ptr);
    world.look(degrees(0), degrees(-pitch));
}

void flatHole(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    walk.buildWall(world, HOLE_BLOCKS);
    walk.checkStanding(world, "back on the floor");
    clearAhead(world, 0, "upper half");
    clearAhead(world, LOWER_BLOCK_DEGREES, "lower half");
    world.hold(Key.forward);
    world.wait(APPROACH_SECONDS);
    world.press(SEARCH_SECONDS, Key.left);
    world.press(2 * SEARCH_SECONDS, Key.right);
    world.wait(THROUGH_SECONDS);
    world.release(Key.forward);
    walk.checkStanding(world, "after squeezing through the hole");
    walk.forward(world, FREE_SECONDS, LEAST_FREE_FRACTION);
}

enum float IDEAL_RISE = 0.085f;
enum float LEAST_RISE_FRACTION = 0.97f;
enum float MOST_RISE_FRACTION = 1.001f;

struct Jump {
    float apex = 0;
    float drift = 0;
}

void jumpHook(ref Script world, void* context) {
    Jump* jump = cast(Jump*) context;
    jump.apex = higherOf(jump.apex, world.altitude().value);
    jump.drift = higherOf(jump.drift, world.horizontalSpeed().value);
}

void flatJump(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    walk.checkStanding(world, "before jumping");
    float standing = world.altitude().value;
    Jump jump = Jump(standing, 0);
    world.onStep(StepHook(&jumpHook, &jump));
    world.press(0.1, Key.up);
    world.wait(1.5);
    world.onStep(StepHook.init);
    float rise = jump.apex - standing;
    world.claim(Topic.movement, "A standing jump rises to the body's jump height.", rise >= LEAST_RISE_FRACTION * IDEAL_RISE && rise <= MOST_RISE_FRACTION * IDEAL_RISE, Measure.of("rose", rise), Measure.of("expected", IDEAL_RISE), Measure.of("jump height setting", world.game.character.jumpHeight.value));
    world.claim(Topic.movement, "A standing jump does not drift sideways.", jump.drift < walk.SPEED_TOLERANCE, Measure.of("fastest sideways speed", jump.drift));
    walk.checkStanding(world, "after landing");
}

enum double AHEAD_DEGREES = 30;

void flatItems(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    Item ground = itemOf(world.targetMaterial().value);
    uint before = world.game.inventory.countOf(ground);
    bool broke = world.breakBlock();
    world.claim(Topic.blocks, "Breaking a block puts one of it in the inventory.", broke && world.game.inventory.countOf(ground) == before + 1, Measure.of("held before", before), Measure.of("held after", world.game.inventory.countOf(ground)));
    Item held = world.game.inventory.held();
    uint stock = world.game.inventory.countOf(held);
    bool placed = world.placeBlock();
    world.claim(Topic.blocks, "Placing a block takes one of it out of the inventory.", placed && world.game.inventory.countOf(held) == stock - 1, Measure.of("held before", stock), Measure.of("held after", world.game.inventory.countOf(held)));
    world.breakBlock();
    world.game.inventory.slots[world.game.inventory.selected] = Stack.init;
    world.check(!world.placeBlock(), "placed a block with none held");
}

enum double MINING_SLACK_SECONDS = 0.2;

void flatMining(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.inventory = Inventory.init;
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.step();
    Item ground = itemOf(world.targetMaterial().value);
    double needed = world.game.breakTimeOf(ground.block).value;
    world.hold(Key.mine);
    world.wait(needed / 2);
    world.claim(Topic.blocks, "Half way through its break time a block is still whole and shows mining progress.", world.game.inventory.countOf(ground) == 0 && world.game.miningShare().value > 0.3f, Measure.of("break time (seconds)",needed), Measure.of("progress shown", world.game.miningShare().value));
    world.wait(needed / 2 + MINING_SLACK_SECONDS);
    world.release(Key.mine);
    world.claim(Topic.blocks, "Holding mine on a block for its break time breaks it and puts it in the inventory.", world.game.inventory.countOf(ground) == 1, Measure.of("break time (seconds)",needed), Measure.of("held after", world.game.inventory.countOf(ground)));
}

enum uint SANDSTONE_SLOT = 6;
enum string SANDSTONE = "base:sandstone";

void flatTiers(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.material(SANDSTONE_SLOT);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.check(world.placeBlock() && walk.isMaterial(world.targetMaterial(), SANDSTONE), "could not place the sandstone");
    world.game.inventory = Inventory.init;
    double needed = world.game.breakTimeOf(materialNamed(SANDSTONE)).value;
    world.hold(Key.mine);
    world.wait(needed + MINING_SLACK_SECONDS);
    world.claim(Topic.blocks, "A block that needs a pickaxe cannot be mined by hand, however long the key is held.", world.game.inventory.countOf(named(SANDSTONE)) == 0 && world.game.mineableOf(materialNamed(SANDSTONE)) == Mineable.tooHard, Measure.of("block", SANDSTONE), Measure.of("seconds held", needed + MINING_SLACK_SECONDS));
    world.check(world.game.notes.length > 0 && world.game.notes.ptr[world.game.notes.length - 1].kind == NoteKind.needsTier, "mining sandstone by hand left no note saying what it needs");
    world.release(Key.mine);
    world.game.owned.set(upgradeNamed(WOODEN_PICKAXE).id);
    double picked = world.game.breakTimeOf(materialNamed(SANDSTONE)).value;
    world.claim(Topic.blocks, "A pickaxe shortens a block's break time.", picked < needed, Measure.of("block", SANDSTONE), Measure.of("by hand (seconds)", needed), Measure.of("with a wooden pickaxe (seconds)", picked));
    world.hold(Key.mine);
    world.wait(picked + MINING_SLACK_SECONDS);
    world.release(Key.mine);
    world.claim(Topic.blocks, "With the pickaxe it needs, a block is mined in its shortened break time.", world.game.inventory.countOf(named(SANDSTONE)) == 1, Measure.of("block", SANDSTONE), Measure.of("seconds held", picked + MINING_SLACK_SECONDS));
}

enum uint STATION_SLOT = HOTBAR_SLOTS - 1;
enum string PLANKS_RECIPE = "base:planks";
enum string WORKBENCH_RECIPE = "base:make-workbench";
enum string WOOD_PICK_RECIPE = "base:make-wooden-pickaxe";
enum string GLASS_RECIPE = "base:smelt-glass";
enum string SIFT_SAND_RECIPE = "base:sift-sand";
enum string WOODEN_PICKAXE = "base:wooden-pickaxe";
enum string WORKBENCH_STATION = "base:workbench-station";
enum string SIFTING = "base:sifting";
enum string CHARRING = "base:charring";
enum string PRESS_DOSE = "base:press-dose";
enum string PRESS_EXTRACT = "base:press-extract";

double secondsOf(const(char)[] recipe) {
    return recipes()[recipeNamed(recipe)].time.value;
}

void flatCrafting(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.inventory = Inventory.init;
    world.check(!world.game.craft(recipeNamed(WORKBENCH_RECIPE)), "made a workbench from nothing");
    world.game.inventory.gain(Stack(named("base:birch-wood"), 2));
    world.claim(Topic.crafting, "Queuing a recipe also queues, ahead of it, the recipes that make its missing ingredients.", world.game.craft(recipeNamed(WORKBENCH_RECIPE)) && world.game.crafts.length == 3, Measure.of("steps queued for a workbench from two wood", world.game.crafts.length));
    double total = 2 * secondsOf(PLANKS_RECIPE) + secondsOf(WORKBENCH_RECIPE);
    world.wait(total + MINING_SLACK_SECONDS);
    Item planks = named("base:wood-planks");
    world.check(world.game.inventory.countOf(named("base:workbench")) == 1 && world.game.inventory.countOf(planks) == 2 && world.game.crafts.length == 0, "two wood made %u workbenches and left %u planks", world.game.inventory.countOf(named("base:workbench")), world.game.inventory.countOf(planks));
    world.game.inventory.gain(Stack(named("base:spruce-wood"), 1));
    world.check(world.game.craft(recipeNamed(PLANKS_RECIPE)), "could not queue planks");
    world.step();
    world.check(world.game.crafts.length == 1 && world.game.crafts.ptr[0].started == Readiness.ready && world.game.inventory.countOf(named("base:spruce-wood")) == 0, "the planks did not start on the first step");
    world.game.cancelCraft(0);
    world.claim(Topic.crafting, "Cancelling a craft that has started gives back exactly the ingredients it took.", world.game.inventory.countOf(named("base:spruce-wood")) == 1 && world.game.inventory.countOf(named("base:oak-wood")) == 0 && world.game.crafts.length == 0, Measure.of("spruce wood back", world.game.inventory.countOf(named("base:spruce-wood"))), Measure.of("oak wood back", world.game.inventory.countOf(named("base:oak-wood"))));
    world.check(world.game.craft(recipeNamed(WOOD_PICK_RECIPE)) && world.game.crafts.length == 2, "two planks and a wood queued %zu steps for a wooden pickaxe, not planks and the pickaxe", world.game.crafts.length);
    world.check(!world.game.craft(recipeNamed(WOOD_PICK_RECIPE)) && world.game.crafts.length == 2 && world.game.notes.ptr[world.game.notes.length - 1].kind == NoteKind.upgradeQueued, "a second wooden pickaxe was queued while the first waits");
    world.wait(secondsOf(PLANKS_RECIPE) + secondsOf(WOOD_PICK_RECIPE) + MINING_SLACK_SECONDS);
    world.claim(Topic.crafting, "Work for a station waits while the player has used no station of that kind nearby.", !world.game.owned.has(upgradeNamed(WOODEN_PICKAXE).id) && world.game.crafts.length == 1, Measure.of("crafts still waiting", world.game.crafts.length));
    world.check(world.game.inventory.spend(named("base:workbench"), 1), "the workbench left the inventory");
    world.game.inventory.slots[STATION_SLOT] = Stack(named("base:workbench"), 1);
    world.material(STATION_SLOT + 1);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.check(world.placeBlock() && walk.isMaterial(world.targetMaterial(), "base:workbench"), "could not place the workbench");
    world.interact();
    world.check(world.game.screen == Screen.station && world.game.workstation == stationNamed(WORKBENCH_STATION), "using the workbench did not open it");
    world.wait(secondsOf(WOOD_PICK_RECIPE) + MINING_SLACK_SECONDS);
    world.claim(Topic.crafting, "Once the player has placed and used the station, the work that waited for it is done.", world.game.owned.has(upgradeNamed(WOODEN_PICKAXE).id) && world.game.crafts.length == 0, Measure.of("crafts still waiting", world.game.crafts.length));
}

void geneRipening(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.game.inventory.slots[0] = Stack(named("base:flower"), 1);
    world.material(1);
    world.check(world.placeBlock() && world.game.inventory.slots[0].isEmpty, "could not plant the flower");
    world.check(world.breakBlock() && world.game.compounds.length == 0 && world.game.notes.ptr[world.game.notes.length - 1].kind == NoteKind.unripeHarvest, "breaking an unripe flower gave %zu compounds or no note that it was unripe", world.game.compounds.length);
    Stack back = world.game.inventory.slots[0];
    world.claim(Topic.plants, "Breaking a plant before it is ripe gives back the one plant with its genes, and nothing more.", back.count == 1 && back.item == named("base:flower") && back.genes.exists, Measure.of("given back", back.count));
    world.check(world.placeBlock() && world.game.notes.ptr[world.game.notes.length - 1].kind == NoteKind.planted, "the flower that came back did not replant with its own genes");
    world.wait(GROWN_SECONDS.value + 1);
    uint slot = world.game.world.graph.slotOf(world.game.characterState.position.node).value;
    float fit = expressionIn(materialNamed("base:flower"), world.game.world.graph.stateAt(slot).climate.climate());
    uint predicted = 1 + cast(uint) roundf(MOST_EXTRA_YIELD * fit);
    world.check(world.breakBlock(), "could not break the ripe flower");
    uint gathered = world.game.inventory.countOfKind(back);
    world.link(Topic.climate, Topic.plants, "A ripe plant yields one of itself and up to two more, in proportion to how well the climate suits it.", gathered == predicted && world.game.compounds.length == 0, Measure.of("how well the climate suits it (0 to 1)", fit), Measure.of("yielded", gathered), Measure.of("predicted", predicted));
}

void flatLearning(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    uint sifting = insightNamed(SIFTING).id;
    world.check(!world.game.noticed.has(sifting) && !world.game.isKnownRecipe(recipeNamed(SIFT_SAND_RECIPE)), "sifting was known before any soil was broken");
    world.check(walk.isMaterial(world.targetMaterial(), "base:dirt") && world.breakBlock(), "could not break the dirt ground");
    world.claim(Topic.learning, "Breaking the right block teaches an insight, and the recipes that need it become known.", world.game.noticed.has(sifting) && world.game.isKnownRecipe(recipeNamed(SIFT_SAND_RECIPE)) && world.game.notes.ptr[world.game.notes.length - 1].kind == NoteKind.learned, Measure.of("block broken", walk.GROUND), Measure.of("insight", SIFTING), Measure.of("recipe", SIFT_SAND_RECIPE));
    world.game.rules = Rules.creative;
    world.game.inventory = Inventory.init;
    world.game.inventory.gain(Stack(named("base:sand"), 2));
    world.check(world.game.craft(recipeNamed(GLASS_RECIPE)), "could not queue glass");
    world.wait(secondsOf(GLASS_RECIPE) + MINING_SLACK_SECONDS);
    world.claim(Topic.learning, "Finishing work at a station can teach an insight.", world.game.noticed.has(insightNamed(CHARRING).id), Measure.of("recipe worked", GLASS_RECIPE), Measure.of("insight", CHARRING));
}

void saveRefunds(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.rules = Rules.creative;
    world.game.inventory = Inventory.init;
    world.game.inventory.gain(Stack(named("base:spruce-wood"), 1));
    world.game.keepCompound(starterDoses.ptr[0].molecule, RAW_PER_DOSE, 0);
    UiAction choose = {kind: UiKind.chooseCompound, index: 0};
    world.game.apply(choose, Click.primary);
    world.check(world.game.synthesize(synthesisNamed(PRESS_DOSE)) && world.game.craft(recipeNamed(PLANKS_RECIPE)), "could not queue a pressing and planks");
    world.step();
    world.check(world.game.crafts.length == 2 && world.game.crafts.ptr[0].started == Readiness.ready && world.game.crafts.ptr[1].started == Readiness.pending && world.game.compounds.ptr[0].raw == 0, "the pressing did not start alone on the first step");
    Writer writer;
    writeGame(*world.game, writer);
    SaveData data;
    const(char)* problem = readGame(writer.bytes.slice(), *world.game, data);
    world.check(problem is null, "the save written mid-craft does not read back");
    if (!world.isFailed) {
        world.check(data.inventory.countOf(named("base:spruce-wood")) == 1 && data.inventory.countOf(named("base:oak-wood")) == 0 && data.inventory.countOf(named("base:wood-planks")) == 0, "saving with planks queued kept %u spruce, %u oak and %u planks", data.inventory.countOf(named("base:spruce-wood")), data.inventory.countOf(named("base:oak-wood")), data.inventory.countOf(named("base:wood-planks")));
        world.check(data.compounds.length == 1 && data.compounds.ptr[0].raw == RAW_PER_DOSE && data.compounds.ptr[0].doses == 0, "saving during a pressing kept %zu compounds", data.compounds.length);
        world.check(data.time.value == world.game.time.value && data.time.value > 0, "the save holds the clock at %.3f s, the game is at %.3f s", data.time.value, world.game.time.value);
    }
    data.release();
    writer.bytes.release();
}

enum uint LEAVES_SLOT = 2;

enum uint PRESS_SLOT = HOTBAR_SLOTS - 1;

Maybe!uint slotHolding(ref Script world, Stack kind) {
    uint slot = 0;
    while (slot < SLOT_COUNT && !(!world.game.inventory.slots[slot].isEmpty && world.game.inventory.slots[slot].isSameKind(kind))) {
        slot += 1;
    }
    if (slot < SLOT_COUNT) {
        return Maybe!uint.of(slot);
    } else {
        return Maybe!uint.init;
    }
}

void geneHarvest(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.rules = Rules.creative;
    world.material(LEAVES_SLOT + 1);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.check(world.placeBlock() && walk.isMaterial(world.targetMaterial(), "base:oak-leaves"), "could not place the leaves");
    world.step();
    world.check(world.game.aim.kind == AimKind.living, "aiming at leaves does not read them as living");
    Molecule product = world.game.aim.living.product;
    uint leaves = world.game.inventory.countOf(named("base:oak-leaves"));
    world.check(world.breakBlock() && world.game.compounds.length == 0 && world.game.inventory.countOf(named("base:oak-leaves")) == leaves + 1, "breaking the leaves gave %zu compounds and %u leaves back", world.game.compounds.length, world.game.inventory.countOf(named("base:oak-leaves")) - leaves);
    Maybe!uint held = Maybe!uint.init;
    foreach (slot; 0 .. SLOT_COUNT) {
        if (world.game.inventory.slots[slot].genes.exists) {
            held = Maybe!uint.of(slot);
        }
    }
    world.check(held.exists && productOf(materialNamed("base:oak-leaves"), world.game.inventory.slots[held.value].genes.value) == product, "the broken leaves did not keep the genes that make the compound they read as");
    if (!world.isFailed) {
        Stack kind = world.game.inventory.slots[held.value].taken(1);
        world.game.inventory.slots[PRESS_SLOT] = Stack(named("base:press"), 1);
        world.material(PRESS_SLOT + 1);
        world.check(world.placeBlock() && world.interact() && world.game.screen == Screen.station, "could not place and open the press");
        world.check(world.game.pressLiving(held.value), "could not queue pressing the leaves");
        world.step();
        world.check(world.game.inventory.countOfKind(kind) == 0, "pressing did not take the leaves");
        world.game.cancelCraft(0);
        world.check(world.game.inventory.countOfKind(kind) == 1, "cancelling the pressing did not give the same leaves back");
        Maybe!uint again = slotHolding(world, kind);
        world.check(again.exists && world.game.pressLiving(again.value), "could not queue pressing the leaves again");
        world.wait(syntheses()[synthesisNamed(PRESS_EXTRACT).id].time.value + MINING_SLACK_SECONDS);
        world.link(Topic.plants, Topic.chemistry, "Pressing a living block yields extract of the compound that its genes make.", world.game.compounds.length == 1 && world.game.compounds.ptr[0].molecule == product && world.game.compounds.ptr[0].raw == HARVEST_RAW, Measure.of("compounds held", world.game.compounds.length), Measure.of("extract expected", HARVEST_RAW));
        world.check(world.game.inventory.countOfKind(kind) == 0, "the pressed leaves are still held");
    }
}

void geneKept(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    WildGenes genes = WildGenes([41, 42, 43, 44]);
    Stack kind = Stack(named("base:oak-leaves"), 1, Maybe!WildGenes.of(genes));
    world.game.inventory.slots[0] = kind;
    world.material(1);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.check(world.placeBlock() && world.game.inventory.countOfKind(kind) == 0, "could not place the leaves");
    world.step();
    world.check(world.game.aim.kind == AimKind.living && world.game.aim.living.product == productOf(materialNamed("base:oak-leaves"), genes), "placed leaves read as another compound than their genes make");
    world.claim(Topic.plants, "A living block that is placed and broken again comes back with the genes it had.", world.breakBlock() && world.game.inventory.countOfKind(kind) == 1);
}

void geneSynthesis(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.rules = Rules.creative;
    Molecule starter = starterDoses.ptr[0].molecule;
    world.game.keepCompound(starter, 2 * RAW_PER_DOSE, 0);
    UiAction choose = {kind: UiKind.chooseCompound, index: 0};
    world.game.apply(choose, Click.primary);
    Synthesis press = synthesisNamed(PRESS_DOSE);
    world.check(world.game.synthesize(press) && world.game.synthesize(press), "could not queue two pressings");
    world.wait(2 * syntheses()[press.id].time.value + MINING_SLACK_SECONDS);
    world.claim(Topic.chemistry, "A press turns extract into doses.", world.game.compounds.ptr[0].doses == 2 && world.game.compounds.ptr[0].raw == 0, Measure.of("extract before", 2 * RAW_PER_DOSE), Measure.of("doses after", world.game.compounds.ptr[0].doses), Measure.of("extract after", world.game.compounds.ptr[0].raw));
    uint changing = 0;
    while (changing < syntheses().length && (syntheses()[changing].reaction == Reaction.press || synthesized(starter, Synthesis(cast(ubyte) changing)).value == starter)) {
        changing += 1;
    }
    world.check(changing < syntheses().length, "no lab operation changes the starter compound");
    if (!world.isFailed) {
        Synthesis chosen = Synthesis(cast(ubyte) changing);
        world.check(world.game.synthesize(chosen), "could not queue a change to the compound");
        world.wait(syntheses()[chosen.id].time.value + MINING_SLACK_SECONDS);
        world.claim(Topic.chemistry, "A lab reaction waits until its reagent is in the inventory.", world.game.compounds.length == 1 && world.game.crafts.length == 1, Measure.of("compounds held", world.game.compounds.length), Measure.of("crafts waiting", world.game.crafts.length));
        world.game.inventory.gain(Stack(syntheses()[chosen.id].reagent, 1));
        world.wait(syntheses()[chosen.id].time.value + MINING_SLACK_SECONDS);
        world.check(world.game.compounds.length == 2 && world.game.compounds.ptr[1].doses == 1 && world.game.compounds.ptr[1].molecule == synthesized(starter, chosen).value, "the lab made %zu compounds", world.game.compounds.length);
        world.claim(Topic.chemistry, "A dose cannot be taken by a route whose device the player lacks.", !world.game.takeDose(routeIndexOf(Route.injected)), Measure.of("route", "injected"));
        world.link(Topic.chemistry, Topic.body, "Taking a dose puts its compound into the body.", world.game.takeDose(routeIndexOf(Route.ingested)) && world.game.organism.body.count == 1, Measure.of("compounds in the body", world.game.organism.body.count));
    }
}

uint routeIndexOf(Route route) {
    uint index = 0;
    while (doseRoutes()[index].route != route) {
        index += 1;
    }
    return index;
}

void flatPlace(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    bool placed = world.placeBlock();
    world.claim(Topic.blocks, "A block cannot be placed where the body stands.", !placed);
    world.wait(0.5);
    walk.checkStanding(world, "after the refused placement");
    world.look(degrees(0), degrees(AHEAD_DEGREES - walk.STRAIGHT_DOWN_DEGREES));
    placed = world.placeBlock();
    world.check(placed, "placing a block ahead succeeds");
    world.wait(0.5);
    walk.checkStanding(world, "after placing ahead");
}

enum double STEP_WALK_SECONDS = 3;
enum float CLIMB_SPEED_TOLERANCE = 1.5f;

void flatStair(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    walk.checkStanding(world, "before building");
    walk.buildStep(world);
    float standing = world.altitude().value;
    Motion motion;
    walk.trackMotion(world, &motion);
    double deadline = world.time().value + STEP_WALK_SECONDS;
    world.hold(Key.forward);
    bool onStep = walk.probeOnStep(world, standing);
    while (!world.isFailed && world.time().value < deadline && !onStep) {
        world.step();
        onStep = walk.probeOnStep(world, standing);
    }
    world.release(Key.forward);
    world.wait(walk.SETTLE_SECONDS);
    world.onStep(StepHook.init);
    world.claim(Topic.movement, "The body walks up a step one block high without leaving the ground.", motion.offGround == 0, Measure.of("steps spent off the ground", motion.offGround));
    walk.checkOnStep(world, standing, "after walking onto the step");
}

struct Stepover {
    Motion motion;
    float fastest = 0;
    float traveled = 0;
}

void stepoverHook(ref Script world, void* context) {
    Stepover* over = cast(Stepover*) context;
    over.fastest = higherOf(over.fastest, (world.traveled().value - over.traveled) / world.timestep.value);
    over.traveled = world.traveled().value;
    walk.observe(world, over.motion);
}

void flatStepover(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    walk.buildStep(world);
    float standing = world.altitude().value;
    Stepover over = Stepover(walk.motionFrom(world), 0, world.traveled().value);
    world.onStep(StepHook(&stepoverHook, &over));
    double deadline = world.time().value + STEP_WALK_SECONDS;
    world.hold(Key.forward);
    bool onStep = walk.probeOnStep(world, standing);
    while (!world.isFailed && world.time().value < deadline && !onStep) {
        world.step();
        onStep = walk.probeOnStep(world, standing);
    }
    world.release(Key.forward);
    world.onStep(StepHook.init);
    onStep = walk.probeOnStep(world, standing);
    world.check(onStep, "walked onto the step");
    world.check(over.motion.offGround == 0, "left the ground on %u steps walking up a one-block step", over.motion.offGround);
    world.check(over.fastest <= walk.SPEED * CLIMB_SPEED_TOLERANCE, "moved at %.4f stepping up, walking is %.4f", over.fastest, walk.SPEED);
}

enum float DROP_HEIGHT = 0.3f;
enum Time DROP_STEP = Time(2.0f);
enum double TIMESTEP_WALK_SECONDS = 2;
enum Time LONG_STEP = Time(0.5f);
enum double TIMESTEP_CLIMB_SECONDS = 4;
enum Time CLIMB_STEP = Time(0.25f);
enum double STOP_SECONDS = 0.5;
enum float WALK_TOLERANCE = 0.001f;

float walkFromRest(ref Script world, Time dt) {
    float start = world.traveled().value;
    world.hold(Key.forward);
    world.wait(TIMESTEP_WALK_SECONDS, dt);
    world.release(Key.forward);
    float walked = world.traveled().value - start;
    world.wait(STOP_SECONDS);
    return walked;
}

void flatTimestep(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    walk.checkStanding(world, "before the drop");
    world.mode(MovementMode.fly);
    world.press(DROP_HEIGHT / walk.FLY_SPEED, Key.up);
    world.step();
    world.mode(MovementMode.walk);
    world.step(DROP_STEP);
    walk.checkStanding(world, "after one 2.0 s step falling 0.30");
    float inShortSteps = walkFromRest(world, world.timestep);
    float inLongSteps = walkFromRest(world, LONG_STEP);
    world.claim(Topic.movement, "Walking covers the same distance whether time advances in long steps or in short ones.", fabs(inLongSteps - inShortSteps) <= WALK_TOLERANCE, Measure.of("walked in long steps", inLongSteps), Measure.of("long step (seconds)", LONG_STEP.value), Measure.of("walked in short steps", inShortSteps), Measure.of("short step (seconds)", world.timestep.value));
    walk.checkStanding(world, "after walking in long steps");
    walk.buildStep(world);
    float standing = world.altitude().value;
    walk.climbForward(world, TIMESTEP_CLIMB_SECONDS, CLIMB_STEP, ClimbGoal.ontoStep, standing);
    world.wait(walk.SETTLE_SECONDS);
    walk.checkOnStep(world, standing, "after jumping onto the step in 0.25 s steps");
}

immutable int[4] HEADINGS = [0, 90, 180, 270];
immutable float[4] AXIS_HEIGHTS = [0.25f, 1.0f, 2.0f, 3.0f];
enum double LEG_SECONDS = 3;
enum float LEAST_WALKED_FRACTION = 0.95f;

void flatWalk(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    walk.checkStanding(world, "after landing");
    Motion motion;
    walk.trackMotion(world, &motion);
    foreach (heading; HEADINGS) {
        float start = world.traveled().value;
        world.press(LEG_SECONDS, Key.forward);
        world.wait(0.5);
        float walked = world.traveled().value - start;
        float free = walk.SPEED * LEG_SECONDS;
        world.claim(Topic.movement, "On level ground the body walks at its walk speed whichever way it faces.", walked >= LEAST_WALKED_FRACTION * free, Measure.of("heading (degrees)", heading), Measure.of("walked", walked), Measure.of("expected", free), Measure.of("walk speed setting", world.game.character.walkSpeed.value));
        walk.checkStanding(world, "after a heading");
        world.turn(degrees(90), degrees(0), 0.5);
    }
    world.press(LEG_SECONDS, Key.forward, Key.up);
    world.wait(1);
    world.onStep(StepHook.init);
    walk.checkSpeedLimit(world, motion);
    walk.checkStanding(world, "after hopping");
}

enum uint WALL_BLOCKS = 2;
enum double WALL_APPROACH_SECONDS = 0.3;
enum double WALL_PUSH_SECONDS = 2.5;
enum float CONTACT_SPEED_FRACTION = 0.8f;
enum float MOST_CLIMB = 0.0025f;
enum float VERTICAL_SPEED_TOLERANCE = 0.005f;

void flatWall(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    walk.checkStanding(world, "before building");
    walk.buildWall(world, WALL_BLOCKS);
    world.wait(2);
    walk.checkStanding(world, "back on the floor");
    float standing = world.altitude().value;
    Motion motion;
    walk.trackMotion(world, &motion);
    float start = world.traveled().value;
    world.hold(Key.forward);
    world.wait(WALL_APPROACH_SECONDS + WALL_PUSH_SECONDS);
    world.release(Key.forward);
    world.onStep(StepHook.init);
    float walked = world.traveled().value - start;
    float free = walk.SPEED * (WALL_APPROACH_SECONDS + WALL_PUSH_SECONDS);
    world.check(walked <= CONTACT_SPEED_FRACTION * free, "walked %.4f of a free %.4f, so the wall was not reached", walked, free);
    world.claim(Topic.movement, "The body cannot walk up a wall two blocks high.", motion.highest - standing <= MOST_CLIMB, Measure.of("climbed", motion.highest - standing));
    world.check(motion.rise <= VERTICAL_SPEED_TOLERANCE, "vertical speed reached %.4f against the wall", motion.rise);
    world.check(motion.offGround == 0, "left the ground on %u steps walking into the wall", motion.offGround);
    walk.checkSpeedLimit(world, motion);
    walk.checkStanding(world, "against the wall");
}

enum double DRIFT_CLIMB_SECONDS = 2;
enum uint DRIFT_LEGS = 6;
enum float DRIFT_LEG_DISTANCE = 1.0f;
enum Length DRIFT_RADIUS = Length(2.0f);
enum float MOST_DRIFT = 1e-3f;

void liveDrift(ref Script world) {
    world.live();
    world.mode(MovementMode.fly);
    world.press(DRIFT_CLIMB_SECONDS, Key.up);
    foreach (leg; 0 .. DRIFT_LEGS) {
        world.press(DRIFT_LEG_DISTANCE / walk.FLY_SPEED, Key.forward);
        float drift = world.probeFrameDrift(DRIFT_RADIUS).value;
        world.claim(Topic.world, "However far the player flies, cells are drawn where they are.", drift < MOST_DRIFT, Measure.of("flown", (leg + 1) * DRIFT_LEG_DISTANCE), Measure.of("largest offset", drift));
    }
}

enum uint BENCH_SLOT = 7;

void geneBreedSplice(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    WildGenes first = WildGenes([11, 12, 13, 14]);
    WildGenes second = WildGenes([21, 22, 23, 24]);
    Stack mother = Stack(named("base:flower"), 2, Maybe!WildGenes.of(first));
    Stack father = Stack(named("base:flower"), 1, Maybe!WildGenes.of(second));
    world.game.inventory.slots[HOTBAR_SLOTS] = mother;
    world.game.inventory.slots[HOTBAR_SLOTS + 1] = father;
    world.material(BENCH_SLOT);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.check(world.placeBlock() && walk.isMaterial(world.targetMaterial(), "base:bench"), "could not place the bench");
    world.interact();
    world.check(world.game.screen == Screen.bench, "right clicking the bench did not open it");
    world.check(world.game.chosen[0] == MaybeIndex!uint.of(HOTBAR_SLOTS) && world.game.chosen[1] == MaybeIndex!uint.of(HOTBAR_SLOTS + 1), "opening the bench did not mark the two flowers");
    uint flowers = world.game.inventory.countOf(named("base:flower"));
    world.check(world.cross(), "could not cross the flowers");
    world.check(world.game.inventory.countOfKind(mother) == 1 && world.game.inventory.countOfKind(father) == 1 && world.game.inventory.countOf(named("base:flower")) == flowers, "crossing did not turn one of the first flower into the cross: %u first, %u second, %u flowers from %u", world.game.inventory.countOfKind(mother), world.game.inventory.countOfKind(father), world.game.inventory.countOf(named("base:flower")), flowers);
    Maybe!uint childSlot = Maybe!uint.init;
    foreach (slot; 0 .. SLOT_COUNT) {
        Stack stack = world.game.inventory.slots[slot];
        if (!stack.isEmpty && stack.genes.exists && !stack.isSameKind(mother) && !stack.isSameKind(father)) {
            childSlot = Maybe!uint.of(slot);
        }
    }
    world.check(childSlot.exists, "the cross is not in the inventory");
    if (!world.isFailed) {
        WildGenes child = world.game.inventory.slots[childSlot.value].genes.value;
        uint inherited = 0;
        foreach (index; 0 .. WILD_GENES) {
            if (child.seeds[index] == first.seeds[index] || child.seeds[index] == second.seeds[index]) {
                inherited += 1;
            }
        }
        world.claim(Topic.breeding, "A cross takes each of its genes from one of its two parents, apart from the occasional mutation.", inherited >= WILD_GENES - 1, Measure.of("genes taken from a parent", inherited), Measure.of("genes in all", WILD_GENES));
        uint genes = world.game.organism.genome.count;
        world.link(Topic.breeding, Topic.body, "Splicing uses up the plant and adds one gene to the player's genome.", world.splice() && world.game.organism.genome.count == genes + 1 && world.game.inventory.countOfKind(mother) == 0, Measure.of("genes before", genes), Measure.of("genes after", world.game.organism.genome.count));
    }
}

void geneGrow(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    WildGenes genes = WildGenes([31, 32, 33, 34]);
    world.game.inventory.slots[0] = Stack(named("base:flower"), 1, Maybe!WildGenes.of(genes));
    world.material(1);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.check(world.placeBlock() && world.game.inventory.slots[0].isEmpty, "planting did not use the flower");
    world.step();
    world.check(world.game.aim.kind == AimKind.living && world.game.aim.living.growth == Readiness.pending && world.game.aim.living.product == productOf(materialNamed("base:flower"), genes), "aiming at the planted flower does not read it as a growing plant with its genes");
    world.wait(GROWN_SECONDS.value + 1);
    world.claim(Topic.plants, "A planted plant reads as growing at first, and as ripe once its growing time has passed.", world.game.aim.living.growth == Readiness.ready, Measure.of("growing time (seconds)", GROWN_SECONDS.value));
}

enum double HALF_EAT_SECONDS = 0.5;
enum float EATEN_TOLERANCE = 0.01f;

bool notedSince(ref Script world, NoteKind kind, Time since) {
    size_t index = 0;
    while (index < world.game.notes.length && !(world.game.notes.ptr[index].kind == kind && !(world.game.notes.ptr[index].at < since))) {
        index += 1;
    }
    return index < world.game.notes.length;
}

void plantEat(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.inventory.slots[0] = Stack(named("base:flower"), 2);
    world.material(1);
    Time tried = world.time();
    world.check(!world.eat() && notedSince(world, NoteKind.noGenes, tried), "ate a flower with no genes of its own");
    WildGenes genes = WildGenes([51, 52, 53, 54]);
    world.game.inventory.slots[0] = Stack(named("base:flower"), 2, Maybe!WildGenes.of(genes));
    world.press(HALF_EAT_SECONDS, Key.eat);
    world.step();
    world.check(world.game.inventory.slots[0].count == 2 && world.game.organism.body.count == 0, "letting go of eat after %.1f s still ate", HALF_EAT_SECONDS);
    world.check(world.eat() && world.game.inventory.slots[0].count == 1 && world.game.organism.body.count == 1, "holding eat did not eat one flower: %u left, %u molecules in the body", world.game.inventory.slots[0].count, world.game.organism.body.count);
    if (!world.isFailed) {
        const(Body)* body = &world.game.organism.body;
        float eaten = body.species[0].gut.value + body.species[0].blood.value;
        world.link(Topic.plants, Topic.body, "Eating a living block puts one dose of the compound its genes make into the body.", body.species[0].molecule == productOf(materialNamed("base:flower"), genes) && fabs(eaten - PLANT_DOSE.value) < EATEN_TOLERANCE, Measure.of("amount in the body", eaten), Measure.of("one dose", PLANT_DOSE.value));
    }
    world.material(2);
    tried = world.time();
    world.check(!world.eat() && notedSince(world, NoteKind.nothingToEat, tried), "ate something that is not living");
}

enum double SCREEN_WALK_SECONDS = 1;
enum float SCREEN_DRIFT = 1e-3f;
enum uint PACK_SLOT = HOTBAR_SLOTS + 3;

void uiScreenHolds(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.open(Screen.character);
    float start = world.traveled().value;
    world.press(SCREEN_WALK_SECONDS, Key.forward);
    float walked = world.traveled().value - start;
    world.check(walked < SCREEN_DRIFT, "walked %.5f while the inventory was open", walked);
    Stack first = world.game.inventory.slots[0];
    UiAction pick = {kind: UiKind.slot, index: 0};
    world.game.apply(pick, Click.primary);
    world.check(world.game.inventory.slots[0].isEmpty && world.game.carried == first, "clicking slot 1 did not pick up its stack");
    UiAction drop = {kind: UiKind.slot, index: PACK_SLOT};
    world.game.apply(drop, Click.secondary);
    world.check(world.game.inventory.slots[PACK_SLOT].count == 1 && world.game.carried.count == first.count - 1, "a right click put %u in the pack slot, leaving %u carried", world.game.inventory.slots[PACK_SLOT].count, world.game.carried.count);
    UiAction closing = {kind: UiKind.close};
    world.game.apply(closing, Click.primary);
    world.check(world.game.carried.isEmpty && world.game.inventory.countOf(first.item) == first.count, "closing the inventory lost carried blocks: %u of %u left", world.game.inventory.countOf(first.item), first.count);
    walk.forward(world, SCREEN_WALK_SECONDS, LEAST_FREE_FRACTION);
}

void uiCatalog(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.rules = Rules.creative;
    world.game.inventory = Inventory.init;
    world.open(Screen.character);
    UiAction catalog = {kind: UiKind.sheet, index: Sheet.catalog};
    world.game.apply(catalog, Click.primary);
    Item lab = named("base:lab");
    UiAction take = {kind: UiKind.takeItem, index: lab.id};
    world.game.apply(take, Click.primary);
    world.check(world.game.sheet == Sheet.catalog && world.game.carried == Stack(lab, STACK_LIMIT), "the catalog gave %u of item %u, not a stack of labs", world.game.carried.count, world.game.carried.item.id);
    UiAction drop = {kind: UiKind.slot, index: PACK_SLOT};
    world.game.apply(drop, Click.primary);
    Item syringe = named("base:syringe");
    UiAction one = {kind: UiKind.takeItem, index: syringe.id};
    world.game.apply(one, Click.secondary);
    world.check(world.game.inventory.slots[PACK_SLOT] == Stack(lab, STACK_LIMIT) && world.game.carried == Stack(syringe, 1), "dropping the labs and taking one syringe left %u in the slot and %u carried", world.game.inventory.slots[PACK_SLOT].count, world.game.carried.count);
}

enum uint COLLECTOR_SLOT = 8;
enum double COLLECTING_SECONDS = 30;
enum float COLLECTED_TOLERANCE = 1e-3f;

void plantCollector(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.material(COLLECTOR_SLOT);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.check(world.placeBlock(), "could not place the collector");
    world.wait(COLLECTING_SECONDS);
    world.interact();
    world.check(world.game.screen == Screen.collector, "right clicking the collector did not open it");
    world.game.breatheMachine();
    const(Body)* body = &world.game.organism.body;
    world.check(body.count == GAS_COUNT, "breathing the collected air dosed %u gases", body.count);
    if (!world.isFailed) {
        uint slot = world.game.world.graph.slotOf(world.game.characterState.position.node).value;
        AirMix air = airOf(world.game.world.graph.stateAt(slot).climate.climate());
        float expected = air.fractions[0].value * COLLECTION_RATE.value * cast(float) COLLECTING_SECONDS;
        float held = body.species[0].lung.value + body.species[0].blood.value;
        world.link(Topic.air, Topic.body, "A collector gathers a gas at its share of the local air times the collection rate, and breathing it in puts that much into the body.", fabs(held - expected) < COLLECTED_TOLERANCE + expected * 0.05f, Measure.of("seconds collecting", COLLECTING_SECONDS), Measure.of("first gas breathed in", held), Measure.of("predicted", expected));
        world.game.breatheMachine();
        float again = body.species[0].lung.value + body.species[0].blood.value;
        world.check(fabs(again - held) < COLLECTED_TOLERANCE, "collecting again at once added %.4f", again - held);
    }
}

enum uint BEACON_SLOT = 9;
enum float BEACON_AWAY = 6.0f;
enum float BEACON_DISTANCE_TOLERANCE = 0.3f;
enum double BEHIND_DEGREES = 150;

void beaconHome(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.material(BEACON_SLOT);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.check(world.placeBlock() && world.game.beacons.length == 1, "placed no beacon");
    if (!world.isFailed) {
        world.look(degrees(0), degrees(-AHEAD_DEGREES));
        float near = world.game.sightingOf(world.game.beacons.ptr[0]).distance.value;
        world.mode(MovementMode.noclip);
        world.press(BEACON_AWAY / walk.NOCLIP_SPEED, Key.back);
        world.step();
        BeaconSighting far = world.game.sightingOf(world.game.beacons.ptr[0]);
        double toward = world.game.yawToward(far.direction).value / RADIANS_PER_DEGREE;
        world.claim(Topic.navigation, "Backing straight away from a beacon, its distance grows by the distance travelled.", fabs(far.distance.value - near - BEACON_AWAY) < BEACON_DISTANCE_TOLERANCE, Measure.of("distance at first", near), Measure.of("backed away by", BEACON_AWAY), Measure.of("distance then", far.distance.value));
        world.claim(Topic.navigation, "A beacon the player backed away from still lies ahead.", fabs(toward) < 180 - BEHIND_DEGREES, Measure.of("direction off straight ahead (degrees)", toward));
        world.press(BEACON_AWAY / walk.NOCLIP_SPEED, Key.forward);
        world.mode(MovementMode.walk);
        world.wait(walk.LANDING_SECONDS);
        world.look(degrees(0), degrees(AHEAD_DEGREES));
        world.check(world.breakBlock() && world.game.beacons.length == 0, "breaking the beacon left %zu beacons", world.game.beacons.length);
    }
}

enum float SAVE_WALK = 0.5f;
enum float SAVE_PLACE_TOLERANCE = 1e-3f;

void saveRoundTrip(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.mode(MovementMode.noclip);
    world.press(SAVE_WALK / walk.NOCLIP_SPEED, Key.forward);
    world.mode(MovementMode.walk);
    world.wait(walk.LANDING_SECONDS);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.check(world.placeBlock(), "placed a block to save");
    world.dose();
    world.wait(1);
    Writer writer;
    writeGame(*world.game, writer);
    ClientConfig config;
    Game copy = Game.make(world.game.world.graph.worldgen, config.reach);
    copy.supply = ChunkSupply.onDemand;
    SaveData data;
    const(char)* problem = readGame(writer.bytes.slice(), copy, data);
    world.check(problem is null, "the save did not read back: it %s", problem);
    if (problem is null) {
        applyEdits(copy, data);
        StructureProblem placed = copy.placeStructure();
        world.check(!placed.isPresent, "the copy's world did not start");
        applyState(copy, data);
        world.claim(Topic.saves, "A save keeps every block the player changed.", copy.world.graph.edits.cellCount == world.game.world.graph.edits.cellCount, Measure.of("blocks changed", world.game.world.graph.edits.cellCount), Measure.of("loaded back", copy.world.graph.edits.cellCount));
        world.claim(Topic.saves, "A save keeps the inventory.", copy.inventory == world.game.inventory);
        world.claim(Topic.saves, "A save keeps what is in the body.", copy.organism.body.count == world.game.organism.body.count && copy.organism.body.species[0].blood == world.game.organism.body.species[0].blood, Measure.of("compounds in the body", world.game.organism.body.count));
        Position here = world.game.characterState.position;
        Position there = copy.characterState.position;
        float apart = (here.local * Point!float.origin()).distance(there.local * Point!float.origin());
        world.claim(Topic.saves, "A save keeps where the player stands.", here.node == there.node && apart < SAVE_PLACE_TOLERANCE, Measure.of("came back this far away", apart));
    }
    Game other = Game.make(Worldgen.makeTerrain(), config.reach);
    SaveData refused;
    world.claim(Topic.saves, "A save made in one world does not load into another.", readGame(writer.bytes.slice(), other, refused) !is null);
    refused.release();
    other.release();
    data.release();
    copy.release();
    writer.bytes.release();
}

enum float EDIT_AWAY = 12.0f;
enum float EDIT_RISE = 0.5f;
enum double EDIT_LOAD_SECONDS = 3;
enum double EDIT_AHEAD_DEGREES = 30;
enum double MOST_EVICTION_SECONDS = 30;

void travel(ref Script world, Key along) {
    world.press(EDIT_RISE / walk.NOCLIP_SPEED, Key.up);
    world.press(EDIT_AWAY / walk.NOCLIP_SPEED, along);
    world.press(EDIT_RISE / walk.NOCLIP_SPEED, Key.down);
    world.wait(EDIT_LOAD_SECONDS);
}

Maybe!Material storedAt(ref Script world, Placement placement) {
    const(Graph)* graph = &world.game.world.graph;
    MaybeIndex!uint slot = graph.slotOf(placement.chunk.node);
    if (slot.exists && graph.chunks.at(ChunkSlot(slot.value, placement.chunk.corner)).state == ChunkState.populated) {
        return Maybe!Material.of(graph.chunks.at(ChunkSlot(slot.value, placement.chunk.corner)).voxels.at(cellIndex(graph.layout.dimension, placement.coords.x, placement.coords.y, placement.coords.z)));
    } else {
        return Maybe!Material.init;
    }
}

void liveEditKept(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.live();
    world.mode(MovementMode.noclip);
    travel(world, Key.forward);
    world.look(degrees(0), degrees(EDIT_AHEAD_DEGREES));
    Maybe!Placement target = world.game.world.placementTarget();
    world.check(target.exists && world.placeBlock(), "could not place the block to keep");
    if (!world.isFailed) {
        NodeId edited = target.value.chunk.node;
        Maybe!Material placed = world.targetMaterial();
        world.look(degrees(0), degrees(-EDIT_AHEAD_DEGREES));
        travel(world, Key.back);
        double waited = 0;
        while (!world.isFailed && world.game.world.graph.slotOf(edited).exists && waited < MOST_EVICTION_SECONDS) {
            world.wait(ONSET_STEP_SECONDS);
            waited += ONSET_STEP_SECONDS;
        }
        world.check(!world.game.world.graph.slotOf(edited).exists, "the edited node is still loaded %.0f s after going %.0f back toward the root, so nothing was evicted", MOST_EVICTION_SECONDS, EDIT_AWAY);
        travel(world, Key.forward);
        Maybe!Material back = storedAt(world, target.value);
        const(char)[] before = walk.nameOf(placed);
        const(char)[] after = walk.nameOf(back);
        world.claim(Topic.world, "A block the player placed is still there after its cell was dropped and made again.", placed.exists && back.exists && back.value == placed.value, Measure.of("placed", before), Measure.of("found afterwards", after));
    }
}

enum double FAR_CLIMB_SECONDS = 2;
enum uint FAR_LEGS = 8;
enum float FAR_LEG_DISTANCE = 4.0f;
enum float ALTITUDE_DRIFT = 0.01f;
enum float MOST_PROBE_DEPTH = 2.0f;
enum double AWAY_FROM_TREE_DEGREES = 180;
enum Length CLOSE = Length(0.5f);

struct Probe {
    Maybe!Material below;
    float depth = 0;
}

Probe groundBelow(ref Script world) {
    uint mostSteps = cast(uint)(MOST_PROBE_DEPTH / (walk.NOCLIP_SPEED * world.timestep.value) + 0.999f);
    Maybe!Material below = walk.lookBelow(world);
    uint steps = 0;
    world.hold(Key.down);
    while (!world.isFailed && !below.exists && steps < mostSteps) {
        world.step();
        steps += 1;
        below = walk.lookBelow(world);
    }
    world.release(Key.down);
    world.hold(Key.up);
    foreach (_; 0 .. steps) {
        world.step();
    }
    world.release(Key.up);
    return Probe(below, steps * walk.NOCLIP_SPEED * world.timestep.value);
}

void liveFar(ref Script world) {
    world.live();
    world.look(degrees(AWAY_FROM_TREE_DEGREES), degrees(0));
    world.mode(MovementMode.fly);
    world.press(FAR_CLIMB_SECONDS, Key.up);
    world.mode(MovementMode.noclip);
    float start = world.altitude().value;
    foreach (leg; 0 .. FAR_LEGS) {
        world.press(FAR_LEG_DISTANCE / walk.NOCLIP_SPEED, Key.forward);
        float altitude = world.altitude().value;
        UnloadedCount unloaded = world.unloadedWithin(CLOSE);
        Probe probe = groundBelow(world);
        world.check(fabs(altitude - start) < ALTITUDE_DRIFT && probe.below.exists, "after %.0f units: altitude %.3f from %.3f, %u fresh %u generating %u nodes missing, %s below within %.2f", (leg + 1) * FAR_LEG_DISTANCE, altitude, start, unloaded.fresh, unloaded.generating, unloaded.missingNodes, textFor(probe.below.exists, "something", "nothing"), probe.depth);
    }
}

enum uint FLY_SECONDS = 40;
enum uint NOCLIP_SECONDS = 30;
enum float LEAST_FLY_FRACTION = 0.9f;
enum double FLY_CLIMB_SECONDS = 3;

void checkClose(ref Script world, const(char)* what, uint second) {
    UnloadedCount unloaded = world.unloadedWithin(CLOSE);
    world.check(unloaded.fresh + unloaded.dropped == 0, "%s, second %u: %u fresh and %u dropped chunks right around the body (%u generating, %u waiting for a building, %u nodes missing)", what, second, unloaded.fresh, unloaded.dropped, unloaded.generating, unloaded.awaitingBuilding, unloaded.missingNodes);
}

void liveFly(ref Script world) {
    world.live();
    world.look(degrees(AWAY_FROM_TREE_DEGREES), degrees(0));
    world.mode(MovementMode.fly);
    world.press(FLY_CLIMB_SECONDS, Key.up);
    foreach (second; 1 .. FLY_SECONDS + 1) {
        float before = world.traveled().value;
        world.press(1, Key.forward);
        float flown = world.traveled().value - before;
        world.check(flown >= LEAST_FLY_FRACTION * walk.FLY_SPEED, "flew %.3f in second %u, %s at altitude %.3f", flown, second, textFor(world.isLoaded(), "loaded", "not loaded"), world.altitude().value);
        checkClose(world, "flying", second);
    }
    world.mode(MovementMode.walk);
    world.wait(walk.LANDING_SECONDS);
    world.check(world.isLoaded(), "landed where the world is loaded");
    world.mode(MovementMode.noclip);
    foreach (second; 1 .. NOCLIP_SECONDS + 1) {
        float before = world.traveled().value;
        world.press(1, Key.forward);
        world.check(world.traveled().value - before >= LEAST_FLY_FRACTION * walk.NOCLIP_SPEED, "noclip moved %.3f in second %u", world.traveled().value - before, second);
        checkClose(world, "noclip", second);
    }
}

enum double MOST_ONSET_SECONDS = 30;
enum double ONSET_STEP_SECONDS = 0.5;
enum double SOBER_SECONDS = 20;
enum float SOBER_SIGNAL = 1e-4f;

void biologyDosedClimb(ref Script world) {
    world.structure("hiddenstair");
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    world.dose();
    double waited = 0;
    while (!world.isFailed && !world.game.reveal.revealed.has(materialNamed("base:mist-stone")) && waited < MOST_ONSET_SECONDS) {
        world.wait(ONSET_STEP_SECONDS);
        waited += ONSET_STEP_SECONDS;
    }
    world.link(Topic.body, Topic.perception, "A swallowed dose of the first starter compound raises the mist signal until the hidden mist blocks are revealed.", world.game.reveal.revealed.has(materialNamed("base:mist-stone")), Measure.of("seconds until revealed", waited), Measure.of("mist signal then", world.game.organism.signaling.signalOf(0).value));
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    world.link(Topic.perception, Topic.movement, "Blocks that a dose reveals are solid: the body can climb a stair made of them.", !world.routeWaypoint(reached + 1).exists && world.altitude().value > HIDDEN_RISE, Measure.of("climbed to", world.altitude().value), Measure.of("stops reached", reached));
}

void biologySober(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.wait(SOBER_SECONDS);
    foreach (signal; 0 .. 3) {
        float level = world.game.organism.signaling.signalOf(signal).value;
        world.claim(Topic.body, "With nothing in the body, its signals stay at rest.", level <= SOBER_SIGNAL && level >= -SOBER_SIGNAL, Measure.of("signal", signal), Measure.of("level", level));
    }
}

enum float HIDDEN_RISE = 1.5f;
enum size_t INSIDE_STOP = 6;
enum float SINK_INTO_TREAD = 0.03f;

void hiddenClimb(ref Script world) {
    world.structure("hiddenstair");
    world.perceive("base:mist-sight");
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    world.check(world.isOnGround(), "standing at the foot of the revealed stair");
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    world.check(!world.routeWaypoint(reached + 1).exists, "stopped after %zu waypoints on the revealed stair", reached);
    world.link(Topic.perception, Topic.movement, "A stair of hidden blocks can be climbed while perception reveals them.", world.isOnGround() && world.altitude().value > HIDDEN_RISE, Measure.of("climbed to", world.altitude().value));
}

void hiddenUnrevealed(ref Script world) {
    world.structure("hiddenstair");
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    climb.follow(world, Maybe!size_t.init);
    bool stuck = world.takeFailure();
    world.check(stuck, "walked the whole route of a stair that is not revealed");
    world.link(Topic.perception, Topic.movement, "Hidden blocks that are not revealed do not hold the body up.", world.altitude().value < HIDDEN_RISE, Measure.of("rose to", world.altitude().value));
}

void hiddenRevealInside(ref Script world) {
    world.structure("hiddenstair");
    world.perceive("base:mist-sight");
    world.enterRoute(INSIDE_STOP);
    world.wait(walk.SETTLE_SECONDS);
    world.check(world.isOnGround(), "standing on a revealed tread");
    world.perceive("plain");
    world.mode(MovementMode.noclip);
    world.press(SINK_INTO_TREAD / walk.NOCLIP_SPEED, Key.down);
    world.perceive("base:mist-sight");
    world.link(Topic.perception, Topic.movement, "Hidden blocks that are revealed while the body is inside them stay passable.", !world.game.reveal.touchable.has(materialNamed("base:mist-stone")));
    world.mode(MovementMode.walk);
    world.wait(walk.LANDING_SECONDS);
    world.check(world.isOnGround(), "did not land after falling out of the stair");
    world.link(Topic.perception, Topic.movement, "Revealed hidden blocks turn solid once the body is no longer inside them.", world.game.reveal.touchable.has(materialNamed("base:mist-stone")));
}

enum string FELT_PRESET = "base:heavy";
enum double FELT_WALK_SECONDS = 3;
enum float MOST_WALKED_FRACTION = 1.001f;

void perceptionBody(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.perceive(FELT_PRESET);
    CharacterConfig felt = world.game.character.effectiveFor(world.game.perception);
    world.check(felt.walkSpeed.value < walk.SPEED && felt.jumpHeight.value < IDEAL_RISE, "the preset should slow walking and lower the jump, but walks at %.4f and jumps %.4f", felt.walkSpeed.value, felt.jumpHeight.value);
    float standing = world.altitude().value;
    Jump jump = Jump(standing, 0);
    world.onStep(StepHook(&jumpHook, &jump));
    world.press(0.1, Key.up);
    world.wait(1.5);
    world.onStep(StepHook.init);
    float rise = jump.apex - standing;
    world.link(Topic.perception, Topic.movement, "Perception that lowers the jump height lowers the jump by as much.", rise >= LEAST_RISE_FRACTION * felt.jumpHeight.value && rise <= MOST_RISE_FRACTION * felt.jumpHeight.value, Measure.of("rose", rise), Measure.of("felt jump height", felt.jumpHeight.value), Measure.of("jump height without it", world.game.character.jumpHeight.value));
    walk.checkStanding(world, "after the heavy jump");
    float start = world.traveled().value;
    world.press(FELT_WALK_SECONDS, Key.forward);
    float walked = world.traveled().value - start;
    float free = felt.walkSpeed.value * FELT_WALK_SECONDS;
    world.link(Topic.perception, Topic.movement, "Perception that lowers the walk speed slows the walk by as much.", walked >= LEAST_WALKED_FRACTION * free && walked <= MOST_WALKED_FRACTION * free, Measure.of("walked", walked), Measure.of("felt walk speed times the time", free), Measure.of("walk speed without it", world.game.character.walkSpeed.value));
}

enum double TILT_DEGREES = 25;
enum double SLOPE_WALK_SECONDS = 8;
enum float LEAST_SLOPE_FRACTION = 0.8f;
enum float LEAST_CLIMB_FRACTION = 0.4f;

void slopeAcross(ref Script world) {
    walk.acrossSlope(world, TILT_DEGREES, 90, SLOPE_WALK_SECONDS, LEAST_SLOPE_FRACTION);
}

void slopeDownhill(ref Script world) {
    walk.acrossSlope(world, TILT_DEGREES, 180, SLOPE_WALK_SECONDS, LEAST_SLOPE_FRACTION);
}

void slopeUphill(ref Script world) {
    Across across = walk.acrossSlope(world, TILT_DEGREES, 0, SLOPE_WALK_SECONDS, LEAST_SLOPE_FRACTION);
    double ideal = across.walked * sin(TILT_DEGREES * RADIANS_PER_DEGREE);
    world.check(across.climbed >= LEAST_CLIMB_FRACTION * ideal, "climbed %.4f walking %.4f up a 25 degree slope", across.climbed, across.walked);
}

enum uint HOPS = 6;
enum double SECONDS_BETWEEN_HOPS = 0.544;
enum double JUMP_PRESS_SECONDS = 0.096;
enum double HOP_LANDING_SECONDS = 0.96;

void slopeHopping(ref Script world) {
    walk.onSlope(world, TILT_DEGREES, 0);
    Motion motion;
    walk.trackMotion(world, &motion);
    foreach (heading; 0 .. 3) {
        world.hold(Key.forward);
        foreach (_; 0 .. HOPS) {
            world.wait(SECONDS_BETWEEN_HOPS);
            world.press(JUMP_PRESS_SECONDS, Key.up);
        }
        world.release(Key.forward);
        world.wait(HOP_LANDING_SECONDS);
        world.turn(degrees(90), degrees(0), walk.TURN_SECONDS);
    }
    world.onStep(StepHook.init);
    walk.checkSpeedLimit(world, motion);
    world.check(world.isOnGround(), "on ground at the end");
}

enum double STEEP_DEGREES = 40;

void slopeSteep(ref Script world) {
    walk.onSlope(world, STEEP_DEGREES, 0);
    Motion motion;
    walk.trackMotion(world, &motion);
    float start = world.altitude().value;
    walk.climbForward(world, SLOPE_WALK_SECONDS, world.timestep, ClimbGoal.timed, 0);
    world.wait(walk.LANDING_SECONDS);
    world.onStep(StepHook.init);
    walk.checkSpeedLimit(world, motion);
    world.check(world.altitude().value > start, "climbed some of the slope");
    world.check(world.isOnGround(), "on ground at the end");
}

enum double TURN_DEGREES_PER_SECOND = 25;
enum double TURNING_SECONDS = 14.4;

void slopeTurning(ref Script world) {
    walk.onSlope(world, TILT_DEGREES, 0);
    Motion motion;
    walk.trackMotion(world, &motion);
    world.turnRate(degrees(TURN_DEGREES_PER_SECOND) / ONE_SECOND, AngularSpeed(0));
    world.press(TURNING_SECONDS, Key.forward);
    world.turnRate(AngularSpeed(0), AngularSpeed(0));
    world.wait(walk.SETTLE_SECONDS);
    world.onStep(StepHook.init);
    walk.checkSpeedLimit(world, motion);
    world.check(world.isOnGround(), "on ground at the end");
}

enum uint SLOPE_WALL_BLOCKS = 3;
enum double SLOPE_APPROACH_SECONDS = 0.5;
enum float MOST_RISE_SPEED = 0.1f;

struct Pushing {
    Motion motion;
    float slowest;
}

void pushingHook(ref Script world, void* context) {
    Pushing* pushing = cast(Pushing*) context;
    pushing.slowest = lowerOf(pushing.slowest, world.horizontalSpeed().value);
    walk.observe(world, pushing.motion);
}

void slopeWall(ref Script world) {
    walk.onSlope(world, TILT_DEGREES, 0);
    foreach (heading; HEADINGS) {
        if (heading != 0) {
            world.turn(degrees(90), degrees(0), walk.TURN_SECONDS);
        }
        walk.buildWall(world, SLOPE_WALL_BLOCKS);
        world.wait(2);
        world.check(world.isOnGround(), "heading %d: back on the ground after building", heading);
        Pushing pushing = Pushing(walk.motionFrom(world), world.horizontalSpeed().value);
        world.onStep(StepHook(&walk.observeHook, &pushing.motion));
        world.hold(Key.forward);
        world.wait(SLOPE_APPROACH_SECONDS);
        world.onStep(StepHook(&pushingHook, &pushing));
        world.wait(WALL_PUSH_SECONDS);
        world.release(Key.forward);
        world.wait(walk.SETTLE_SECONDS);
        world.onStep(StepHook.init);
        world.check(pushing.slowest <= CONTACT_SPEED_FRACTION * walk.SPEED, "heading %d: never slowed below %.4f, so the wall was not reached", heading, pushing.slowest);
        world.check(pushing.motion.rise <= MOST_RISE_SPEED, "heading %d: rose at %.4f against the wall", heading, pushing.motion.rise);
        walk.checkSpeedLimit(world, pushing.motion);
        world.check(world.isOnGround(), "heading %d: on ground against the wall", heading);
        world.press(walk.WALL_DISTANCE / walk.SPEED, Key.back);
    }
}

void climbing(string name, float minClimb, SpawnCheck spawnCheck)(ref Script world) {
    world.structure(name);
    if (spawnCheck == SpawnCheck.checked) {
        walk.spawn(world);
    }
    climb.route(world, minClimb);
}

void structureAxis(ref Script world) {
    world.structure("tower");
    world.mode(MovementMode.noclip);
    foreach (height; AXIS_HEIGHTS) {
        world.enterStructure(Length(height));
        world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
        world.step();
        world.check(world.targetMaterial().exists, "%.2f up the axis: no floor within reach below", height);
        world.look(degrees(0), degrees(-walk.STRAIGHT_DOWN_DEGREES));
    }
}

enum float RISEN_BACKROOMS_ALTITUDE = 1.5f;

void checkBackroomsAround(ref Script world) {
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    Maybe!Material below = world.targetMaterial();
    world.look(degrees(0), degrees(-2 * walk.STRAIGHT_DOWN_DEGREES));
    Maybe!Material above = world.targetMaterial();
    const(char)[] floor = walk.nameOf(below);
    const(char)[] ceiling = walk.nameOf(above);
    world.check(walk.isOneOf(below, walk.BACKROOMS_FLOORS[]), "standing on %.*s instead of the backrooms' floor", cast(int) floor.length, floor.ptr);
    world.check(walk.isOneOf(above, walk.BACKROOMS_CEILINGS[]), "under %.*s instead of the backrooms' ceiling", cast(int) ceiling.length, ceiling.ptr);
}

void structureBackrooms(ref Script world) {
    world.structure("risenbackrooms");
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    world.check(world.altitude().value < RISEN_BACKROOMS_ALTITUDE, "starting on the ground, %.3f up", world.altitude().value);
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    world.check(!world.routeWaypoint(reached + 1).exists, "stopped after %zu waypoints", reached);
    world.check(world.isOnGround(), "standing in the backrooms");
    world.check(world.altitude().value > RISEN_BACKROOMS_ALTITUDE, "ended only %.3f above the ground", world.altitude().value);
    checkBackroomsAround(world);
}

void structureBackroomsWorld(ref Script world) {
    world.structure("backrooms");
    walk.spawn(world);
    checkBackroomsAround(world);
}

enum float CHAIN_LOWER_ALTITUDE = 1.5f;
enum float LEAST_MOVED = 0.5f;

void structureChain(ref Script world) {
    world.structure("chain");
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    world.check(world.isOnGround(), "standing on the first city outside the connector's lower door");
    float start = world.altitude().value;
    world.check(start > CHAIN_LOWER_ALTITUDE, "starting only %.3f above the ground, not on the first city", start);
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    world.check(!world.routeWaypoint(reached + 1).exists, "stopped after %zu waypoints", reached);
    world.check(world.isOnGround(), "standing in the city risen from the first");
    world.check(fabs(world.altitude().value - start) > LEAST_MOVED, "ended %.3f above the ground from %.3f, still by the first city", world.altitude().value, start);
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    const(char)[] below = walk.nameOf(world.targetMaterial());
    world.check(walk.isMaterial(world.targetMaterial(), "base:concrete"), "standing on %.*s instead of the connector's landing", cast(int) below.length, below.ptr);
}

enum size_t ENTRY_STOPS = 2;
enum size_t STOPS_PER_STORY = 7;
enum size_t ROUTE_STORIES = 2;
enum float CITY_LEAST_CLIMB = 0.25f;

void structureCity(ref Script world) {
    world.structure("city");
    walk.spawn(world);
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    const(char)[] spawned = walk.nameOf(world.targetMaterial());
    world.check(walk.isOneOf(world.targetMaterial(), walk.STREET_MATERIALS[]), "spawned on %.*s instead of the street", cast(int) spawned.length, spawned.ptr);
    world.look(degrees(0), degrees(-walk.STRAIGHT_DOWN_DEGREES));
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    float ground = world.altitude().value;
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    world.check(reached == ENTRY_STOPS + ROUTE_STORIES * STOPS_PER_STORY, "reached %zu stops from the street up the stairs", reached);
    world.check(world.isOnGround(), "standing upstairs");
    world.check(world.altitude().value - ground >= CITY_LEAST_CLIMB, "climbed only %.3f", world.altitude().value - ground);
}

enum double CROWN_WALK_SECONDS = 6;
enum float CROWN_LEAST_WALKED = 0.9f;

void structureCrown(ref Script world) {
    world.structure("crown");
    walk.spawn(world);
    float ground = world.altitude().value;
    float start = world.traveled().value;
    world.press(CROWN_WALK_SECONDS, Key.forward);
    world.wait(walk.SETTLE_SECONDS);
    float walked = world.traveled().value - start;
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    Maybe!Material below = world.targetMaterial();
    const(char)[] name = walk.nameOf(below);
    world.check(world.isOnGround(), "standing in the hall");
    world.check(walked >= CROWN_LEAST_WALKED * walk.SPEED * CROWN_WALK_SECONDS, "walked only %.3f toward the hall door", walked);
    world.check(world.altitude().value - ground > walk.LEAST_BLOCK_EDGE / 2, "rose %.3f, not over the door's threshold", world.altitude().value - ground);
    world.check(walk.isOneOf(below, walk.TOWER_MATERIALS[]), "standing on %.*s instead of the hall floor", cast(int) name.length, name.ptr);
}

enum float ENDLESS_FLIGHT = 5;
enum uint ENDLESS_SAMPLES = 10;

void structureEndless(ref Script world) {
    world.structure("city");
    world.mode(MovementMode.noclip);
    foreach (sample; 1 .. ENDLESS_SAMPLES + 1) {
        world.press(ENDLESS_FLIGHT / ENDLESS_SAMPLES / walk.NOCLIP_SPEED, Key.forward);
        world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
        world.step();
        Maybe!Material below = world.targetMaterial();
        const(char)[] name = walk.nameOf(below);
        world.claim(Topic.structures, "Flying over the city there is always city below, and never bare ground.", below.exists && !walk.isMaterial(below, walk.GROUND), Measure.of("flown", sample * ENDLESS_FLIGHT / ENDLESS_SAMPLES), Measure.of("below", name));
        world.look(degrees(0), degrees(-walk.STRAIGHT_DOWN_DEGREES));
    }
}

enum size_t HUTS = 5;
enum size_t STOPS_PER_HUT = 14;
enum double HAMLET_WALK_SECONDS = 6;

void structureHamlet(ref Script world) {
    world.structure("hamlet");
    world.check(world.routeWaypoint(HUTS * STOPS_PER_HUT).exists, "every hut added its stair route");
    world.check(!world.routeWaypoint(HUTS * STOPS_PER_HUT + 1).exists, "and nothing else did");
    walk.spawn(world);
    float ground = world.altitude().value;
    world.press(HAMLET_WALK_SECONDS, Key.forward);
    world.wait(walk.SETTLE_SECONDS);
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    const(char)[] name = walk.nameOf(world.targetMaterial());
    world.check(walk.isMaterial(world.targetMaterial(), "base:wood-planks"), "standing on %.*s instead of the first hut's floor", cast(int) name.length, name.ptr);
    world.check(world.altitude().value - ground > walk.LEAST_BLOCK_EDGE / 2, "stepped over the hut's threshold");
}

immutable string[3] PLATFORMS = ["base:wood-planks", "base:marble", "base:grey-brick"];

void structureLattice(ref Script world) {
    world.structure("lattice");
    walk.spawn(world);
    float standing = world.altitude().value;
    world.check(standing > 0, "standing at altitude %.4f, not below the plane gravity points away from", standing);
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    const(char)[] name = walk.nameOf(world.targetMaterial());
    world.check(walk.isOneOf(world.targetMaterial(), PLATFORMS[]), "standing on %.*s instead of the root platform", cast(int) name.length, name.ptr);
    world.press(world.timestep.value, Key.up);
    world.step();
    world.check(!world.isOnGround(), "jumped off the platform");
    world.check(world.altitude().value > standing, "jumped to %.4f from %.4f, not away from the platform", world.altitude().value, standing);
    world.wait(walk.LANDING_SECONDS);
    world.check(world.isOnGround(), "landed back on the platform");
    world.check(fabs(world.altitude().value - standing) < walk.ALTITUDE_TOLERANCE, "landed at %.4f instead of %.4f", world.altitude().value, standing);
}

void risen(string name, float risenAltitude, string landing, string what)(ref Script world) {
    world.structure(name);
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    world.check(world.isOnGround(), "standing at the start of the route");
    world.check(world.altitude().value < risenAltitude, "starting on the ground, %.3f up", world.altitude().value);
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    world.check(!world.routeWaypoint(reached + 1).exists, "stopped after %zu waypoints", reached);
    world.check(world.isOnGround(), "standing at the end of the route");
    world.claim(Topic.structures, "A connector's route leads on foot from the lower ground up onto the risen one.", world.altitude().value > risenAltitude, Measure.of("ended this high", world.altitude().value));
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    const(char)[] below = walk.nameOf(world.targetMaterial());
    world.check(walk.isMaterial(world.targetMaterial(), landing), "standing on %.*s instead of %.*s", cast(int) below.length, below.ptr, cast(int) what.length, what.ptr);
}

enum float TRIP_LEAST_RISE = 1.5f;
enum float TRIP_HOME_TOLERANCE = 0.1f;
enum float MOST_PULL_PER_STEP = 0.15f;

struct PullWatch {
    Vec3!float last = ZERO_VECTOR;
    float largest = 0;
    float highest = 0;
    uint steps;
}

void pullWatchHook(ref Script world, void* context) {
    PullWatch* watch = cast(PullWatch*) context;
    Vec3!float pull = world.game.characterState.pull;
    if (watch.steps > 0) {
        watch.largest = higherOf(watch.largest, pull.minus(watch.last).magnitude);
    }
    watch.last = pull;
    watch.highest = higherOf(watch.highest, world.altitude().value);
    watch.steps += 1;
}

void roundTrip(string name)(ref Script world) {
    world.structure(name);
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    world.check(world.isOnGround(), "standing at the start of the round trip");
    float start = world.altitude().value;
    PullWatch watch;
    world.onStep(StepHook(&pullWatchHook, &watch));
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    world.onStep(StepHook.init);
    world.check(!world.routeWaypoint(reached + 1).exists, "stopped after %zu waypoints", reached);
    world.check(world.isOnGround(), "standing at the end of the round trip");
    world.check(watch.highest - start > TRIP_LEAST_RISE, "rose only %.3f on the way", watch.highest - start);
    world.check(fabs(world.altitude().value - start) < TRIP_HOME_TOLERANCE, "came back to altitude %.3f from %.3f", world.altitude().value, start);
    world.claim(Topic.gravity, "On the way up to a risen ground and back down, the pull of gravity changes gradually and never jumps.", watch.largest <= MOST_PULL_PER_STEP, Measure.of("largest change in one step", watch.largest), Measure.of("rose", watch.highest - start));
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    const(char)[] below = walk.nameOf(world.targetMaterial());
    world.check(walk.isMaterial(world.targetMaterial(), "base:concrete"), "ended on %.*s instead of the lower landing", cast(int) below.length, below.ptr);
}

void structureRoad(ref Script world) {
    world.structure("road");
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    world.check(world.isOnGround(), "standing on the road after %zu waypoints", reached);
    world.check(!world.routeWaypoint(reached + 1).exists, "stopped after %zu waypoints", reached);
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    const(char)[] below = walk.nameOf(world.targetMaterial());
    world.check(walk.isOneOf(world.targetMaterial(), walk.STREET_MATERIALS[]), "standing on %.*s instead of the road", cast(int) below.length, below.ptr);
}

enum double TOWER_WALK_SECONDS = 20;
enum float TOWER_MOST_WALKED_FRACTION = 0.8f;

void highestHook(ref Script world, void* context) {
    float* highest = cast(float*) context;
    *highest = higherOf(*highest, world.altitude().value);
}

void structureTower(ref Script world) {
    world.structure("tower");
    walk.spawn(world);
    float start = world.traveled().value;
    float ground = world.altitude().value;
    float highest = ground;
    world.onStep(StepHook(&highestHook, &highest));
    world.press(TOWER_WALK_SECONDS, Key.forward);
    world.wait(walk.SETTLE_SECONDS);
    world.onStep(StepHook.init);
    float walked = world.traveled().value - start;
    float free = walk.SPEED * TOWER_WALK_SECONDS;
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    Maybe!Material below = world.targetMaterial();
    const(char)[] name = walk.nameOf(below);
    world.check(world.isOnGround(), "standing inside the tower");
    world.check(world.altitude().value - ground > walk.LEAST_BLOCK_EDGE / 2, "rose %.3f, not onto the ground floor through the door", world.altitude().value - ground);
    world.check(highest - ground < walk.MOST_BLOCK_EDGE, "climbed %.3f, more than the door's threshold", highest - ground);
    world.check(walked < TOWER_MOST_WALKED_FRACTION * free, "walked %.3f of %.3f without reaching the far wall", walked, free);
    world.check(walk.isOneOf(below, walk.TOWER_MATERIALS[]), "standing on %.*s instead of the ground floor", cast(int) name.length, name.ptr);
}

enum size_t TRAIL_STOPS = 12;
enum float MOST_STRAIGHTNESS = 0.8f;

size_t stopCount(ref Script world) {
    size_t count = 0;
    while (world.routeWaypoint(count + 1).exists) {
        count += 1;
    }
    return count;
}

void structureTrail(ref Script world) {
    world.structure("trail");
    size_t built = stopCount(world);
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    float start = world.traveled().value;
    size_t reached = climb.follow(world, Maybe!size_t.of(TRAIL_STOPS));
    world.wait(walk.SETTLE_SECONDS);
    world.check(reached == TRAIL_STOPS, "walked %zu of %zu trail stops", reached, TRAIL_STOPS);
    world.check(stopCount(world) > built, "the trail did not grow past its first %zu stops as the world grew", built);
    float back = world.needWaypoint(1).horizontal.value;
    float walked = world.traveled().value - start;
    world.check(back < MOST_STRAIGHTNESS * walked, "the trail ran straight: %.3f back to its start after walking %.3f", back, walked);
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    const(char)[] below = walk.nameOf(world.targetMaterial());
    world.check(walk.isMaterial(world.targetMaterial(), "base:gravel"), "standing on %.*s instead of the trail", cast(int) below.length, below.ptr);
}

enum float TOP_ALTITUDE = 3.2f;
enum float TRUNK_CLIMB = 0.1f;
enum float NUDGE = 0.01f;
enum uint MOST_NUDGES = 200;

immutable string[2] TREE_MATERIALS = ["base:oak-wood", "base:oak-leaves"];

void approachBark(ref Script world) {
    uint nudges = 0;
    while (!world.isFailed && !walk.isOneOf(world.targetMaterial(), TREE_MATERIALS[]) && nudges < MOST_NUDGES) {
        world.press(NUDGE / walk.NOCLIP_SPEED, Key.forward);
        nudges += 1;
    }
    const(char)[] facing = walk.nameOf(world.targetMaterial());
    world.check(walk.isOneOf(world.targetMaterial(), TREE_MATERIALS[]), "no tree ahead at altitude %.3f, facing %.*s", world.altitude().value, cast(int) facing.length, facing.ptr);
}

immutable float[6] ENDLESS_SPOTS = [2.1f, 5.3f, 9.7f, 14.2f, 20.4f, 40.0f];
enum float LIBRARY_LEAST_DESCENT = 20.0f;
enum double MOST_FLOOR_TILT = 3;
enum double LIBRARY_LOAD_SECONDS = 3;
enum float LIBRARY_FLIGHT_DEPTH = 30.0f;
enum float LIBRARY_FLIGHT_LEG = 0.5f;
enum float LIBRARY_MOST_FALL = 0.5f;
enum double LIBRARY_FREE_SECONDS = 0.1;
enum float LIBRARY_NUDGE = 0.03f;
enum uint LIBRARY_MOST_NUDGES = 10;

void structureArborEndless(ref Script world) {
    world.structure("arbor");
    world.mode(MovementMode.noclip);
    foreach (height; ENDLESS_SPOTS) {
        world.enterStructure(Length(height));
        world.step();
        world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
        const(char)[] below = walk.nameOf(world.targetMaterial());
        world.check(walk.isOneOf(world.targetMaterial(), TREE_MATERIALS[]), "standing in the trunk %.1f up, facing %.*s", height, cast(int) below.length, below.ptr);
        world.look(degrees(0), degrees(-walk.STRAIGHT_DOWN_DEGREES));
    }
}

void walkDownShaft(ref Script world) {
    world.check(world.isOnGround(), "standing at the top of the shaft's stair");
    float start = world.altitude().value;
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    double tilt = world.floorTilt().value / RADIANS_PER_DEGREE;
    world.check(!world.routeWaypoint(reached + 1).exists, "stopped after %zu waypoints", reached);
    world.check(world.isOnGround(), "standing in the shaft after %zu waypoints", reached);
    world.check(start - world.altitude().value >= LIBRARY_LEAST_DESCENT, "went down only %.3f", start - world.altitude().value);
    world.check(tilt <= MOST_FLOOR_TILT, "standing still, the floor tilts %.1f degrees against gravity at altitude %.2f", tilt, world.altitude().value);
}

void structureLibraryFlight(ref Script world) {
    world.structure("library");
    world.live();
    world.enterRoute();
    world.wait(LIBRARY_LOAD_SECONDS);
    world.mode(MovementMode.noclip);
    float start = world.altitude().value;
    while (!world.isFailed && start - world.altitude().value < LIBRARY_FLIGHT_DEPTH) {
        world.press(LIBRARY_FLIGHT_LEG / walk.NOCLIP_SPEED, Key.down);
        Maybe!Material below = walk.lookBelow(world);
        world.check(below.exists, "flying down the stair's ring, no floor below after %.1f down", start - world.altitude().value);
    }
}

void structureLibrary(ref Script world) {
    world.structure("library");
    walk.spawn(world);
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    walkDownShaft(world);
}

void structureLibraryLive(ref Script world) {
    world.structure("library");
    world.live();
    world.enterRoute();
    world.wait(LIBRARY_LOAD_SECONDS);
    walkDownShaft(world);
}

void structureLibraryEndless(ref Script world) {
    world.structure("library");
    world.mode(MovementMode.noclip);
    foreach (depth; ENDLESS_SPOTS) {
        world.enterStructure(Length(-depth));
        world.step();
        Maybe!Material below = walk.lookBelow(world);
        const(char)[] name = walk.nameOf(below);
        world.check(walk.isMaterial(below, "base:glass"), "no glass floor over the well %.1f down, facing %.*s", depth, cast(int) name.length, name.ptr);
    }
}

void structureLibraryNoHole(ref Script world) {
    world.structure("library");
    foreach (depth; ENDLESS_SPOTS) {
        world.mode(MovementMode.noclip);
        world.enterStructure(Length(-depth));
        float dropped = world.altitude().value;
        uint nudges = 0;
        world.mode(MovementMode.walk);
        world.wait(LIBRARY_FREE_SECONDS);
        while (!world.isFailed && world.altitude().value == dropped && nudges < LIBRARY_MOST_NUDGES) {
            world.mode(MovementMode.noclip);
            world.press(LIBRARY_NUDGE / walk.NOCLIP_SPEED, Key.up);
            dropped = world.altitude().value;
            world.mode(MovementMode.walk);
            world.wait(LIBRARY_FREE_SECONDS);
            nudges += 1;
        }
        world.check(world.altitude().value != dropped, "stuck in solid %.1f down after %u nudges", depth, nudges);
        world.wait(walk.LANDING_SECONDS);
        world.check(world.isOnGround(), "still falling down the well after %.1f from %.1f down", cast(double)(dropped - world.altitude().value), depth);
        world.check(dropped - world.altitude().value < LIBRARY_MOST_FALL, "fell %.2f down the well from %.1f down", cast(double)(dropped - world.altitude().value), depth);
    }
}

void structureTreetrunk(ref Script world) {
    world.terrain();
    world.mode(MovementMode.noclip);
    approachBark(world);
    while (!world.isFailed && world.altitude().value < TOP_ALTITUDE) {
        world.press(TRUNK_CLIMB / walk.NOCLIP_SPEED, Key.up);
        approachBark(world);
    }
}

enum float CAVES_LEAST_DESCENT = 0.9f;
enum float CAVES_HOME_TOLERANCE = 0.05f;

void lowestHook(ref Script world, void* context) {
    float* lowest = cast(float*) context;
    *lowest = lowerOf(*lowest, world.altitude().value);
}

void structureCaves(ref Script world) {
    world.structure("caves");
    walk.spawn(world);
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    world.check(world.isOnGround(), "standing on the rim of the sinkhole");
    float start = world.altitude().value;
    float lowest = start;
    world.onStep(StepHook(&lowestHook, &lowest));
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    world.onStep(StepHook.init);
    world.check(!world.routeWaypoint(reached + 1).exists, "stopped after %zu waypoints down the sinkhole and back", reached);
    world.check(world.isOnGround(), "standing on the rim again after %zu waypoints", reached);
    world.check(start - lowest >= CAVES_LEAST_DESCENT, "went down only %.3f into the cave", start - lowest);
    world.check(fabs(world.altitude().value - start) < CAVES_HOME_TOLERANCE, "came back up to %.3f from %.3f", world.altitude().value, start);
}
