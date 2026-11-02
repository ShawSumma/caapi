module unit.names;

import base.names : ENUM_NAMES, NameLookup;

enum Kind : ubyte {
    first,
    second,
    third,
}

unittest {
    assert(ENUM_NAMES!Kind[Kind.second] == "second");
    assert(NameLookup!Kind.fromName("third").value == Kind.third);
    assert(!NameLookup!Kind.fromName("fourth").isFound);
}
