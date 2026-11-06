module scripts.tests;

import core.math : sqrt;
import core.stdc.math : atan2, exp, fabs, sin;
import base.maybe : Maybe;
import base.names : textFor;
import base.numbers : RADIANS_PER_DEGREE, higherOf, lowerOf;
import base.units : AngularSpeed, Length, Time;
import base.vector3 : Vec3, ZERO_VECTOR, magnitude, minus;
import client.game : Key, Preset, RouteWaypoint, UnloadedCount;
import client.config : ClientConfig;
import client.game : BeaconSighting, ChunkSupply, Game;
import client.save : SaveData, Writer, applyEdits, applyState, readGame, writeGame;
import client.structures : StructureProblem, placeStructure;
import client.world : Placement;
import common.position : Position;
import common.worldgen.generation : Worldgen;
import geometry.lorentz : Point;
import base.maybe : MaybeIndex;
import common.graph : Graph, NodeId;
import common.node : ChunkSlot, ChunkState, cellIndex;
import client.hud : Growth;
import client.script : NamedScript, ONE_SECOND, Script, StepHook, degrees;
import common.character.controller : MovementMode;
import common.biology.air : AirMix, GAS_COUNT, airOf;
import common.biology.kinetics : Body;
import common.biology.molecule : fragmentCount;
import client.game : COLLECTION_RATE, GROWN_SECONDS, PLANT_DOSE, Seed;
import common.biology.breeding : expressionIn;
import common.biology.wild : WILD_GENES, WildGenes;
import common.material : has;
import common.perception : effectiveFor;
import common.settings : CharacterConfig;
import plugins.api.api : Material;
import climb = scripts.climb;
import walk = scripts.walk;
import scripts.walk : Across, ClimbGoal, Motion;

immutable NamedScript[] TESTS = [
    NamedScript("api", &api),
    NamedScript("demo/growth", &demoGrowth),
    NamedScript("demo/holonomy", &demoHolonomy),
    NamedScript("demo/throw", &demoThrow),
    NamedScript("flat/corner", &flatCorner),
    NamedScript("flat/curve", &flatCurve),
    NamedScript("flat/hole", &flatHole),
    NamedScript("flat/items", &flatItems),
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
    NamedScript("hidden/climb", &hiddenClimb),
    NamedScript("hidden/reveal-inside", &hiddenRevealInside),
    NamedScript("hidden/unrevealed", &hiddenUnrevealed),
    NamedScript("live/drift", &liveDrift),
    NamedScript("live/edit-kept", &liveEditKept),
    NamedScript("live/far", &liveFar),
    NamedScript("live/fly", &liveFly),
    NamedScript("save/round-trip", &saveRoundTrip),
    NamedScript("perception/body", &perceptionBody),
    NamedScript("plant/collector", &plantCollector),
    NamedScript("plant/scan-eat", &plantScanEat),
    NamedScript("slope/across", &slopeAcross),
    NamedScript("slope/downhill", &slopeDownhill),
    NamedScript("slope/hopping", &slopeHopping),
    NamedScript("slope/steep", &slopeSteep),
    NamedScript("slope/turning", &slopeTurning),
    NamedScript("slope/uphill", &slopeUphill),
    NamedScript("slope/wall", &slopeWall),
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
    NamedScript("structure/risen", &risen!("risencity", 1.5f, Material.concrete, "the risen city's paved lot")),
    NamedScript("structure/road", &structureRoad),
    NamedScript("structure/spiral", &risen!("spiralcity", 1.5f, Material.concrete, "the spiral's landing")),
    NamedScript("structure/drift", &risen!("driftcity", 1.5f, Material.concrete, "the drift's landing")),
    NamedScript("structure/lantern", &risen!("lanterncity", 1.5f, Material.concrete, "the lantern's landing")),
    NamedScript("structure/stacked", &risen!("stacked", 1.5f, Material.concrete, "the connector's landing")),
    NamedScript("structure/stackedrooms", &risen!("stackedrooms", 1.5f, Material.concrete, "the connector's landing")),
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
    NamedScript("structure/wild", &risen!("risenwild", 2.0f, Material.concrete, "the connector's landing")),
];

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
    world.material(10);
    bool refused = world.takeFailure();
    world.check(refused, "material slots past the palette are an error");
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

    world.hold(Key.fwd);
    world.look(degrees(0.25), degrees(-0.5));
    world.wait(0.48, DEFAULT_TIMESTEP);
    world.release(Key.fwd);
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

float pentagonLap(ref Script world) {
    world.look(degrees(0), degrees(0));
    world.resetCompass();
    float before = world.compassOff().value;
    foreach (_; 0 .. PENTAGON_SIDES) {
        world.press(PENTAGON_SIDE / walk.NOCLIP_SPEED, Key.fwd);
        world.look(degrees(QUARTER_TURN), degrees(0));
    }
    world.step();
    return world.compassOff().value - before;
}

void demoHolonomy(ref Script world) {
    world.plane(degrees(0));
    world.mode(MovementMode.noclip);
    world.resetCompass();
    world.press(0.2f / walk.NOCLIP_SPEED, Key.fwd);
    double straight = world.compassOff().value / RADIANS_PER_DEGREE;
    world.check(fabs(straight) < STRAIGHT_TOLERANCE, "walking straight turned the compass %.2f degrees", straight);
    double off = pentagonLap(world) / RADIANS_PER_DEGREE;
    world.check(fabs(fabs(off) - QUARTER_TURN) < QUARTER_TOLERANCE, "five right turns around a block moved the compass %.2f degrees, curvature predicts %.0f", off, QUARTER_TURN);
}

void demoThrow(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.throwBlock();
    world.check(world.thrownCount() == 1, "a thrown block is flying");
    world.check(!world.isThrownResting(0), "a thrown block starts in the air");
    world.wait(4);
    world.check(world.thrownCount() == 1, "the block is still there after it lands");
    world.check(world.isThrownResting(0), "the block came to rest on the ground");
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
        world.check(rate > LEAST_GROWTH, "cells within %u steps: %u, within %u: %u, a rate of only %.2f", step - 1, growth.within[step - 1], step, growth.within[step], rate);
    }
    growth.release();
}

enum uint CORNER_BLOCKS = 2;
enum double ARRIVAL_MARGIN_SECONDS = 0.5;
enum double PUSH_SECONDS = 2;
enum float MAX_PUSH_TRAVEL = 0.0025f;
enum float MAX_CAMERA_ACCELERATION = 0.05f;

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
    world.hold(Key.fwd);
    world.wait(sqrt(walk.WALL_DISTANCE * walk.WALL_DISTANCE + walk.WALL_HALF_WIDTH * walk.WALL_HALF_WIDTH) / walk.SPEED + ARRIVAL_MARGIN_SECONDS);
    float start = world.traveled().value;
    float shake = 0;
    world.onStep(StepHook(&shakeHook, &shake));
    world.wait(PUSH_SECONDS);
    world.release(Key.fwd);
    world.onStep(StepHook.init);
    float pushed = world.traveled().value - start;
    world.check(pushed <= MAX_PUSH_TRAVEL, "moved %.4f while pushed into the corner for %.1f s", pushed, PUSH_SECONDS);
    world.check(shake <= MAX_CAMERA_ACCELERATION, "camera shook at %.4f/s^2 in the corner", shake);
    walk.checkStanding(world, "in the corner");
}

enum float CURVE_ALTITUDE = 1;
enum double FALL_SECONDS = 0.25;
enum double MIN_CURVE_FRACTION = 0.75;
enum double MAX_CURVE_FRACTION = 1.25;

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
        world.hold(Key.fwd);
        world.step();
    }
    world.mode(MovementMode.walk);
    if (launch == Launch.moving) {
        world.release(Key.fwd);
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
    world.check(gained >= MIN_CURVE_FRACTION * predicted && gained <= MAX_CURVE_FRACTION * predicted, "moving at %.3f, %.3f up: the fall was %.4f slower than from rest, a geodesic predicts %.4f", moving.speed, moving.altitude, gained, predicted);
}

enum uint HOLE_BLOCKS = 2;
enum double LOWER_BLOCK_DEGREES = 18;
enum uint MAX_BREAKS = 4;
enum double APPROACH_SECONDS = 1;
enum double SEARCH_SECONDS = 0.5;
enum double THROUGH_SECONDS = 2;
enum double FREE_SECONDS = 1;
enum float MIN_FREE_FRACTION = 0.8f;

bool isWall(Maybe!Material target) {
    return walk.isMaterial(target, walk.BUILD_LAYERS[0].material) || walk.isMaterial(target, walk.BUILD_LAYERS[1].material);
}

void clearAhead(ref Script world, double pitch, const(char)* what) {
    world.look(degrees(0), degrees(pitch));
    uint breaks = 0;
    while (!world.isFailed && isWall(world.targetMaterial()) && breaks < MAX_BREAKS) {
        bool broke = world.breakBlock();
        world.check(broke, "broke the %s block of the hole", what);
        breaks += 1;
    }
    string facing = walk.nameOf(world.targetMaterial());
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
    world.hold(Key.fwd);
    world.wait(APPROACH_SECONDS);
    world.press(SEARCH_SECONDS, Key.left);
    world.press(2 * SEARCH_SECONDS, Key.right);
    world.wait(THROUGH_SECONDS);
    world.release(Key.fwd);
    walk.checkStanding(world, "after squeezing through the hole");
    walk.forward(world, FREE_SECONDS, MIN_FREE_FRACTION);
}

enum float IDEAL_RISE = 0.085f;
enum float MIN_RISE_FRACTION = 0.97f;
enum float MAX_RISE_FRACTION = 1.001f;

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
    world.check(rise >= MIN_RISE_FRACTION * IDEAL_RISE && rise <= MAX_RISE_FRACTION * IDEAL_RISE, "standing jump rose %.5f (ideal %.5f)", rise, IDEAL_RISE);
    world.check(jump.drift < walk.SPEED_TOLERANCE, "standing jump drifted at %.5f", jump.drift);
    walk.checkStanding(world, "after landing");
}

enum double AHEAD_DEGREES = 30;

void flatItems(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    Maybe!Material ground = world.targetMaterial();
    uint before = world.game.inventory.counts[ground.value];
    bool broke = world.breakBlock();
    world.check(broke && world.game.inventory.counts[ground.value] == before + 1, "breaking %u to %u of the ground block", before, world.game.inventory.counts[ground.value]);
    Material held = world.game.inventory.held();
    uint stock = world.game.inventory.counts[held];
    bool placed = world.placeBlock();
    world.check(placed && world.game.inventory.counts[held] == stock - 1, "placing left %u of %u held blocks", world.game.inventory.counts[held], stock);
    world.breakBlock();
    world.game.inventory.counts[held] = 0;
    world.check(!world.placeBlock(), "placed a block with none held");
}

void flatPlace(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    bool placed = world.placeBlock();
    world.check(!placed, "placing a block where the player stands is refused");
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
    world.hold(Key.fwd);
    bool onStep = walk.probeOnStep(world, standing);
    while (!world.isFailed && world.time().value < deadline && !onStep) {
        world.step();
        onStep = walk.probeOnStep(world, standing);
    }
    world.release(Key.fwd);
    world.wait(walk.SETTLE_SECONDS);
    world.onStep(StepHook.init);
    world.check(motion.offGround == 0, "left the ground on %u steps walking up a one-block step", motion.offGround);
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
    world.hold(Key.fwd);
    bool onStep = walk.probeOnStep(world, standing);
    while (!world.isFailed && world.time().value < deadline && !onStep) {
        world.step();
        onStep = walk.probeOnStep(world, standing);
    }
    world.release(Key.fwd);
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
    world.hold(Key.fwd);
    world.wait(TIMESTEP_WALK_SECONDS, dt);
    world.release(Key.fwd);
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
    world.check(fabs(inLongSteps - inShortSteps) <= WALK_TOLERANCE, "walked %.5f in %.1f s steps and %.5f in %.3f s steps", inLongSteps, LONG_STEP.value, inShortSteps, world.timestep.value);
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
enum float MIN_WALKED_FRACTION = 0.95f;

void flatWalk(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    walk.checkStanding(world, "after landing");
    Motion motion;
    walk.trackMotion(world, &motion);
    foreach (heading; HEADINGS) {
        float start = world.traveled().value;
        world.press(LEG_SECONDS, Key.fwd);
        world.wait(0.5);
        float walked = world.traveled().value - start;
        float free = walk.SPEED * LEG_SECONDS;
        world.check(walked >= MIN_WALKED_FRACTION * free, "heading %d: walked %.4f of %.4f", heading, walked, free);
        walk.checkStanding(world, "after a heading");
        world.turn(degrees(90), degrees(0), 0.5);
    }
    world.press(LEG_SECONDS, Key.fwd, Key.up);
    world.wait(1);
    world.onStep(StepHook.init);
    walk.checkSpeedLimit(world, motion);
    walk.checkStanding(world, "after hopping");
}

enum uint WALL_BLOCKS = 2;
enum double WALL_APPROACH_SECONDS = 0.3;
enum double WALL_PUSH_SECONDS = 2.5;
enum float CONTACT_SPEED_FRACTION = 0.8f;
enum float MAX_CLIMB = 0.0025f;
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
    world.hold(Key.fwd);
    world.wait(WALL_APPROACH_SECONDS + WALL_PUSH_SECONDS);
    world.release(Key.fwd);
    world.onStep(StepHook.init);
    float walked = world.traveled().value - start;
    float free = walk.SPEED * (WALL_APPROACH_SECONDS + WALL_PUSH_SECONDS);
    world.check(walked <= CONTACT_SPEED_FRACTION * free, "walked %.4f of a free %.4f, so the wall was not reached", walked, free);
    world.check(motion.highest - standing <= MAX_CLIMB, "climbed %.4f up a two-block wall", motion.highest - standing);
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
        world.press(DRIFT_LEG_DISTANCE / walk.FLY_SPEED, Key.fwd);
        float drift = world.probeFrameDrift(DRIFT_RADIUS).value;
        world.check(drift < MOST_DRIFT, "nodes drawn %.3g from where they are after %u units flown", drift, leg + 1);
    }
}

enum uint BENCH_SLOT = 7;
enum float EXPRESSED_TOLERANCE = 1e-4f;

void geneBreedSplice(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    WildGenes first = WildGenes([11, 12, 13, 14]);
    WildGenes second = WildGenes([21, 22, 23, 24]);
    world.game.keepSeed(Seed(first, Material.flower));
    world.game.keepSeed(Seed(second, Material.flower));
    world.material(BENCH_SLOT);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.check(world.placeBlock() && walk.isMaterial(world.targetMaterial(), Material.bench), "could not place the bench");
    world.use();
    world.check(world.game.seeds.length == 3, "crossing at the bench left %zu seeds", world.game.seeds.length);
    if (!world.isFailed) {
        WildGenes child = world.game.seeds.ptr[2].genes;
        uint inherited = 0;
        foreach (index; 0 .. WILD_GENES) {
            if (child.seeds[index] == first.seeds[index] || child.seeds[index] == second.seeds[index]) {
                inherited += 1;
            }
        }
        world.check(inherited >= WILD_GENES - 1, "the crossed seed inherited only %u of %u genes", inherited, WILD_GENES);
        uint genes = world.game.organism.genome.count;
        world.check(world.eat() && world.game.organism.genome.count == genes + 1 && world.game.seeds.length == 2, "splicing at the bench left %u genes and %zu seeds", world.game.organism.genome.count, world.game.seeds.length);
    }
}

void geneGrow(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.keepSeed(Seed(WildGenes([31, 32, 33, 34]), Material.flower));
    world.game.inventory.hotbar[0] = Material.flower;
    world.game.inventory.counts[Material.flower] = 1;
    world.material(1);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.check(world.placeBlock() && world.game.seeds.length == 0, "planting did not use the seed");
    world.check(!world.eat(), "ate a plant that had not grown");
    world.wait(GROWN_SECONDS.value + 1);
    uint slot = world.game.world.graph.slotOf(world.game.characterState.position.node).value;
    float expression = expressionIn(Material.flower, world.game.world.graph.stateAt(slot).climate.climate());
    world.check(world.eat() && world.game.organism.body.count == 1, "could not eat the grown plant");
    if (!world.isFailed) {
        float eaten = world.game.organism.body.species[0].gut.value;
        world.check(fabs(eaten - PLANT_DOSE.value * expression) < EXPRESSED_TOLERANCE, "ate %.4f of a plant the climate expresses at %.4f", eaten, expression);
    }
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
    world.use();
    const(Body)* body = &world.game.organism.body;
    world.check(body.count == GAS_COUNT, "breathing the collected air dosed %u gases", body.count);
    if (!world.isFailed) {
        uint slot = world.game.world.graph.slotOf(world.game.characterState.position.node).value;
        AirMix air = airOf(world.game.world.graph.stateAt(slot).climate.climate());
        float expected = air.fractions[0].value * COLLECTION_RATE.value * cast(float) COLLECTING_SECONDS;
        float held = body.species[0].lung.value + body.species[0].blood.value;
        world.check(fabs(held - expected) < COLLECTED_TOLERANCE + expected * 0.05f, "collected %.4f of the first gas over %.0f s, the air predicts %.4f", held, COLLECTING_SECONDS, expected);
        world.use();
        float again = body.species[0].lung.value + body.species[0].blood.value;
        world.check(fabs(again - held) < COLLECTED_TOLERANCE, "collecting again at once added %.4f", again - held);
    }
}

void plantScanEat(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.inventory.hotbar[0] = Material.flower;
    world.game.inventory.counts[Material.flower] = 1;
    world.material(1);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.check(world.placeBlock(), "could not place the flower");
    world.check(walk.isMaterial(world.targetMaterial(), Material.flower), "the flower is not ahead after placing it");
    world.use();
    world.check(world.game.isScanShown && fragmentCount(world.game.scan.value.product) > 0, "scanning the flower showed no product");
    world.check(world.eat() && world.game.organism.body.count == 1, "eating the flower dosed %u molecules", world.game.organism.body.count);
    world.check(!walk.isMaterial(world.targetMaterial(), Material.flower), "the eaten flower is still there");
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
        world.check(fabs(far.distance.value - near - BEACON_AWAY) < BEACON_DISTANCE_TOLERANCE, "backed %.1f away from a beacon %.3f off, and it reads %.3f", BEACON_AWAY, near, far.distance.value);
        world.check(fabs(toward) < 180 - BEHIND_DEGREES, "backing away, the beacon needle points %.1f degrees off ahead", toward);
        world.press(BEACON_AWAY / walk.NOCLIP_SPEED, Key.fwd);
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
    world.press(SAVE_WALK / walk.NOCLIP_SPEED, Key.fwd);
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
        world.check(copy.world.graph.edits.cellCount == world.game.world.graph.edits.cellCount, "kept %zu of %zu edited cells", copy.world.graph.edits.cellCount, world.game.world.graph.edits.cellCount);
        world.check(copy.inventory == world.game.inventory, "the inventory changed through the save");
        world.check(copy.organism.body.count == world.game.organism.body.count && copy.organism.body.species[0].blood == world.game.organism.body.species[0].blood, "the body changed through the save");
        Position here = world.game.characterState.position;
        Position there = copy.characterState.position;
        float apart = (here.local * Point!float.origin()).distance(there.local * Point!float.origin());
        world.check(here.node == there.node && apart < SAVE_PLACE_TOLERANCE, "the body came back %.5f away from where it was saved", apart);
    }
    Game other = Game.make(Worldgen.makeTerrain(), config.reach);
    SaveData refused;
    world.check(readGame(writer.bytes.slice(), other, refused) !is null, "a save from a flat world loaded into the terrain world");
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
    travel(world, Key.fwd);
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
        travel(world, Key.fwd);
        Maybe!Material back = storedAt(world, target.value);
        string before = walk.nameOf(placed);
        string after = walk.nameOf(back);
        world.check(placed.exists && back.exists && back.value == placed.value, "placed %.*s, the edited cell holds %.*s after the node was evicted and reloaded", cast(int) before.length, before.ptr, cast(int) after.length, after.ptr);
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
        world.press(FAR_LEG_DISTANCE / walk.NOCLIP_SPEED, Key.fwd);
        float altitude = world.altitude().value;
        UnloadedCount unloaded = world.unloadedWithin(CLOSE);
        Probe probe = groundBelow(world);
        world.check(fabs(altitude - start) < ALTITUDE_DRIFT && probe.below.exists, "after %.0f units: altitude %.3f from %.3f, %u fresh %u generating %u nodes missing, %s below within %.2f", (leg + 1) * FAR_LEG_DISTANCE, altitude, start, unloaded.fresh, unloaded.generating, unloaded.missingNodes, textFor(probe.below.exists, "something", "nothing"), probe.depth);
    }
}

enum uint FLY_SECONDS = 40;
enum uint NOCLIP_SECONDS = 30;
enum float MIN_FLY_FRACTION = 0.9f;
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
        world.press(1, Key.fwd);
        float flown = world.traveled().value - before;
        world.check(flown >= MIN_FLY_FRACTION * walk.FLY_SPEED, "flew %.3f in second %u, %s at altitude %.3f", flown, second, textFor(world.isLoaded(), "loaded", "not loaded"), world.altitude().value);
        checkClose(world, "flying", second);
    }
    world.mode(MovementMode.walk);
    world.wait(walk.LANDING_SECONDS);
    world.check(world.isLoaded(), "landed where the world is loaded");
    world.mode(MovementMode.noclip);
    foreach (second; 1 .. NOCLIP_SECONDS + 1) {
        float before = world.traveled().value;
        world.press(1, Key.fwd);
        world.check(world.traveled().value - before >= MIN_FLY_FRACTION * walk.NOCLIP_SPEED, "noclip moved %.3f in second %u", world.traveled().value - before, second);
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
    while (!world.isFailed && !world.game.reveal.revealed.has(Material.mistStone) && waited < MOST_ONSET_SECONDS) {
        world.wait(ONSET_STEP_SECONDS);
        waited += ONSET_STEP_SECONDS;
    }
    world.check(world.game.reveal.revealed.has(Material.mistStone), "the swallowed dose did not reveal the mist stair within %.0f s, the mist signal is %.3f", MOST_ONSET_SECONDS, world.game.organism.signaling.signalOf(0).value);
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    world.check(!world.routeWaypoint(reached + 1).exists && world.altitude().value > HIDDEN_RISE, "climbed the dosed stair to %.3f after %zu waypoints", world.altitude().value, reached);
}

void biologySober(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.wait(SOBER_SECONDS);
    foreach (signal; 0 .. 3) {
        float level = world.game.organism.signaling.signalOf(signal).value;
        world.check(level <= SOBER_SIGNAL && level >= -SOBER_SIGNAL, "an undosed body drifted to signal %u at %.6f", signal, level);
    }
}

enum float HIDDEN_RISE = 1.5f;
enum size_t INSIDE_STOP = 6;
enum float SINK_INTO_TREAD = 0.03f;

void hiddenClimb(ref Script world) {
    world.structure("hiddenstair");
    world.perceive(Preset.mist);
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    world.check(world.isOnGround(), "standing at the foot of the revealed stair");
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    world.check(!world.routeWaypoint(reached + 1).exists, "stopped after %zu waypoints on the revealed stair", reached);
    world.check(world.isOnGround() && world.altitude().value > HIDDEN_RISE, "climbed the revealed stair only to %.3f", world.altitude().value);
}

void hiddenUnrevealed(ref Script world) {
    world.structure("hiddenstair");
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    climb.follow(world, Maybe!size_t.init);
    bool stuck = world.takeFailure();
    world.check(stuck, "walked the whole route of a stair that is not revealed");
    world.check(world.altitude().value < HIDDEN_RISE, "rose to %.3f on a stair that is not revealed", world.altitude().value);
}

void hiddenRevealInside(ref Script world) {
    world.structure("hiddenstair");
    world.perceive(Preset.mist);
    world.enterRoute(INSIDE_STOP);
    world.wait(walk.SETTLE_SECONDS);
    world.check(world.isOnGround(), "standing on a revealed tread");
    world.perceive(Preset.plain);
    world.mode(MovementMode.noclip);
    world.press(SINK_INTO_TREAD / walk.NOCLIP_SPEED, Key.down);
    world.perceive(Preset.mist);
    world.check(!world.game.reveal.touchable.has(Material.mistStone), "the stair became solid around a body standing inside it");
    world.mode(MovementMode.walk);
    world.wait(walk.LANDING_SECONDS);
    world.check(world.isOnGround(), "did not land after falling out of the stair");
    world.check(world.game.reveal.touchable.has(Material.mistStone), "the stair stayed passable after the body left it");
}

enum Preset FELT_PRESET = Preset.heavy;
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
    world.check(rise >= MIN_RISE_FRACTION * felt.jumpHeight.value && rise <= MAX_RISE_FRACTION * felt.jumpHeight.value, "a standing jump while heavy rose %.5f, the felt jump height is %.5f", rise, felt.jumpHeight.value);
    walk.checkStanding(world, "after the heavy jump");
    float start = world.traveled().value;
    world.press(FELT_WALK_SECONDS, Key.fwd);
    float walked = world.traveled().value - start;
    float free = felt.walkSpeed.value * FELT_WALK_SECONDS;
    world.check(walked >= MIN_WALKED_FRACTION * free && walked <= MOST_WALKED_FRACTION * free, "walked %.4f in %.1f s while heavy, the felt walk speed allows %.4f", walked, FELT_WALK_SECONDS, free);
}

enum double TILT_DEGREES = 25;
enum double SLOPE_WALK_SECONDS = 8;
enum float MIN_SLOPE_FRACTION = 0.8f;
enum float MIN_CLIMB_FRACTION = 0.4f;

void slopeAcross(ref Script world) {
    walk.acrossSlope(world, TILT_DEGREES, 90, SLOPE_WALK_SECONDS, MIN_SLOPE_FRACTION);
}

void slopeDownhill(ref Script world) {
    walk.acrossSlope(world, TILT_DEGREES, 180, SLOPE_WALK_SECONDS, MIN_SLOPE_FRACTION);
}

void slopeUphill(ref Script world) {
    Across across = walk.acrossSlope(world, TILT_DEGREES, 0, SLOPE_WALK_SECONDS, MIN_SLOPE_FRACTION);
    double ideal = across.walked * sin(TILT_DEGREES * RADIANS_PER_DEGREE);
    world.check(across.climbed >= MIN_CLIMB_FRACTION * ideal, "climbed %.4f walking %.4f up a 25 degree slope", across.climbed, across.walked);
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
        world.hold(Key.fwd);
        foreach (_; 0 .. HOPS) {
            world.wait(SECONDS_BETWEEN_HOPS);
            world.press(JUMP_PRESS_SECONDS, Key.up);
        }
        world.release(Key.fwd);
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
    world.press(TURNING_SECONDS, Key.fwd);
    world.turnRate(AngularSpeed(0), AngularSpeed(0));
    world.wait(walk.SETTLE_SECONDS);
    world.onStep(StepHook.init);
    walk.checkSpeedLimit(world, motion);
    world.check(world.isOnGround(), "on ground at the end");
}

enum uint SLOPE_WALL_BLOCKS = 3;
enum double SLOPE_APPROACH_SECONDS = 0.5;
enum float MAX_RISE_SPEED = 0.1f;

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
        world.hold(Key.fwd);
        world.wait(SLOPE_APPROACH_SECONDS);
        world.onStep(StepHook(&pushingHook, &pushing));
        world.wait(WALL_PUSH_SECONDS);
        world.release(Key.fwd);
        world.wait(walk.SETTLE_SECONDS);
        world.onStep(StepHook.init);
        world.check(pushing.slowest <= CONTACT_SPEED_FRACTION * walk.SPEED, "heading %d: never slowed below %.4f, so the wall was not reached", heading, pushing.slowest);
        world.check(pushing.motion.rise <= MAX_RISE_SPEED, "heading %d: rose at %.4f against the wall", heading, pushing.motion.rise);
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
    string floor = walk.nameOf(below);
    string ceiling = walk.nameOf(above);
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
    string below = walk.nameOf(world.targetMaterial());
    world.check(walk.isMaterial(world.targetMaterial(), Material.concrete), "standing on %.*s instead of the connector's landing", cast(int) below.length, below.ptr);
}

enum size_t ENTRY_STOPS = 2;
enum size_t STOPS_PER_STORY = 7;
enum size_t ROUTE_STORIES = 2;
enum float CITY_MIN_CLIMB = 0.25f;

void structureCity(ref Script world) {
    world.structure("city");
    walk.spawn(world);
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    string spawned = walk.nameOf(world.targetMaterial());
    world.check(walk.isOneOf(world.targetMaterial(), walk.STREET_MATERIALS[]), "spawned on %.*s instead of the street", cast(int) spawned.length, spawned.ptr);
    world.look(degrees(0), degrees(-walk.STRAIGHT_DOWN_DEGREES));
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    float ground = world.altitude().value;
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    world.check(reached == ENTRY_STOPS + ROUTE_STORIES * STOPS_PER_STORY, "reached %zu stops from the street up the stairs", reached);
    world.check(world.isOnGround(), "standing upstairs");
    world.check(world.altitude().value - ground >= CITY_MIN_CLIMB, "climbed only %.3f", world.altitude().value - ground);
}

enum double CROWN_WALK_SECONDS = 6;
enum float CROWN_MIN_WALKED = 0.9f;

void structureCrown(ref Script world) {
    world.structure("crown");
    walk.spawn(world);
    float ground = world.altitude().value;
    float start = world.traveled().value;
    world.press(CROWN_WALK_SECONDS, Key.fwd);
    world.wait(walk.SETTLE_SECONDS);
    float walked = world.traveled().value - start;
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    Maybe!Material below = world.targetMaterial();
    string name = walk.nameOf(below);
    world.check(world.isOnGround(), "standing in the hall");
    world.check(walked >= CROWN_MIN_WALKED * walk.SPEED * CROWN_WALK_SECONDS, "walked only %.3f toward the hall door", walked);
    world.check(world.altitude().value - ground > walk.MIN_BLOCK_EDGE / 2, "rose %.3f, not over the door's threshold", world.altitude().value - ground);
    world.check(walk.isOneOf(below, walk.TOWER_MATERIALS[]), "standing on %.*s instead of the hall floor", cast(int) name.length, name.ptr);
}

enum float ENDLESS_FLIGHT = 5;
enum uint ENDLESS_SAMPLES = 10;

void structureEndless(ref Script world) {
    world.structure("city");
    world.mode(MovementMode.noclip);
    foreach (sample; 1 .. ENDLESS_SAMPLES + 1) {
        world.press(ENDLESS_FLIGHT / ENDLESS_SAMPLES / walk.NOCLIP_SPEED, Key.fwd);
        world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
        world.step();
        Maybe!Material below = world.targetMaterial();
        string name = walk.nameOf(below);
        world.check(below.exists && below.value != walk.GROUND, "bare %.*s below after %.1f of %.1f", cast(int) name.length, name.ptr, sample * ENDLESS_FLIGHT / ENDLESS_SAMPLES, ENDLESS_FLIGHT);
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
    world.press(HAMLET_WALK_SECONDS, Key.fwd);
    world.wait(walk.SETTLE_SECONDS);
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    string name = walk.nameOf(world.targetMaterial());
    world.check(walk.isMaterial(world.targetMaterial(), Material.woodPlanks), "standing on %.*s instead of the first hut's floor", cast(int) name.length, name.ptr);
    world.check(world.altitude().value - ground > walk.MIN_BLOCK_EDGE / 2, "stepped over the hut's threshold");
}

immutable Material[3] PLATFORMS = [Material.woodPlanks, Material.marble, Material.greyBrick];

void structureLattice(ref Script world) {
    world.structure("lattice");
    walk.spawn(world);
    float standing = world.altitude().value;
    world.check(standing > 0, "standing at altitude %.4f, not below the plane gravity points away from", standing);
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    string name = walk.nameOf(world.targetMaterial());
    world.check(walk.isOneOf(world.targetMaterial(), PLATFORMS[]), "standing on %.*s instead of the root platform", cast(int) name.length, name.ptr);
    world.press(world.timestep.value, Key.up);
    world.step();
    world.check(!world.isOnGround(), "jumped off the platform");
    world.check(world.altitude().value > standing, "jumped to %.4f from %.4f, not away from the platform", world.altitude().value, standing);
    world.wait(walk.LANDING_SECONDS);
    world.check(world.isOnGround(), "landed back on the platform");
    world.check(fabs(world.altitude().value - standing) < walk.ALTITUDE_TOLERANCE, "landed at %.4f instead of %.4f", world.altitude().value, standing);
}

void risen(string name, float risenAltitude, Material landing, string what)(ref Script world) {
    world.structure(name);
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    world.check(world.isOnGround(), "standing at the start of the route");
    world.check(world.altitude().value < risenAltitude, "starting on the ground, %.3f up", world.altitude().value);
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    world.check(!world.routeWaypoint(reached + 1).exists, "stopped after %zu waypoints", reached);
    world.check(world.isOnGround(), "standing at the end of the route");
    world.check(world.altitude().value > risenAltitude, "ended only %.3f above the ground", world.altitude().value);
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    string below = walk.nameOf(world.targetMaterial());
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
    world.check(watch.largest <= MOST_PULL_PER_STEP, "gravity jumped %.3f in one step of the round trip", watch.largest);
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    string below = walk.nameOf(world.targetMaterial());
    world.check(walk.isMaterial(world.targetMaterial(), Material.concrete), "ended on %.*s instead of the lower landing", cast(int) below.length, below.ptr);
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
    string below = walk.nameOf(world.targetMaterial());
    world.check(walk.isOneOf(world.targetMaterial(), walk.STREET_MATERIALS[]), "standing on %.*s instead of the road", cast(int) below.length, below.ptr);
}

enum double TOWER_WALK_SECONDS = 20;
enum float MAX_WALKED_FRACTION = 0.8f;

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
    world.press(TOWER_WALK_SECONDS, Key.fwd);
    world.wait(walk.SETTLE_SECONDS);
    world.onStep(StepHook.init);
    float walked = world.traveled().value - start;
    float free = walk.SPEED * TOWER_WALK_SECONDS;
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    Maybe!Material below = world.targetMaterial();
    string name = walk.nameOf(below);
    world.check(world.isOnGround(), "standing inside the tower");
    world.check(world.altitude().value - ground > walk.MIN_BLOCK_EDGE / 2, "rose %.3f, not onto the ground floor through the door", world.altitude().value - ground);
    world.check(highest - ground < walk.MAX_BLOCK_EDGE, "climbed %.3f, more than the door's threshold", highest - ground);
    world.check(walked < MAX_WALKED_FRACTION * free, "walked %.3f of %.3f without reaching the far wall", walked, free);
    world.check(walk.isOneOf(below, walk.TOWER_MATERIALS[]), "standing on %.*s instead of the ground floor", cast(int) name.length, name.ptr);
}

enum size_t TRAIL_STOPS = 12;
enum float MAX_STRAIGHTNESS = 0.8f;

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
    world.check(back < MAX_STRAIGHTNESS * walked, "the trail ran straight: %.3f back to its start after walking %.3f", back, walked);
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    string below = walk.nameOf(world.targetMaterial());
    world.check(walk.isMaterial(world.targetMaterial(), Material.gravel), "standing on %.*s instead of the trail", cast(int) below.length, below.ptr);
}

enum float TOP_ALTITUDE = 3.2f;
enum float TRUNK_CLIMB = 0.1f;
enum float NUDGE = 0.01f;
enum uint MOST_NUDGES = 200;

immutable Material[2] TREE_MATERIALS = [Material.oakWood, Material.oakLeaves];

void approachBark(ref Script world) {
    uint nudges = 0;
    while (!world.isFailed && !walk.isOneOf(world.targetMaterial(), TREE_MATERIALS[]) && nudges < MOST_NUDGES) {
        world.press(NUDGE / walk.NOCLIP_SPEED, Key.fwd);
        nudges += 1;
    }
    string facing = walk.nameOf(world.targetMaterial());
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
        string below = walk.nameOf(world.targetMaterial());
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
        string name = walk.nameOf(below);
        world.check(walk.isMaterial(below, Material.glass), "no glass floor over the well %.1f down, facing %.*s", depth, cast(int) name.length, name.ptr);
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
