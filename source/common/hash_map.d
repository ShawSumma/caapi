module common.hash_map;

import core.stdc.stdlib : calloc, free;

enum size_t INITIAL_HASH_MAP_CAPACITY = 16;
enum size_t MIGRATED_SLOTS_PER_INSERT = 8;
enum size_t TEST_KEYS = 100000;
enum size_t TEST_HASH_MULTIPLIER = 0x9E3779B97F4A7C15;

struct HashTable(K, V) {
    K* keys;
    V* values;
    bool* used;
    size_t capacity;
    size_t count;

    void allocate(size_t slots) {
        keys = cast(K*) calloc(slots, K.sizeof);
        values = cast(V*) calloc(slots, V.sizeof);
        used = cast(bool*) calloc(slots, bool.sizeof);
        capacity = slots;
        count = 0;
    }

    size_t slotOf(K key) const {
        size_t mask = capacity - 1;
        size_t index = key.toHash() & mask;
        while (used[index] && !(keys[index] == key)) {
            index = (index + 1) & mask;
        }
        return index;
    }

    inout(V)* find(K key) inout {
        inout(V)* found = null;
        if (capacity > 0) {
            size_t index = slotOf(key);
            if (used[index]) {
                found = &values[index];
            }
        }
        return found;
    }

    void put(K key, V value, bool overwrite) {
        size_t index = slotOf(key);
        if (!used[index]) {
            used[index] = true;
            keys[index] = key;
            values[index] = value;
            count += 1;
        } else if (overwrite) {
            values[index] = value;
        }
    }

    void release() {
        free(keys);
        free(values);
        free(used);
        this = HashTable.init;
    }
}

struct HashMap(K, V) {
    HashTable!(K, V) current;
    HashTable!(K, V) previous;
    size_t migrated;

    inout(V)* find(K key) inout {
        inout(V)* found = current.find(key);
        if (found is null) {
            found = previous.find(key);
        }
        return found;
    }

    void insert(K key, V value) {
        if ((current.count + 1) * 2 > current.capacity) {
            grow();
        }
        current.put(key, value, true);
        migrate(MIGRATED_SLOTS_PER_INSERT);
    }

    void grow() {
        migrate(previous.capacity);
        size_t slots = INITIAL_HASH_MAP_CAPACITY;
        if (current.capacity > 0) {
            slots = current.capacity * 2;
        }
        previous = current;
        current.allocate(slots);
        migrated = 0;
    }

    void migrate(size_t slots) {
        size_t end = migrated + slots;
        if (end > previous.capacity) {
            end = previous.capacity;
        }
        foreach (i; migrated .. end) {
            if (previous.used[i]) {
                current.put(previous.keys[i], previous.values[i], false);
            }
        }
        migrated = end;
        if (previous.capacity > 0 && migrated == previous.capacity) {
            previous.release();
            migrated = 0;
        }
    }

    void release() {
        current.release();
        previous.release();
        migrated = 0;
    }
}

struct TestKey {
    size_t value;

    size_t toHash() const {
        return value * TEST_HASH_MULTIPLIER;
    }
}

unittest {
    HashMap!(TestKey, size_t) map;
    foreach (i; 0 .. TEST_KEYS) {
        map.insert(TestKey(i), i * 2);
        assert(*map.find(TestKey(i / 2)) == (i / 2) * 2);
    }
    foreach (i; 0 .. TEST_KEYS) {
        assert(*map.find(TestKey(i)) == i * 2);
    }
    assert(map.find(TestKey(TEST_KEYS)) is null);
    map.insert(TestKey(3), 7);
    assert(*map.find(TestKey(3)) == 7);
    map.release();
}
