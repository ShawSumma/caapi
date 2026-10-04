module common.range_allocator;

import common.array : Array;

enum uint TEST_CAPACITY = 100;

struct Range {
    uint offset;
    uint count;
}

struct Allocation {
    uint offset;
    bool isFound;
}

struct RangeAllocator {
    Array!Range free;
    uint capacity;

    Allocation allocate(uint count) {
        foreach (i, range; free.slice()) {
            if (range.count >= count) {
                free.ptr[i] = Range(range.offset + count, range.count - count);
                removeEmpty();
                return Allocation(range.offset, true);
            }
        }
        return Allocation(0, false);
    }

    void release(uint offset, uint count) {
        size_t position = 0;
        while (position < free.length && free.ptr[position].offset < offset) {
            position += 1;
        }
        free.append(Range.init);
        size_t i = free.length - 1;
        while (i > position) {
            free.ptr[i] = free.ptr[i - 1];
            i -= 1;
        }
        free.ptr[position] = Range(offset, count);
        coalesce();
    }

    uint used() const {
        uint available = 0;
        foreach (range; free.slice()) {
            available += range.count;
        }
        return capacity - available;
    }

    void grow(uint newCapacity) {
        release(capacity, newCapacity - capacity);
        capacity = newCapacity;
    }

    void removeEmpty() {
        size_t kept = 0;
        foreach (range; free.slice()) {
            if (range.count > 0) {
                free.ptr[kept] = range;
                kept += 1;
            }
        }
        free.length = kept;
    }

    void coalesce() {
        size_t kept = 0;
        foreach (range; free.slice()) {
            if (kept > 0 && free.ptr[kept - 1].offset + free.ptr[kept - 1].count == range.offset) {
                free.ptr[kept - 1].count += range.count;
            } else {
                free.ptr[kept] = range;
                kept += 1;
            }
        }
        free.length = kept;
    }

    void release() {
        free.release();
        capacity = 0;
    }
}

unittest {
    RangeAllocator allocator;
    allocator.grow(TEST_CAPACITY);
    Allocation a = allocator.allocate(30);
    Allocation b = allocator.allocate(30);
    Allocation c = allocator.allocate(30);
    assert(a.isFound && b.isFound && c.isFound);
    assert(a.offset == 0 && b.offset == 30 && c.offset == 60);
    assert(!allocator.allocate(30).isFound);
    allocator.release(b.offset, 30);
    assert(allocator.allocate(20).offset == 30);
    allocator.release(a.offset, 30);
    allocator.release(30, 20);
    assert(allocator.free.length == 2);
    assert(allocator.allocate(60).offset == 0);
    allocator.grow(2 * TEST_CAPACITY);
    assert(allocator.allocate(110).offset == 90);
    allocator.release();
}
