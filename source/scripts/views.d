module scripts.views;

import base.maybe : Maybe;
import base.units : Length;
import base.vector3 : Vec3;
import client.bindings : Rules;
import client.game : Click, Key, RAW_PER_DOSE, RouteWaypoint, Screen, Sheet, UiAction, UiKind;
import client.script : NamedScript, Script, degrees, insightNamed, materialNamed, named, upgradeNamed;
import common.biology.organism : starterDoses;
import common.biology.wild : WildGenes;
import common.character.controller : MovementMode;
import common.crafting : Insight, Upgrade;
import common.graph : Graph;
import common.inventory : HOTBAR_SLOTS, Inventory, Stack;
import common.node : ChunkSlot, ChunkState;
import common.position : Position;
import geometry.honeycomb : CORNER_COUNT, Corner, cubeToNode;
import geometry.lorentz : Motion, Point, Vec4;
import plugins.api.api : Material;
import climb = scripts.climb;
import walk = scripts.walk : FLY_SPEED, NOCLIP_SPEED, SETTLE_SECONDS, STRAIGHT_DOWN_DEGREES;

enum float LANDMARK_APART = 1.5f;
enum double DOSED_SECONDS = 8;
enum double COLLECTOR_WAIT_SECONDS = 40;
enum double MINING_WAIT_SECONDS = 0.4;
enum uint STATION_SLOT = HOTBAR_SLOTS - 1;
enum uint FIRST_PACK_SLOT = HOTBAR_SLOTS;
enum uint THREAD_BEADS_SHOWN = 1024;
enum float FLORA_RISE = 0.1f;
enum float FLORA_BACK = 0.5f;
enum double FLORA_PITCH = 15;

immutable NamedScript[] VIEWS = [
    NamedScript("arborcrown", &rising!("arbor", 0.9f, 1.6f, 30)),
    NamedScript("arbor", &looking!("arbor", 0, -40)),
    NamedScript("arborclimb", &alongRoute!("arbor", 30, -30)),
    NamedScript("arboraside", &besideAxis!("arbor", 4.0f, 0.9f, -46)),
    NamedScript("arch", &arch),
    NamedScript("babel", &looking!("babel", 0, -30)),
    NamedScript("babeltop", &rising!("babel", 1.0f, 1.5f, 50)),
    NamedScript("backroomsbasement", &atRouteStart!("basement", 150, 0)),
    NamedScript("backroomsdeep", &backroomsDeep),
    NamedScript("backroomsdown", &atRouteStart!("backroomsstairs", 150, 0)),
    NamedScript("backrooms", &backrooms),
    NamedScript("backroomsstairs", &atRouteStart!("backroomsstairs", -60, -20)),
    NamedScript("backroomstop", &backroomsTop),
    NamedScript("backroomswalk", &looking!("backrooms", 0, 0)),
    NamedScript("bigtree", &bigtree),
    NamedScript("blocks", &blocks),
    NamedScript("building", &looking!("tower", 0, 0)),
    NamedScript("cityaerial", &cityAerial),
    NamedScript("cityblock", &cityBlock),
    NamedScript("cityedge", &rising!("city", 4, 0.15f, -10)),
    NamedScript("city", &looking!("city", 0, -12)),
    NamedScript("climb", &climbTower),
    NamedScript("corner", &corner),
    NamedScript("crownarch", &rising!("crown", 0, 0.6f, -12)),
    NamedScript("crown", &looking!("crown", 0, 0)),
    NamedScript("connectorspiral", &connectorFromAside!("spiralcity")),
    NamedScript("connectordrift", &connectorFromAside!("driftcity")),
    NamedScript("connectorlantern", &connectorFromAside!("lanterncity")),
    NamedScript("crowntops", &rising!("crown", 1.45f, 0.45f, -35)),
    NamedScript("cubes", &cubes),
    NamedScript("far", &far),
    NamedScript("flight", &flight),
    NamedScript("hamlet", &rising!("hamlet", 0, 0.5f, 20)),
    NamedScript("hiddenstair", &stairFromAside!("plain")),
    NamedScript("hiddenstairmist", &stairFromAside!("base:mist-sight")),
    NamedScript("interior", &towardWaypoint!("tower", 6, -10)),
    NamedScript("inventory", &inventoryView),
    NamedScript("landscape", &landscape),
    NamedScript("latticebelow", &rising!("lattice", 0, 0.6f, 50)),
    NamedScript("lattice", &looking!("lattice", 0, -10)),
    NamedScript("library", &looking!("library", 0, -5)),
    NamedScript("libraryroof", &rising!("library", 0, 1.9f, 60)),
    NamedScript("librarystair", &alongRoute!("library", 46, 35)),
    NamedScript("librarywell", &libraryWell),
    NamedScript("libraryturn", &looking!("library", 100, -10)),
    NamedScript("overview", &overview),
    NamedScript("plantscan", &plantScan),
    NamedScript("bench", &benchView),
    NamedScript("around0", &around!(0)),
    NamedScript("around90", &around!(90)),
    NamedScript("around180", &around!(180)),
    NamedScript("around270", &around!(270)),
    NamedScript("landmark1", &landmarkOf!(1)),
    NamedScript("landmark2", &landmarkOf!(2)),
    NamedScript("landmark3", &landmarkOf!(3)),
    NamedScript("palaceinside", &rising!("palace", 1.3f, 0, 25)),
    NamedScript("palace", &looking!("palace", 0, -10)),
    NamedScript("palacestair", &towardWaypoint!("palace", 6, -15)),
    NamedScript("risencity", &routeEnd!("risencity", Maybe!size_t.init, -20)),
    NamedScript("risencross", &routeEnd!("risencity", Maybe!size_t.of(24), -70)),
    NamedScript("risen", &behindRoute!("risencity")),
    NamedScript("risenwild", &behindRoute!("risenwild")),
    NamedScript("risings", &risings!(3.0f)),
    NamedScript("risingsup", &risings!(4.0f)),
    NamedScript("roadaerial", &roadAerial),
    NamedScript("road", &road),
    NamedScript("showcase", &showcase!(0.12f, 225, -20)),
    NamedScript("showcaseroofs", &showcase!(1.4f, 45, 60)),
    NamedScript("skyline", &skyline),
    NamedScript("skyward", &skyward),
    NamedScript("slope", &slope),
    NamedScript("sheetbody", &sheetBody),
    NamedScript("sheetcontrols", &sheet!(Sheet.controls)),
    NamedScript("sheetsurroundings", &sheet!(Sheet.surroundings)),
    NamedScript("collector", &collectorView),
    NamedScript("crafting", &craftingView),
    NamedScript("workbench", &workbenchView),
    NamedScript("mushroom", &floraView!("base:mushroom-cap")),
    NamedScript("lab", &labView),
    NamedScript("press", &pressView),
    NamedScript("sheetchemistry", &chemistryView),
    NamedScript("sheetcatalog", &catalogView),
    NamedScript("sheetjournal", &journalView),
    NamedScript("mining", &miningView),
    NamedScript("stairs", &towardWaypoint!("tower", 3, -20)),
    NamedScript("starter", &starterView),
    NamedScript("terrain", &lookingHere!(10)),
    NamedScript("terrainbehind", &perceiving!("base:behind", 10)),
    NamedScript("terraindosed", &dosed),
    NamedScript("terrainnarrow", &perceiving!("base:narrow", 10)),
    NamedScript("terrainsharp", &perceiving!("base:sharp", 10)),
    NamedScript("terrainsoft", &perceiving!("base:soft", 10)),
    NamedScript("terrainswaying", &perceiving!("base:swaying", 10)),
    NamedScript("terrainturned", &perceiving!("base:turned", 10)),
    NamedScript("terrainwide", &perceiving!("base:wide", 10)),
    NamedScript("tower", &tower),
    NamedScript("trail", &trail),
    NamedScript("treebase", &lookingHere!(-10)),
    NamedScript("trees", &trees),
    NamedScript("treetop", &treetop),
    NamedScript("wild", &routeEnd!("risenwild", Maybe!size_t.init, -10)),
    NamedScript("zenith", &zenith),
    NamedScript("caves", &cavesRim),
    NamedScript("cavesstair", &cavesAlong!(14, 15, 40)),
    NamedScript("cavesdome", &cavesAlong!(27, 20, -35)),
    NamedScript("cavesglow", &cavesFound!("base:cave-grass", 0.1f, -25)),
    NamedScript("cavesgypsum", &cavesFound!("base:silty-loam", 1.2f, -10)),
    NamedScript("caveschandelier", &cavesFound!("base:snow", 1.2f, -40, Key.down, 0.3f)),
    NamedScript("cavescrystal", &cavesFound!("base:glass", 2.2f, 0)),
    NamedScript("vaults", &looking!("vaults", 0, -20)),
    NamedScript("vaultsup", &rising!("vaults", 0, 0.75f, -89)),
    NamedScript("vaultsgallery", &vaultsGallery),
    NamedScript("thread", &threadView),
];

void threadView(ref Script view) {
    view.plane(degrees(0));
    view.game.thread.most = THREAD_BEADS_SHOWN;
    view.press(3, Key.forward);
    view.look(degrees(90), degrees(0));
    view.press(2, Key.forward);
    view.look(degrees(150), degrees(25));
    view.step();
}

void noclip(ref Script view, float distance, Key key) {
    view.press(distance / NOCLIP_SPEED, key);
}

void looking(string name, double yaw, double pitch)(ref Script view) {
    view.structure(name);
    view.look(degrees(yaw), degrees(pitch));
    view.step();
}

void lookingHere(double pitch)(ref Script view) {
    view.look(degrees(0), degrees(pitch));
    view.step();
}

void benchPlaced(ref Script view) {
    view.plane(degrees(0));
    view.step();
    view.game.inventory.slots[FIRST_PACK_SLOT] = Stack(named("base:flower"), 3, Maybe!WildGenes.of(WildGenes([0x1234_5678_9ABC_DEF0, 0x0FED_CBA9_8765_4321, 0x1357_9BDF_2468_ACE0, 0xA5A5_5A5A_F0F0_0F0F])));
    view.game.inventory.slots[FIRST_PACK_SLOT + 1] = Stack(named("base:fern"), 2, Maybe!WildGenes.of(WildGenes([0x1111_2222_3333_4444, 0x5555_6666_7777_8888, 0x9999_AAAA_BBBB_CCCC, 0xDDDD_EEEE_FFFF_0000])));
    view.material(7);
    view.look(degrees(0), degrees(30));
    view.placeBlock();
}

void benchView(ref Script view) {
    benchPlaced(view);
    view.interact();
    view.step();
}

void benchAimed(ref Script view) {
    benchPlaced(view);
    view.step();
}

void plantScan(ref Script view) {
    view.plane(degrees(0));
    view.step();
    view.game.inventory.slots[0] = Stack(named("base:flower"), 1);
    view.material(1);
    view.look(degrees(0), degrees(30));
    view.placeBlock();
    view.step();
}

void inventoryView(ref Script view) {
    view.plane(degrees(0));
    view.look(degrees(0), degrees(30));
    view.step();
    view.breakBlock();
    view.open(Screen.character);
    view.step();
}

void starterView(ref Script view) {
    view.game.inventory = Inventory.init;
    lookingHere!(10)(view);
}

void sheet(Sheet shown)(ref Script view) {
    view.open(Screen.character);
    view.game.sheet = shown;
    lookingHere!(10)(view);
}

void sheetBody(ref Script view) {
    view.dose();
    view.wait(DOSED_SECONDS);
    view.open(Screen.character);
    view.game.sheet = Sheet.body;
    lookingHere!(10)(view);
}

void collectorView(ref Script view) {
    view.plane(degrees(0));
    view.step();
    view.material(8);
    view.look(degrees(0), degrees(30));
    view.placeBlock();
    view.wait(COLLECTOR_WAIT_SECONDS);
    view.interact();
    view.step();
}

void craftingView(ref Script view) {
    view.game.inventory = Inventory.init;
    view.game.inventory.gain(Stack(named("base:oak-wood"), 6));
    view.game.inventory.gain(Stack(named("base:sand"), 5));
    view.game.inventory.gain(Stack(named("base:iron-ore"), 2));
    view.game.craft(1);
    view.open(Screen.character);
    lookingHere!(10)(view);
}

void stationPlaced(string station)(ref Script view) {
    view.plane(degrees(0));
    view.step();
    view.game.inventory.slots[STATION_SLOT] = Stack(named(station), 1);
    view.material(STATION_SLOT + 1);
    view.look(degrees(0), degrees(30));
    view.placeBlock();
    view.interact();
}

void workbenchView(ref Script view) {
    view.game.inventory = Inventory.init;
    view.game.inventory.gain(Stack(named("base:oak-wood"), 3));
    view.game.inventory.gain(Stack(named("base:granite"), 9));
    stationPlaced!("base:workbench")(view);
    view.game.craft(3);
    view.step();
}

void keepCompounds(ref Script view) {
    foreach (index, ref dose; starterDoses.slice()) {
        view.game.keepCompound(dose.molecule, RAW_PER_DOSE * (index + 1), index);
    }
    UiAction choose = {kind: UiKind.chooseCompound, index: 1};
    view.game.apply(choose, Click.primary);
}

void labView(ref Script view) {
    view.game.owned.set(upgradeNamed("base:assay-kit").id);
    view.game.inventory.gain(Stack(named("base:oxidizer"), 2));
    view.game.inventory.gain(Stack(named("base:sulfur"), 3));
    stationPlaced!("base:lab")(view);
    keepCompounds(view);
    view.step();
}

void pressView(ref Script view) {
    view.game.owned.set(upgradeNamed("base:assay-kit").id);
    view.game.inventory.slots[FIRST_PACK_SLOT] = Stack(named("base:oak-leaves"), 4, Maybe!WildGenes.of(WildGenes([0x0123_4567_89AB_CDEF, 0x7654_3210_FEDC_BA98, 0x1357_9BDF_2468_ACE0, 0x0F0F_F0F0_5A5A_A5A5])));
    stationPlaced!("base:press")(view);
    keepCompounds(view);
    view.step();
}

void journalView(ref Script view) {
    view.game.learn(insightNamed("base:charring"));
    view.game.learn(insightNamed("base:sifting"));
    view.game.learn(insightNamed("base:salvage"));
    sheet!(Sheet.journal)(view);
}

void catalogView(ref Script view) {
    view.game.rules = Rules.creative;
    sheet!(Sheet.catalog)(view);
}

void chemistryView(ref Script view) {
    view.game.owned.set(upgradeNamed("base:assay-kit").id);
    keepCompounds(view);
    view.open(Screen.character);
    view.game.sheet = Sheet.chemistry;
    lookingHere!(10)(view);
}

Maybe!Position firstOf(ref Script view, Material wanted) {
    const(Graph)* graph = &view.game.world.graph;
    ubyte dimension = graph.layout.dimension;
    foreach (slot; 0 .. graph.slotCount) {
        foreach (corner; 0 .. CORNER_COUNT) {
            ChunkSlot chunk = ChunkSlot(slot, cast(Corner) corner);
            if (graph.chunks.at(chunk).state == ChunkState.populated) {
                foreach (cell; 0 .. dimension * dimension * dimension) {
                    if (graph.chunks.at(chunk).voxels.at(cell) == wanted) {
                        Vec3!float cube = graph.layout.cellCenter(Vec3!int(cell % dimension, cell / dimension % dimension, cell / (dimension * dimension)));
                        Point!float inNode = (chunk.corner.cubeToNode * Vec4!float([cube.x, cube.y, cube.z, 1])).toPoint();
                        return Maybe!Position.of(Position(graph.idAt(slot), Motion!float.shiftTo(inNode)));
                    }
                }
            }
        }
    }
    return Maybe!Position.init;
}

void floraView(string wanted)(ref Script view) {
    view.mode(MovementMode.noclip);
    view.wait(SETTLE_SECONDS);
    Maybe!Position found = firstOf(view, materialNamed(wanted));
    view.check(found.exists, "found no %s among %u loaded nodes", wanted.ptr, view.game.world.graph.slotCount);
    if (found.exists) {
        view.game.placeAt(view.game.world.graph.ensureNormalized(found.value), Length(0));
        noclip(view, FLORA_RISE, Key.up);
        noclip(view, FLORA_BACK, Key.back);
        view.look(degrees(0), degrees(FLORA_PITCH));
    }
    view.wait(SETTLE_SECONDS);
}

void miningView(ref Script view) {
    view.plane(degrees(0));
    view.game.inventory = Inventory.init;
    view.look(degrees(0), degrees(30));
    view.hold(Key.mine);
    view.wait(MINING_WAIT_SECONDS);
}

void dosed(ref Script view) {
    view.dose();
    view.wait(DOSED_SECONDS);
    view.look(degrees(0), degrees(10));
    view.step();
}

void perceiving(string preset, double pitch)(ref Script view) {
    view.perceive(preset);
    lookingHere!(pitch)(view);
}

void rising(string name, float ahead, float rise, double pitch)(ref Script view) {
    view.structure(name);
    view.mode(MovementMode.noclip);
    if (ahead > 0) {
        noclip(view, ahead, Key.forward);
    }
    if (rise > 0) {
        noclip(view, rise, Key.up);
    }
    view.look(degrees(0), degrees(pitch));
    view.step();
}

void backedOut(string name, float back, double pitch)(ref Script view) {
    view.structure(name);
    view.mode(MovementMode.noclip);
    noclip(view, back, Key.back);
    view.look(degrees(0), degrees(pitch));
    view.step();
}

void atRouteStart(string name, double yaw, double pitch)(ref Script view) {
    view.structure(name);
    view.enterRoute();
    view.wait(SETTLE_SECONDS);
    view.look(degrees(yaw), degrees(pitch));
    view.step();
}

void towardWaypoint(string name, size_t number, double pitch)(ref Script view) {
    view.structure(name);
    view.enterRoute();
    view.wait(SETTLE_SECONDS);
    view.look(view.needWaypoint(number).yaw, degrees(pitch));
    view.step();
}

void followRoute(ref Script view, Maybe!size_t last) {
    view.enterRoute();
    view.wait(SETTLE_SECONDS);
    climb.follow(view, last);
    view.wait(SETTLE_SECONDS);
}

void routeEnd(string name, Maybe!size_t last, double pitch)(ref Script view) {
    view.structure(name);
    followRoute(view, last);
    view.look(degrees(0), degrees(pitch));
    view.step();
}

void alongRoute(string name, size_t last, double pitch)(ref Script view) {
    view.structure(name);
    followRoute(view, Maybe!size_t.of(last));
    view.look(view.needWaypoint(last + 1).yaw, degrees(pitch));
    view.step();
}

void besideAxis(string name, float height, float away, double pitch)(ref Script view) {
    view.structure(name);
    view.mode(MovementMode.noclip);
    view.enterStructure(Length(height));
    noclip(view, away, Key.back);
    view.look(degrees(0), degrees(pitch));
    view.step();
}

void libraryWell(ref Script view) {
    view.structure("library");
    view.mode(MovementMode.noclip);
    view.enterStructure(Length(-2.0f));
    view.look(degrees(0), degrees(55));
    view.step();
}

void behindRoute(string name)(ref Script view) {
    view.structure(name);
    view.enterRoute();
    view.mode(MovementMode.noclip);
    noclip(view, 1.2f, Key.back);
    view.look(degrees(0), degrees(-40));
    view.step();
}

void connectorFromAside(string name)(ref Script view) {
    view.structure(name);
    view.enterRoute();
    view.mode(MovementMode.noclip);
    noclip(view, 0.5f, Key.up);
    noclip(view, 1.1f, Key.back);
    view.look(degrees(0), degrees(-15));
    view.step();
}

void stairFromAside(string preset)(ref Script view) {
    view.structure("hiddenstair");
    view.perceive(preset);
    view.enterRoute();
    view.mode(MovementMode.noclip);
    noclip(view, 0.5f, Key.up);
    noclip(view, 1.1f, Key.back);
    view.look(degrees(0), degrees(-15));
    view.step();
}

void around(double yaw)(ref Script view) {
    view.mode(MovementMode.noclip);
    noclip(view, 0.5f, Key.up);
    view.look(degrees(yaw), degrees(-8));
    view.step();
}

size_t landmarkStop(ref Script view, uint wanted) {
    size_t stop = 1;
    uint found = 0;
    view.enterRoute(stop);
    Maybe!RouteWaypoint next = view.routeWaypoint(stop + 1);
    while (found < wanted && next.exists) {
        if (next.value.horizontal.value > LANDMARK_APART) {
            found += 1;
        }
        stop += 1;
        view.enterRoute(stop);
        next = view.routeWaypoint(stop + 1);
    }
    return stop;
}

void landmarkOf(uint wanted)(ref Script view) {
    view.terrain();
    view.mode(MovementMode.noclip);
    landmarkStop(view, wanted);
    noclip(view, 0.9f, Key.up);
    noclip(view, 1.2f, Key.back);
    view.look(degrees(0), degrees(30));
    view.step();
}

void overview(ref Script view) {
    view.mode(MovementMode.noclip);
    view.look(degrees(0), degrees(-STRAIGHT_DOWN_DEGREES));
    noclip(view, 1.6f, Key.forward);
    view.look(degrees(0), degrees(2 * STRAIGHT_DOWN_DEGREES));
    view.step();
}

void arch(ref Script view) {
    view.structure("crown");
    view.enterRoute();
    climb.follow(view, Maybe!size_t.of(45));
    view.look(view.needWaypoint(50).yaw, degrees(-15));
    view.step();
}

void backroomsDeep(ref Script view) {
    view.structure("risenbackrooms");
    followRoute(view, Maybe!size_t.init);
    view.look(degrees(40), degrees(0));
    view.press(5, Key.forward);
    view.press(1, Key.back);
    view.look(degrees(-60), degrees(0));
    view.step();
}

void backrooms(ref Script view) {
    view.structure("risenbackrooms");
    followRoute(view, Maybe!size_t.init);
    view.press(1.5, Key.forward);
    view.look(degrees(180), degrees(0));
    view.step();
}

void backroomsTop(ref Script view) {
    view.structure("risenbackrooms");
    followRoute(view, Maybe!size_t.init);
    view.mode(MovementMode.noclip);
    noclip(view, 0.55f, Key.up);
    view.look(degrees(120), degrees(0));
    view.step();
}

void bigtree(ref Script view) {
    view.terrain();
    view.mode(MovementMode.noclip);
    noclip(view, 1.0f, Key.back);
    noclip(view, 0.5f, Key.up);
    view.look(degrees(0), degrees(-5));
    view.step();
}

void blocks(ref Script view) {
    enum double yawStep = 15;
    enum uint materials = 9;
    view.plane(degrees(0));
    view.step();
    view.look(degrees(0), degrees(20));
    view.look(degrees(-yawStep * (materials - 1) / 2), degrees(0));
    foreach (slot; 1 .. materials + 1) {
        view.material(slot);
        view.placeBlock();
        view.look(degrees(yawStep), degrees(0));
    }
    view.look(degrees(-yawStep * (materials + 1) / 2), degrees(-10));
    view.step();
}

void cityAerial(ref Script view) {
    view.structure("city");
    view.mode(MovementMode.noclip);
    view.look(degrees(0), degrees(-STRAIGHT_DOWN_DEGREES));
    noclip(view, 2.0f, Key.forward);
    view.look(degrees(0), degrees(2 * STRAIGHT_DOWN_DEGREES));
    view.step();
}

void cityBlock(ref Script view) {
    view.structure("city");
    view.mode(MovementMode.noclip);
    view.look(degrees(90), degrees(0));
    noclip(view, 0.3f, Key.back);
    noclip(view, 0.3f, Key.up);
    view.look(degrees(0), degrees(20));
    view.step();
}

void climbTower(ref Script view) {
    view.structure("tower");
    climb.route(view, 2.5f);
    view.takeFailure();
}

void corner(ref Script view) {
    view.plane(degrees(0));
    walk.buildWall(view, 2);
    view.press(0.5, Key.right);
    view.look(degrees(-35), degrees(0));
    view.step();
}

void cubes(ref Script view) {
    view.plane(degrees(0));
    walk.buildWall(view, 3);
    view.press(0.3, Key.back);
    view.wait(SETTLE_SECONDS);
}

void far(ref Script view) {
    view.look(degrees(180), degrees(0));
    view.mode(MovementMode.fly);
    view.press(3, Key.up);
    view.press(10.0f / FLY_SPEED, Key.forward);
    view.look(degrees(0), degrees(60));
    view.step();
}

void flight(ref Script view) {
    view.live();
    view.look(degrees(180), degrees(0));
    view.mode(MovementMode.fly);
    view.press(3, Key.up);
    view.press(8, Key.forward);
    view.step();
}

void landscape(ref Script view) {
    view.mode(MovementMode.noclip);
    noclip(view, 2.0f, Key.forward);
    view.look(degrees(0), degrees(-STRAIGHT_DOWN_DEGREES));
    noclip(view, 0.7f, Key.forward);
    view.look(degrees(0), degrees(STRAIGHT_DOWN_DEGREES + 25));
    view.step();
}

void risings(float distance)(ref Script view) {
    view.mode(MovementMode.noclip);
    view.look(degrees(90), degrees(0));
    noclip(view, distance, Key.forward);
    view.look(degrees(0), degrees(-30));
    view.step();
}

void roadAerial(ref Script view) {
    enum float edge = 1.0613f;
    enum uint vertex = 6;
    view.terrain();
    view.mode(MovementMode.noclip);
    view.enterRoute();
    view.look(view.needWaypoint(5).yaw, degrees(0));
    noclip(view, vertex * edge, Key.forward);
    noclip(view, 0.6f, Key.left);
    noclip(view, 0.8f, Key.down);
    view.look(degrees(90), degrees(0));
    view.step();
}

void road(ref Script view) {
    view.terrain();
    view.mode(MovementMode.noclip);
    view.enterRoute();
    noclip(view, 0.3f, Key.up);
    view.look(view.needWaypoint(5).yaw, degrees(25));
    view.step();
}

void showcase(float height, double yaw, double pitch)(ref Script view) {
    view.structure("showcase");
    view.mode(MovementMode.noclip);
    view.enterStructure(Length(height));
    view.look(degrees(yaw), degrees(pitch));
    view.step();
}

void skyline(ref Script view) {
    view.structure("city");
    view.mode(MovementMode.noclip);
    noclip(view, 0.45f, Key.up);
    view.look(degrees(150), degrees(5));
    view.step();
}

void skyward(ref Script view) {
    view.mode(MovementMode.noclip);
    view.look(degrees(90), degrees(-STRAIGHT_DOWN_DEGREES));
    noclip(view, 2.5f, Key.forward);
    view.look(degrees(0), degrees(STRAIGHT_DOWN_DEGREES + 70));
    view.step();
}

void slope(ref Script view) {
    view.plane(degrees(40));
    view.press(3, Key.forward);
    view.look(degrees(60), degrees(0));
    view.step();
}

void tower(ref Script view) {
    view.structure("tower");
    view.mode(MovementMode.noclip);
    view.enterStructure(Length(2));
    noclip(view, 0.75f, Key.forward);
    view.look(degrees(180), degrees(20));
    view.step();
}

void trail(ref Script view) {
    view.structure("trail");
    view.enterRoute();
    view.mode(MovementMode.noclip);
    noclip(view, 0.7f, Key.up);
    view.look(degrees(0), degrees(75));
    view.step();
}

void trees(ref Script view) {
    view.mode(MovementMode.fly);
    view.press(1, Key.up);
    view.press(5, Key.forward);
    view.look(degrees(0), degrees(20));
    view.step();
}

void treetop(ref Script view) {
    view.terrain();
    view.mode(MovementMode.noclip);
    noclip(view, 1.2f, Key.forward);
    view.look(degrees(0), degrees(-75));
    view.step();
}

void zenith(ref Script view) {
    view.mode(MovementMode.noclip);
    view.look(degrees(90), degrees(0));
    noclip(view, 3.0f, Key.forward);
    view.look(degrees(0), degrees(-STRAIGHT_DOWN_DEGREES));
    view.step();
}

enum double VAULTS_GALLERY_YAW = 135;
enum double VAULTS_GALLERY_PITCH = 20;

void vaultsGallery(ref Script view) {
    view.structure("vaults");
    followRoute(view, Maybe!size_t.init);
    view.look(degrees(VAULTS_GALLERY_YAW), degrees(VAULTS_GALLERY_PITCH));
    view.step();
}

enum double CAVES_LOAD_SECONDS = 4;
enum size_t CAVES_DEEP_STOP = 28;
enum float CAVES_RISE = 0.12f;
enum float CAVES_BACK = 0.45f;
enum float CAVES_RIM_RISE = 0.3f;
enum float CAVES_RIM_BACK = 0.35f;

void cavesRim(ref Script view) {
    view.structure("caves");
    view.enterRoute();
    view.look(view.needWaypoint(2).yaw, degrees(0));
    view.mode(MovementMode.noclip);
    noclip(view, CAVES_RIM_RISE, Key.up);
    noclip(view, CAVES_RIM_BACK, Key.back);
    view.look(degrees(0), degrees(40));
    view.step();
}

void cavesAlong(size_t stop, size_t toward, double pitch)(ref Script view) {
    view.structure("caves");
    view.enterRoute(stop);
    view.wait(SETTLE_SECONDS);
    view.look(view.needWaypoint(toward).yaw, degrees(pitch));
    view.step();
}

void cavesFound(string wanted, float depth, double pitch, Key shift = Key.up, float shifted = CAVES_RISE)(ref Script view) {
    view.structure("caves");
    view.live();
    view.enterRoute(CAVES_DEEP_STOP);
    view.mode(MovementMode.noclip);
    noclip(view, depth, Key.down);
    view.wait(CAVES_LOAD_SECONDS);
    Maybe!Position found = firstOf(view, materialNamed(wanted));
    view.check(found.exists, "found no %s among %u loaded nodes %.1f down", wanted.ptr, view.game.world.graph.slotCount, depth);
    if (found.exists) {
        view.game.placeAt(view.game.world.graph.ensureNormalized(found.value), Length(0));
        noclip(view, shifted, shift);
        noclip(view, CAVES_BACK, Key.back);
        view.look(degrees(0), degrees(pitch));
    }
    view.wait(SETTLE_SECONDS);
}
