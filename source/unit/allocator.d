module unit.allocator;

import base.allocator : NO_OFFSET, RangeAllocator;

enum uint CAPACITY = 100;

unittest {
    RangeAllocator allocator;
    allocator.grow(CAPACITY);
    uint a = allocator.allocate(30);
    uint b = allocator.allocate(30);
    uint c = allocator.allocate(30);
    assert(a == 0 && b == 30 && c == 60);
    assert(allocator.allocate(30) == NO_OFFSET);
    allocator.release(b, 30);
    assert(allocator.allocate(20) == 30);
    allocator.release(a, 30);
    allocator.release(30, 20);
    assert(allocator.used() == 30);
    assert(allocator.allocate(60) == 0);
    allocator.grow(2 * CAPACITY);
    assert(allocator.allocate(110) == 90);
    assert(allocator.used() == 2 * CAPACITY);
    allocator.release();
}
