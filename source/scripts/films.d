module scripts.films;

import base.maybe : Maybe;
import base.units : Time;
import client.game : Key;
import client.script : NamedScript, Script, degrees;
import common.character.controller : MovementMode;
import climb = scripts.climb;
import scripts.walk : NOCLIP_SPEED, SETTLE_SECONDS, STRAIGHT_DOWN_DEGREES;

enum Time FILM_STEP = Time(1.0f / 30);
enum float BLOCK_EDGE = 1.0613f;
enum double LEG_SECONDS = 3;
enum double TURN_SECONDS = 1;
enum uint PENTAGON_LEGS = 5;
enum size_t SPIRAL_WAYPOINTS = 40;

struct NamedFilm {
    string name;
    immutable(NamedScript)[] shots;
}

void takeOff(ref Script shot) {
    shot.setTimestep(FILM_STEP);
    shot.mode(MovementMode.noclip);
    shot.look(degrees(90), degrees(0));
    shot.press(0.4f / NOCLIP_SPEED, Key.up);
    shot.roll();
    shot.glide(Key.forward, 2.4f, degrees(-30), degrees(-10), 8);
    shot.glide(Key.up, 1.6f, degrees(40), degrees(55), 8);
    shot.ease(degrees(120), degrees(-40), 5);
}

void cityLap(ref Script shot) {
    shot.structure("city");
    shot.setTimestep(FILM_STEP);
    shot.mode(MovementMode.noclip);
    shot.press(0.08f / NOCLIP_SPEED, Key.up);
    shot.resetCompass();
    shot.roll();
    foreach (_; 0 .. PENTAGON_LEGS) {
        shot.glide(Key.forward, BLOCK_EDGE, degrees(0), degrees(0), LEG_SECONDS);
        shot.ease(degrees(90), degrees(0), TURN_SECONDS);
    }
    shot.wait(2);
}

void spiralClimb(ref Script shot) {
    shot.structure("spiralcity");
    shot.setTimestep(FILM_STEP);
    shot.enterRoute();
    shot.wait(SETTLE_SECONDS);
    shot.roll();
    climb.follow(shot, Maybe!size_t.of(SPIRAL_WAYPOINTS));
}

void lanternPass(ref Script shot) {
    shot.structure("lanterncity");
    shot.setTimestep(FILM_STEP);
    shot.enterRoute();
    shot.mode(MovementMode.noclip);
    shot.press(0.5f / NOCLIP_SPEED, Key.up);
    shot.press(1.1f / NOCLIP_SPEED, Key.back);
    shot.look(degrees(0), degrees(-15));
    shot.roll();
    shot.glide(Key.up, 0.9f, degrees(25), degrees(-40), 9);
}

void backrooms(ref Script shot) {
    shot.structure("backrooms");
    shot.setTimestep(FILM_STEP);
    shot.mode(MovementMode.noclip);
    shot.roll();
    shot.glide(Key.forward, 2.0f, degrees(-40), degrees(0), 8);
    shot.glide(Key.forward, 1.5f, degrees(70), degrees(-5), 6);
}

void library(ref Script shot) {
    shot.structure("library");
    shot.setTimestep(FILM_STEP);
    shot.mode(MovementMode.noclip);
    shot.roll();
    shot.glide(Key.forward, 1.5f, degrees(60), degrees(-5), 8);
    shot.glide(Key.forward, 1.5f, degrees(-90), degrees(5), 8);
}

void lattice(ref Script shot) {
    shot.structure("lattice");
    shot.setTimestep(FILM_STEP);
    shot.mode(MovementMode.noclip);
    shot.roll();
    shot.glide(Key.forward, 3.0f, degrees(120), degrees(-20), 10);
}

void cityFromAbove(ref Script shot) {
    shot.structure("city");
    shot.setTimestep(FILM_STEP);
    shot.mode(MovementMode.noclip);
    shot.look(degrees(0), degrees(-STRAIGHT_DOWN_DEGREES));
    shot.press(0.4f / NOCLIP_SPEED, Key.forward);
    shot.look(degrees(0), degrees(2 * STRAIGHT_DOWN_DEGREES));
    shot.roll();
    shot.glide(Key.back, 2.2f, degrees(90), degrees(0), 10);
}

void pan(ref Script shot) {
    shot.setTimestep(FILM_STEP);
    shot.roll();
    shot.ease(degrees(30), degrees(-10), 1);
}

immutable NamedScript[] TRAILER = [
    NamedScript("trailer/takeoff", &takeOff),
    NamedScript("trailer/citylap", &cityLap),
    NamedScript("trailer/spiral", &spiralClimb),
    NamedScript("trailer/lantern", &lanternPass),
    NamedScript("trailer/backrooms", &backrooms),
    NamedScript("trailer/library", &library),
    NamedScript("trailer/lattice", &lattice),
    NamedScript("trailer/above", &cityFromAbove),
];

immutable NamedScript[] PAN = [
    NamedScript("pan", &pan),
];

immutable NamedFilm[] FILMS = [
    NamedFilm("trailer", TRAILER),
    NamedFilm("pan", PAN),
];
