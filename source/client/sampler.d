module client.sampler;

import core.atomic : atomicLoad, atomicOp, atomicStore;
import core.stdc.stdio : FILE, fprintf, snprintf;
import core.stdc.stdlib : calloc, free;
import core.sys.posix.pthread : pthread_equal, pthread_self, pthread_t;
import core.sys.posix.signal : SA_RESTART, SIGPROF, sigaction, sigaction_t, sigemptyset;
import core.sys.posix.sys.time : itimerval, setitimer, timeval;
import base.array : Array;
import base.flags : Bits;
import base.hashmap : FIBONACCI_MULTIPLIER, HashMap;
import base.numbers : lowerOf;

enum uint SAMPLE_FRAMES = 48;
enum uint SAMPLE_CAPACITY = 1 << 18;
enum uint SIGNAL_FRAMES = 2;
enum int SAMPLE_MICROSECONDS = 4000;
enum uint LISTED_FUNCTIONS = 60;
enum uint LISTED_CALLEES = 30;
enum uint LISTED_CALLERS = 4;
enum double SHARED_FRAME_PERCENT = 90.0;
enum size_t NAME_CAPACITY = 160;
enum long NANOSECONDS_PER_MICROSECOND = 1000;

version (OSX) {
    import core.sys.darwin.dlfcn : Dl_info, dladdr;
    import core.sys.darwin.execinfo : backtrace;

    enum int ITIMER_PROF = 2;
    enum long MAIN_SAMPLE_NANOSECONDS = SAMPLE_MICROSECONDS * NANOSECONDS_PER_MICROSECOND;

    extern (C) int* __error() nothrow @nogc;

    alias errnoLocation = __error;
} else {
    import core.sys.linux.dlfcn : Dl_info, dladdr;
    import core.sys.linux.execinfo : backtrace;
    import core.sys.posix.signal : sigevent;
    import core.sys.posix.sys.time : ITIMER_PROF;
    import core.sys.posix.time : CLOCK_THREAD_CPUTIME_ID, itimerspec, timer_create, timer_delete, timer_settime, timer_t, timespec;
    import base.parallel : syscall;
    import bindings.kernel : CALL_GETTID, SIGNAL_ONE_THREAD;

    enum long MAIN_SAMPLE_NANOSECONDS = 500_000;

    extern (C) int* __errno_location() nothrow @nogc;
    extern (C) int __libc_current_sigrtmin() nothrow @nogc;

    alias errnoLocation = __errno_location;
}

enum SampledThread : ubyte {
    worker,
    main,
}

enum SamplerState : ubyte {
    stopped,
    running,
}

struct Sample {
    void*[SAMPLE_FRAMES] frames;
    int depth;
    SampledThread thread;
}

__gshared Sample* samples;
__gshared pthread_t mainThread;
shared uint sampleCount;

extern (C) void recordWorkerSample(int signal) {
    if (pthread_equal(pthread_self(), mainThread) == 0) {
        record(SampledThread.worker);
    }
}

extern (C) void recordMainSample(int signal) {
    record(SampledThread.main);
}

extern (C) void recordAnySample(int signal) {
    if (pthread_equal(pthread_self(), mainThread) != 0) {
        record(SampledThread.main);
    } else {
        record(SampledThread.worker);
    }
}

void record(SampledThread thread) {
    int saved = *errnoLocation();
    uint index = atomicOp!"+="(sampleCount, 1) - 1;
    if (index < SAMPLE_CAPACITY) {
        Sample* sample = &samples[index];
        sample.depth = backtrace(sample.frames.ptr, SAMPLE_FRAMES);
        sample.thread = thread;
    }
    *errnoLocation() = saved;
}

struct AddressKey {
    size_t address;

    size_t toHash() const {
        return address * FIBONACCI_MULTIPLIER;
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
        return (cast(size_t) callee << 32 | caller) * FIBONACCI_MULTIPLIER;
    }
}

struct CallCounts {
    CallKey key;
    uint main;
    uint lastSample;
}

struct Sampler {
    version (OSX) {
    } else {
        timer_t mainTimer;
    }
    SamplerState state;

    void start() {
        if (samples is null) {
            samples = cast(Sample*) calloc(SAMPLE_CAPACITY, Sample.sizeof);
            void*[1] warm;
            backtrace(warm.ptr, 1);
        }
        mainThread = pthread_self();
        atomicStore(sampleCount, 0);
        version (OSX) {
            handle(SIGPROF, &recordAnySample);
        } else {
            handle(SIGPROF, &recordWorkerSample);
            handle(__libc_current_sigrtmin(), &recordMainSample);
            sigevent event;
            event.sigev_notify = SIGNAL_ONE_THREAD;
            event.sigev_signo = __libc_current_sigrtmin();
            event._tid = cast(int) syscall(CALL_GETTID);
            timer_create(CLOCK_THREAD_CPUTIME_ID, &event, &mainTimer);
            itimerspec mainPeriod = itimerspec(timespec(0, MAIN_SAMPLE_NANOSECONDS), timespec(0, MAIN_SAMPLE_NANOSECONDS));
            timer_settime(mainTimer, 0, &mainPeriod, null);
        }
        itimerval timer = itimerval(timeval(0, SAMPLE_MICROSECONDS), timeval(0, SAMPLE_MICROSECONDS));
        setitimer(ITIMER_PROF, &timer, null);
        state = SamplerState.running;
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
        version (OSX) {
        } else {
            timer_delete(mainTimer);
        }
        state = SamplerState.stopped;
    }

    void report(FILE* output, const(char)* title) {
        stop();
        uint taken = atomicLoad(sampleCount);
        uint count = lowerOf(taken, SAMPLE_CAPACITY);
        HashMap!(AddressKey, uint) byAddress;
        HashMap!(AddressKey, uint) byStart;
        HashMap!(CallKey, uint) callIndex;
        Array!FunctionCounts functions;
        Array!CallCounts calls;
        uint mainSamples = 0;
        uint workerSamples = 0;
        foreach (index; 0 .. count) {
            Sample* sample = &samples[index];
            if (sample.thread == SampledThread.main) {
                mainSamples += 1;
            } else {
                workerSamples += 1;
            }
            uint callee = uint.max;
            foreach (depth; SIGNAL_FRAMES .. sample.depth) {
                uint current = functionOf(sample.frames[depth], byAddress, byStart, functions);
                FunctionCounts* counts = &functions.ptr[current];
                uint lastSeen = counts.lastSample;
                counts.lastSample = index + 1;
                if (sample.thread == SampledThread.main) {
                    if (depth == SIGNAL_FRAMES) {
                        counts.selfMain += 1;
                    }
                    if (lastSeen != index + 1) {
                        counts.totalMain += 1;
                    }
                    if (callee != uint.max && callee != current) {
                        countCall(CallKey(callee, current), index, callIndex, calls);
                    }
                } else {
                    if (depth == SIGNAL_FRAMES) {
                        counts.selfWorker += 1;
                    }
                    if (lastSeen != index + 1) {
                        counts.totalWorker += 1;
                    }
                }
                callee = current;
            }
        }
        fprintf(output, "profile %s: main %u samples of %ldus of its cpu, workers %u samples of %dus of process cpu (%u dropped)\n", title, mainSamples, MAIN_SAMPLE_NANOSECONDS / NANOSECONDS_PER_MICROSECOND, workerSamples, SAMPLE_MICROSECONDS, taken - count);
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
        if (state == SamplerState.running) {
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
        while (written + 1 < NAME_CAPACITY && (isDigit(*cursor) || isTemplateMark(cursor))) {
            char joiner = '.';
            if (isTemplateMark(cursor)) {
                joiner = '!';
                cursor += 3;
            }
            size_t length = 0;
            while (isDigit(*cursor)) {
                length = length * 10 + (*cursor - '0');
                cursor += 1;
            }
            if (written > 0) {
                name[written] = joiner;
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
            if (joiner == '!') {
                break;
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
    Bits listed;
    listed.cover(functions.length);
    uint count = 0;
    while (samples > 0 && count < LISTED_CALLEES) {
        size_t best = functions.length;
        foreach (index, ref counts; functions.slice()) {
            if (!listed.has(index) && 100.0 * counts.totalMain / samples < SHARED_FRAME_PERCENT && counts.totalMain > 0 && (best == functions.length || counts.totalMain > functions.ptr[best].totalMain)) {
                best = index;
            }
        }
        if (best == functions.length) {
            break;
        }
        listed.set(best);
        fprintf(output, "    %5.1f  %s\n", 100.0 * functions.ptr[best].totalMain / samples, functions.ptr[best].name.ptr);
        listCallersOf(output, functions, calls, cast(uint) best, samples);
        count += 1;
    }
    listed.release();
}

void listCallersOf(FILE* output, ref Array!FunctionCounts functions, ref Array!CallCounts calls, uint callee, uint samples) {
    Bits listed;
    listed.cover(calls.length);
    uint count = 0;
    while (count < LISTED_CALLERS) {
        size_t best = calls.length;
        foreach (index, ref counts; calls.slice()) {
            if (!listed.has(index) && counts.key.callee == callee && (best == calls.length || counts.main > calls.ptr[best].main)) {
                best = index;
            }
        }
        if (best == calls.length) {
            break;
        }
        listed.set(best);
        fprintf(output, "           %5.1f  from %s\n", 100.0 * calls.ptr[best].main / samples, functions.ptr[calls.ptr[best].key.caller].name.ptr);
        count += 1;
    }
    listed.release();
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
    Bits listed;
    listed.cover(functions.length);
    uint count = 0;
    while (samples > 0 && count < LISTED_FUNCTIONS) {
        size_t best = functions.length;
        foreach (index, ref counts; functions.slice()) {
            if (!listed.has(index) && countIn(counts, rank) > 0 && (best == functions.length || countIn(counts, rank) > countIn(functions.ptr[best], rank))) {
                best = index;
            }
        }
        if (best == functions.length) {
            break;
        }
        listed.set(best);
        FunctionCounts* counts = &functions.ptr[best];
        fprintf(output, "    %5.1f %5.1f  %s\n", 100.0 * countIn(*counts, total) / samples, 100.0 * countIn(*counts, self) / samples, counts.name.ptr);
        count += 1;
    }
    listed.release();
}
