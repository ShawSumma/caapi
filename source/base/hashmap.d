module base.hashmap;

import core.bitop : bsr;
import core.stdc.stdlib : calloc, free, malloc;
import core.stdc.string : memset;
import base.numbers : lowerOf;
import base.pages : giveBack;

enum size_t FIBONACCI_MULTIPLIER = 0x9E3779B97F4A7C15;
enum size_t INITIAL_HASH_MAP_CAPACITY = 16;
enum size_t MIGRATED_SLOTS_PER_CHANGE = 8;
enum size_t RELEASED_BYTES = 1 << 20;
enum size_t FULLEST_EIGHTHS = 6;
enum size_t EMPTIEST_EIGHTHS = 1;
enum size_t EIGHTHS = 8;
enum uint TAG_BITS = 7;
enum ubyte EMPTY = 0;
enum ubyte REMOVED = 1;
enum ubyte LIVE = 0x80;
enum size_t TEST_KEYS = 100000;
enum size_t TEST_KEPT = 3;
enum size_t TEST_RANGE = 4096;
enum size_t TEST_STEPS = 2_000_000;
enum size_t TEST_SWING = 200_000;

struct HashSlot(K, V) {
    K key;
    V value;
}

struct HashTable(K, V) {
    ubyte* controls;
    HashSlot!(K, V)* slots;
    size_t capacity;
    size_t used;
    size_t released;
    uint shift;

    void allocate(size_t count) {
        controls = cast(ubyte*) calloc(count, 1);
        slots = cast(HashSlot!(K, V)*) malloc(count * HashSlot!(K, V).sizeof);
        capacity = count;
        used = 0;
        released = 0;
        shift = cast(uint)(size_t.sizeof * 8 - bsr(count));
    }

    static size_t hashOf(K key) {
        return key.toHash() * FIBONACCI_MULTIPLIER;
    }

    ubyte tagOf(size_t hash) const {
        return cast(ubyte)(LIVE | ((hash >> (shift - TAG_BITS)) & (LIVE - 1)));
    }

    size_t homeOf(K key) const {
        return hashOf(key) >> shift;
    }

    size_t probe(K key, size_t hash) const {
        size_t mask = capacity - 1;
        ubyte tag = tagOf(hash);
        size_t index = hash >> shift;
        while (controls[index] != EMPTY && !(controls[index] == tag && slots[index].key == key)) {
            index = (index + 1) & mask;
        }
        return index;
    }

    inout(V)* find(K key) inout {
        if (capacity == 0) {
            return null;
        } else {
            size_t index = probe(key, hashOf(key));
            if (controls[index] == EMPTY) {
                return null;
            } else {
                return &slots[index].value;
            }
        }
    }

    void assign(K key, V value, bool isKept) {
        size_t hash = hashOf(key);
        size_t index = probe(key, hash);
        if (controls[index] == EMPTY) {
            controls[index] = tagOf(hash);
            slots[index] = HashSlot!(K, V)(key, value);
            used += 1;
        } else if (!isKept) {
            slots[index].value = value;
        }
    }

    void erase(K key) {
        if (capacity > 0) {
            size_t mask = capacity - 1;
            size_t hole = probe(key, hashOf(key));
            if (controls[hole] != EMPTY) {
                size_t next = (hole + 1) & mask;
                while (controls[next] != EMPTY) {
                    if (((next - homeOf(slots[next].key)) & mask) >= ((next - hole) & mask)) {
                        controls[hole] = controls[next];
                        slots[hole] = slots[next];
                        hole = next;
                    }
                    next = (next + 1) & mask;
                }
                controls[hole] = EMPTY;
                used -= 1;
            }
        }
    }

    void bury(K key) {
        if (capacity > 0) {
            size_t index = probe(key, hashOf(key));
            if (controls[index] != EMPTY) {
                controls[index] = REMOVED;
            }
        }
    }

    void releaseBefore(size_t cursor) {
        if ((cursor - released) * HashSlot!(K, V).sizeof >= RELEASED_BYTES) {
            size_t edge = cursor;
            while (edge > released && controls[edge - 1] != EMPTY) {
                edge -= 1;
            }
            giveBack(slots, released * HashSlot!(K, V).sizeof, edge * HashSlot!(K, V).sizeof);
            giveBack(controls, released, edge);
            released = edge;
        }
    }

    void clear() {
        if (capacity > 0) {
            memset(controls, EMPTY, capacity);
        }
        used = 0;
    }

    void release() {
        free(controls);
        free(slots);
        this = HashTable.init;
    }
}

struct HashMap(K, V) {
    HashTable!(K, V) current;
    HashTable!(K, V) previous;
    size_t migrated;

    inout(V)* find(K key) inout {
        inout(V)* found = current.find(key);
        if (found !is null) {
            return found;
        } else {
            return previous.find(key);
        }
    }

    void insert(K key, V value) {
        if (current.capacity == 0) {
            resize(INITIAL_HASH_MAP_CAPACITY);
        } else if ((current.used + 1) * EIGHTHS > current.capacity * FULLEST_EIGHTHS) {
            resize(current.capacity * 2);
        }
        current.assign(key, value, false);
        migrate(MIGRATED_SLOTS_PER_CHANGE);
    }

    void remove(K key) {
        current.erase(key);
        previous.bury(key);
        migrate(MIGRATED_SLOTS_PER_CHANGE);
        shrinkIfSparse();
    }

    pragma(inline, false) void shrinkIfSparse() {
        if (previous.capacity == 0 && current.capacity > INITIAL_HASH_MAP_CAPACITY && current.used * EIGHTHS < current.capacity * EMPTIEST_EIGHTHS) {
            resize(current.capacity / 2);
        }
    }

    void clear() {
        current.clear();
        previous.release();
        migrated = 0;
    }

    void resize(size_t capacity) {
        migrate(previous.capacity);
        previous = current;
        current.allocate(capacity);
        migrated = 0;
    }

    void migrate(size_t count) {
        size_t end = lowerOf(migrated + count, previous.capacity);
        foreach (index; migrated .. end) {
            if ((previous.controls[index] & LIVE) != 0) {
                current.assign(previous.slots[index].key, previous.slots[index].value, true);
            }
        }
        migrated = end;
        if (previous.capacity > 0 && migrated == previous.capacity) {
            previous.release();
            migrated = 0;
        } else {
            previous.releaseBefore(migrated);
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
        return value;
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
    size_t capacity = map.current.capacity;
    map.clear();
    assert(map.find(TestKey(3)) is null && map.current.capacity == capacity);
    map.insert(TestKey(3), 1);
    assert(*map.find(TestKey(3)) == 1);
    map.release();
    HashMap!(TestKey, size_t) churn;
    foreach (i; 0 .. TEST_KEYS) {
        churn.insert(TestKey(i), i);
        if (i >= TEST_KEPT) {
            churn.remove(TestKey(i - TEST_KEPT));
            assert(churn.find(TestKey(i - TEST_KEPT)) is null);
        }
        assert(*churn.find(TestKey(i)) == i);
    }
    assert(churn.current.capacity < TEST_KEYS);
    churn.remove(TestKey(TEST_KEYS - 1));
    churn.insert(TestKey(TEST_KEYS - 1), 1);
    assert(*churn.find(TestKey(TEST_KEYS - 1)) == 1);
    churn.release();
    HashMap!(TestKey, size_t) emptied;
    foreach (i; 0 .. TEST_KEYS) {
        emptied.insert(TestKey(i * FIBONACCI_MULTIPLIER), i);
    }
    foreach (i; TEST_KEPT .. TEST_KEYS) {
        emptied.remove(TestKey(i * FIBONACCI_MULTIPLIER));
    }
    foreach (i; 0 .. TEST_KEYS) {
        size_t* found = emptied.find(TestKey(i * FIBONACCI_MULTIPLIER));
        if (i < TEST_KEPT) {
            assert(found !is null && *found == i);
        } else {
            assert(found is null);
        }
    }
    emptied.release();
}

unittest {
    HashMap!(TestKey, size_t) map;
    bool[TEST_RANGE] isPresent;
    ulong state = 1;
    foreach (step; 0 .. TEST_STEPS) {
        state = state * 6364136223846793005UL + 1442695040888963407UL;
        size_t key = (state >> 33) % TEST_RANGE;
        bool isFilling = (step / TEST_SWING) % 2 == 0;
        bool isInserting = isFilling;
        if ((state >> 20) % 4 == 0) {
            isInserting = !isFilling;
        }
        if (isInserting) {
            map.insert(TestKey(key), key);
            isPresent[key] = true;
        } else {
            map.remove(TestKey(key));
            isPresent[key] = false;
        }
        size_t probed = (state >> 40) % TEST_RANGE;
        size_t* found = map.find(TestKey(probed));
        if (isPresent[probed]) {
            assert(found !is null && *found == probed);
        } else {
            assert(found is null);
        }
    }
    foreach (key; 0 .. TEST_RANGE) {
        assert((map.find(TestKey(key)) !is null) == isPresent[key]);
    }
    map.release();
}
