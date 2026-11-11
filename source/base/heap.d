module base.heap;

import core.atomic : atomicExchange, cas;
import base.array : Array;
import base.maybe : Maybe;
import base.parallel : waitWhile, wakeSome;

enum uint LOCK_FREE = 0;
enum uint LOCK_HELD = 1;
enum uint LOCK_AWAITED = 2;

struct Lock {
    shared uint state;

    void take() {
        bool free = cas(&state, LOCK_FREE, LOCK_HELD);
        if (!free) {
            uint before = atomicExchange(&state, LOCK_AWAITED);
            while (before != LOCK_FREE) {
                waitWhile(state, LOCK_AWAITED);
                before = atomicExchange(&state, LOCK_AWAITED);
            }
        }
    }

    void give() {
        uint before = atomicExchange(&state, LOCK_FREE);
        if (before == LOCK_AWAITED) {
            wakeSome(state, 1);
        }
    }
}

struct HeapEntry {
    float key;
    uint item;
}

struct WorkHeap(T) {
    Array!HeapEntry entries;
    Array!T items;
    Array!uint spare;
    Lock lock;

    void push(float key, T value) {
        lock.take();
        uint item = cast(uint) items.length;
        if (spare.length > 0) {
            spare.length -= 1;
            item = spare.ptr[spare.length];
            items.ptr[item] = value;
        } else {
            items.append(value);
        }
        entries.append(HeapEntry(key, item));
        raise(entries.length - 1);
        lock.give();
    }

    bool pop(ref T value) {
        lock.take();
        bool found = entries.length > 0;
        if (found) {
            uint item = entries.ptr[0].item;
            value = items.ptr[item];
            spare.append(item);
            entries.length -= 1;
            if (entries.length > 0) {
                entries.ptr[0] = entries.ptr[entries.length];
                sink(0);
            }
        }
        lock.give();
        return found;
    }

    float nearest() {
        lock.take();
        float key = float.infinity;
        if (entries.length > 0) {
            key = entries.ptr[0].key;
        }
        lock.give();
        return key;
    }

    void raise(size_t index) {
        HeapEntry moved = entries.ptr[index];
        size_t at = index;
        while (at > 0 && moved.key < entries.ptr[(at - 1) / 2].key) {
            entries.ptr[at] = entries.ptr[(at - 1) / 2];
            at = (at - 1) / 2;
        }
        entries.ptr[at] = moved;
    }

    void sink(size_t index) {
        HeapEntry moved = entries.ptr[index];
        size_t at = index;
        size_t child = lowerChild(at);
        while (child < entries.length && entries.ptr[child].key < moved.key) {
            entries.ptr[at] = entries.ptr[child];
            at = child;
            child = lowerChild(at);
        }
        entries.ptr[at] = moved;
    }

    size_t lowerChild(size_t index) const {
        size_t left = 2 * index + 1;
        if (left + 1 < entries.length && entries.ptr[left + 1].key < entries.ptr[left].key) {
            return left + 1;
        } else {
            return left;
        }
    }

    void release() {
        entries.release();
        items.release();
        spare.release();
    }
}

void rekeyed(alias keyOf, T)(ref WorkHeap!T heap) {
    heap.lock.take();
    size_t kept = 0;
    foreach (index; 0 .. heap.entries.length) {
        uint item = heap.entries.ptr[index].item;
        Maybe!float key = keyOf(heap.items.ptr[item]);
        if (key.exists) {
            heap.entries.ptr[kept] = HeapEntry(key.value, item);
            kept += 1;
        } else {
            heap.spare.append(item);
        }
    }
    heap.entries.length = kept;
    size_t index = kept / 2;
    while (index > 0) {
        index -= 1;
        heap.sink(index);
    }
    heap.lock.give();
}
