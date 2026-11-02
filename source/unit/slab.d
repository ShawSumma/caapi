module unit.slab;

import base.array : Array;
import base.pages : pageSize;
import base.slab : DiscardPass, FreeIndices, NOTED_PAGES_PER_DISCARD, Run, RunPool, SLAB_SHIFT, SLAB_SIZE, Slab;

enum uint RUNS = 3000;
enum uint INDICES = 10000;
enum uint INDEX_STRIDE = 7;

struct Record {
    uint[3] values;
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

unittest {
    Slab!Record slab;
    FreeIndices free;
    size_t count = (NOTED_PAGES_PER_DISCARD + 2) * pageSize() / Record.sizeof;
    size_t straddling = pageSize() / Record.sizeof;
    size_t inside = count / 2;
    slab.ensure(count);
    foreach (index; 0 .. count) {
        slab.at(index).values[0] = cast(uint) index + 1;
    }
    foreach (index; 0 .. count) {
        if (index != straddling && index != inside) {
            *slab.at(index) = Record.init;
            free.add(cast(uint) index);
            slab.note(index, 1);
        }
    }
    do {
        uint calls = 1;
        slab.discardNoted(free, count, 1, calls);
    } while (slab.pass == DiscardPass.sweeping);
    assert(slab.notedCount == 0);
    assert(slab.at(straddling).values[0] == straddling + 1 && slab.at(inside).values[0] == inside + 1);
    foreach (index; 0 .. count) {
        assert(index == straddling || index == inside || slab.at(index).values[0] == 0);
    }
    slab.release();
    free.release();
}

unittest {
    RunPool!uint pool;
    Array!Run runs;
    foreach (index; 0 .. RUNS) {
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

unittest {
    FreeIndices free;
    foreach (step; 0 .. INDICES) {
        free.add(step * INDEX_STRIDE % INDICES);
    }
    foreach (expected; 0 .. INDICES / 2) {
        assert(free.takeLowest() == expected);
    }
    free.add(INDEX_STRIDE);
    assert(free.contains(INDEX_STRIDE) && !free.contains(INDEX_STRIDE + 1));
    assert(free.containsAll(INDICES / 2, INDICES) && !free.containsAll(INDICES / 2 - 1, INDICES));
    assert(free.containsAll(INDEX_STRIDE, INDEX_STRIDE + 1) && !free.containsAll(0, INDEX_STRIDE + 1));
    assert(free.takeLowest() == INDEX_STRIDE);
    free.drop(INDICES / 2);
    assert(free.takeLowest() == INDICES / 2 + 1);
    assert(free.count == INDICES / 2 - 2);
    free.release();
}
