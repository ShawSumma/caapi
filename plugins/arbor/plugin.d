module plugins.arbor.plugin;

import plugins.api.api : Api, Color, HorosphereForm, KindId, Look, Material, Registry, Risen, RisingKind, Site, Span, Spot, Tint, entryOf;
import plugins.connector.connector : Tag;
import plugins.horospheres.tree : TRUNK_RADIUS, Trunk, segment;
import plugins.turtle.turtle : Offset, Rows, STAIR_HEADROOM, TREAD_THICKNESS, TURN_TREADS, Turtle, boxOf, floorMod, lawn, onWedge, ringRows, treadSpan, wedgeRows;

immutable Look LOOK = Look("arbor", Color(0.72f, 0.84f, 0.74f), Tint.fog);

enum double TREAD_IN = TRUNK_RADIUS - 1;
enum double ROOM_IN = TRUNK_RADIUS + 1.5;
enum double TREAD_OUT = 8.5;
enum double DECK_OUT = 9.5;
enum double RAIL_IN = 8.5;
enum double ROUTE_RADIUS = 6.5;
enum int BURIED_TREADS = 8;
enum int DECK_EVERY = 3;
enum int ROUTE_TURNS = 4;
enum int LANTERN_EVERY = 6;
enum int LANTERN_HEIGHT = 2;
enum uint TREE_EDGES = 2;
enum double ROOT_SHARE = 0.1;
enum Material STEP = Material.spruceWood;
enum Material DECK = Material.woodPlanks;
enum Material POST = Material.spruceWood;
immutable Spot SPAWN = Spot(6, 0, 0);

void climb(Turtle tower, int bottom, int ground) {
    Rows[TURN_TREADS] treads = wedgeRows(tower.column(), TREAD_IN, TREAD_OUT);
    Rows[TURN_TREADS] rooms = wedgeRows(tower.column(), ROOM_IN, TREAD_OUT);
    foreach (tread; -STAIR_HEADROOM .. TURN_TREADS) {
        Rows* wedge = &treads[floorMod(tread, TURN_TREADS)];
        int height = bottom + tread;
        Rows* room = &rooms[floorMod(tread, TURN_TREADS)];
        if (height >= ground - TREAD_THICKNESS) {
            tower.clearOver(*room, tread);
        }
        if (tread >= 0 && height >= ground - BURIED_TREADS) {
            tower.fillRows(STEP, *wedge, treadSpan(tread));
            if (height >= ground) {
                tower.paintRows(STEP, *room, treadSpan(tread));
            }
        }
    }
}

void deck(Turtle tower) {
    Rows floor = ringRows(tower.column(), TREAD_IN, DECK_OUT);
    Rows rail = ringRows(tower.column(), RAIL_IN, DECK_OUT);
    tower.fillRows(DECK, floor, Span(0, 0));
    tower.fillRows(POST, rail, Span(1, 1));
    foreach (tread; 0 .. TURN_TREADS / LANTERN_EVERY) {
        Offset at = onWedge(tread * LANTERN_EVERY, RAIL_IN);
        int x = cast(int) at.x;
        int y = cast(int) at.y;
        tower.fill(Material.lightPanel, boxOf(Span(x, x), Span(y, y), Span(2, LANTERN_HEIGHT)));
    }
}

void tile(const(Api)* api, Site base, const(Risen)* risen, const(void)* data) {
    Turtle tower = Turtle(api, base);
    segment(tower, risen.segment, risen.ground, Trunk.climbed);
    int bottom = risen.segment * tower.edgeCells();
    if (bottom + tower.edgeCells() > risen.ground - BURIED_TREADS) {
        if (floorMod(risen.segment, DECK_EVERY) == 0 && bottom > risen.ground) {
            deck(tower);
        }
        climb(tower, bottom, risen.ground);
    }
}

void plant(const(Api)* api, Site at) {
    KindId kind = api.horosphere(api, 0, HorosphereForm.upright, Tag.tree, &tile, null, 0);
    api.openHorosphere(api, at, kind, TREE_EDGES);
}

void route(Turtle tower) {
    Offset foot = onWedge(0, TREAD_OUT + 2);
    tower.stop(foot.x, foot.y, 0);
    foreach (tread; 0 .. ROUTE_TURNS * TURN_TREADS) {
        Offset at = onWedge(tread, ROUTE_RADIUS);
        tower.stop(at.x, at.y, tread + 1);
    }
}

void landmark(const(Api)* api, Site at, const(void)* data) {
    plant(api, at);
}

void world(const(Api)* api, Site at, const(void)* data) {
    plant(api, at);
    api.tile(api, &lawn, null, 0);
    api.worldLook(api, &LOOK);
    Turtle tower = Turtle(api, at).columnSite();
    route(tower);
    tower.entrance(SPAWN.x, SPAWN.y, SPAWN.z);
}

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.add(registry, "arbor", &world);
    RisingKind rising = RisingKind(ROOT_SHARE, HorosphereForm.upright, Tag.tree, &tile, null, 0, LOOK);
    registry.addKind(registry, "arbor", &rising);
    registry.addLandmark(registry, "arbor", &landmark);
}
