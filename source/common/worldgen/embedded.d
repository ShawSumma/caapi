module common.worldgen.embedded;

enum string LUA_SUFFIX = ".lua";

struct EmbeddedLua {
    string name;
    string source;
}

immutable EmbeddedLua[8] EMBEDDED_STRUCTURES = [
    EmbeddedLua("tower", import("tower.lua")),
    EmbeddedLua("crown", import("crown.lua")),
    EmbeddedLua("road", import("road.lua")),
    EmbeddedLua("trail", import("trail.lua")),
    EmbeddedLua("city", import("city.lua")),
    EmbeddedLua("planet", import("planet.lua")),
    EmbeddedLua("bigtree", import("bigtree.lua")),
    EmbeddedLua("backrooms", import("backrooms.lua")),
];

immutable EmbeddedLua[19] EMBEDDED_MODULES = [
    EmbeddedLua("connector", import("connector.lua")),
    EmbeddedLua("tower.box", import("tower/box.lua")),
    EmbeddedLua("city.blocks", import("city/blocks.lua")),
    EmbeddedLua("skies.wild", import("skies/wild.lua")),
    EmbeddedLua("skies.city", import("skies/city.lua")),
    EmbeddedLua("skies.spires", import("skies/spires.lua")),
    EmbeddedLua("skies.backrooms", import("skies/backrooms.lua")),
    EmbeddedLua("backrooms.layout", import("backrooms/layout.lua")),
    EmbeddedLua("backrooms.rooms", import("backrooms/rooms.lua")),
    EmbeddedLua("backrooms.levels", import("backrooms/levels.lua")),
    EmbeddedLua("buildings.building", import("buildings/building.lua")),
    EmbeddedLua("buildings.brownstone", import("buildings/brownstone.lua")),
    EmbeddedLua("buildings.tenement", import("buildings/tenement.lua")),
    EmbeddedLua("buildings.deco", import("buildings/deco.lua")),
    EmbeddedLua("buildings.glass", import("buildings/glass.lua")),
    EmbeddedLua("buildings.rowhouse", import("buildings/rowhouse.lua")),
    EmbeddedLua("buildings.warehouse", import("buildings/warehouse.lua")),
    EmbeddedLua("buildings.modern", import("buildings/modern.lua")),
    EmbeddedLua("buildings.civic", import("buildings/civic.lua")),
];

immutable string[EMBEDDED_STRUCTURES.length] EMBEDDED_STRUCTURE_NAMES = namesOf(EMBEDDED_STRUCTURES);

string[EMBEDDED_STRUCTURES.length] namesOf(immutable EmbeddedLua[EMBEDDED_STRUCTURES.length] structures) {
    string[EMBEDDED_STRUCTURES.length] names;
    foreach (index, structure; structures) {
        names[index] = structure.name;
    }
    return names;
}

bool isLuaPath(const(char)[] name) {
    return name.length > LUA_SUFFIX.length && name[$ - LUA_SUFFIX.length .. $] == LUA_SUFFIX;
}

uint embeddedIndex(const(char)[] name) {
    uint index = 0;
    while (index < EMBEDDED_STRUCTURES.length && EMBEDDED_STRUCTURES[index].name != name) {
        index += 1;
    }
    return index;
}
