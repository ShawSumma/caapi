module common.hash_map;

import core.stdc.stdlib : calloc, free;

enum size_t INITIAL_HASH_MAP_CAPACITY = 16;

struct HashMap(K, V) {
    K* keys;
    V* values;
    bool* used;
    size_t capacity;
    size_t count;

    inout(V)* find(K key) inout {
        inout(V)* found = null;
        if (capacity > 0) {
            size_t mask = capacity - 1;
            size_t index = key.toHash() & mask;
            bool searching = true;
            while (searching) {
                if (!used[index]) {
                    searching = false;
                } else if (keys[index] == key) {
                    found = &values[index];
                    searching = false;
                } else {
                    index = (index + 1) & mask;
                }
            }
        }
        return found;
    }

    void insert(K key, V value) {
        if ((count + 1) * 2 > capacity) {
            grow();
        }
        size_t mask = capacity - 1;
        size_t index = key.toHash() & mask;
        while (used[index] && !(keys[index] == key)) {
            index = (index + 1) & mask;
        }
        if (!used[index]) {
            used[index] = true;
            keys[index] = key;
            count += 1;
        }
        values[index] = value;
    }

    void grow() {
        K* oldKeys = keys;
        V* oldValues = values;
        bool* oldUsed = used;
        size_t oldCapacity = capacity;
        size_t newCapacity = INITIAL_HASH_MAP_CAPACITY;
        if (capacity > 0) {
            newCapacity = capacity * 2;
        }
        keys = cast(K*) calloc(newCapacity, K.sizeof);
        values = cast(V*) calloc(newCapacity, V.sizeof);
        used = cast(bool*) calloc(newCapacity, bool.sizeof);
        capacity = newCapacity;
        count = 0;
        foreach (i; 0 .. oldCapacity) {
            if (oldUsed[i]) {
                insert(oldKeys[i], oldValues[i]);
            }
        }
        free(oldKeys);
        free(oldValues);
        free(oldUsed);
    }

    void release() {
        free(keys);
        free(values);
        free(used);
        keys = null;
        values = null;
        used = null;
        capacity = 0;
        count = 0;
    }
}
