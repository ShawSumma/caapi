module common.slab;

import core.stdc.stdlib : free, malloc;
import common.array : Array;

enum uint SLAB_SHIFT = 12;
enum uint SLAB_SIZE = 1u << SLAB_SHIFT;
enum uint SLAB_MASK = SLAB_SIZE - 1;

struct Slab(T) {
    Array!(T*) blocks;

    inout(T)* at(size_t index) inout {
        return blocks.ptr[index >> SLAB_SHIFT] + (index & SLAB_MASK);
    }

    void ensure(size_t count) {
        while (blocks.length * SLAB_SIZE < count) {
            T* block = cast(T*) malloc(SLAB_SIZE * T.sizeof);
            foreach (i; 0 .. SLAB_SIZE) {
                block[i] = T.init;
            }
            blocks.append(block);
        }
    }

    void release() {
        foreach (block; blocks.slice()) {
            free(block);
        }
        blocks.release();
    }
}

unittest {
    Slab!uint slab;
    slab.ensure(SLAB_SIZE + 1);
    uint* first = slab.at(0);
    *slab.at(SLAB_SIZE) = SLAB_SIZE;
    slab.ensure(SLAB_SIZE * 3);
    assert(slab.at(0) is first);
    assert(*slab.at(SLAB_SIZE) == SLAB_SIZE);
    assert(*slab.at(SLAB_SIZE * 3 - 1) == 0);
    slab.release();
}
