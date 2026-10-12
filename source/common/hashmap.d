module common.hashmap;

import core.bitop : bsr;
import core.stdc.stdlib : calloc, free;

enum size_t FIBONACCI_MULTIPLIER = 0x9E3779B97F4A7C15;
enum size_t INITIAL_HASH_MAP_CAPACITY = 16;
enum size_t MIGRATED_SLOTS_PER_INSERT = 8;
enum size_t LIVE_SPREAD = 2;
enum size_t TEST_KEYS = 100000;
enum size_t TEST_KEPT = 3;

struct HashEntry(K, V) {
    K key;
    V value;
    bool isUsed;
    bool isRemoved;

    bool isLive() const {
        return isUsed && !isRemoved;
    }
}

struct HashTable(K, V) {
    HashEntry!(K, V)* entries;
    size_t capacity;
    size_t count;
    size_t removed;
    uint shift;

    void allocate(size_t slots) {
        entries = cast(HashEntry!(K, V)*) calloc(slots, HashEntry!(K, V).sizeof);
        capacity = slots;
        count = 0;
        removed = 0;
        shift = cast(uint)(size_t.sizeof * 8 - bsr(slots));
    }

    size_t live() const {
        return count - removed;
    }

    size_t slotOf(K key) const {
        size_t mask = capacity - 1;
        size_t index = (key.toHash() * FIBONACCI_MULTIPLIER) >> shift;
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
            if (entry.isLive()) {
                return &entry.value;
            } else {
                return null;
            }
        }
    }

    void assign(K key, V value) {
        HashEntry!(K, V)* entry = &entries[slotOf(key)];
        if (entry.isUsed) {
            if (entry.isRemoved) {
                entry.isRemoved = false;
                removed -= 1;
            }
            entry.value = value;
        } else {
            *entry = HashEntry!(K, V)(key, value, true, false);
            count += 1;
        }
    }

    void assignIfMissing(K key, V value) {
        HashEntry!(K, V)* entry = &entries[slotOf(key)];
        if (!entry.isUsed) {
            *entry = HashEntry!(K, V)(key, value, true, false);
            count += 1;
        }
    }

    void remove(K key) {
        if (capacity > 0) {
            HashEntry!(K, V)* entry = &entries[slotOf(key)];
            if (entry.isLive()) {
                entry.isRemoved = true;
                removed += 1;
            }
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
        if (current.capacity > 0 && current.entries[current.slotOf(key)].isUsed) {
            return current.find(key);
        } else {
            return previous.find(key);
        }
    }

    void insert(K key, V value) {
        if ((current.count + 1) * 2 > current.capacity) {
            grow();
        }
        current.assign(key, value);
        migrate(MIGRATED_SLOTS_PER_INSERT);
    }

    void remove(K key) {
        current.remove(key);
        previous.remove(key);
    }

    void grow() {
        migrate(previous.capacity);
        previous = current;
        current.allocate(capacityFor(previous.live()));
        migrated = 0;
    }

    void migrate(size_t slots) {
        size_t end = migrated + slots;
        if (end > previous.capacity) {
            end = previous.capacity;
        }
        foreach (i; migrated .. end) {
            if (previous.entries[i].isLive()) {
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
