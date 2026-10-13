module base.slab;

import core.bitop : bsf, bsr;
import core.stdc.stdlib : calloc, free, malloc;
import base.array : Array;

enum uint SLAB_SHIFT = 12;
enum uint SLAB_SIZE = 2 ^^ SLAB_SHIFT;
enum uint SLAB_MASK = SLAB_SIZE - 1;
enum uint RUN_CLASSES = SLAB_SHIFT + 1;

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

struct Run {
    uint start;
    uint length;
}

struct RunPool(T) {
    Slab!T items;
    Array!uint[RUN_CLASSES] free;
    uint end;

    inout(T)[] slice(Run run) inout {
        return run.length == 0 ? null : items.at(run.start)[0 .. run.length];
    }

    Run reserve(uint length) {
        if (length == 0) {
            return Run(0, 0);
        } else {
            assert(length <= SLAB_SIZE);
            uint size = runClass(length);
            if (free[size].length > 0) {
                free[size].length -= 1;
                return Run(free[size].ptr[free[size].length], length);
            } else {
                uint span = 1u << size;
                uint start = (end + span - 1) & ~(span - 1);
                keepGap(end, start);
                end = start + span;
                items.ensure(end);
                return Run(start, length);
            }
        }
    }

    void release(Run run) {
        if (run.length > 0) {
            free[runClass(run.length)].append(run.start);
        }
    }

    void keepGap(uint from, uint to) {
        while (from < to) {
            uint size = bsf(from) < SLAB_SHIFT ? bsf(from) : SLAB_SHIFT;
            while ((1u << size) > to - from) {
                size -= 1;
            }
            free[size].append(from);
            from += 1u << size;
        }
    }

    void release() {
        items.release();
        foreach (ref list; free) {
            list.release();
        }
        end = 0;
    }
}

uint runClass(uint length) {
    return length <= 1 ? 0 : bsr(length - 1) + 1;
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

enum uint TEST_RUNS = 3000;

unittest {
    RunPool!uint pool;
    Array!Run runs;
    foreach (index; 0 .. TEST_RUNS) {
        Run run = pool.reserve(index % 37 + 1);
        assert(run.start >> SLAB_SHIFT == (run.start + run.length - 1) >> SLAB_SHIFT);
        foreach (ref item; pool.slice(run)) {
            item = index;
        }
        runs.append(run);
    }
    foreach (index, run; runs.slice()) {
        foreach (item; pool.slice(run)) {
            assert(item == index);
        }
    }
    uint end = pool.end;
    foreach (run; runs.slice()) {
        pool.release(run);
    }
    foreach (run; runs.slice()) {
        pool.reserve(run.length);
    }
    assert(pool.end == end);
    runs.release();
    pool.release();
}
