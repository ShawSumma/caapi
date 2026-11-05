module base.parallel;

import core.atomic : atomicFetchAdd, atomicLoad, atomicOp, atomicStore, cas;
import core.stdc.stdlib : calloc, free;
import base.clock : Deadline, nowMilliseconds;
import base.numbers : higherOf, lowerOf;

enum uint MAIN_WORKER = 0;
enum size_t CACHE_LINE = 64;
enum size_t GRAINS_PER_PARTICIPANT = 8;

version (WebAssembly) {
    void waitWhile(ref shared uint word, uint expected) {
    }

    void wake(ref shared uint word) {
    }
} else version (OSX) {
    import core.sys.posix.pthread : pthread_create, pthread_join, pthread_t;

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
    import core.sys.posix.pthread : pthread_create, pthread_join, pthread_t;
    import bindings.kernel : CALL_FUTEX, FUTEX_WAIT_HERE, FUTEX_WAKE_HERE;

    enum int WAKE_ALL = int.max;

    extern (C) long syscall(long number, ...) nothrow @nogc;

    void waitWhile(ref shared uint word, uint expected) {
        syscall(CALL_FUTEX, &word, FUTEX_WAIT_HERE, expected, null, null, 0);
    }

    void wake(ref shared uint word) {
        syscall(CALL_FUTEX, &word, FUTEX_WAKE_HERE, WAKE_ALL, null, null, 0);
    }
}

enum Pace : ubyte {
    onTime,
    late,
}

enum PoolLife : ubyte {
    serving,
    stopping,
}

struct ParallelJob {
    void function(void* context, size_t index, uint worker) run;
    void* context;
    Deadline deadline;
    size_t count;
    size_t grain = 1;
    shared size_t claimed;
    shared Pace pace;

    void work(uint worker) {
        Pace current = atomicLoad(pace);
        while (current == Pace.onTime) {
            size_t first = atomicFetchAdd(claimed, grain);
            if (first >= count) {
                return;
            }
            size_t end = lowerOf(first + grain, count);
            foreach (index; first .. end) {
                run(context, index, worker);
            }
            if (deadline.isBounded) {
                double now = nowMilliseconds();
                if (deadline.hasPassed(now)) {
                    atomicStore(pace, Pace.late);
                }
            }
            current = atomicLoad(pace);
        }
    }

    bool hasOpenWork() const {
        size_t taken = atomicLoad(claimed);
        Pace current = atomicLoad(pace);
        return taken < count && current == Pace.onTime;
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
    version (WebAssembly) {
    } else {
        pthread_t* threads;
        WorkerStart* starts;
    }
    shared size_t job;
    shared uint active;
    shared uint epoch;
    shared uint sleepers;
    shared uint joiners;
    shared PoolLife life;
    uint workerCount;
    uint runs;
    double waitedMs = 0;

    static WorkerPool* make(uint workers, TaskSource source) {
        WorkerPool* pool = cast(WorkerPool*) calloc(1, WorkerPool.sizeof);
        pool.source = source;
        pool.workerCount = workers;
        version (WebAssembly) {
            assert(workers == 0);
        } else {
            pool.threads = cast(pthread_t*) calloc(workers, pthread_t.sizeof);
            pool.starts = cast(WorkerStart*) calloc(workers, WorkerStart.sizeof);
            foreach (index; 0 .. workers) {
                pool.starts[index] = WorkerStart(pool, index + 1);
                pthread_create(&pool.threads[index], null, &workerMain, &pool.starts[index]);
            }
        }
        return pool;
    }

    uint participants() const {
        return workerCount + 1;
    }

    void signal() {
        atomicOp!"+="(epoch, 1);
        uint sleeping = atomicLoad(sleepers);
        if (sleeping > 0) {
            wake(epoch);
        }
    }

    void serve(uint worker) {
        PoolLife current = atomicLoad(life);
        while (current == PoolLife.serving) {
            uint seen = atomicLoad(epoch);
            bool worked = joinJob(worker);
            if (!worked) {
                worked = source.take(source.context, worker);
            }
            if (!worked) {
                atomicOp!"+="(sleepers, 1);
                uint latest = atomicLoad(epoch);
                PoolLife standing = atomicLoad(life);
                if (latest == seen && standing == PoolLife.serving) {
                    waitWhile(epoch, seen);
                }
                atomicOp!"-="(sleepers, 1);
            }
            current = atomicLoad(life);
        }
    }

    bool joinJob(uint worker) {
        atomicOp!"+="(active, 1);
        ParallelJob* open = cast(ParallelJob*) atomicLoad(job);
        if (open !is null) {
            bool hasWork = open.hasOpenWork();
            if (hasWork) {
                open.work(worker);
            } else {
                open = null;
            }
        }
        uint inside = atomicOp!"-="(active, 1);
        uint waiting = atomicLoad(joiners);
        if (inside == 0 && waiting != 0) {
            wake(active);
        }
        return open !is null;
    }

    void helpWithJob(uint worker) {
        size_t open = atomicLoad(job);
        if (open != 0) {
            joinJob(worker);
        }
    }

    void run(ParallelJob* parallel) {
        if (!parallel.deadline.isBounded) {
            parallel.grain = grainFor(parallel.count, participants());
        }
        atomicStore(job, cast(size_t) parallel);
        signal();
        parallel.work(MAIN_WORKER);
        atomicStore(job, 0);
        double start = nowMilliseconds();
        atomicStore(joiners, 1);
        uint inside = atomicLoad(active);
        while (inside != 0) {
            waitWhile(active, inside);
            inside = atomicLoad(active);
        }
        atomicStore(joiners, 0);
        parallel.finish();
        runs += 1;
        waitedMs += nowMilliseconds() - start;
    }

    void release() {
        atomicStore(life, PoolLife.stopping);
        signal();
        wake(epoch);
        version (WebAssembly) {
        } else {
            foreach (index; 0 .. workerCount) {
                pthread_join(threads[index], null);
            }
            free(threads);
            free(starts);
        }
    }
}

size_t grainFor(size_t count, uint participants) {
    return higherOf(count / (cast(size_t) participants * GRAINS_PER_PARTICIPANT), size_t(1));
}

version (WebAssembly) {
} else {
    extern (C) void* workerMain(void* argument) {
        WorkerStart* start = cast(WorkerStart*) argument;
        start.pool.serve(start.worker);
        return null;
    }
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
                bool won = cas(&head, position, position + 1);
                if (won) {
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
                bool won = cas(&tail, position, position + 1);
                if (won) {
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
