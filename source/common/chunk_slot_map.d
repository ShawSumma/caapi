module common.chunk_slot_map;

import core.stdc.stdlib : calloc, free;
import common.node : ChunkId;

enum ubyte ENTRY_EMPTY = 0;
enum ubyte ENTRY_FILLED = 1;

// What the renderer tracks per resident chunk. The generation and the slot
// used to live in two separate tables keyed the same way, which meant hashing
// and probing twice for every chunk every frame.
struct ChunkSlot {
    uint slot;
    uint generation;
    bool hasData;
}

struct ChunkSlotLookup {
    bool found;
    ChunkSlot value;
}

// Open addressing with linear probing over three flat arrays.
//
// A D associative array hashes into a bucket array and then follows a pointer
// to a separately allocated entry, so a hit touches two cache lines at best and
// every insert allocates. Here a probe walks neighbouring entries that are
// already in cache, the whole table is three allocations made once, and the
// per-frame sweep for stale slots is a linear scan instead of a walk over
// scattered nodes.
//
// Deletion shifts entries backward rather than leaving tombstones. Tombstones
// would lengthen probes forever under the insert and remove churn this sees
// every frame, and clearing them needs either a rehash or scratch memory.
//
// Capacity is a power of two and never grows. The caller knows its slot budget
// up front, and rehashing in the middle of a frame would be worse than
// refusing the insert.
struct ChunkSlotMap {
    ChunkId* keys;
    ChunkSlot* values;
    ubyte* states;
    uint capacity;
    uint mask;
    uint count;

    void init(uint maxEntries) {
        // Keep the load factor near two thirds so probe runs stay short.
        uint wanted = maxEntries + maxEntries / 2;
        capacity = 16;
        while (capacity < wanted) {
            capacity = capacity * 2;
        }
        mask = capacity - 1;
        keys = cast(ChunkId*) calloc(capacity, ChunkId.sizeof);
        values = cast(ChunkSlot*) calloc(capacity, ChunkSlot.sizeof);
        states = cast(ubyte*) calloc(capacity, ubyte.sizeof);
        count = 0;
    }

    void cleanup() {
        if (keys !is null) {
            free(keys);
            keys = null;
        }
        if (values !is null) {
            free(values);
            values = null;
        }
        if (states !is null) {
            free(states);
            states = null;
        }
        capacity = 0;
        mask = 0;
        count = 0;
    }

    // The mask keeps only the low bits, so fold the whole hash down into them
    // before taking it.
    uint indexFor(ChunkId key) const {
        ulong h = key.toHash();
        h = h ^ (h >> 32);
        h = h * 0xD6E8FEB86659FD93;
        h = h ^ (h >> 32);
        return cast(uint) (h & mask);
    }

    // Returns capacity when the key is absent.
    uint findIndex(ChunkId key) const {
        uint i = indexFor(key);
        uint probes = 0;
        while (probes < capacity) {
            if (states[i] == ENTRY_EMPTY) {
                return capacity;
            }
            if (keys[i] == key) {
                return i;
            }
            i = (i + 1) & mask;
            probes = probes + 1;
        }
        return capacity;
    }

    ChunkSlotLookup lookup(ChunkId key) const {
        ChunkSlotLookup result;
        uint i = findIndex(key);
        if (i == capacity) {
            return result;
        }
        result.found = true;
        result.value = values[i];
        return result;
    }

    bool contains(ChunkId key) const {
        return findIndex(key) != capacity;
    }

    // False when the table is full, which the caller should treat as a refused
    // insert rather than an error.
    bool set(ChunkId key, ChunkSlot value) {
        uint i = indexFor(key);
        uint probes = 0;
        while (probes < capacity) {
            if (states[i] == ENTRY_EMPTY) {
                keys[i] = key;
                values[i] = value;
                states[i] = ENTRY_FILLED;
                count = count + 1;
                return true;
            }
            if (keys[i] == key) {
                values[i] = value;
                return true;
            }
            i = (i + 1) & mask;
            probes = probes + 1;
        }
        return false;
    }

    bool remove(ChunkId key) {
        uint hole = findIndex(key);
        if (hole == capacity) {
            return false;
        }

        // Walk forward closing the gap. An entry may move back into the hole
        // only if its own probe run started at or before it, otherwise a later
        // lookup would stop at the hole and miss it.
        uint cur = hole;
        while (true) {
            cur = (cur + 1) & mask;
            if (states[cur] == ENTRY_EMPTY) {
                break;
            }
            uint ideal = indexFor(keys[cur]);
            uint fromIdeal = (cur - ideal) & mask;
            uint fromHole = (cur - hole) & mask;
            if (fromIdeal >= fromHole) {
                keys[hole] = keys[cur];
                values[hole] = values[cur];
                states[hole] = ENTRY_FILLED;
                hole = cur;
            }
        }

        states[hole] = ENTRY_EMPTY;
        count = count - 1;
        return true;
    }

    bool isFilled(uint index) const {
        return states[index] == ENTRY_FILLED;
    }

    ChunkId keyAt(uint index) const {
        return keys[index];
    }

    ChunkSlot valueAt(uint index) const {
        return values[index];
    }
}
