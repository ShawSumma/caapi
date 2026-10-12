module common.parallel;

import common.clock : nowMilliseconds;

struct ParallelJob {
    void function(void* context, size_t index, uint worker) run;
    void* context;
    double deadline;
    size_t count;
    size_t claimed;
    size_t finished;
}

struct Executor {
    void function(void* context, ParallelJob* job) start;
    void* context;
    uint workers = 1;

    void run(ParallelJob* job) {
        if (start is null) {
            while (job.claimed < job.count) {
                job.claimed += 1;
                job.run(job.context, job.claimed - 1, 0);
                if (nowMilliseconds() >= job.deadline) {
                    job.count = job.claimed;
                }
            }
            job.finished = job.count;
        } else {
            start(context, job);
        }
    }
}
