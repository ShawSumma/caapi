module plugins.caves.plugin;

import plugins.api.api : Api, HorosphereForm, KindId, KindTag, Registry, Risen, Site, SitePart, Span, entryOf, tagNamed;
import plugins.api.content : FIRST_VERSION, Manifest, ON_BASE;
import plugins.caves.caves : Entry, LOOK, NAME, Root, WellShape, enter, entryNear, flightStops, materials, resolveCaves, route, tile, tuning, underlie;
import plugins.turtle.turtle : Found, Turtle, boxOf, ownerAround;

enum uint CAVE_TAG = tagNamed("caves:caves");
enum uint WELL_RIG_TAG = tagNamed("caves:well-rig");
enum int WELL_RIG_EDGES = 3;
enum Span INLAY_ACROSS = Span(-2, 1);
enum Span INLAY_HEIGHTS = Span(-3, 3);
enum Span MAST_ACROSS = Span(0, 3);
enum double MAST_REACH = 6;
enum int MAST_EDGES = 4;
enum int VERTEX_MARK_CELLS = 4;

void world(const(Api)* api, Site site, const(void)* data) {
    KindId kind = api.horosphere(api, 0, HorosphereForm.terrain, CAVE_TAG, null, null, 0);
    api.rooted(api, kind);
    api.look(api, kind, LOOK);
    api.worldLook(api, LOOK);
    api.fog(api, tuning.fog);
    Root root;
    Entry entry = entryNear(Turtle(api, site), root.blocked);
    if (entry.found == Found.none) {
        api.fail(api, "no sinkhole near the root opens into a branching cave");
    } else {
        root.spawn = entry.surface.frame.probeHash(SitePart.vertex);
        api.tileEdges(api, &tile, &root, Root.sizeof);
        api.flatten(api, entry.surface.frame.site);
        route(entry);
        enter(entry);
    }
}

void underground(const(Api)* api, Site site, const(void)* data) {
    underlie(api);
}

bool everyVertex(const(Api)* api, Site vertex, double rolled, const(void)* data) {
    return true;
}

void everyPort(const(Api)* api, Site site, const(void)* data) {
    underlie(api);
    api.portRule(api, KindTag.init, 1, &everyVertex, null, 0);
}

bool facedVertex(const(Api)* api, Site vertex, double rolled, const(void)* data) {
    return ownerAround(Turtle(api, vertex)).probeHash(SitePart.face) % 2 == 0;
}

void facedPort(const(Api)* api, Site site, const(void)* data) {
    underlie(api);
    api.portRule(api, KindTag.init, 1, &facedVertex, null, 0);
}

bool rolledVertex(const(Api)* api, Site vertex, double rolled, const(void)* data) {
    return api.pick(api, 2) == 0;
}

void rolledPort(const(Api)* api, Site site, const(void)* data) {
    underlie(api);
    api.portRule(api, KindTag.init, 1, &rolledVertex, null, 0);
}

void wellStair(const(Api)* api, Site site, const(void)* data) {
    KindId kind = api.horosphere(api, 0, HorosphereForm.solid, WELL_RIG_TAG, null, null, 0);
    api.rooted(api, kind);
    underlie(api);
    api.portRule(api, KindTag.of(WELL_RIG_TAG), 1, &everyVertex, null, 0);
    flightStops(Turtle(api, site).forward(1).pitchDown(), WellShape.spiral, WELL_RIG_EDGES);
}

void inlay(const(Api)* api, Site site, const(void)* data) {
    Turtle(api, site).pitchUp().replace(materials.stair, boxOf(INLAY_ACROSS, INLAY_ACROSS, INLAY_HEIGHTS));
}

void mast(const(Api)* api, Site face, const(Risen)* risen, const(void)* data) {
    Turtle(api, face).pitchUp().paint(materials.stair, boxOf(MAST_ACROSS, MAST_ACROSS, Span(0, MAST_EDGES * api.edgeCells(api))));
}

void markStair(const(Api)* api, Site site, const(Risen)* risen, const(void)* data) {
    Turtle(api, site).paint(materials.stair, boxOf(Span(0, 0), Span(0, 0), Span(0, 0)));
}

void markLining(const(Api)* api, Site site, const(Risen)* risen, const(void)* data) {
    Turtle(api, site).paint(materials.lining, boxOf(Span(1, 1), Span(0, 0), Span(0, 0)));
}

void twoEdges(const(Api)* api, Site site, const(void)* data) {
    api.tileEdges(api, &markStair, null, 0);
    api.tileEdges(api, &markLining, null, 0);
}

void markVertex(const(Api)* api, Site vertex, const(Risen)* risen, const(void)* data) {
    Turtle(api, vertex).pitchUp().paint(materials.stair, boxOf(Span(0, 0), Span(0, 0), Span(0, VERTEX_MARK_CELLS - 1)));
}

void vertexMarks(const(Api)* api, Site site, const(void)* data) {
    api.tileVertices(api, &markVertex, null, 0);
}

void overreach(const(Api)* api, Site site, const(void)* data) {
    api.tile(api, &mast, null, 0);
    api.tileReach(api, KindTag.init, MAST_REACH, 0);
}

immutable Manifest MANIFEST = Manifest(NAME, FIRST_VERSION, ON_BASE[], null, &resolveCaves, null, import("plugins/caves/settings.conf"), import("plugins/caves/caves.decl"), import("plugins/caves/caves.content"));

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
    registry.add(registry, "caves", &world);
    registry.addDebug(registry, "underground", &underground);
    registry.addDebug(registry, "inlay", &inlay);
    registry.addDebug(registry, "wellstair", &wellStair);
    registry.addDebug(registry, "everyport", &everyPort);
    registry.addDebug(registry, "rolledport", &rolledPort);
    registry.addDebug(registry, "facedport", &facedPort);
    registry.addDebug(registry, "overreach", &overreach);
    registry.addDebug(registry, "twoedges", &twoEdges);
    registry.addDebug(registry, "vertexmarks", &vertexMarks);
}
