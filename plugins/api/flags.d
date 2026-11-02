module plugins.api.flags;

struct Flags(E) {
    static if (E.max < 8) {
        alias Word = ubyte;
    } else static if (E.max < 16) {
        alias Word = ushort;
    } else {
        static assert(E.max < 32);
        alias Word = uint;
    }

    Word bits;

    static Flags of(E flag) {
        return Flags(cast(Word)(1u << flag));
    }

    bool has(E flag) const {
        return (bits & (1u << flag)) != 0;
    }

    void set(E flag) {
        bits |= cast(Word)(1u << flag);
    }

    void clear(E flag) {
        bits &= cast(Word) ~(1u << flag);
    }

    void put(E flag, bool on) {
        if (on) {
            set(flag);
        } else {
            clear(flag);
        }
    }
}
