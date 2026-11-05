module base.pages;

version (WebAssembly) {
    import core.stdc.stdlib : calloc, free;

    enum size_t WASM_PAGE_BYTES = 65536;

    void* mapPages(size_t size) {
        void* memory = calloc(size, 1);
        assert(memory !is null);
        return memory;
    }

    void unmapPages(void* memory, size_t size) {
        free(memory);
    }

    size_t pageSize() {
        return WASM_PAGE_BYTES;
    }

    void giveBack(void* base, size_t from, size_t to) {
    }
} else {
    import core.atomic : MemoryOrder, atomicLoad, atomicStore;
    import core.sys.posix.sys.mman : MAP_ANON, MAP_PRIVATE, PROT_READ, PROT_WRITE, mmap, munmap;
    import core.sys.posix.unistd : _SC_PAGESIZE, sysconf;

    version (OSX) {
        enum int MADV_DONTNEED = 4;

        extern (C) int madvise(void* address, size_t length, int advice) nothrow @nogc;
    } else {
        import core.sys.linux.sys.mman : MADV_DONTNEED, madvise;
    }

    void* mapPages(size_t size) {
        return mmap(null, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    }

    void unmapPages(void* memory, size_t size) {
        munmap(memory, size);
    }

    shared size_t pageBytes;

    size_t pageSize() {
        size_t known = atomicLoad!(MemoryOrder.raw)(pageBytes);
        if (known == 0) {
            known = sysconf(_SC_PAGESIZE);
            atomicStore!(MemoryOrder.raw)(pageBytes, known);
        }
        return known;
    }

    void giveBack(void* base, size_t from, size_t to) {
        size_t page = pageSize();
        size_t start = (cast(size_t) base + from + page - 1) & ~(page - 1);
        size_t end = (cast(size_t) base + to) & ~(page - 1);
        if (end > start) {
            madvise(cast(void*) start, end - start, MADV_DONTNEED);
        }
    }
}
