module base.hashmap;

import core.bitop : bsr;
import core.stdc.stdlib : calloc, free, malloc;
import core.stdc.string : memset;

enum size_t FIBONACCI_MULTIPLIER = 0x9E3779B97F4A7C15;
enum size_t INITIAL_HASH_MAP_CAPACITY = 16;
enum size_t MIGRATED_SLOTS_PER_INSERT = 8;
enum size_t LIVE_SPREAD = 2;
enum uint TAG_BITS = 7;
enum ubyte EMPTY = 0;
enum ubyte REMOVED = 1;
enum ubyte LIVE = 0x80;
enum size_t TEST_KEYS = 100000;
enum size_t TEST_KEPT = 3;

struct HashSlot(K, V) {
    K key;
    V value;
}

struct HashTable(K, V) {
    ubyte* controls;
    HashSlot!(K, V)* slots;
    size_t capacity;
    size_t used;
    size_t removed;
    uint shift;

    void allocate(size_t count) {
        controls = cast(ubyte*) calloc(count, 1);
        slots = cast(HashSlot!(K, V)*) malloc(count * HashSlot!(K, V).sizeof);
        capacity = count;
        used = 0;
        removed = 0;
        shift = cast(uint)(size_t.sizeof * 8 - bsr(count));
    }

    size_t live() const {
        return used - removed;
    }

    static size_t hashOf(K key) {
        return key.toHash() * FIBONACCI_MULTIPLIER;
    }

    ubyte tagOf(size_t hash) const {
        return cast(ubyte)(LIVE | ((hash >> (shift - TAG_BITS)) & (LIVE - 1)));
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
            return controls[index] == EMPTY ? null : &slots[index].value;
        }
    }

    void assign(K key, V value, bool isKept) {
        size_t hash = hashOf(key);
        size_t mask = capacity - 1;
        ubyte tag = tagOf(hash);
        size_t index = hash >> shift;
        size_t reusable = size_t.max;
        while (controls[index] != EMPTY && !(controls[index] == tag && slots[index].key == key)) {
            if (controls[index] == REMOVED && reusable == size_t.max) {
                reusable = index;
            }
            index = (index + 1) & mask;
        }
        if (controls[index] != EMPTY) {
            if (!isKept) {
                slots[index].value = value;
            }
        } else if (reusable != size_t.max) {
            controls[reusable] = tag;
            slots[reusable] = HashSlot!(K, V)(key, value);
            removed -= 1;
        } else {
            controls[index] = tag;
            slots[index] = HashSlot!(K, V)(key, value);
            used += 1;
        }
    }

    void remove(K key) {
        if (capacity > 0) {
            size_t index = probe(key, hashOf(key));
            if (controls[index] != EMPTY) {
                controls[index] = REMOVED;
                removed += 1;
            }
        }
    }

    void clear() {
        if (capacity > 0) {
            memset(controls, EMPTY, capacity);
        }
        used = 0;
        removed = 0;
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
        return found !is null ? found : previous.find(key);
    }

    void insert(K key, V value) {
        if ((current.used + 1) * 2 > current.capacity) {
            grow();
        }
        current.assign(key, value, false);
        migrate(MIGRATED_SLOTS_PER_INSERT);
    }

    void remove(K key) {
        current.remove(key);
        previous.remove(key);
    }

    void clear() {
        current.clear();
        previous.release();
        migrated = 0;
    }

    void grow() {
        migrate(previous.capacity);
        previous = current;
        current.allocate(capacityFor(previous.live()));
        migrated = 0;
    }

    void migrate(size_t count) {
        size_t end = migrated + count;
        if (end > previous.capacity) {
            end = previous.capacity;
        }
        foreach (index; migrated .. end) {
            if ((previous.controls[index] & LIVE) != 0) {
                current.assign(previous.slots[index].key, previous.slots[index].value, true);
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

size_t capacityFor(size_t live) {
    size_t capacity = INITIAL_HASH_MAP_CAPACITY;
    while (capacity < live * LIVE_SPREAD) {
        capacity *= 2;
    }
    return capacity;
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
}
