module unit.hashmap;

import base.flags : Bits;
import base.hashmap : FIBONACCI_MULTIPLIER, HashMap;

enum size_t KEYS = 100000;
enum size_t KEPT = 3;
enum size_t RANGE = 4096;
enum size_t STEPS = 2_000_000;
enum size_t SWING = 200_000;
enum size_t VISIT_STEPS = 1009;
enum size_t BIG_RANGE = 1 << 18;
enum size_t BIG_STEPS = 1_500_000;
enum size_t BIG_SWING = 500_000;
enum size_t BIG_VISIT_STEPS = 4999;
enum ulong STATE_MULTIPLIER = 6364136223846793005UL;
enum ulong STATE_INCREMENT = 1442695040888963407UL;

struct Key {
    size_t value;

    size_t toHash() const {
        return value;
    }
}

unittest {
    HashMap!(Key, size_t) map;
    foreach (i; 0 .. KEYS) {
        map.insert(Key(i), i * 2);
        assert(*map.find(Key(i / 2)) == (i / 2) * 2);
    }
    foreach (i; 0 .. KEYS) {
        assert(*map.find(Key(i)) == i * 2);
    }
    assert(map.find(Key(KEYS)) is null);
    map.insert(Key(3), 7);
    assert(*map.find(Key(3)) == 7);
    size_t capacity = map.current.capacity;
    map.clear();
    assert(map.find(Key(3)) is null && map.current.capacity == capacity);
    map.insert(Key(3), 1);
    assert(*map.find(Key(3)) == 1);
    map.release();
    HashMap!(Key, size_t) churn;
    foreach (i; 0 .. KEYS) {
        churn.insert(Key(i), i);
        if (i >= KEPT) {
            churn.remove(Key(i - KEPT));
            assert(churn.find(Key(i - KEPT)) is null);
        }
        assert(*churn.find(Key(i)) == i);
    }
    assert(churn.current.capacity < KEYS);
    churn.remove(Key(KEYS - 1));
    churn.insert(Key(KEYS - 1), 1);
    assert(*churn.find(Key(KEYS - 1)) == 1);
    churn.release();
    HashMap!(Key, size_t) emptied;
    foreach (i; 0 .. KEYS) {
        emptied.insert(Key(i * FIBONACCI_MULTIPLIER), i);
    }
    foreach (i; KEPT .. KEYS) {
        emptied.remove(Key(i * FIBONACCI_MULTIPLIER));
    }
    foreach (i; 0 .. KEYS) {
        size_t* found = emptied.find(Key(i * FIBONACCI_MULTIPLIER));
        if (i < KEPT) {
            assert(found !is null && *found == i);
        } else {
            assert(found is null);
        }
    }
    emptied.release();
}

unittest {
    HashMap!(Key, size_t) map;
    Bits held;
    held.cover(RANGE);
    ulong state = 1;
    foreach (step; 0 .. STEPS) {
        state = state * STATE_MULTIPLIER + STATE_INCREMENT;
        size_t key = (state >> 33) % RANGE;
        if (((step / SWING) % 2 == 0) != ((state >> 20) % 4 == 0)) {
            map.insert(Key(key), key);
            held.set(key);
        } else {
            map.remove(Key(key));
            held.clear(key);
        }
        size_t probed = (state >> 40) % RANGE;
        size_t* found = map.find(Key(probed));
        if (held.has(probed)) {
            assert(found !is null && *found == probed);
        } else {
            assert(found is null);
        }
        if (step % VISIT_STEPS == 0) {
            size_t visited = 0;
            foreach (ref const visitedKey, ref value; map) {
                assert(held.has(visitedKey.value) && value == visitedKey.value);
                visited += 1;
            }
            size_t present = 0;
            foreach (cell; 0 .. RANGE) {
                if (held.has(cell)) {
                    present += 1;
                }
            }
            assert(visited == present);
        }
    }
    foreach (key; 0 .. RANGE) {
        assert((map.find(Key(key)) !is null) == held.has(key));
    }
    held.release();
    map.release();
}

unittest {
    HashMap!(Key, size_t) map;
    Bits held;
    held.cover(BIG_RANGE);
    size_t present = 0;
    ulong state = 1;
    foreach (step; 0 .. BIG_STEPS) {
        state = state * STATE_MULTIPLIER + STATE_INCREMENT;
        size_t key = (state >> 30) % BIG_RANGE;
        if (((step / BIG_SWING) % 2 == 0) != ((state >> 20) % 4 == 0)) {
            if (!held.has(key)) {
                map.insert(Key(key), key);
                held.set(key);
                present += 1;
            }
        } else if (held.has(key)) {
            map.remove(Key(key));
            held.clear(key);
            present -= 1;
        }
        size_t probed = (state >> 40) % BIG_RANGE;
        assert((map.find(Key(probed)) !is null) == held.has(probed));
        if (step % BIG_VISIT_STEPS == 0) {
            size_t visited = 0;
            foreach (ref const visitedKey, ref value; map) {
                assert(held.has(visitedKey.value) && value == visitedKey.value);
                visited += 1;
            }
            assert(visited == present);
        }
    }
    held.release();
    map.release();
}

unittest {
    HashMap!(Key, size_t) map;
    size_t count = 0;
    while (map.previous.capacity == 0) {
        map.insert(Key(count), count);
        count += 1;
    }
    assert(map.migrated > 0);
    size_t visited = 0;
    foreach (ref const key, ref value; map) {
        assert(key.value == value && value < count);
        visited += 1;
    }
    assert(visited == count);
    map.release();
}
