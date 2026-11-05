module base.maybe;

struct Maybe(T) {
    T stored;
    bool exists;

    static Maybe of(T found) {
        return Maybe(found, true);
    }

    ref inout(T) value() inout return {
        assert(exists);
        return stored;
    }
}

struct MaybeIndex(T) {
    T bits;

    static MaybeIndex of(T index) {
        assert(index != T.max);
        return MaybeIndex(cast(T)(index + 1));
    }

    bool exists() const {
        return bits != 0;
    }

    T value() const {
        assert(exists);
        return cast(T)(bits - 1);
    }
}
