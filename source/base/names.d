module base.names;

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

enum TestKind : ubyte {
    first,
    second,
    third,
}

unittest {
    assert(ENUM_NAMES!TestKind[TestKind.second] == "second");
    assert(NameLookup!TestKind.fromName("third").value == TestKind.third);
    assert(!NameLookup!TestKind.fromName("fourth").isFound);
}
