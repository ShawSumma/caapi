module base.maybe;

struct Maybe(T) {
    T value;
    bool exists;

    static Maybe of(T found) {
        return Maybe(found, true);
    }
}
