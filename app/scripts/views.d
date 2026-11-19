module app.scripts.views;

import core.stdc.math : ceil;
import base.maybe : Maybe;
import base.names : textFor;
import base.units : Length;
import base.vector3 : Vec3;
import common.character.controller : MovementMode;
import common.graph : Graph;
import common.node : ChunkSlot, ChunkState;
import common.position : Position;
import client.structures : ensureRisingTag;
import common.worldgen.horospheres : HorosphereId, ROOT, Rise, edgeOf, ensureAirSideNode, ensureHorosphereOver, ensurePlaneHeight, ensureRise, ensureUndersideAt;
import common.worldgen.lineage : Lineage;
import common.worldgen.structure : ColumnSpot, SiteFrame, columnPoint, edgeCells, forwarded, groundSite, moveToLevel, rootSite, siteOf, sitePlacement, turnSite;
import geometry.honeycomb : CORNER_COUNT, Corner, Face, cubeToNode;
import geometry.lorentz : Motion, Point, Vec4;
import plugins.api.api : KindTag, Material, Turn, tagNamed;
import plugins.crafting.crafting : Insight, Upgrade;
import plugins.crafting.inventory : HOTBAR_SLOTS, Inventory, Sorting, Stack;
import plugins.game.bindings : Rules;
import plugins.game.game : Click, Key, RouteWaypoint, Screen, UiAction, UiKind;
import plugins.game.screens : CATALOG_SHEET, SURROUNDINGS_SHEET, sheetNamed;
import app.script : NamedScript, Script, degrees, extractOf, insightNamed, materialNamed, named, upgradeNamed;
import plugins.pharmacology.organism : starterDoses;
import plugins.pharmacology.panels : BODY_SHEET, CHEMISTRY_SHEET, acting;
import plugins.pharmacology.player : chooseCompound, chosenCompound, compounds, keepCompound, organism, pharma;
import climb = app.scripts.climb;
import walk = app.scripts.walk : FLY_SPEED, NOCLIP_SPEED, SETTLE_SECONDS, STRAIGHT_DOWN_DEGREES;

enum float LANDMARK_APART = 1.5f;
enum double DOSED_SECONDS = 8;
enum double COLLECTOR_WAIT_SECONDS = 40;
enum double MINING_WAIT_SECONDS = 0.4;
enum uint STATION_SLOT = HOTBAR_SLOTS - 1;
enum uint FIRST_PACK_SLOT = HOTBAR_SLOTS;
enum uint THREAD_BEADS_SHOWN = 1024;
enum uint MOST_FLOOR_TRIES = 256;
enum float FLORA_RISE = 0.1f;
enum float FLORA_BACK = 0.5f;
enum double FLORA_PITCH = 15;

void above(string structure, string material, uint rings, float lift, double pitch)(ref Script world) {
    world.structure(structure);
    walk.spawn(world);
    Maybe!Position found = walk.ensureNearest(world, world.game.characterState.position, materialNamed(material), rings);
    world.check(found.exists, "no %s stands within %u hops of where the world starts", material.ptr, rings);
    if (!world.isFailed) {
        world.mode(MovementMode.noclip);
        world.game.placeAt(found.value, Length(lift));
        world.look(degrees(0), degrees(pitch));
        world.step();
    }
}

void backedFrom(string structure, string material, uint rings, float lift, float back, double pitch, float drop = 0, double yaw = 0)(ref Script world) {
    world.structure(structure);
    walk.spawn(world);
    if (drop > 0) {
        world.mode(MovementMode.noclip);
        noclip(world, drop, Key.down);
    }
    Maybe!Position found = walk.ensureNearest(world, world.game.characterState.position, materialNamed(material), rings);
    world.check(found.exists, "no %s lies within %u hops of where the world starts", material.ptr, rings);
    if (!world.isFailed) {
        world.mode(MovementMode.noclip);
        world.game.placeAt(found.value, Length(lift));
        world.look(degrees(yaw), degrees(0));
        noclip(world, back, Key.back);
        world.look(degrees(0), degrees(pitch));
        world.step();
    }
}

void landedIn(string structure, string material, uint rings, float lift)(ref Script world) {
    world.structure(structure);
    walk.spawn(world);
    Maybe!Position found = walk.ensureNearest(world, world.game.characterState.position, materialNamed(material), rings);
    world.check(found.exists, "no %s lies within %u hops of where the world starts", material.ptr, rings);
    if (!world.isFailed) {
        world.mode(MovementMode.noclip);
        world.game.placeAt(found.value, Length(lift));
        world.mode(MovementMode.walk);
        world.wait(walk.LANDING_SECONDS);
        world.look(degrees(0), degrees(0));
        world.step();
    }
}

void landmarkFound(string material, uint rings, float back, float rise, double pitch)(ref Script world) {
    world.terrain();
    walk.spawn(world);
    Maybe!Position found = walk.ensureNearest(world, world.game.characterState.position, materialNamed(material), rings);
    world.check(found.exists, "no %s stands within %u hops of where the default world starts", material.ptr, rings);
    if (!world.isFailed) {
        world.mode(MovementMode.noclip);
        world.game.placeAt(found.value, Length(0));
        world.press(back / NOCLIP_SPEED, Key.back);
        world.press(rise / NOCLIP_SPEED, Key.down);
        world.look(degrees(0), degrees(pitch));
        world.step();
    }
}

void overPort(string structure, float lift, double pitch)(ref Script world) {
    world.structure(structure);
    Maybe!Position port = walk.ensurePort(world);
    world.check(port.exists, "found no port near where the world starts");
    if (!world.isFailed) {
        world.mode(MovementMode.noclip);
        world.game.placeAt(port.value, Length(lift));
        world.look(degrees(0), degrees(pitch));
        world.step();
    }
}

void terrainPort(float lift, float back, double pitch)(ref Script world) {
    world.terrain();
    Maybe!Position port = walk.ensurePort(world);
    world.check(port.exists, "found no port near where the default world starts");
    if (!world.isFailed) {
        world.mode(MovementMode.noclip);
        world.game.placeAt(port.value, Length(lift));
        noclip(world, back, Key.back);
        world.look(degrees(0), degrees(pitch));
        world.step();
    }
}

immutable Lineage[3] BUNDLED_STRAINS = [Lineage([0x1A2B, 0x3C4D, 0x5E6F, 0x7081]), Lineage([0x9F3E, 0x2D1C, 0x4B5A, 0x6978]), Lineage([0x8877, 0x6655, 0x4433, 0x2211])];
immutable uint[3] BUNDLED_COUNTS = [4, 2, 1];

void bundle(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    Stack flowers;
    foreach (index, genes; BUNDLED_STRAINS) {
        Stack run = Stack.ofLiving(named("base:flower"), BUNDLED_COUNTS[index], genes, Sorting.unsorted);
        run.pourInto(flowers);
    }
    world.game.inventory.slots[0] = flowers;
    world.game.inventory.slots[FIRST_PACK_SLOT] = flowers;
    world.material(1);
    world.open(Screen.character);
    world.hover(UiKind.slot, FIRST_PACK_SLOT);
}

immutable NamedScript[] VIEWS = [
    NamedScript("arborcrown", &rising!("arbor", 0.9f, 3.5f, 60)),
    NamedScript("arbor", &looking!("arbor", 0, -40)),
    NamedScript("arborclimb", &alongRoute!("arbor", 30, -30)),
    NamedScript("arboraside", &besideAxis!("arbor", 4.0f, 0.9f, 30)),
    NamedScript("arch", &arch),
    NamedScript("babel", &looking!("babel", 0, -30)),
    NamedScript("babeltop", &rising!("babel", 1.0f, 1.5f, 50)),
    NamedScript("babelroom", &above!("babel", "game:pamphlet", 6, 0.12f, 75)),
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
    NamedScript("bundle", &bundle),
    NamedScript("cityaerial", &cityAerial),
    NamedScript("cityblock", &cityBlock),
    NamedScript("cityfar", &streetFar),
    NamedScript("city", &looking!("city", 0, -12)),
    NamedScript("climb", &climbTower),
    NamedScript("corner", &corner),
    NamedScript("crownarch", &rising!("crown", 0, 0.6f, -12)),
    NamedScript("crown", &looking!("crown", 0, 0)),
    NamedScript("connectorspiral", &connectorFromAside!("spiralcity")),
    NamedScript("connectorpaired", &connectorFromAside!("trippaired")),
    NamedScript("connectortrunk", &connectorFromAside!("trippairedwild")),
    NamedScript("trunkfoot", &connectorFoot!("trippairedwild", 0.7f, 0.08f)),
    NamedScript("trunkaside", &connectorFoot!("trippairedwild", 1.5f, 0.3f)),
    NamedScript("spiralfoot", &connectorFoot!("spiralcity", 0.7f, 0.08f)),
    NamedScript("pairedfoot", &connectorFoot!("trippaired", 0.7f, 0.08f)),
    NamedScript("driftfoot", &connectorFoot!("driftcity", 0.7f, 0.08f)),
    NamedScript("lanternfoot", &connectorFoot!("lanterncity", 0.7f, 0.08f)),
    NamedScript("citystreet", &looking!("city", 40, 0)),
    NamedScript("citytunnel", &landedIn!("city", "base:gravel", 3, 0.12f)),
    NamedScript("subwayplatform", &backedFrom!("city", "base:pollen", 4, 0.06f, 0.1f, 0, 0, 90)),
    NamedScript("subwaybore", &above!("city", "base:sunlight", 4, -0.09f, 0)),
    NamedScript("subwaymezzanine", &backedFrom!("city", "base:ceiling-tile", 4, 0.07f, 0.02f, 20, 0, 180)),
    NamedScript("subwayentrance", &sidedView!(walk.isEntrance, 3, 10, -3, 3, -2, 8, 45)),
    NamedScript("subwaycorner", &sidedView!(walk.isEntranceCorner, 1, 9, 1, 4, 0, 6, 80)),
    NamedScript("shallowplatform", &sidedView!(walk.isShallowStation, 2.5f, -3, 7.5f, 2.5f, -3, 16, 5)),
    NamedScript("subwaywell", &sidedView!(walk.isWellDoor, 0, -6, 12, 0, -10, 3, 15)),
    NamedScript("subwaycontinued", &sidedView!(walk.isContinuedStation, 0, -5, 6.5f, 0, -5, -10, 15)),
    NamedScript("subwaycrossing", &backedFrom!("city", "base:acacia-wood", 6, 0.08f, 0.1f, 20)),
    NamedScript("watchtower", &landmarkFound!("base:lava", 8, 0.9f, 0.1f, 5)),
    NamedScript("towerfoot", &backedOut!("tower", 0.3f, -25)),
    NamedScript("hamletfoot", &backedOut!("hamlet", 0.2f, -8)),
    NamedScript("vaultshall", &looking!("vaults", 0, 0)),
    NamedScript("vaultscrypt", &sunk!("vaults", 0.5f, 0.5f, -10)),
    NamedScript("terraces", &looking!("terraces", 0, -15)),
    NamedScript("garden", &looking!("garden", 0, -10)),
    NamedScript("gardenbeds", &rising!("garden", 1.0f, 0.5f, 40)),
    NamedScript("trellis", &looking!("trellis", 0, -10)),
    NamedScript("connectordrift", &connectorFromAside!("driftcity")),
    NamedScript("connectorlantern", &connectorFromAside!("lanterncity")),
    NamedScript("crowntops", &rising!("crown", 1.45f, 0.55f, -35)),
    NamedScript("cubes", &cubes),
    NamedScript("far", &far),
    NamedScript("flight", &flight),
    NamedScript("hamlet", &rising!("hamlet", 0, 0.5f, 20)),
    NamedScript("hiddenstair", &stairFromAside!("plain")),
    NamedScript("hiddenstairmist", &stairFromAside!("base:mist-sight")),
    NamedScript("vaultsstair", &stairFromAside!("plain", "risenvaults")),
    NamedScript("vaultsstairmist", &stairFromAside!("base:mist-sight", "risenvaults")),
    NamedScript("interior", &towardWaypoint!("tower", 6, -10)),
    NamedScript("inventory", &inventoryView),
    NamedScript("landscape", &landscape),
    NamedScript("latticebelow", &rising!("lattice", 0, 0.6f, 50)),
    NamedScript("lattice", &looking!("lattice", 0, -10)),
    NamedScript("latticestair", &poleStair),
    NamedScript("library", &looking!("library", 0, -5)),
    NamedScript("libraryroof", &rising!("library", 0, 1.0f, 60)),
    NamedScript("librarystair", &alongRoute!("library", 46, 35)),
    NamedScript("librarystaff", &above!("library", "game:workbench", 6, 0.12f, 89)),
    NamedScript("librarystaffroom", &backedFrom!("library", "game:workbench", 6, 0.08f, 0.3f, 5, 0, 180)),
    NamedScript("vaultsport", &overPort!("vaults", 0.3f, 70)),
    NamedScript("backroomswellbelow", &downWell!("backrooms", 0.5f, 0.15f, 0, 45)),
    NamedScript("vaultswellbelow", &downWell!("vaults", 0.8f, 0.15f, 0, 45)),
    NamedScript("backroomsworks", &inStack!("backrooms", 1.5f, "base:grey-brick", 0.15f, 0.25f, 0)),
    NamedScript("librarystudy", &above!("library", "pharmacology:press", 3, 0.15f, 80)),
    NamedScript("librarywell", &libraryWell),
    NamedScript("catalog", &catalogDesk),
    NamedScript("libraryturn", &looking!("library", 100, -10)),
    NamedScript("libraryconnector", &connectorFoot!("risenlibrary", 0.8f, 0.3f)),
    NamedScript("libraryconnectorup", &connectorFromAside!("risenlibrary")),
    NamedScript("libraryboiler", &backedFrom!("library", "base:lava", 4, 0.06f, 0.05f, 25, 0.4f)),
    NamedScript("librarybasement", &sunk!("library", 0.4f, 1.0f, 0)),
    NamedScript("librarymeeting", &backedFrom!("library", "base:white-brick", 4, 0.08f, 0.1f, 30)),
    NamedScript("librarystairsdown", &backedFrom!("library", "base:limestone", 4, 0.06f, 0.1f, 35)),
    NamedScript("overview", &overview),
    NamedScript("plantscan", &plantScan),
    NamedScript("bench", &benchView),
    NamedScript("around0", &around!(0)),
    NamedScript("around90", &around!(90)),
    NamedScript("around180", &around!(180)),
    NamedScript("around270", &around!(270)),
    NamedScript("standing0", &standing!(0)),
    NamedScript("standing90", &standing!(90)),
    NamedScript("standing180", &standing!(180)),
    NamedScript("standing270", &standing!(270)),
    NamedScript("landmark1", &landmarkOf!(1)),
    NamedScript("landmark2", &landmarkOf!(2)),
    NamedScript("landmark3", &landmarkOf!(3, 50)),
    NamedScript("palaceinside", &rising!("palace", 1.3f, 0, 25)),
    NamedScript("palace", &looking!("palace", 0, -10)),
    NamedScript("palacestair", &towardWaypoint!("palace", 6, -15)),
    NamedScript("risencity", &routeEnd!("risencity", Maybe!size_t.init, -20)),
    NamedScript("risencross", &routeEnd!("risencity", Maybe!size_t.of(24), -70)),
    NamedScript("risen", &behindRoute!("risencity")),
    NamedScript("risenwild", &behindRoute!("risenwild")),
    NamedScript("risings", &risings!(2.0f, -25)),
    NamedScript("risingsup", &risings!(1.2f, -45)),
    NamedScript("showcase", &showcase!(0.12f, 225, -20)),
    NamedScript("showcaseroofs", &showcase!(1.4f, 45, 60)),
    NamedScript("skyline", &skyline),
    NamedScript("skyward", &skyward),
    NamedScript("slope", &slope),
    NamedScript("sheetbody", &sheetBody),
    NamedScript("controls", &screen!(Screen.controls)),
    NamedScript("menu", &screen!(Screen.menu)),
    NamedScript("menuscenes", &menuScenes),
    NamedScript("sheetsurroundings", &sheet!(SURROUNDINGS_SHEET)),
    NamedScript("collector", &collectorView),
    NamedScript("crafting", &craftingView),
    NamedScript("workbench", &workbenchView),
    NamedScript("mushroom", &floraView!("base:mushroom-cap")),
    NamedScript("lab", &labView),
    NamedScript("press", &pressView),
    NamedScript("sheetchemistry", &chemistryView),
    NamedScript("sheetcatalog", &catalogView),
    NamedScript("journal", &journalView),
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
    NamedScript("zenith", &risings!(0.3f, -85)),
    NamedScript("caves", &cavesRim),
    NamedScript("cavesstair", &cavesAlong!(14, 15, 40)),
    NamedScript("cavesdome", &cavesAlong!(27, 20, -35)),
    NamedScript("cavesglow", &cavesGlow),
    NamedScript("cavesgypsum", &cavesFound!("base:silty-loam", 1.2f, -10)),
    NamedScript("caveschandelier", &cavesFound!("base:snow", 1.2f, -40, Key.down, 0.3f, 0.2f)),
    NamedScript("cavescrystal", &cavesFound!("base:glass", 2.2f, 0, Key.up, CAVES_RISE, 0.2f)),
    NamedScript("vaults", &looking!("vaults", 0, -20)),
    NamedScript("vaultsup", &rising!("vaults", 0, 0.3f, -89)),
    NamedScript("vaultsgallery", &vaultsGallery),
    NamedScript("vaultspassage", &backedFrom!("vaults", "base:red-carpet", 4, 0.06f, 0.05f, 0, 0, 270)),
    NamedScript("wildport", &terrainPort!(0.15f, 0.2f, 40)),
    NamedScript("wildwell", &terrainPort!(-1.9f, 0, -60)),
    NamedScript("vaultscistern", &backedFrom!("vaults", "base:water", 4, 0.1f, 0.35f, 15, 0.3f)),
    NamedScript("vaultsundercroft", &backedFrom!("vaults", "base:lava", 4, 0.1f, 0.25f, 15, 0.3f)),
    NamedScript("sinkhole", &sinkhole),
    NamedScript("routeshaft", &routeShaftTop),
    NamedScript("vertexmarks", &rising!("vertexmarks", 0, 0.4f, 50)),
    NamedScript("backroomspool", &foundIn!("backrooms", "base:water", 0, 0.14f, 0.12f, 60)),
    NamedScript("backroomscourt", &foundIn!("backrooms", "base:oak-wood", 0, 0.6f, 0.35f, 55)),
    NamedScript("cityculvert", &inStack!("city", 1.85f, "base:wet-concrete", 0.15f, 0.25f, -15)),
    NamedScript("cityslag", &inStack!("city", 3.85f, "base:lava", 0.15f, 0.25f, -15)),
    NamedScript("backroomsdamp", &inStack!("backrooms", 1.85f, "base:damp-carpet", 0.15f, 0.25f, -15)),
    NamedScript("backroomsflooded", &inStack!("backrooms", 2.85f, "base:water", 0.15f, 0.25f, -15)),
    NamedScript("backroomsboiler", &inStack!("backrooms", 3.85f, "base:lava", 0.15f, 0.25f, -15)),
    NamedScript("vaultscave", &downWell!("vaults", 2.85f, 0.3f, 0, 10)),
    NamedScript("vaultsreliquary", &inStack!("vaults", 2.85f, "base:red-sandstone", 0.15f, 0.25f, -15)),
    NamedScript("vaultsdrowned", &inStack!("vaults", 3.85f, "base:water", 0.15f, 0.25f, -15)),
    NamedScript("librarywalk", &rising!("library", 1.5f, 0, 0)),
    NamedScript("citywell", &atPort!("city", 0.3f, 0.35f, 40)),
    NamedScript("citywelljoint", &downWell!("city", 1.0f, 0.15f, 90, 15)),
    NamedScript("wildwelljoint", &downWildWell!(1.0f, 0.15f, 15)),
    NamedScript("wildwelllanding", &downWildWell!(2.6f, 0.5f, 20)),
    NamedScript("wildwellbottom", &downWildWell!(2.7f, 0.35f, 60)),
    NamedScript("citywellchamber", &downWell!("city", 2.85f, 0.3f, 0, 10)),
    NamedScript("backroomswell", &atPort!("backrooms", 0.08f, 0.3f, 15)),
    NamedScript("backroomsstairwell", &signAtPort!("backrooms", "base:sunlight", 90, 0.2f, -10)),
    NamedScript("void", &voidBelow),
    NamedScript("under25", &underCave!(2.5f)),
    NamedScript("under35", &underSpawn!(3.5f)),
    NamedScript("under45", &underSpawn!(4.5f)),
    NamedScript("under90", &underSpawn!(9.0f, 0.6f)),
    NamedScript("underwindow", &underWindow),
    NamedScript("island", &islandFound),
    NamedScript("stars", &starField),
    NamedScript("maze", &mazeWalk),
    NamedScript("mazeabove", &mazeAbove),
    NamedScript("mazeside", &mazeFrom!(-20, 3, -20, 12, 24, 4)),
    NamedScript("mazelights", &mazeFrom!(-20, 8, -20, 12, 24, 35)),
    NamedScript("libraryvoid", &libraryVoid),
    NamedScript("terracesrising", &terracesRising),
    NamedScript("wellbottom", &wellBottom),
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

void menuScenes(ref Script view) {
    view.plane(degrees(0));
    view.step();
    view.game.rules = Rules.creative;
    view.open(Screen.menu);
    UiAction pick = {kind: UiKind.pickScene, index: 0};
    view.game.apply(pick, Click.primary);
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
    view.game.inventory.slots[FIRST_PACK_SLOT] = Stack.ofLiving(named("base:flower"), 3, Lineage([0x1234_5678_9ABC_DEF0, 0x0FED_CBA9_8765_4321, 0x1357_9BDF_2468_ACE0, 0xA5A5_5A5A_F0F0_0F0F]), Sorting.sorted);
    view.game.inventory.slots[FIRST_PACK_SLOT + 1] = Stack.ofLiving(named("base:fern"), 2, Lineage([0x1111_2222_3333_4444, 0x5555_6666_7777_8888, 0x9999_AAAA_BBBB_CCCC, 0xDDDD_EEEE_FFFF_0000]), Sorting.unsorted);
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

void sheet(string shown)(ref Script view) {
    view.open(Screen.character);
    view.game.sheet = sheetNamed(shown);
    lookingHere!(10)(view);
}

void screen(Screen shown)(ref Script view) {
    view.open(shown);
    lookingHere!(10)(view);
}

void sheetBody(ref Script view) {
    view.dose();
    view.wait(DOSED_SECONDS);
    view.open(Screen.character);
    view.game.sheet = sheetNamed(BODY_SHEET);
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
    stationPlaced!("game:workbench")(view);
    view.game.craft(3);
    view.step();
}

void keepCompounds(ref Script view) {
    foreach (index, ref dose; starterDoses.slice()) {
        view.game.keepCompound(dose.molecule, extractOf("pharmacology:press-dose") * (index + 1), index);
    }
    view.game.apply(acting(&chooseCompound, 1), Click.primary);
}

void labView(ref Script view) {
    view.game.owned.set(upgradeNamed("pharmacology:assay-kit").id);
    view.game.inventory.gain(Stack(named("pharmacology:oxidizer"), 2));
    view.game.inventory.gain(Stack(named("base:sulfur"), 3));
    stationPlaced!("pharmacology:lab")(view);
    keepCompounds(view);
    view.step();
}

void pressView(ref Script view) {
    view.game.owned.set(upgradeNamed("pharmacology:assay-kit").id);
    view.game.inventory.slots[FIRST_PACK_SLOT] = Stack.ofLiving(named("base:oak-leaves"), 4, Lineage([0x0123_4567_89AB_CDEF, 0x7654_3210_FEDC_BA98, 0x1357_9BDF_2468_ACE0, 0x0F0F_F0F0_5A5A_A5A5]), Sorting.sorted);
    stationPlaced!("pharmacology:press")(view);
    keepCompounds(view);
    view.step();
}

void journalView(ref Script view) {
    view.game.learn(insightNamed("game:charring"));
    view.game.learn(insightNamed("game:sifting"));
    view.game.learn(insightNamed("game:salvage"));
    view.game.learn(insightNamed("pharmacology:seen-mist"));
    view.game.learn(insightNamed("pharmacology:rumor-ember"));
    screen!(Screen.journal)(view);
}

void catalogView(ref Script view) {
    view.game.rules = Rules.creative;
    sheet!(CATALOG_SHEET)(view);
}

void chemistryView(ref Script view) {
    view.game.owned.set(upgradeNamed("pharmacology:assay-kit").id);
    keepCompounds(view);
    view.open(Screen.character);
    view.game.sheet = sheetNamed(CHEMISTRY_SHEET);
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

Maybe!Position openFloorOf(ref Script view, Material wanted, float lift, float room) {
    const(Graph)* graph = &view.game.world.graph;
    ubyte dimension = graph.layout.dimension;
    Maybe!Position found;
    uint tried = 0;
    foreach (slot; 0 .. graph.slotCount) {
        foreach (corner; 0 .. CORNER_COUNT) {
            ChunkSlot chunk = ChunkSlot(slot, cast(Corner) corner);
            if (!found.exists && tried < MOST_FLOOR_TRIES && graph.chunks.at(chunk).state == ChunkState.populated) {
                foreach (cell; 0 .. dimension * dimension * dimension) {
                    if (!found.exists && tried < MOST_FLOOR_TRIES && graph.chunks.at(chunk).voxels.at(cell) == wanted) {
                        Vec3!float cube = graph.layout.cellCenter(Vec3!int(cell % dimension, cell / dimension % dimension, cell / (dimension * dimension)));
                        Point!float inNode = (chunk.corner.cubeToNode * Vec4!float([cube.x, cube.y, cube.z, 1])).toPoint();
                        Position at = view.game.world.graph.ensureNormalized(Position(graph.idAt(slot), Motion!float.shiftTo(inNode)));
                        view.game.placeAt(at, Length(lift));
                        view.step();
                        tried += 1;
                        if (view.isClearAhead(Length(room))) {
                            found = Maybe!Position.of(at);
                        }
                    }
                }
            }
        }
    }
    return found;
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

void sunk(string name, float down, float ahead, double pitch)(ref Script view) {
    view.structure(name);
    view.mode(MovementMode.noclip);
    noclip(view, ahead, Key.forward);
    noclip(view, down, Key.down);
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

void connectorFoot(string name, float back, float rise)(ref Script view) {
    view.structure(name);
    view.enterRoute();
    view.mode(MovementMode.noclip);
    noclip(view, rise, Key.up);
    noclip(view, back, Key.back);
    view.look(degrees(0), degrees(0));
    view.step();
}

void stairFromAside(string preset, string rig = "hiddenstair")(ref Script view) {
    view.structure(rig);
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
    view.look(degrees(yaw), degrees(10));
    view.step();
}

void standing(double yaw)(ref Script view) {
    view.look(degrees(yaw), degrees(0));
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

void landmarkOf(uint wanted, double pitch = 30)(ref Script view) {
    view.terrain();
    view.mode(MovementMode.noclip);
    landmarkStop(view, wanted);
    noclip(view, 0.9f, Key.up);
    noclip(view, 1.2f, Key.back);
    view.look(degrees(0), degrees(pitch));
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
    noclip(view, 0.7f, Key.up);
    view.look(degrees(120), degrees(0));
    view.step();
}

enum int BIG_TREE_EDGES = 1;
enum float BIG_TREE_BACK = 1.0f;
enum float BIG_TREE_RISE = 0.3f;
enum double BIG_TREE_PITCH = -20;

void bigtree(ref Script view) {
    view.terrain();
    Graph* graph = &view.game.world.graph;
    SiteFrame tree = forwarded(graph.view.turnSite(rootSite(graph.anchorSlot), Turn.right), BIG_TREE_EDGES);
    Point!float foot = sitePlacement(tree, graph.layout) * Point!float.origin();
    view.mode(MovementMode.noclip);
    view.game.placeAt((*graph).ensureNormalized(Position(graph.idAt(tree.node), Motion!float.shiftTo(foot))), Length(0));
    noclip(view, BIG_TREE_BACK, Key.back);
    noclip(view, BIG_TREE_RISE, Key.up);
    view.look(degrees(0), degrees(BIG_TREE_PITCH));
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
    noclip(view, 1.0f, Key.forward);
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

enum double FLIGHT_PITCH = 60;

void flight(ref Script view) {
    view.live();
    view.look(degrees(180), degrees(0));
    view.mode(MovementMode.fly);
    view.press(3, Key.up);
    view.press(8, Key.forward);
    view.look(degrees(0), degrees(FLIGHT_PITCH));
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

void risings(float back, double pitch)(ref Script view) {
    view.terrain();
    Graph* graph = &view.game.world.graph;
    Maybe!SiteFrame rising = ensureRisingFrom(view, rootSite(graph.anchorSlot), ROOT, KindTag.of(TERRACES_GROUND));
    view.check(rising.exists, "no terraces rise among the ground vertices searched from spawn");
    if (rising.exists) {
        Point!float foot = sitePlacement(rising.value, graph.layout) * Point!float.origin();
        view.mode(MovementMode.noclip);
        view.game.placeAt((*graph).ensureNormalized(Position(graph.idAt(rising.value.node), Motion!float.shiftTo(foot))), Length(TERRACES_LIFT));
        noclip(view, back, Key.back);
        view.look(degrees(0), degrees(pitch));
    }
    view.step();
    view.game.world.settleFogColor();
}

void showcase(float height, double yaw, double pitch)(ref Script view) {
    view.structure("showcase");
    view.mode(MovementMode.noclip);
    view.enterStructure(Length(height));
    view.look(degrees(yaw), degrees(pitch));
    view.step();
}

enum double STREET_YAW = 40;
enum float STREET_RISE = 0.5f;
enum double STREET_PITCH = 5;

void streetFar(ref Script view) {
    view.structure("city");
    view.mode(MovementMode.noclip);
    view.look(degrees(STREET_YAW), degrees(0));
    noclip(view, STREET_RISE, Key.up);
    view.look(degrees(0), degrees(STREET_PITCH));
    view.step();
}

void skyline(ref Script view) {
    view.structure("city");
    view.mode(MovementMode.noclip);
    noclip(view, 0.45f, Key.up);
    view.look(degrees(330), degrees(5));
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

enum double TREES_YAW = 90;

void trees(ref Script view) {
    view.mode(MovementMode.fly);
    view.press(1, Key.up);
    view.look(degrees(TREES_YAW), degrees(0));
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

enum double VAULTS_GALLERY_YAW = 135;
enum double VAULTS_GALLERY_PITCH = 35;

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

enum double CAVES_PITCH_RESET = 180;
enum float GLOW_DEPTH = 0.1f;
enum float GLOW_ROOM = 0.4f;
enum double GLOW_PITCH = 15;

void cavesGlow(ref Script view) {
    view.structure("caves");
    view.live();
    view.enterRoute(CAVES_DEEP_STOP);
    view.mode(MovementMode.noclip);
    noclip(view, GLOW_DEPTH, Key.down);
    view.wait(CAVES_LOAD_SECONDS);
    view.look(degrees(0), degrees(-CAVES_PITCH_RESET));
    view.look(degrees(0), degrees(CAVES_PITCH_RESET / 2));
    Maybe!Position found = openFloorOf(view, materialNamed("base:cave-grass"), CAVES_RISE, GLOW_ROOM);
    view.check(found.exists, "no cave grass among the first %u found has %.2f of open room in front of it", MOST_FLOOR_TRIES, GLOW_ROOM);
    if (found.exists) {
        view.game.placeAt(found.value, Length(CAVES_RISE));
        view.look(degrees(0), degrees(GLOW_PITCH));
    }
    view.wait(SETTLE_SECONDS);
}

void foundIn(string name, string wanted, float depth, float rise, float back, double pitch)(ref Script view) {
    view.structure(name);
    view.live();
    view.mode(MovementMode.noclip);
    if (depth > 0) {
        noclip(view, depth, Key.down);
    }
    view.wait(CAVES_LOAD_SECONDS);
    Maybe!Position found = firstOf(view, materialNamed(wanted));
    view.check(found.exists, "found no %s among %u loaded nodes of %s", wanted.ptr, view.game.world.graph.slotCount, name.ptr);
    if (found.exists) {
        view.game.placeAt(view.game.world.graph.ensureNormalized(found.value), Length(0));
        noclip(view, rise, Key.up);
        noclip(view, back, Key.back);
        view.look(degrees(0), degrees(pitch));
    }
    view.wait(SETTLE_SECONDS);
}

void sinkhole(ref Script view) {
    view.terrain();
    Maybe!Position rim = walk.ensureLastFlat(view);
    view.check(rim.exists, "the default world flattened no ground, so it has no sinkhole");
    if (rim.exists) {
        view.mode(MovementMode.noclip);
        view.game.placeAt(rim.value, Length(0));
        noclip(view, CAVES_RIM_RISE, Key.up);
        noclip(view, CAVES_RIM_BACK, Key.back);
        view.look(degrees(0), degrees(40));
    }
    view.step();
}

void atPort(string name, float rise, float back, double pitch)(ref Script view) {
    view.structure(name);
    Maybe!Position port = walk.ensurePort(view);
    view.check(port.exists, "found no port among the vertices nearest the root of %s", name.ptr);
    if (port.exists) {
        view.mode(MovementMode.noclip);
        view.game.placeAt(port.value, Length(0));
        noclip(view, rise, Key.up);
        noclip(view, back, Key.back);
        view.look(degrees(0), degrees(pitch));
    }
    view.step();
}

void inWell(ref Script view, float edges, float aside, double yaw, double pitch) {
    Maybe!Position port = walk.ensurePort(view);
    view.check(port.exists, "found no port among the vertices nearest the world's root");
    if (port.exists) {
        view.mode(MovementMode.noclip);
        view.game.placeAt(port.value, Length(-edges * view.game.world.graph.view.edgeOf()));
        noclip(view, aside, Key.back);
        view.look(degrees(yaw), degrees(pitch));
    }
    view.step();
}

void downWell(string name, float edges, float aside, double yaw, double pitch)(ref Script view) {
    view.structure(name);
    inWell(view, edges, aside, yaw, pitch);
}

void inStack(string name, float edges, string floor, float lift, float back, double pitch)(ref Script view) {
    view.structure(name);
    Maybe!Position port = walk.ensurePort(view);
    view.check(port.exists, "found no port among the vertices nearest the root of %s", name.ptr);
    if (port.exists) {
        view.mode(MovementMode.noclip);
        view.game.placeAt(port.value, Length(-edges * view.game.world.graph.view.edgeOf()));
        Maybe!Position found = walk.nearestAround(view, view.game.characterState.position, materialNamed(floor));
        view.check(found.exists, "no %s lies within %.2f of the well %.2f edges down in %s", floor.ptr, walk.SEARCH_REACH, edges, name.ptr);
        if (found.exists) {
            view.game.placeAt(found.value, Length(lift));
            noclip(view, back, Key.back);
            view.look(degrees(0), degrees(pitch));
        }
    }
    view.step();
}

void downWildWell(float edges, float aside, double pitch)(ref Script view) {
    view.terrain();
    inWell(view, edges, aside, 0, pitch);
}

enum float SIGN_DROP = 0.08f;

void signAtPort(string name, string material, double yaw, float back, double pitch)(ref Script view) {
    view.structure(name);
    Maybe!Position port = walk.ensurePort(view);
    view.check(port.exists, "found no port among the vertices nearest the root of %s", name.ptr);
    if (port.exists) {
        Maybe!Position sign = walk.nearestAround(view, port.value, materialNamed(material));
        view.check(sign.exists, "no %s lies within %.2f of the port of %s", material.ptr, walk.SEARCH_REACH, name.ptr);
        if (sign.exists) {
            view.mode(MovementMode.noclip);
            view.game.placeAt(sign.value, Length(0));
            noclip(view, SIGN_DROP, Key.down);
            view.look(degrees(yaw), degrees(0));
            noclip(view, back, Key.back);
            view.look(degrees(0), degrees(pitch));
        }
    }
    view.step();
}

enum float CATALOG_DROP = 0.45f;
enum uint CATALOG_HOPS = 12;

void catalogDesk(ref Script view) {
    view.structure("library");
    view.mode(MovementMode.noclip);
    noclip(view, CATALOG_DROP, Key.down);
    Maybe!Position found = walk.ensureNearest(view, view.game.characterState.position, materialNamed("pharmacology:catalog"), CATALOG_HOPS);
    view.check(found.exists, "no catalog stands within %u hops of the library's start", CATALOG_HOPS);
    if (found.exists) {
        view.game.owned.set(upgradeNamed("pharmacology:assay-kit").id);
        view.game.placeAt(found.value, Length(0.06f));
        view.look(degrees(0), degrees(STRAIGHT_DOWN_DEGREES));
        view.interact();
        view.step();
    }
}

enum size_t SHAFT_TOP_STOP = 4;
enum float SHAFT_TOP_BELOW_EDGES = 0.5f;
enum float SHAFT_TOP_LIFT = 0.12f;
enum float SHAFT_TOP_BACK = 0.1f;
enum double SHAFT_TOP_PITCH = -60;

void routeShaftTop(ref Script view) {
    view.terrain();
    Graph* graph = &view.game.world.graph;
    float edge = graph.view.edgeOf();
    size_t under = 0;
    Maybe!Position at;
    Maybe!Position next;
    foreach (stop; graph.structures.blueprint.route.slice()) {
        Position here = walk.columnPosition(view, stop.site, stop.spot.x, stop.spot.y, stop.spot.z);
        if (graph.view.ensurePlaneHeight(ROOT, here) < -SHAFT_TOP_BELOW_EDGES * edge) {
            if (under == SHAFT_TOP_STOP) {
                at = Maybe!Position.of(here);
            } else if (under == SHAFT_TOP_STOP + 1) {
                next = Maybe!Position.of(here);
            }
            under += 1;
        }
    }
    view.check(next.exists, "the default world laid %zu route stops under the ground, too few to reach the shaft on its route down", under);
    if (!view.isFailed) {
        view.mode(MovementMode.noclip);
        view.game.placeAt(at.value, Length(SHAFT_TOP_LIFT));
        RouteWaypoint toward = climb.waypointTo(view, next.value);
        view.look(toward.yaw, degrees(0));
        noclip(view, SHAFT_TOP_BACK, Key.back);
        view.look(degrees(0), degrees(SHAFT_TOP_PITCH));
    }
    view.step();
}

enum float VOID_DEPTH = 6.5f;
enum double VOID_PITCH = -20;

void voidBelow(ref Script view) {
    view.terrain();
    view.mode(MovementMode.noclip);
    noclip(view, VOID_DEPTH, Key.down);
    view.look(degrees(0), degrees(VOID_PITCH));
    view.step();
}

enum double UNDER_SPAWN_YAW = 90;
enum float UNDER_ROOM = 0.2f;

void underCave(float depth)(ref Script view) {
    view.terrain();
    view.live();
    view.mode(MovementMode.noclip);
    noclip(view, depth, Key.down);
    view.wait(CAVES_LOAD_SECONDS);
    view.look(degrees(0), degrees(-CAVES_PITCH_RESET));
    view.look(degrees(0), degrees(CAVES_PITCH_RESET / 2));
    Maybe!Position found = openFloorOf(view, materialNamed("base:cave-grass"), CAVES_RISE, UNDER_ROOM);
    view.check(found.exists, "no cave grass among the first %u found %.1f under spawn has %.2f of open room in front of it", MOST_FLOOR_TRIES, depth, UNDER_ROOM);
    if (found.exists) {
        view.game.placeAt(found.value, Length(CAVES_RISE));
    }
    view.wait(SETTLE_SECONDS);
}

void underSpawn(float depth, float back = 0)(ref Script view) {
    view.terrain();
    view.mode(MovementMode.noclip);
    noclip(view, depth, Key.down);
    view.look(degrees(UNDER_SPAWN_YAW), degrees(0));
    if (back > 0) {
        noclip(view, back, Key.back);
    }
    view.step();
}

enum float ISLAND_FALL_DEPTH = 6.6f;

enum float ISLAND_LIFT = 0.3f;
enum float ISLAND_BACK = 0.6f;
enum double ISLAND_PITCH = 30;

void islandFound(ref Script view) {
    view.terrain();
    view.live();
    view.mode(MovementMode.noclip);
    noclip(view, ISLAND_FALL_DEPTH, Key.down);
    view.wait(CAVES_LOAD_SECONDS);
    Maybe!Position turf = firstOf(view, materialNamed("base:grass"));
    view.check(turf.exists, "no island turf among %u loaded nodes %.1f under spawn", view.game.world.graph.slotCount, ISLAND_FALL_DEPTH);
    if (turf.exists) {
        view.game.placeAt(view.game.world.graph.ensureNormalized(turf.value), Length(ISLAND_LIFT));
        noclip(view, ISLAND_BACK, Key.back);
        view.look(degrees(0), degrees(ISLAND_PITCH));
    }
    view.wait(SETTLE_SECONDS);
    view.game.world.settleFogColor();
}

void descendBelowUnderside(ref Script view, float edges) {
    Graph* graph = &view.game.world.graph;
    Position here = view.game.characterState.position;
    float edge = graph.view.edgeOf();
    float depth = graph.view.ensureUndersideAt(ROOT, here) + edges * edge;
    noclip(view, graph.view.ensurePlaneHeight(ROOT, here) + depth, Key.down);
}

enum float STARS_EDGES = 6.0f;
enum double STARS_PITCH = 25;

void starField(ref Script view) {
    view.terrain();
    view.mode(MovementMode.noclip);
    descendBelowUnderside(view, STARS_EDGES);
    view.look(degrees(0), degrees(STARS_PITCH));
    view.step();
    view.game.world.settleFogColor();
}

enum float MAZE_STAND = 0.12f;
enum double MAZE_PITCH = -12;
enum float MAZE_OVER = 0.5f;
enum double MAZE_OVER_PITCH = 70;

void mazeWalk(ref Script view) {
    view.terrain();
    Maybe!HorosphereId maze = walk.ensureMaze(view);
    if (maze.exists) {
        Maybe!Position found = walk.ensureMazeDeck(view, maze.value);
        view.check(found.exists, "no walkway runs along an edge from the maze's foot");
        if (found.exists) {
            view.mode(MovementMode.noclip);
            view.game.placeAt(found.value, Length(MAZE_STAND));
            view.mode(MovementMode.walk);
            view.wait(walk.LANDING_SECONDS);
            float height = view.game.world.graph.view.ensurePlaneHeight(maze.value, view.game.characterState.position);
            view.check(view.isOnGround() && height > 0 && height < MAZE_STAND, "the body set down on a walkway of the maze is %.3f over the maze's plane, %s", height, textFor(view.isOnGround(), "standing", "not standing"));
            view.look(degrees(0), degrees(MAZE_PITCH));
        }
    }
    view.step();
    view.game.world.settleFogColor();
}

void mazeFrom(float x, float y, float z, float toX, float toZ, double pitch)(ref Script view) {
    view.terrain();
    Maybe!HorosphereId maze = walk.ensureMaze(view);
    if (maze.exists) {
        Graph* graph = &view.game.world.graph;
        SiteFrame foot = graph.horospheres.horosphere(maze.value).foot;
        view.mode(MovementMode.noclip);
        view.game.placeAt(walk.ensureOnMaze(*graph, foot, ColumnSpot(x, y, z)), Length(0));
        view.look(climb.waypointTo(view, walk.ensureOnMaze(*graph, foot, ColumnSpot(toX, 0, toZ))).yaw, degrees(pitch));
    }
    view.step();
    view.game.world.settleFogColor();
}

void mazeAbove(ref Script view) {
    view.terrain();
    Maybe!HorosphereId maze = walk.ensureMaze(view);
    if (maze.exists) {
        Graph* graph = &view.game.world.graph;
        view.mode(MovementMode.noclip);
        view.game.placeAt(walk.ensureOnMaze(*graph, graph.horospheres.horosphere(maze.value).foot, ColumnSpot(3, 0, 3)), Length(MAZE_OVER));
        view.look(degrees(0), degrees(MAZE_OVER_PITCH));
    }
    view.step();
    view.game.world.settleFogColor();
}

enum uint LIBRARY_GROUND = tagNamed("library:library");
enum uint LIBRARY_WELL = tagNamed("library:stacks");
enum int LIBRARY_AWAY_EDGES = 5;
enum int LIBRARY_BELOW_EDGES = 2;
enum float LIBRARY_DROP = 0.5f;
enum float WELL_WALLED = 0.5f;
enum float WELL_SPIRAL_BELOW = 1;
enum float WELL_ABOVE_LANDING = 0.3f;
enum float WELL_BACK = 1.2f;
enum double LIBRARY_VOID_PITCH = 10;
enum double WELL_BOTTOM_PITCH = -15;

Maybe!SiteFrame ensureRisingFrom(ref Script view, SiteFrame from, HorosphereId over, KindTag wanted) {
    Graph* graph = &view.game.world.graph;
    SiteFrame[walk.MOST_PORT_SITES] sites;
    sites[0] = from;
    size_t count = 1;
    size_t next = 0;
    Maybe!SiteFrame found;
    while (!found.exists && next < count) {
        SiteFrame site = graph.view.moveToLevel(sites[next], 0);
        next += 1;
        if (graph.view.ensureRisingTag(siteOf(site), over) == wanted) {
            found = Maybe!SiteFrame.of(site);
        } else if (count + 3 <= sites.length) {
            SiteFrame ahead = forwarded(site, 1);
            sites[count] = ahead;
            sites[count + 1] = graph.view.turnSite(ahead, Turn.left);
            sites[count + 2] = graph.view.turnSite(ahead, Turn.right);
            count += 3;
        }
    }
    return found;
}

struct RisenGround {
    SiteFrame foot;
    HorosphereId ground;
}

Maybe!RisenGround ensureRisen(ref Script view, uint tag) {
    Graph* graph = &view.game.world.graph;
    Maybe!SiteFrame rising = ensureRisingFrom(view, rootSite(graph.anchorSlot), ROOT, KindTag.of(tag));
    view.check(rising.exists, "no ground of that kind rises among the ground vertices searched from spawn");
    if (!rising.exists) {
        return Maybe!RisenGround.init;
    } else {
        SiteFrame site = rising.value;
        Rise rise = graph.view.ensureRise(site.node, site.corner, ROOT);
        SiteFrame top = graph.view.moveToLevel(forwarded(graph.view.turnSite(site, Turn.pitchUp), rise.edges), 0);
        Face label = top.zSide();
        SiteFrame foot = groundSite(graph.view.ensureAirSideNode(top.node, top.corner, label), top.corner, label);
        Maybe!HorosphereId ground = graph.view.ensureHorosphereOver(site.node, site.corner, ROOT);
        view.check(ground.exists, "the ground that rises from the vertex found has no horosphere");
        if (!ground.exists) {
            return Maybe!RisenGround.init;
        } else {
            return Maybe!RisenGround.of(RisenGround(foot, ground.value));
        }
    }
}

enum uint TERRACES_GROUND = tagNamed("skies:terraces");
enum float TERRACES_LIFT = 0.3f;
enum float TERRACES_BACK = 1.2f;
enum double TERRACES_PITCH = 35;

void terracesRising(ref Script view) {
    view.terrain();
    Graph* graph = &view.game.world.graph;
    Maybe!SiteFrame rising = ensureRisingFrom(view, rootSite(graph.anchorSlot), ROOT, KindTag.of(TERRACES_GROUND));
    view.check(rising.exists, "no terraces rise among the ground vertices searched from spawn");
    if (rising.exists) {
        Point!float foot = sitePlacement(rising.value, graph.layout) * Point!float.origin();
        view.mode(MovementMode.noclip);
        view.game.placeAt((*graph).ensureNormalized(Position(graph.idAt(rising.value.node), Motion!float.shiftTo(foot))), Length(TERRACES_LIFT));
        noclip(view, TERRACES_BACK, Key.back);
        view.look(degrees(0), degrees(TERRACES_PITCH));
    }
    view.step();
    view.game.world.settleFogColor();
}

void libraryVoid(ref Script view) {
    view.terrain();
    Maybe!RisenGround library = ensureRisen(view, LIBRARY_GROUND);
    if (library.exists) {
        Graph* graph = &view.game.world.graph;
        SiteFrame away = graph.view.moveToLevel(forwarded(library.value.foot, LIBRARY_AWAY_EDGES), 0);
        view.mode(MovementMode.noclip);
        view.game.placeAt(walk.ensureBelowVertex(*graph, away, LIBRARY_BELOW_EDGES), Length(0));
        noclip(view, LIBRARY_DROP, Key.down);
        view.look(degrees(0), degrees(LIBRARY_VOID_PITCH));
    }
    view.step();
    view.game.world.settleFogColor();
}

void wellBottom(ref Script view) {
    view.terrain();
    Maybe!RisenGround library = ensureRisen(view, LIBRARY_GROUND);
    if (library.exists) {
        Maybe!SiteFrame well = ensureRisingFrom(view, library.value.foot, library.value.ground, KindTag.of(LIBRARY_WELL));
        view.check(well.exists, "no well sinks among the library's vertices searched from its foot");
        if (well.exists) {
            Graph* graph = &view.game.world.graph;
            SiteFrame up = graph.view.turnSite(well.value, Turn.pitchUp);
            Point!float top = sitePlacement(up, graph.layout) * Point!float.origin();
            float crust = graph.view.ensureUndersideAt(library.value.ground, (*graph).ensureNormalized(Position(graph.idAt(up.node), Motion!float.shiftTo(top)))) / graph.view.edgeOf();
            float cells = edgeCells(graph.layout.dimension) * (ceil(crust + WELL_WALLED) + WELL_SPIRAL_BELOW - WELL_ABOVE_LANDING);
            Point!float spot = sitePlacement(up, graph.layout) * columnPoint(graph.layout, ColumnSpot(0, 0, -cells));
            view.mode(MovementMode.noclip);
            view.game.placeAt((*graph).ensureNormalized(Position(graph.idAt(up.node), Motion!float.shiftTo(spot))), Length(0));
            noclip(view, WELL_BACK, Key.back);
            view.look(degrees(0), degrees(WELL_BOTTOM_PITCH));
        }
    }
    view.step();
    view.game.world.settleFogColor();
}

void sidedView(alias matches, float x, float y, float z, float toX, float toY, float toZ, double pitch)(ref Script view) {
    view.structure("city");
    Maybe!(walk.Sided) found = walk.ensureSided!(matches)(view);
    view.check(found.exists, "no such place in the subway lies near the city's start");
    if (found.exists) {
        view.mode(MovementMode.noclip);
        view.game.placeAt(found.value.spot(view, x, y, z), Length(0));
        view.look(climb.waypointTo(view, found.value.spot(view, toX, toY, toZ)).yaw, degrees(pitch));
    }
    view.step();
}

enum float POLE_BACK = 0.5f;
enum int POLE_BELOW = 8;
enum double POLE_PITCH = 0;

void poleStair(ref Script view) {
    view.structure("lattice");
    Maybe!(walk.PoleStair) stair = walk.ensurePoleStair(view);
    view.check(stair.exists, "no pole stair of two edges stands on the lines through the lattice's vertices near its start");
    if (stair.exists) {
        int cells = edgeCells(view.game.world.graph.layout.dimension);
        view.mode(MovementMode.noclip);
        view.game.placeAt(walk.columnPosition(view, stair.value.line, 0, 0, (stair.value.edge + 1) * cells - POLE_BELOW), Length(0));
        noclip(view, POLE_BACK, Key.back);
        view.look(degrees(0), degrees(POLE_PITCH));
    }
    view.step();
}

enum float WINDOW_RISE = 0.6f;
enum double WINDOW_PITCH = -70;

void underWindow(ref Script view) {
    view.terrain();
    Maybe!Position window = walk.ensureUnderGround(view, walk.Beneath.open);
    view.check(window.exists, "no node %d and a half edges under a ground vertex near spawn is in the open void", walk.BENEATH_EDGES);
    if (window.exists) {
        view.mode(MovementMode.noclip);
        view.game.placeAt(window.value, Length(0));
        noclip(view, WINDOW_RISE, Key.up);
        view.look(degrees(0), degrees(WINDOW_PITCH));
    }
    view.step();
    view.game.world.settleFogColor();
}

void cavesAlong(size_t stop, size_t toward, double pitch)(ref Script view) {
    view.structure("caves");
    view.enterRoute(stop);
    view.wait(SETTLE_SECONDS);
    view.look(view.needWaypoint(toward).yaw, degrees(pitch));
    view.step();
}

void cavesFound(string wanted, float depth, double pitch, Key shift = Key.up, float shifted = CAVES_RISE, float back = CAVES_BACK)(ref Script view) {
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
        noclip(view, back, Key.back);
        view.look(degrees(0), degrees(pitch));
    }
    view.wait(SETTLE_SECONDS);
}
