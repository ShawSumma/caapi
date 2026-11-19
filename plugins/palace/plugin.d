module plugins.palace.plugin;

import plugins.api.api : Api, Registry, Risen, Site, SitePart, Turn, dataOf, entryOf;
import plugins.api.content : Content, FIRST_VERSION, Manifest, ON_BASE;
import plugins.palace.palace : DOOR_X, FaceHashes, GROUND, Halls, halls, materials, resolvePalace;
import plugins.turtle.turtle : Turtle, grass, middle;

enum string LOOK = "base:sky";

void lawn(const(Api)* api, Site site, const(Risen)* risen, const(void)* data) {
    Turtle face = Turtle(api, site);
    ulong hash = face.probeHash(SitePart.face);
    if (!dataOf!FaceHashes(data).contains(hash)) {
        grass(face, materials.lawn);
    }
}

void landmark(const(Api)* api, Site site, const(void)* data) {
    halls(Turtle(api, site));
}

void world(const(Api)* api, Site site, const(void)* data) {
    Halls built = halls(Turtle(api, site));
    built.entranceRun.near.turn(Turn.rollLeft).entrance(0, -middle(DOOR_X), GROUND);
    api.tile(api, &lawn, &built.footprint.hashes, FaceHashes.sizeof);
    api.worldLook(api, LOOK);
}

immutable Manifest MANIFEST = Manifest("palace", FIRST_VERSION, ON_BASE[], null, &resolvePalace, null, null, import("plugins/palace/palace.decl"), import("plugins/palace/palace.content"));

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
    registry.addDebug(registry, "palace", &world);
    registry.addLandmark(registry, "palace", &landmark);
}
