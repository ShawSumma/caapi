module unit.allocator;

import base.allocator : Allocation, RangeAllocator;

enum uint CAPACITY = 100;

unittest {
    RangeAllocator allocator;
    allocator.grow(CAPACITY);
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
    allocator.grow(2 * CAPACITY);
    assert(allocator.allocate(110).offset == 90);
    assert(allocator.used() == 2 * CAPACITY);
    allocator.release();
}
