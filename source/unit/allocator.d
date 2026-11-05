module unit.allocator;

import base.allocator : RangeAllocator;
import base.maybe : Maybe;

enum uint CAPACITY = 100;

unittest {
    RangeAllocator allocator;
    allocator.grow(CAPACITY);
    Maybe!uint a = allocator.allocate(30);
    Maybe!uint b = allocator.allocate(30);
    Maybe!uint c = allocator.allocate(30);
    assert(a == Maybe!uint.of(0) && b == Maybe!uint.of(30) && c == Maybe!uint.of(60));
    Maybe!uint tooMuch = allocator.allocate(30);
    assert(!tooMuch.exists);
    allocator.release(b.value, 30);
    Maybe!uint reused = allocator.allocate(20);
    assert(reused == Maybe!uint.of(30));
    allocator.release(a.value, 30);
    allocator.release(30, 20);
    assert(allocator.used() == 30);
    Maybe!uint merged = allocator.allocate(60);
    assert(merged == Maybe!uint.of(0));
    allocator.grow(2 * CAPACITY);
    Maybe!uint grown = allocator.allocate(110);
    assert(grown == Maybe!uint.of(90));
    assert(allocator.used() == 2 * CAPACITY);
    allocator.release();
}
