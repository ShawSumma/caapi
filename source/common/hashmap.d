module common.hashmap;

import core.stdc.stdlib : calloc, free;

enum size_t INITIAL_HASH_MAP_CAPACITY = 16;
enum size_t MIGRATED_SLOTS_PER_INSERT = 8;
enum size_t TEST_KEYS = 100000;
enum size_t TEST_HASH_MULTIPLIER = 0x9E3779B97F4A7C15;

struct HashEntry(K, V) {
    K key;
    V value;
    bool isUsed;
}

struct HashTable(K, V) {
    HashEntry!(K, V)* entries;
    size_t capacity;
    size_t count;

    void allocate(size_t slots) {
        entries = cast(HashEntry!(K, V)*) calloc(slots, HashEntry!(K, V).sizeof);
        capacity = slots;
        count = 0;
    }

    size_t slotOf(K key) const {
        size_t mask = capacity - 1;
        size_t index = key.toHash() & mask;
        while (entries[index].isUsed && !(entries[index].key == key)) {
            index = (index + 1) & mask;
        }
        return index;
    }

    inout(V)* find(K key) inout {
        if (capacity == 0) {
            return null;
        } else {
            inout(HashEntry!(K, V))* entry = &entries[slotOf(key)];
            if (entry.isUsed) {
                return &entry.value;
            } else {
                return null;
            }
        }
    }

    void assign(K key, V value) {
        HashEntry!(K, V)* entry = &entries[slotOf(key)];
        if (entry.isUsed) {
            entry.value = value;
        } else {
            *entry = HashEntry!(K, V)(key, value, true);
            count += 1;
        }
    }

    void assignIfMissing(K key, V value) {
        HashEntry!(K, V)* entry = &entries[slotOf(key)];
        if (!entry.isUsed) {
            *entry = HashEntry!(K, V)(key, value, true);
            count += 1;
        }
    }

    void release() {
        free(entries);
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
            return previous.find(key);
        } else {
            return found;
        }
    }

    void insert(K key, V value) {
        if ((current.count + 1) * 2 > current.capacity) {
            grow();
        }
        current.assign(key, value);
        migrate(MIGRATED_SLOTS_PER_INSERT);
    }

    void grow() {
        migrate(previous.capacity);
        previous = current;
        if (previous.capacity == 0) {
            current.allocate(INITIAL_HASH_MAP_CAPACITY);
        } else {
            current.allocate(previous.capacity * 2);
        }
        migrated = 0;
    }

    void migrate(size_t slots) {
        size_t end = migrated + slots;
        if (end > previous.capacity) {
            end = previous.capacity;
        }
        foreach (i; migrated .. end) {
            if (previous.entries[i].isUsed) {
                current.assignIfMissing(previous.entries[i].key, previous.entries[i].value);
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

void keepWhere(alias isKept, K, V, C)(ref HashMap!(K, V) map, ref C context) {
    size_t capacity = INITIAL_HASH_MAP_CAPACITY;
    while (capacity < (map.current.count + map.previous.count) * 2) {
        capacity *= 2;
    }
    HashMap!(K, V) kept;
    kept.current.allocate(capacity);
    insertKept!isKept(kept.current, map.current, context);
    insertKept!isKept(kept.current, map.previous, context);
    map.release();
    map = kept;
}

void insertKept(alias isKept, K, V, C)(ref HashTable!(K, V) kept, ref const HashTable!(K, V) table, ref C context) {
    foreach (entry; table.entries[0 .. table.capacity]) {
        if (entry.isUsed && isKept(context, entry.key, entry.value)) {
            kept.assignIfMissing(entry.key, entry.value);
        }
    }
}

void visitEntries(alias visit, K, V, C)(ref const HashMap!(K, V) map, ref C context) {
    foreach (entry; map.current.entries[0 .. map.current.capacity]) {
        if (entry.isUsed) {
            visit(context, entry.key, entry.value);
        }
    }
    foreach (entry; map.previous.entries[0 .. map.previous.capacity]) {
        if (entry.isUsed && map.current.find(entry.key) is null) {
            visit(context, entry.key, entry.value);
        }
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
    size_t divisor = 3;
    keepWhere!((ref size_t every, TestKey key, size_t value) => key.value % every == 0)(map, divisor);
    foreach (i; 0 .. TEST_KEYS) {
        assert((map.find(TestKey(i)) !is null) == (i % divisor == 0));
    }
    assert(*map.find(TestKey(3)) == 7);
    size_t visited = 0;
    visitEntries!((ref size_t count, TestKey key, size_t value) { count += 1; })(map, visited);
    assert(visited == (TEST_KEYS + divisor - 1) / divisor);
    map.release();
}
