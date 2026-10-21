module base.crash;

import core.stdc.signal : SIGABRT, SIGFPE, SIGILL, SIGSEGV;
import core.stdc.stdlib : _Exit;
version (OSX) {
    import core.sys.darwin.execinfo : backtrace, backtrace_symbols_fd;
} else {
    import core.sys.linux.execinfo : backtrace, backtrace_symbols_fd;
}
import core.sys.posix.signal : SA_RESETHAND, SIGALRM, SIGBUS, SIGTRAP, sigaction, sigaction_t, sigemptyset;
import core.sys.posix.unistd : STDERR_FILENO, alarm, write;

enum uint CRASH_FRAMES = 64;
enum int CRASH_STATUS = 128;
immutable int[6] CRASH_SIGNALS = [SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE, SIGABRT];

void reportCrashes() {
    void*[1] warm;
    backtrace(warm.ptr, 1);
    foreach (signal; CRASH_SIGNALS) {
        reportOn(signal);
    }
}

void reportHangAfter(uint seconds) {
    reportOn(SIGALRM);
    alarm(seconds);
}

void reportOn(int signal) {
    sigaction_t action;
    action.sa_handler = &printCrash;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_RESETHAND;
    sigaction(signal, &action, null);
}

extern (C) void printCrash(int signal) nothrow @nogc {
    string heading ="crashed, backtrace:\n";
    write(STDERR_FILENO, heading.ptr, heading.length);
    void*[CRASH_FRAMES] frames;
    int depth = backtrace(frames.ptr, CRASH_FRAMES);
    backtrace_symbols_fd(frames.ptr, depth, STDERR_FILENO);
    _Exit(CRASH_STATUS + signal);
}
