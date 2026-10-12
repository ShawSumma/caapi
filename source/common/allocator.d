module common.allocator;

import core.bitop : bsr;
import common.array : Array;
import common.hashmap : HashMap;

enum uint TEST_CAPACITY = 100;
enum uint NO_RANGE = uint.max;
enum uint SIZE_CLASSES = 32;

struct Allocation {
    uint offset;
    bool isFound;
}

struct FreeRange {
    uint offset;
    uint count;
    uint previous;
    uint next;
}

struct Offset {
    uint value;

    size_t toHash() const {
        return value;
    }
}

struct RangeAllocator {
    Array!FreeRange ranges;
    Array!uint spare;
    HashMap!(Offset, uint) starts;
    HashMap!(Offset, uint) ends;
    uint[SIZE_CLASSES] heads = NO_RANGE;
    uint capacity;
    uint available;

    Allocation allocate(uint count) {
        uint size = sizeClass(count);
        uint found = NO_RANGE;
        uint larger = size + 1;
        while (larger < SIZE_CLASSES && heads[larger] == NO_RANGE) {
            larger += 1;
        }
        if (larger < SIZE_CLASSES) {
            found = heads[larger];
        } else {
            found = heads[size];
            while (found != NO_RANGE && ranges.ptr[found].count < count) {
                found = ranges.ptr[found].next;
            }
        }
        if (found == NO_RANGE) {
            return Allocation(0, false);
        } else {
            FreeRange range = ranges.ptr[found];
            unlink(found);
            if (range.count > count) {
                link(range.offset + count, range.count - count);
            }
            available -= count;
            return Allocation(range.offset, true);
        }
    }

    void release(uint offset, uint count) {
        uint start = offset;
        uint end = offset + count;
        const(uint)* before = ends.find(Offset(start));
        if (before !is null) {
            uint index = *before;
            start = ranges.ptr[index].offset;
            unlink(index);
        }
        const(uint)* after = starts.find(Offset(end));
        if (after !is null) {
            uint index = *after;
            end = ranges.ptr[index].offset + ranges.ptr[index].count;
            unlink(index);
        }
        link(start, end - start);
        available += count;
    }

    void link(uint offset, uint count) {
        uint index = void;
        if (spare.length > 0) {
            index = spare.ptr[spare.length - 1];
            spare.length -= 1;
        } else {
            index = cast(uint) ranges.length;
            ranges.append(FreeRange.init);
        }
        uint size = sizeClass(count);
        ranges.ptr[index] = FreeRange(offset, count, NO_RANGE, heads[size]);
        if (heads[size] != NO_RANGE) {
            ranges.ptr[heads[size]].previous = index;
        }
        heads[size] = index;
        starts.insert(Offset(offset), index);
        ends.insert(Offset(offset + count), index);
    }

    void unlink(uint index) {
        FreeRange range = ranges.ptr[index];
        if (range.previous == NO_RANGE) {
            heads[sizeClass(range.count)] = range.next;
        } else {
            ranges.ptr[range.previous].next = range.next;
        }
        if (range.next != NO_RANGE) {
            ranges.ptr[range.next].previous = range.previous;
        }
        starts.remove(Offset(range.offset));
        ends.remove(Offset(range.offset + range.count));
        spare.append(index);
    }

    uint used() const {
        return capacity - available;
    }

    void grow(uint newCapacity) {
        release(capacity, newCapacity - capacity);
        capacity = newCapacity;
    }

    void release() {
        ranges.release();
        spare.release();
        starts.release();
        ends.release();
        heads = NO_RANGE;
        capacity = 0;
        available = 0;
    }
}

uint sizeClass(uint count) {
    return bsr(count);
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
    assert(allocator.used() == 30);
    assert(allocator.allocate(60).offset == 0);
    allocator.grow(2 * TEST_CAPACITY);
    assert(allocator.allocate(110).offset == 90);
    assert(allocator.used() == 2 * TEST_CAPACITY);
    allocator.release();
}
