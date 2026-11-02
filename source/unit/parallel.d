module unit.parallel;

import core.atomic : atomicLoad, atomicOp;
import core.stdc.stdlib : calloc, free;
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
        ParallelJob job = ParallelJob(&countItem, counts, double.infinity, ITEMS);
        pool.run(&job);
        assert(job.count == ITEMS);
    }
    foreach (index; 0 .. ITEMS) {
        assert(atomicLoad(counts.seen[index]) == ROUNDS);
    }
    ParallelJob late = ParallelJob(&countItem, counts, 0, ITEMS);
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
        assert(queue.push(value));
    }
    assert(!queue.push(4));
    uint popped;
    assert(queue.pop(popped) && popped == 0);
    assert(queue.push(4));
    foreach (expected; 1 .. 5) {
        assert(queue.pop(popped) && popped == expected);
    }
    assert(!queue.pop(popped));
    queue.release();
}
