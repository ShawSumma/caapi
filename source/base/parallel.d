module base.parallel;

import core.atomic : atomicFetchAdd, atomicLoad, atomicOp, atomicStore, cas;
import core.stdc.stdlib : calloc, free;
import core.sys.posix.pthread : pthread_create, pthread_join, pthread_t;
import base.clock : nowMilliseconds;
import base.numbers : higherOf, lowerOf;

enum uint MAIN_WORKER = 0;
enum size_t CACHE_LINE = 64;
enum size_t GRAINS_PER_PARTICIPANT = 8;
enum uint TEST_WORKERS = 3;
enum size_t TEST_ITEMS = 10000;
enum uint TEST_ROUNDS = 50;

version (OSX) {
    enum uint OS_SYNC_NONE = 0;

    extern (C) int os_sync_wait_on_address(shared(void)* address, ulong value, size_t size, uint flags) nothrow @nogc;
    extern (C) int os_sync_wake_by_address_all(shared(void)* address, size_t size, uint flags) nothrow @nogc;

    void waitWhile(ref shared uint word, uint expected) {
        os_sync_wait_on_address(&word, expected, uint.sizeof, OS_SYNC_NONE);
    }

    void wake(ref shared uint word) {
        os_sync_wake_by_address_all(&word, uint.sizeof, OS_SYNC_NONE);
    }
} else {
    version (X86_64) {
        enum long SYS_FUTEX = 202;
    } else version (AArch64) {
        enum long SYS_FUTEX = 98;
    }
    enum int FUTEX_WAIT_PRIVATE = 128;
    enum int FUTEX_WAKE_PRIVATE = 129;
    enum int WAKE_ALL = int.max;

    extern (C) long syscall(long number, ...) nothrow @nogc;

    void waitWhile(ref shared uint word, uint expected) {
        syscall(SYS_FUTEX, &word, FUTEX_WAIT_PRIVATE, expected, null, null, 0);
    }

    void wake(ref shared uint word) {
        syscall(SYS_FUTEX, &word, FUTEX_WAKE_PRIVATE, WAKE_ALL, null, null, 0);
    }
}

struct ParallelJob {
    void function(void* context, size_t index, uint worker) run;
    void* context;
    double deadline;
    size_t count;
    size_t grain = 1;
    shared size_t claimed;
    shared bool isLate;

    void work(uint worker) {
        bool isDone = false;
        while (!isDone && !atomicLoad(isLate)) {
            size_t first = atomicFetchAdd(claimed, grain);
            isDone = first >= count;
            if (!isDone) {
                size_t end = lowerOf(first + grain, count);
                foreach (index; first .. end) {
                    run(context, index, worker);
                }
                if (deadline != double.infinity && nowMilliseconds() >= deadline) {
                    atomicStore(isLate, true);
                }
            }
        }
    }

    void finish() {
        count = lowerOf(count, atomicLoad(claimed));
    }
}

struct TaskSource {
    bool function(void* context, uint worker) take;
    void* context;
}

struct WorkerStart {
    WorkerPool* pool;
    uint worker;
}

struct WorkerPool {
    TaskSource source;
    pthread_t* threads;
    WorkerStart* starts;
    shared size_t job;
    shared uint active;
    shared uint epoch;
    shared uint sleepers;
    shared uint isJoining;
    shared bool isStopping;
    uint workerCount;
    uint runs;
    double waitedMs = 0;

    static WorkerPool* make(uint workers, TaskSource source) {
        WorkerPool* pool = cast(WorkerPool*) calloc(1, WorkerPool.sizeof);
        pool.source = source;
        pool.workerCount = workers;
        pool.threads = cast(pthread_t*) calloc(workers, pthread_t.sizeof);
        pool.starts = cast(WorkerStart*) calloc(workers, WorkerStart.sizeof);
        foreach (index; 0 .. workers) {
            pool.starts[index] = WorkerStart(pool, index + 1);
            pthread_create(&pool.threads[index], null, &workerMain, &pool.starts[index]);
        }
        return pool;
    }

    uint participants() const {
        return workerCount + 1;
    }

    void signal() {
        atomicOp!"+="(epoch, 1);
        if (atomicLoad(sleepers) > 0) {
            wake(epoch);
        }
    }

    void serve(uint worker) {
        while (!atomicLoad(isStopping)) {
            uint seen = atomicLoad(epoch);
            if (!joinJob(worker) && !source.take(source.context, worker)) {
                atomicOp!"+="(sleepers, 1);
                if (atomicLoad(epoch) == seen && !atomicLoad(isStopping)) {
                    waitWhile(epoch, seen);
                }
                atomicOp!"-="(sleepers, 1);
            }
        }
    }

    bool joinJob(uint worker) {
        atomicOp!"+="(active, 1);
        ParallelJob* current = cast(ParallelJob*) atomicLoad(job);
        bool hasWork = current !is null && atomicLoad(current.claimed) < current.count && !atomicLoad(current.isLate);
        if (hasWork) {
            current.work(worker);
        }
        if (atomicOp!"-="(active, 1) == 0 && atomicLoad(isJoining) != 0) {
            wake(active);
        }
        return hasWork;
    }

    void helpWithJob(uint worker) {
        if (atomicLoad(job) != 0) {
            joinJob(worker);
        }
    }

    void run(ParallelJob* parallel) {
        if (parallel.deadline == double.infinity) {
            parallel.grain = grainFor(parallel.count, participants());
        }
        atomicStore(job, cast(size_t) parallel);
        signal();
        parallel.work(MAIN_WORKER);
        atomicStore(job, 0);
        double start = nowMilliseconds();
        atomicStore(isJoining, 1);
        uint inside = atomicLoad(active);
        while (inside != 0) {
            waitWhile(active, inside);
            inside = atomicLoad(active);
        }
        atomicStore(isJoining, 0);
        parallel.finish();
        runs += 1;
        waitedMs += nowMilliseconds() - start;
    }

    void release() {
        atomicStore(isStopping, true);
        signal();
        wake(epoch);
        foreach (index; 0 .. workerCount) {
            pthread_join(threads[index], null);
        }
        free(threads);
        free(starts);
    }
}

size_t grainFor(size_t count, uint participants) {
    return higherOf(count / (cast(size_t) participants * GRAINS_PER_PARTICIPANT), size_t(1));
}

extern (C) void* workerMain(void* argument) {
    WorkerStart* start = cast(WorkerStart*) argument;
    start.pool.serve(start.worker);
    return null;
}

struct Executor {
    WorkerPool* pool;

    uint workers() const {
        if (pool is null) {
            return 1;
        } else {
            return pool.participants();
        }
    }

    void run(ParallelJob* job) {
        if (pool is null) {
            job.work(MAIN_WORKER);
            job.finish();
        } else {
            pool.run(job);
        }
    }
}

struct QueueCell(T) {
    shared size_t sequence;
    T value;
}

struct ConcurrentQueue(T) {
    QueueCell!T* cells;
    size_t mask;
    ubyte[CACHE_LINE] beforeHead;
    shared size_t head;
    ubyte[CACHE_LINE] beforeTail;
    shared size_t tail;
    ubyte[CACHE_LINE] afterTail;

    static ConcurrentQueue make(size_t capacity) {
        assert((capacity & (capacity - 1)) == 0);
        ConcurrentQueue queue;
        queue.cells = cast(QueueCell!T*) calloc(capacity, QueueCell!T.sizeof);
        queue.mask = capacity - 1;
        foreach (index; 0 .. capacity) {
            atomicStore(queue.cells[index].sequence, index);
        }
        return queue;
    }

    bool push(T value) {
        size_t position = atomicLoad(head);
        while (true) {
            QueueCell!T* cell = &cells[position & mask];
            ptrdiff_t difference = cast(ptrdiff_t)(atomicLoad(cell.sequence) - position);
            if (difference == 0) {
                if (cas(&head, position, position + 1)) {
                    cell.value = value;
                    atomicStore(cell.sequence, position + 1);
                    return true;
                }
                position = atomicLoad(head);
            } else if (difference < 0) {
                return false;
            } else {
                position = atomicLoad(head);
            }
        }
    }

    bool pop(ref T value) {
        size_t position = atomicLoad(tail);
        while (true) {
            QueueCell!T* cell = &cells[position & mask];
            ptrdiff_t difference = cast(ptrdiff_t)(atomicLoad(cell.sequence) - (position + 1));
            if (difference == 0) {
                if (cas(&tail, position, position + 1)) {
                    value = cell.value;
                    atomicStore(cell.sequence, position + mask + 1);
                    return true;
                }
                position = atomicLoad(tail);
            } else if (difference < 0) {
                return false;
            } else {
                position = atomicLoad(tail);
            }
        }
    }

    void release() {
        free(cells);
        cells = null;
    }
}

struct TestCounts {
    shared uint[TEST_ITEMS] seen;
}

void countItem(void* context, size_t index, uint worker) {
    atomicOp!"+="((cast(TestCounts*) context).seen[index], 1);
}

bool takeNothing(void* context, uint worker) {
    return false;
}

unittest {
    WorkerPool* pool = WorkerPool.make(TEST_WORKERS, TaskSource(&takeNothing, null));
    TestCounts* counts = cast(TestCounts*) calloc(1, TestCounts.sizeof);
    foreach (round; 0 .. TEST_ROUNDS) {
        ParallelJob job = ParallelJob(&countItem, counts, double.infinity, TEST_ITEMS);
        pool.run(&job);
        assert(job.count == TEST_ITEMS);
    }
    foreach (index; 0 .. TEST_ITEMS) {
        assert(atomicLoad(counts.seen[index]) == TEST_ROUNDS);
    }
    ParallelJob late = ParallelJob(&countItem, counts, 0, TEST_ITEMS);
    pool.run(&late);
    assert(late.count >= 1 && late.count < TEST_ITEMS);
    foreach (index; 0 .. TEST_ITEMS) {
        uint expected = TEST_ROUNDS;
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
