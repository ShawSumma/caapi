module common.slab;

import core.stdc.stdlib : calloc, free, malloc;
import common.array : Array;

enum uint SLAB_SHIFT = 12;
enum uint SLAB_SIZE = 2 ^^ SLAB_SHIFT;
enum uint SLAB_MASK = SLAB_SIZE - 1;

struct Slab(T) {
    Array!(T*) blocks;

    inout(T)* at(size_t index) inout {
        return blocks.ptr[index >> SLAB_SHIFT] + (index & SLAB_MASK);
    }

    void ensure(size_t count) {
        while (blocks.length * SLAB_SIZE < count) {
            blocks.append(allocateBlock());
        }
    }

    T* touch(size_t index) {
        size_t block = index >> SLAB_SHIFT;
        while (blocks.length <= block) {
            blocks.append(null);
        }
        if (blocks.ptr[block] is null) {
            blocks.ptr[block] = allocateBlock();
        }
        return at(index);
    }

    T* allocateBlock() {
        static if (__traits(isZeroInit, T)) {
            return cast(T*) calloc(SLAB_SIZE, T.sizeof);
        } else {
            T* block = cast(T*) malloc(SLAB_SIZE * T.sizeof);
            foreach (i; 0 .. SLAB_SIZE) {
                block[i] = T.init;
            }
            return block;
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
    Slab!uint sparse;
    *sparse.touch(SLAB_SIZE * 5) = 7;
    assert(sparse.blocks.ptr[0] is null);
    assert(*sparse.touch(SLAB_SIZE * 5) == 7);
    sparse.release();
}
