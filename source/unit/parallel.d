module unit.parallel;

import core.atomic : atomicLoad, atomicOp;
import core.stdc.stdlib : calloc, free;
import base.clock : Deadline;
import base.parallel : ConcurrentQueue, ParallelJob, TaskSource, WorkerPool;

enum uint WORKERS = 3;
enum size_t ITEMS = 10000;
enum uint ROUNDS = 50;

struct Counts {
    shared uint[ITEMS] seen;
}

void countItem(void* context, size_t index, uint worker) {
    atomicOp!"+="((cast(Counts*) context).seen[index], 1);
}

bool takeNothing(void* context, uint worker) {
    return false;
}

unittest {
    WorkerPool* pool = WorkerPool.make(WORKERS, TaskSource(&takeNothing, null));
    Counts* counts = cast(Counts*) calloc(1, Counts.sizeof);
    foreach (round; 0 .. ROUNDS) {
        ParallelJob job = ParallelJob(&countItem, counts, Deadline.init, ITEMS);
        pool.run(&job);
        assert(job.count == ITEMS);
    }
    foreach (index; 0 .. ITEMS) {
        assert(atomicLoad(counts.seen[index]) == ROUNDS);
    }
    ParallelJob late = ParallelJob(&countItem, counts, Deadline.at(0), ITEMS);
    pool.run(&late);
    assert(late.count >= 1 && late.count < ITEMS);
    foreach (index; 0 .. ITEMS) {
        uint expected = ROUNDS;
        if (index < late.count) {
            expected += 1;
        }
        assert(atomicLoad(counts.seen[index]) == expected);
    }
    free(counts);
    pool.release();
    free(pool);
}

unittest {
    ConcurrentQueue!uint queue = ConcurrentQueue!uint.make(4);
    foreach (value; 0 .. 4) {
        bool pushed = queue.push(value);
        assert(pushed);
    }
    bool overfull = queue.push(4);
    assert(!overfull);
    uint popped;
    bool took = queue.pop(popped);
    assert(took && popped == 0);
    bool refilled = queue.push(4);
    assert(refilled);
    foreach (expected; 1 .. 5) {
        took = queue.pop(popped);
        assert(took && popped == expected);
    }
    took = queue.pop(popped);
    assert(!took);
    queue.release();
}
