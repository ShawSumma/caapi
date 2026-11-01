module scripts.views;

import base.units : Length;
import client.game : Key, RouteWaypoint;
import client.script : NamedScript, Script, degrees;
import common.character.controller : MovementMode;
import climb = scripts.climb;
import walk = scripts.walk;
import scripts.walk : FLY_SPEED, NOCLIP_SPEED, SETTLE_SECONDS, STRAIGHT_DOWN_DEGREES;

immutable NamedScript[] VIEWS = [
    NamedScript("arborcrown", &rising!("arbor", 0.9f, 1.6f, 30)),
    NamedScript("arbor", &backedOut!("arbor", 0.6f, -35)),
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
    NamedScript("crowntops", &rising!("crown", 1.45f, 0.45f, -35)),
    NamedScript("cubes", &cubes),
    NamedScript("far", &far),
    NamedScript("flight", &flight),
    NamedScript("hamlet", &rising!("hamlet", 0, 0.5f, 20)),
    NamedScript("interior", &towardWaypoint!("tower", 6, -10)),
    NamedScript("landscape", &landscape),
    NamedScript("latticebelow", &rising!("lattice", 0, 0.6f, 50)),
    NamedScript("lattice", &looking!("lattice", 0, -10)),
    NamedScript("library", &looking!("library", 0, -5)),
    NamedScript("libraryroof", &rising!("library", 0, 1.9f, 60)),
    NamedScript("libraryturn", &looking!("library", 100, -10)),
    NamedScript("palaceinside", &rising!("palace", 1.3f, 0, 25)),
    NamedScript("palace", &looking!("palace", 0, -10)),
    NamedScript("palacestair", &towardWaypoint!("palace", 6, -15)),
    NamedScript("risencity", &routeEnd!("risencity", climb.EVERY_WAYPOINT, -20)),
    NamedScript("risencross", &routeEnd!("risencity", 24, -70)),
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
    NamedScript("stairs", &towardWaypoint!("tower", 3, -20)),
    NamedScript("terrain", &lookingHere!(10)),
    NamedScript("tower", &tower),
    NamedScript("trail", &trail),
    NamedScript("treebase", &lookingHere!(-10)),
    NamedScript("trees", &trees),
    NamedScript("treetop", &treetop),
    NamedScript("wild", &routeEnd!("risenwild", climb.EVERY_WAYPOINT, -10)),
    NamedScript("zenith", &zenith),
];

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

void rising(string name, float ahead, float rise, double pitch)(ref Script view) {
    view.structure(name);
    view.mode(MovementMode.noclip);
    if (ahead > 0) {
        noclip(view, ahead, Key.fwd);
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
    view.look(view.routeWaypoint(number).yaw, degrees(pitch));
    view.step();
}

void followRoute(ref Script view, size_t last) {
    view.enterRoute();
    view.wait(SETTLE_SECONDS);
    climb.follow(view, last);
    view.wait(SETTLE_SECONDS);
}

void routeEnd(string name, size_t last, double pitch)(ref Script view) {
    view.structure(name);
    followRoute(view, last);
    view.look(degrees(0), degrees(pitch));
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

void arch(ref Script view) {
    view.structure("crown");
    view.enterRoute();
    climb.follow(view, 45);
    view.look(view.routeWaypoint(50).yaw, degrees(-15));
    view.step();
}

void backroomsDeep(ref Script view) {
    view.structure("risenbackrooms");
    followRoute(view, climb.EVERY_WAYPOINT);
    view.look(degrees(40), degrees(0));
    view.press(5, Key.fwd);
    view.press(1, Key.back);
    view.look(degrees(-60), degrees(0));
    view.step();
}

void backrooms(ref Script view) {
    view.structure("risenbackrooms");
    followRoute(view, climb.EVERY_WAYPOINT);
    view.press(1.5, Key.fwd);
    view.look(degrees(180), degrees(0));
    view.step();
}

void backroomsTop(ref Script view) {
    view.structure("risenbackrooms");
    followRoute(view, climb.EVERY_WAYPOINT);
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
    noclip(view, 2.0f, Key.fwd);
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
    view.press(10.0f / FLY_SPEED, Key.fwd);
    view.look(degrees(0), degrees(60));
    view.step();
}

void flight(ref Script view) {
    view.live();
    view.look(degrees(180), degrees(0));
    view.mode(MovementMode.fly);
    view.press(3, Key.up);
    view.press(8, Key.fwd);
    view.step();
}

void landscape(ref Script view) {
    view.mode(MovementMode.noclip);
    noclip(view, 2.0f, Key.fwd);
    view.look(degrees(0), degrees(-STRAIGHT_DOWN_DEGREES));
    noclip(view, 0.7f, Key.fwd);
    view.look(degrees(0), degrees(STRAIGHT_DOWN_DEGREES + 25));
    view.step();
}

void risings(float distance)(ref Script view) {
    view.mode(MovementMode.noclip);
    view.look(degrees(90), degrees(0));
    noclip(view, distance, Key.fwd);
    view.look(degrees(0), degrees(-30));
    view.step();
}

void roadAerial(ref Script view) {
    enum float edge = 1.0613f;
    enum uint vertex = 6;
    view.terrain();
    view.mode(MovementMode.noclip);
    view.enterRoute();
    view.look(view.routeWaypoint(5).yaw, degrees(0));
    noclip(view, vertex * edge, Key.fwd);
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
    view.look(view.routeWaypoint(5).yaw, degrees(25));
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
    noclip(view, 2.5f, Key.fwd);
    view.look(degrees(0), degrees(STRAIGHT_DOWN_DEGREES + 70));
    view.step();
}

void slope(ref Script view) {
    view.plane(degrees(40));
    view.press(3, Key.fwd);
    view.look(degrees(60), degrees(0));
    view.step();
}

void tower(ref Script view) {
    view.structure("tower");
    view.mode(MovementMode.noclip);
    view.enterStructure(Length(2));
    noclip(view, 0.75f, Key.fwd);
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
    view.press(5, Key.fwd);
    view.look(degrees(0), degrees(20));
    view.step();
}

void treetop(ref Script view) {
    view.terrain();
    view.mode(MovementMode.noclip);
    noclip(view, 1.2f, Key.fwd);
    view.look(degrees(0), degrees(-75));
    view.step();
}

void zenith(ref Script view) {
    view.mode(MovementMode.noclip);
    view.look(degrees(90), degrees(0));
    noclip(view, 3.0f, Key.fwd);
    view.look(degrees(0), degrees(-STRAIGHT_DOWN_DEGREES));
    view.step();
}
