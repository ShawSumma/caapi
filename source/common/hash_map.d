module common.hash_map;

import core.stdc.stdlib : calloc, free;
import core.stdc.string : memset;

enum ubyte SLOT_EMPTY = 0;
enum ubyte SLOT_FILLED = 1;

// Open addressing with linear probing and backward-shift deletion, so there
// are no tombstones to accumulate and a load factor that stays honest. Growth
// doubles at 3/4 full. Capacity is always a power of two so the modulo is a
// mask.
struct HashMap(K, V) {
    K* keys;
    V* values;
    ubyte* states;
    size_t count;
    size_t capacity;
    size_t mask;

    static HashMap!(K, V) withCapacity(size_t initial) {
        HashMap!(K, V) result;
        size_t wanted = 8;
        while (wanted * 4 < initial * 5) {
            wanted = wanted * 2;
        }
        result.allocate(wanted);
        return result;
    }

    void allocate(size_t newCapacity) {
        keys = cast(K*) calloc(newCapacity, K.sizeof);
        values = cast(V*) calloc(newCapacity, V.sizeof);
        states = cast(ubyte*) calloc(newCapacity, ubyte.sizeof);
        assert(keys !is null, "HashMap allocation failed");
        assert(values !is null, "HashMap allocation failed");
        assert(states !is null, "HashMap allocation failed");
        capacity = newCapacity;
        mask = newCapacity - 1;
        count = 0;
    }

    void release() {
        if (keys !is null) {
            free(keys);
        }
        if (values !is null) {
            free(values);
        }
        if (states !is null) {
            free(states);
        }
        keys = null;
        values = null;
        states = null;
        count = 0;
        capacity = 0;
        mask = 0;
    }

    size_t slotFor(K key) const {
        ulong h;
        static if (__traits(hasMember, K, "toHash")) {
            h = key.toHash();
        } else static if (__traits(isIntegral, K)) {
            h = cast(ulong) key;
        } else {
            h = 0xCBF29CE484222325;
            const(ubyte)* bytes = cast(const(ubyte)*) &key;
            foreach (i; 0 .. K.sizeof) {
                h = h ^ bytes[i];
                h = h * 0x100000001B3;
            }
        }
        h = h ^ (h >> 32);
        h = h * 0xD6E8FEB86659FD93;
        h = h ^ (h >> 32);
        return cast(size_t)(h & mask);
    }

    size_t findSlot(K key) const {
        if (capacity == 0) {
            return 0;
        }
        size_t slot = slotFor(key);
        while (states[slot] == SLOT_FILLED) {
            if (keys[slot] == key) {
                return slot;
            }
            slot = (slot + 1) & mask;
        }
        return capacity;
    }

    bool contains(K key) const {
        return findSlot(key) != capacity;
    }

    V* opBinaryRight(string op : "in")(K key) {
        size_t slot = findSlot(key);
        if (slot == capacity) {
            return null;
        }
        return &values[slot];
    }

    void grow() {
        K* oldKeys = keys;
        V* oldValues = values;
        ubyte* oldStates = states;
        size_t oldCapacity = capacity;

        size_t doubled = capacity * 2;
        if (doubled == 0) {
            doubled = 8;
        }
        allocate(doubled);

        foreach (i; 0 .. oldCapacity) {
            if (oldStates[i] == SLOT_FILLED) {
                insert(oldKeys[i], oldValues[i]);
            }
        }

        if (oldKeys !is null) {
            free(oldKeys);
            free(oldValues);
            free(oldStates);
        }
    }

    void insert(K key, V value) {
        if (capacity == 0) {
            allocate(8);
        }
        if ((count + 1) * 4 >= capacity * 3) {
            grow();
        }
        size_t slot = slotFor(key);
        while (states[slot] == SLOT_FILLED) {
            if (keys[slot] == key) {
                values[slot] = value;
                return;
            }
            slot = (slot + 1) & mask;
        }
        keys[slot] = key;
        values[slot] = value;
        states[slot] = SLOT_FILLED;
        count = count + 1;
    }

    // Returns the existing value for `key`, inserting `fallback` first if the
    // key is absent. The pointer is invalidated by any later insert.
    V* require(K key, V fallback) {
        V* existing = key in this;
        if (existing !is null) {
            return existing;
        }
        insert(key, fallback);
        return key in this;
    }

    bool remove(K key) {
        size_t hole = findSlot(key);
        if (hole == capacity) {
            return false;
        }
        size_t cur = hole;
        while (true) {
            cur = (cur + 1) & mask;
            if (states[cur] == SLOT_EMPTY) {
                break;
            }
            size_t ideal = slotFor(keys[cur]);
            size_t fromIdeal = (cur - ideal) & mask;
            size_t fromHole = (cur - hole) & mask;
            if (fromIdeal >= fromHole) {
                keys[hole] = keys[cur];
                values[hole] = values[cur];
                states[hole] = SLOT_FILLED;
                hole = cur;
            }
        }
        states[hole] = SLOT_EMPTY;
        count = count - 1;
        return true;
    }

    void clear() {
        if (states !is null) {
            memset(states, SLOT_EMPTY, capacity);
        }
        count = 0;
    }

    size_t length() const {
        return count;
    }

    bool empty() const {
        return count == 0;
    }

    int opApply(scope int delegate(ref K, ref V) dg) {
        foreach (i; 0 .. capacity) {
            if (states[i] != SLOT_FILLED) {
                continue;
            }
            int stop = dg(keys[i], values[i]);
            if (stop != 0) {
                return stop;
            }
        }
        return 0;
    }
}

unittest {
    HashMap!(ulong, int) m;
    foreach (i; 0 .. 1000) {
        m.insert(cast(ulong) i, cast(int)(i * 3));
    }
    assert(m.length() == 1000);
    foreach (i; 0 .. 1000) {
        int* v = cast(ulong) i in m;
        assert(v !is null);
        assert(*v == cast(int)(i * 3));
    }

    // Removing every other key must leave the probe chains of the survivors
    // intact, which is the property backward-shift deletion buys over
    // tombstones.
    foreach (i; 0 .. 1000) {
        if (i % 2 == 0) {
            assert(m.remove(cast(ulong) i));
        }
    }
    assert(m.length() == 500);
    foreach (i; 0 .. 1000) {
        int* v = cast(ulong) i in m;
        if (i % 2 == 0) {
            assert(v is null);
        } else {
            assert(v !is null);
            assert(*v == cast(int)(i * 3));
        }
    }

    assert(!m.remove(4));

    int* req = m.require(4, 77);
    assert(*req == 77);
    assert(m.length() == 501);
    req = m.require(4, 99);
    assert(*req == 77);

    size_t seen = 0;
    foreach (ref k, ref v; m) {
        seen = seen + 1;
    }
    assert(seen == 501);

    m.clear();
    assert(m.empty());
    m.release();
}
