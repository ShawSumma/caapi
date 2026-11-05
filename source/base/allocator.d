module base.allocator;

import core.bitop : bsr;
import base.array : Array;
import base.hashmap : HashMap;
import base.maybe : Maybe, MaybeIndex;

enum uint SIZE_CLASSES = 32;

struct FreeRange {
    uint offset;
    uint count;
    MaybeIndex!uint previous;
    MaybeIndex!uint next;
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
    MaybeIndex!uint[SIZE_CLASSES] heads;
    uint capacity;
    uint available;

    Maybe!uint allocate(uint count) {
        uint size = sizeClass(count);
        MaybeIndex!uint found;
        uint larger = size + 1;
        while (larger < SIZE_CLASSES && !heads[larger].exists) {
            larger += 1;
        }
        if (larger < SIZE_CLASSES) {
            found = heads[larger];
        } else {
            found = heads[size];
            while (found.exists && ranges.ptr[found.value].count < count) {
                found = ranges.ptr[found.value].next;
            }
        }
        if (!found.exists) {
            return Maybe!uint.init;
        } else {
            FreeRange range = ranges.ptr[found.value];
            unlink(found.value);
            if (range.count > count) {
                link(range.offset + count, range.count - count);
            }
            available -= count;
            return Maybe!uint.of(range.offset);
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
        ranges.ptr[index] = FreeRange(offset, count, MaybeIndex!uint.init, heads[size]);
        if (heads[size].exists) {
            ranges.ptr[heads[size].value].previous = MaybeIndex!uint.of(index);
        }
        heads[size] = MaybeIndex!uint.of(index);
        starts.insert(Offset(offset), index);
        ends.insert(Offset(offset + count), index);
    }

    void unlink(uint index) {
        FreeRange range = ranges.ptr[index];
        if (!range.previous.exists) {
            heads[sizeClass(range.count)] = range.next;
        } else {
            ranges.ptr[range.previous.value].next = range.next;
        }
        if (range.next.exists) {
            ranges.ptr[range.next.value].previous = range.previous;
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
        heads = MaybeIndex!uint.init;
        capacity = 0;
        available = 0;
    }
}

uint sizeClass(uint count) {
    return bsr(count);
}
