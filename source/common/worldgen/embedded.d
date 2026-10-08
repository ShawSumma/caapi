module common.worldgen.embedded;

enum string LUA_SUFFIX = ".lua";

struct EmbeddedLua {
    string name;
    string source;
}

immutable EmbeddedLua[4] EMBEDDED_STRUCTURES = [
    EmbeddedLua("tower", import("tower.lua")),
    EmbeddedLua("crown", import("crown.lua")),
    EmbeddedLua("road", import("road.lua")),
    EmbeddedLua("trail", import("trail.lua")),
];

immutable EmbeddedLua[1] EMBEDDED_MODULES = [
    EmbeddedLua("box", import("box.lua")),
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
