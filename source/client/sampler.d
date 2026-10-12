module client.sampler;

import core.atomic : atomicLoad, atomicOp, atomicStore;
import core.stdc.stdio : FILE, fprintf, snprintf;
import core.stdc.stdlib : calloc, free;
import core.sys.linux.dlfcn : Dl_info, dladdr;
import core.sys.linux.execinfo : backtrace;
import core.sys.posix.pthread : pthread_equal, pthread_self, pthread_t;
import core.sys.posix.signal : SA_RESTART, SIGPROF, sigaction, sigaction_t, sigemptyset, sigevent;
import core.sys.posix.sys.time : ITIMER_PROF, itimerval, setitimer, timeval;
import core.sys.posix.time : CLOCK_THREAD_CPUTIME_ID, itimerspec, timer_create, timer_delete, timer_settime, timer_t, timespec;
import base.array : Array;
import base.hashmap : HashMap;
import base.parallel : syscall;

version (X86_64) {
    enum long SYS_GETTID = 186;
} else version (AArch64) {
    enum long SYS_GETTID = 178;
}
enum int SIGEV_THREAD_ID = 4;
enum uint SAMPLE_FRAMES = 48;
enum uint SAMPLE_CAPACITY = 1 << 18;
enum uint SIGNAL_FRAMES = 2;
enum int SAMPLE_MICROSECONDS = 4000;
enum long MAIN_SAMPLE_NANOSECONDS = 500_000;
enum uint LISTED_FUNCTIONS = 60;
enum uint LISTED_CALLEES = 30;
enum uint LISTED_CALLERS = 4;
enum double SHARED_FRAME_PERCENT = 90.0;
enum size_t NAME_CAPACITY = 160;
enum size_t ADDRESS_HASH_MULTIPLIER = 0x9E3779B97F4A7C15;

extern (C) int* __errno_location() nothrow @nogc;
extern (C) int __libc_current_sigrtmin() nothrow @nogc;

struct Sample {
    void*[SAMPLE_FRAMES] frames;
    int depth;
    bool isMain;
}

__gshared Sample* samples;
__gshared pthread_t mainThread;
shared uint sampleCount;

// The process timer lands mostly on whichever threads are busiest, so the main thread has a timer of its own and the
// process timer only samples the other threads.
extern (C) void recordWorkerSample(int signal) {
    if (pthread_equal(pthread_self(), mainThread) == 0) {
        record(false);
    }
}

extern (C) void recordMainSample(int signal) {
    record(true);
}

void record(bool isMain) {
    int saved = *__errno_location();
    uint index = atomicOp!"+="(sampleCount, 1) - 1;
    if (index < SAMPLE_CAPACITY) {
        Sample* sample = &samples[index];
        sample.depth = backtrace(sample.frames.ptr, SAMPLE_FRAMES);
        sample.isMain = isMain;
    }
    *__errno_location() = saved;
}

struct AddressKey {
    size_t address;

    size_t toHash() const {
        return address * ADDRESS_HASH_MULTIPLIER;
    }
}

struct FunctionCounts {
    char[NAME_CAPACITY] name;
    uint selfMain;
    uint totalMain;
    uint selfWorker;
    uint totalWorker;
    uint lastSample;
}

struct CallKey {
    uint callee;
    uint caller;

    size_t toHash() const {
        return (cast(size_t) callee << 32 | caller) * ADDRESS_HASH_MULTIPLIER;
    }
}

struct CallCounts {
    CallKey key;
    uint main;
    uint lastSample;
}

struct Sampler {
    timer_t mainTimer;
    bool isRunning;

    void start() {
        if (samples is null) {
            samples = cast(Sample*) calloc(SAMPLE_CAPACITY, Sample.sizeof);
            void*[1] warm;
            backtrace(warm.ptr, 1);
        }
        mainThread = pthread_self();
        atomicStore(sampleCount, 0);
        handle(SIGPROF, &recordWorkerSample);
        handle(__libc_current_sigrtmin(), &recordMainSample);
        sigevent event;
        event.sigev_notify = SIGEV_THREAD_ID;
        event.sigev_signo = __libc_current_sigrtmin();
        event._tid = cast(int) syscall(SYS_GETTID);
        timer_create(CLOCK_THREAD_CPUTIME_ID, &event, &mainTimer);
        itimerspec mainPeriod = itimerspec(timespec(0, MAIN_SAMPLE_NANOSECONDS), timespec(0, MAIN_SAMPLE_NANOSECONDS));
        timer_settime(mainTimer, 0, &mainPeriod, null);
        itimerval timer = itimerval(timeval(0, SAMPLE_MICROSECONDS), timeval(0, SAMPLE_MICROSECONDS));
        setitimer(ITIMER_PROF, &timer, null);
        isRunning = true;
    }

    void handle(int signal, typeof(sigaction_t.sa_handler) handler) {
        sigaction_t action;
        action.sa_handler = handler;
        sigemptyset(&action.sa_mask);
        action.sa_flags = SA_RESTART;
        sigaction(signal, &action, null);
    }

    void stop() {
        itimerval timer;
        setitimer(ITIMER_PROF, &timer, null);
        timer_delete(mainTimer);
        isRunning = false;
    }

    void report(FILE* output, const(char)* title) {
        stop();
        uint taken = atomicLoad(sampleCount);
        uint count = taken < SAMPLE_CAPACITY ? taken : SAMPLE_CAPACITY;
        HashMap!(AddressKey, uint) byAddress;
        HashMap!(AddressKey, uint) byStart;
        HashMap!(CallKey, uint) callIndex;
        Array!FunctionCounts functions;
        Array!CallCounts calls;
        uint mainSamples = 0;
        uint workerSamples = 0;
        foreach (index; 0 .. count) {
            Sample* sample = &samples[index];
            if (sample.isMain) {
                mainSamples += 1;
            } else {
                workerSamples += 1;
            }
            uint callee = uint.max;
            foreach (depth; SIGNAL_FRAMES .. sample.depth) {
                uint current = functionOf(sample.frames[depth], byAddress, byStart, functions);
                FunctionCounts* counts = &functions.ptr[current];
                bool isSelf = depth == SIGNAL_FRAMES;
                bool isFirst = counts.lastSample != index + 1;
                counts.lastSample = index + 1;
                if (sample.isMain) {
                    counts.selfMain += isSelf;
                    counts.totalMain += isFirst;
                    if (callee != uint.max && callee != current) {
                        countCall(CallKey(callee, current), index, callIndex, calls);
                    }
                } else {
                    counts.selfWorker += isSelf;
                    counts.totalWorker += isFirst;
                }
                callee = current;
            }
        }
        fprintf(output, "profile %s: main %u samples of %ldus of its cpu, workers %u samples of %dus of process cpu (%u dropped)\n", title, mainSamples, MAIN_SAMPLE_NANOSECONDS / 1000, workerSamples, SAMPLE_MICROSECONDS, taken - count);
        listTop(output, "main by total", functions, mainSamples, Column.totalMain, Column.selfMain, Column.totalMain);
        listTop(output, "main by self", functions, mainSamples, Column.selfMain, Column.selfMain, Column.totalMain);
        listTop(output, "workers by total", functions, workerSamples, Column.totalWorker, Column.selfWorker, Column.totalWorker);
        listTop(output, "workers by self", functions, workerSamples, Column.selfWorker, Column.selfWorker, Column.totalWorker);
        listCallers(output, functions, calls, mainSamples);
        byAddress.release();
        byStart.release();
        callIndex.release();
        functions.release();
        calls.release();
    }

    void release() {
        if (isRunning) {
            stop();
        }
        free(samples);
        samples = null;
    }
}

uint functionOf(void* frame, ref HashMap!(AddressKey, uint) byAddress, ref HashMap!(AddressKey, uint) byStart, ref Array!FunctionCounts functions) {
    AddressKey address = AddressKey(cast(size_t) frame);
    const(uint)* known = byAddress.find(address);
    if (known !is null) {
        return *known;
    } else {
        Dl_info info;
        AddressKey start = address;
        const(char)* symbol = null;
        if (dladdr(frame, &info) != 0 && info.dli_saddr !is null) {
            start = AddressKey(cast(size_t) info.dli_saddr);
            symbol = info.dli_sname;
        }
        const(uint)* existing = byStart.find(start);
        uint index = void;
        if (existing !is null) {
            index = *existing;
        } else {
            index = cast(uint) functions.length;
            functions.append(FunctionCounts.init);
            readableName(symbol, start.address, functions.ptr[index].name);
            byStart.insert(start, index);
        }
        byAddress.insert(address, index);
        return index;
    }
}

void readableName(const(char)* symbol, size_t start, ref char[NAME_CAPACITY] name) {
    if (symbol is null) {
        snprintf(name.ptr, NAME_CAPACITY, "?%zx", start);
    } else if (symbol[0] == '_' && symbol[1] == 'D' && symbol[2] >= '0' && symbol[2] <= '9') {
        size_t written = 0;
        const(char)* cursor = symbol + 2;
        bool isTemplate = false;
        while (written + 1 < NAME_CAPACITY && !isTemplate && (isDigit(*cursor) || isTemplateMark(cursor))) {
            isTemplate = isTemplateMark(cursor);
            if (isTemplate) {
                cursor += 3;
            }
            size_t length = 0;
            while (isDigit(*cursor)) {
                length = length * 10 + (*cursor - '0');
                cursor += 1;
            }
            if (written > 0) {
                name[written] = isTemplate ? '!' : '.';
                written += 1;
            }
            foreach (_; 0 .. length) {
                if (*cursor != 0 && written + 1 < NAME_CAPACITY) {
                    name[written] = *cursor;
                    written += 1;
                }
                if (*cursor != 0) {
                    cursor += 1;
                }
            }
        }
        name[written] = 0;
    } else {
        snprintf(name.ptr, NAME_CAPACITY, "%s", symbol);
    }
}

void countCall(CallKey key, uint sample, ref HashMap!(CallKey, uint) callIndex, ref Array!CallCounts calls) {
    const(uint)* known = callIndex.find(key);
    uint index = void;
    if (known !is null) {
        index = *known;
    } else {
        index = cast(uint) calls.length;
        calls.append(CallCounts(key, 0, 0));
        callIndex.insert(key, index);
    }
    CallCounts* counts = &calls.ptr[index];
    if (counts.lastSample != sample + 1) {
        counts.lastSample = sample + 1;
        counts.main += 1;
    }
}

void listCallers(FILE* output, ref Array!FunctionCounts functions, ref Array!CallCounts calls, uint samples) {
    fprintf(output, "  main callers of the heaviest functions (total%%):\n");
    Array!bool isListed;
    isListed.resize(functions.length);
    uint listed = 0;
    bool isExhausted = samples == 0;
    while (listed < LISTED_CALLEES && !isExhausted) {
        size_t best = functions.length;
        foreach (index, ref counts; functions.slice()) {
            bool isShared = 100.0 * counts.totalMain / samples >= SHARED_FRAME_PERCENT;
            if (!isListed.ptr[index] && !isShared && counts.totalMain > 0 && (best == functions.length || counts.totalMain > functions.ptr[best].totalMain)) {
                best = index;
            }
        }
        isExhausted = best == functions.length;
        if (!isExhausted) {
            isListed.ptr[best] = true;
            fprintf(output, "    %5.1f  %s\n", 100.0 * functions.ptr[best].totalMain / samples, functions.ptr[best].name.ptr);
            listCallersOf(output, functions, calls, cast(uint) best, samples);
            listed += 1;
        }
    }
    isListed.release();
}

void listCallersOf(FILE* output, ref Array!FunctionCounts functions, ref Array!CallCounts calls, uint callee, uint samples) {
    Array!bool isListed;
    isListed.resize(calls.length);
    uint listed = 0;
    bool isExhausted = false;
    while (listed < LISTED_CALLERS && !isExhausted) {
        size_t best = calls.length;
        foreach (index, ref counts; calls.slice()) {
            if (!isListed.ptr[index] && counts.key.callee == callee && (best == calls.length || counts.main > calls.ptr[best].main)) {
                best = index;
            }
        }
        isExhausted = best == calls.length;
        if (!isExhausted) {
            isListed.ptr[best] = true;
            fprintf(output, "           %5.1f  from %s\n", 100.0 * calls.ptr[best].main / samples, functions.ptr[calls.ptr[best].key.caller].name.ptr);
            listed += 1;
        }
    }
    isListed.release();
}

bool isDigit(char text) {
    return text >= '0' && text <= '9';
}

bool isTemplateMark(const(char)* text) {
    return text[0] == '_' && text[1] == '_' && text[2] == 'T';
}

enum Column : ubyte {
    selfMain,
    totalMain,
    selfWorker,
    totalWorker,
}

uint countIn(ref const FunctionCounts counts, Column column) {
    final switch (column) {
        case Column.selfMain:
            return counts.selfMain;
        case Column.totalMain:
            return counts.totalMain;
        case Column.selfWorker:
            return counts.selfWorker;
        case Column.totalWorker:
            return counts.totalWorker;
    }
}

void listTop(FILE* output, const(char)* heading, ref Array!FunctionCounts functions, uint samples, Column rank, Column self, Column total) {
    fprintf(output, "  %s (total%% self%%):\n", heading);
    Array!bool isListed;
    isListed.resize(functions.length);
    uint listed = 0;
    bool isExhausted = samples == 0;
    while (listed < LISTED_FUNCTIONS && !isExhausted) {
        size_t best = functions.length;
        foreach (index, ref counts; functions.slice()) {
            if (!isListed.ptr[index] && countIn(counts, rank) > 0 && (best == functions.length || countIn(counts, rank) > countIn(functions.ptr[best], rank))) {
                best = index;
            }
        }
        isExhausted = best == functions.length;
        if (!isExhausted) {
            isListed.ptr[best] = true;
            FunctionCounts* counts = &functions.ptr[best];
            fprintf(output, "    %5.1f %5.1f  %s\n", 100.0 * countIn(*counts, total) / samples, 100.0 * countIn(*counts, self) / samples, counts.name.ptr);
            listed += 1;
        }
    }
    isListed.release();
}
