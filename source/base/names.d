module base.names;

import base.maybe : Maybe;

immutable string[E.max + 1] ENUM_NAMES(E) = [__traits(allMembers, E)];

immutable(char)* textFor(bool condition, immutable(char)* yes, immutable(char)* no) {
    if (condition) {
        return yes;
    } else {
        return no;
    }
}

Maybe!E enumNamed(E)(const(char)[] name) {
    uint index = 0;
    while (index < ENUM_NAMES!E.length && ENUM_NAMES!E[index] != name) {
        index += 1;
    }
    if (index < ENUM_NAMES!E.length) {
        return Maybe!E.of(cast(E) index);
    } else {
        return Maybe!E.init;
    }
}
