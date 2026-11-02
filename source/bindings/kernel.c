#ifndef __APPLE__

#undef __SIZEOF_INT128__
#include <linux/futex.h>
#include <signal.h>
#include <sys/syscall.h>

enum {
    CALL_FUTEX = SYS_futex,
    CALL_GETTID = SYS_gettid,
    FUTEX_WAIT_HERE = FUTEX_WAIT_PRIVATE,
    FUTEX_WAKE_HERE = FUTEX_WAKE_PRIVATE,
    SIGNAL_ONE_THREAD = SIGEV_THREAD_ID,
};

#endif
