module unit.names;

import base.names : ENUM_NAMES, enumNamed;

enum Kind : ubyte {
    first,
    second,
    third,
}

unittest {
    assert(ENUM_NAMES!Kind[Kind.second] == "second");
    assert(enumNamed!Kind("third").value == Kind.third);
    assert(!enumNamed!Kind("fourth").exists);
}
