module base.pages;

import core.sys.posix.sys.mman : MAP_ANON, MAP_PRIVATE, PROT_READ, PROT_WRITE, mmap, munmap;
import core.sys.posix.unistd : _SC_PAGESIZE, sysconf;

version (OSX) {
    enum int MADV_DONTNEED = 4;

    extern (C) int madvise(void* address, size_t length, int advice) nothrow @nogc;
} else {
    import core.sys.linux.sys.mman : MADV_DONTNEED, madvise;
}

// Memory mapped straight from the system and zero filled. Unmapping it returns it at once, where malloc would keep
// freed blocks for reuse and leave the process holding its peak.
void* mapPages(size_t size) {
    return mmap(null, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
}

void unmapPages(void* memory, size_t size) {
    munmap(memory, size);
}

size_t pageSize() {
    return sysconf(_SC_PAGESIZE);
}

// Returns the whole pages between two byte offsets to the system. Linux reads them back as zero; macOS may instead keep
// what they held.
void giveBack(void* base, size_t from, size_t to) {
    size_t page = pageSize();
    size_t start = (cast(size_t) base + from + page - 1) & ~(page - 1);
    size_t end = (cast(size_t) base + to) & ~(page - 1);
    if (end > start) {
        madvise(cast(void*) start, end - start, MADV_DONTNEED);
    }
}
