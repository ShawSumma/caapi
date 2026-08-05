module common.array;

import core.stdc.stdlib : calloc, free, malloc, realloc;
import core.stdc.string : memcpy;

// Fixed-size block handed back as a slice so existing indexing and
// slice-assignment code keeps working without the GC. Never resized; release
// with freeSlice.
//
// Elements get T.init, not raw zeroes. Those differ for types like
// NodeContainer whose `neighbors` defaults to NO_SLOT (0xFFFFFFFF), and
// silently handing back zeroes there would mean "points at slot 0".
T[] allocSlice(T)(size_t n) {
    if (n == 0) {
        return null;
    }
    T* block = cast(T*) calloc(n, T.sizeof);
    assert(block !is null, "allocSlice failed");
    static if (!__traits(isZeroInit, T)) {
        foreach (i; 0 .. n) {
            block[i] = T.init;
        }
    }
    return block[0 .. n];
}

void freeSlice(T)(ref T[] items) {
    if (items.ptr !is null) {
        free(items.ptr);
    }
    items = null;
}

// Growable array backed by malloc rather than the GC. Capacity doubles, so
// pointers into the storage are invalidated by any push. Take indices, not
// pointers, if a reference has to outlive a push.
struct Array(T) {
    T* items;
    size_t count;
    size_t capacity;

    static Array!T withCapacity(size_t initial) {
        Array!T result;
        result.reserve(initial);
        return result;
    }

    void release() {
        if (items !is null) {
            free(items);
        }
        items = null;
        count = 0;
        capacity = 0;
    }

    void reserve(size_t wanted) {
        if (wanted <= capacity) {
            return;
        }
        size_t grown = capacity;
        if (grown == 0) {
            grown = 8;
        }
        while (grown < wanted) {
            grown = grown * 2;
        }
        void* block = realloc(items, grown * T.sizeof);
        assert(block !is null, "Array reserve failed");
        items = cast(T*) block;
        capacity = grown;
    }

    void push(T value) {
        reserve(count + 1);
        items[count] = value;
        count = count + 1;
    }

    void clear() {
        count = 0;
    }

    // Grows to `n`, default-initialising anything new. Shrinking only moves
    // the count; the storage is kept for reuse.
    void resize(size_t n) {
        if (n <= count) {
            count = n;
            return;
        }
        reserve(n);
        foreach (i; count .. n) {
            items[i] = T.init;
        }
        count = n;
    }

    // Drops the first `n` entries by shifting the remainder down. Linear, but
    // callers that do this are draining a queue rather than deleting at random.
    void dropFront(size_t n) {
        if (n >= count) {
            count = 0;
            return;
        }
        size_t remaining = count - n;
        memcpy(items, items + n, remaining * T.sizeof);
        count = remaining;
    }

    Array!T dup() const {
        Array!T result;
        result.reserve(count);
        if (count > 0) {
            memcpy(result.items, items, count * T.sizeof);
        }
        result.count = count;
        return result;
    }

    void appendFrom(const ref Array!T other) {
        reserve(count + other.count);
        if (other.count > 0) {
            memcpy(items + count, other.items, other.count * T.sizeof);
        }
        count = count + other.count;
    }

    ref inout(T) opIndex(size_t index) inout return {
        assert(index < count, "Array index out of range");
        return items[index];
    }

    size_t opDollar() const {
        return count;
    }

    size_t length() const {
        return count;
    }

    bool empty() const {
        return count == 0;
    }

    T[] slice() return {
        if (items is null) {
            return null;
        }
        return items[0 .. count];
    }

    const(T)[] slice() const return {
        if (items is null) {
            return null;
        }
        return items[0 .. count];
    }

    int opApply(scope int delegate(ref T) dg) {
        foreach (i; 0 .. count) {
            int stop = dg(items[i]);
            if (stop != 0) {
                return stop;
            }
        }
        return 0;
    }

    int opApply(scope int delegate(ref const T) dg) const {
        foreach (i; 0 .. count) {
            int stop = dg(items[i]);
            if (stop != 0) {
                return stop;
            }
        }
        return 0;
    }
}

// Heapsort: in place, no allocation and no recursion, so it needs neither the
// GC nor a bounded stack. Ordering comes from the element's own opCmp.
void sortSlice(T)(T[] items) {
    size_t n = items.length;
    if (n < 2) {
        return;
    }
    size_t start = n / 2;
    while (start > 0) {
        start = start - 1;
        siftDown(items, start, n);
    }
    size_t end = n;
    while (end > 1) {
        end = end - 1;
        T swap = items[0];
        items[0] = items[end];
        items[end] = swap;
        siftDown(items, 0, end);
    }
}

void siftDown(T)(T[] items, size_t root, size_t end) {
    while (true) {
        size_t child = root * 2 + 1;
        if (child >= end) {
            return;
        }
        if (child + 1 < end && items[child] < items[child + 1]) {
            child = child + 1;
        }
        if (!(items[root] < items[child])) {
            return;
        }
        T swap = items[root];
        items[root] = items[child];
        items[child] = swap;
        root = child;
    }
}

unittest {
    // Reverse order is the worst case for a naive sort and exercises every
    // sift path.
    int[64] backwards;
    foreach (i; 0 .. 64) {
        backwards[i] = cast(int)(63 - i);
    }
    sortSlice(backwards[]);
    foreach (i; 0 .. 64) {
        assert(backwards[i] == cast(int) i);
    }

    int[5] dupes = [3, 1, 3, 1, 2];
    sortSlice(dupes[]);
    assert(dupes == [1, 1, 2, 3, 3]);

    int[1] single = [7];
    sortSlice(single[]);
    assert(single[0] == 7);

    int[] none;
    sortSlice(none);
}

unittest {
    // A type whose default is not all-zero: allocSlice must honour T.init
    // rather than handing back calloc's zeroes.
    struct Defaulted {
        uint slot = uint.max;
        int other;
    }

    Defaulted[] items = allocSlice!Defaulted(4);
    foreach (i; 0 .. 4) {
        assert(items[i].slot == uint.max);
        assert(items[i].other == 0);
    }
    freeSlice(items);
    assert(items is null);
}

unittest {
    Array!int a;
    foreach (i; 0 .. 100) {
        a.push(cast(int) i);
    }
    assert(a.length() == 100);
    assert(a[0] == 0);
    assert(a[99] == 99);

    a.dropFront(10);
    assert(a.length() == 90);
    assert(a[0] == 10);

    Array!int b = a.dup();
    assert(b.length() == 90);
    assert(b[0] == 10);
    b.push(1234);
    assert(b.length() == 91);
    assert(a.length() == 90);

    a.appendFrom(b);
    assert(a.length() == 181);
    assert(a[90] == 10);

    a.clear();
    assert(a.empty());

    a.release();
    b.release();
}
