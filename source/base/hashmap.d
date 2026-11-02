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
        if (found is null && previous.capacity > 0) {
            size_t index = previous.probe(key, previous.hashOf(key));
            if (index >= migrated && previous.controls[index] != EMPTY) {
                found = &previous.slots[index].value;
            }
        }
        return found;
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

    int opApply(scope int delegate(ref const K, ref V) visit) {
        return visitLive(this, visit);
    }

    int opApply(scope int delegate(ref const K, ref const V) visit) const {
        return visitLive(this, visit);
    }

    void release() {
        current.release();
        previous.release();
        migrated = 0;
    }
}

int visitLive(M, D)(ref M map, D visit) {
    int result = 0;
    foreach (index; 0 .. map.current.capacity) {
        if (result == 0 && (map.current.controls[index] & LIVE) != 0) {
            result = visit(map.current.slots[index].key, map.current.slots[index].value);
        }
    }
    foreach (index; map.migrated .. map.previous.capacity) {
        if (result == 0 && (map.previous.controls[index] & LIVE) != 0 && map.current.find(map.previous.slots[index].key) is null) {
            result = visit(map.previous.slots[index].key, map.previous.slots[index].value);
        }
    }
    return result;
}
