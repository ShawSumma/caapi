module common.names;

import common.material : Material;

immutable string[E.max + 1] ENUM_NAMES(E) = [__traits(allMembers, E)];

struct NameLookup(E) {
    E value;
    bool isFound;

    static NameLookup fromName(const(char)[] name) {
        uint index = 0;
        while (index < ENUM_NAMES!E.length && ENUM_NAMES!E[index] != name) {
            index += 1;
        }
        if (index < ENUM_NAMES!E.length) {
            return NameLookup(cast(E) index, true);
        } else {
            return NameLookup(E.init, false);
        }
    }
}

unittest {
    assert(ENUM_NAMES!Material[Material.oakWood] == "oakWood");
    assert(NameLookup!Material.fromName("glass").value == Material.glass);
    assert(!NameLookup!Material.fromName("goo").isFound);
}
