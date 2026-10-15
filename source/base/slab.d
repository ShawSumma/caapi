module base.slab;

import core.bitop : bsf, bsr;
import base.array : Array;
import base.pages : giveBack, mapPages, pageSize, unmapPages;

enum uint SLAB_SHIFT = 12;
enum uint SLAB_SIZE = 2 ^^ SLAB_SHIFT;
enum uint SLAB_MASK = SLAB_SIZE - 1;
enum uint RUN_CLASSES = SLAB_SHIFT + 1;
enum size_t TRIMMED_BLOCKS_PER_CALL = 4;
enum uint WORD_SHIFT = 6;
enum uint WORD_MASK = (1u << WORD_SHIFT) - 1;
enum size_t NOTED_PAGES_PER_DISCARD = 512;

struct Slab(T) {
    Array!(T*) blocks;
    Array!ulong noted;
    size_t notedCount;
    size_t notedCursor;
    bool isDiscarding;

    inout(T)* at(size_t index) inout {
        return blocks.ptr[index >> SLAB_SHIFT] + (index & SLAB_MASK);
    }

    void ensure(size_t count) {
        while (blocks.length * SLAB_SIZE < count) {
            blocks.append(allocateBlock());
        }
    }

    // Gives back a few blocks per call, since freeing hundreds of megabytes at once stalls a frame; one spare block
    // past the needed ones keeps a count wavering around a block boundary from churning memory.
    void trim(size_t count) {
        size_t kept = ((count + SLAB_SIZE - 1) >> SLAB_SHIFT) + 1;
        size_t freed = 0;
        while (blocks.length > kept && freed < TRIMMED_BLOCKS_PER_CALL) {
            unmapBlock(blocks.ptr[blocks.length - 1]);
            blocks.length -= 1;
            freed += 1;
        }
    }

    // Gives back the whole pages between two indices, which may read back as zero bytes, so the items there must be all
    // zero already or ones nothing reads before writing them again.
    void discard(size_t from, size_t to) {
        while (from < to) {
            size_t block = from >> SLAB_SHIFT;
            size_t end = (block + 1) << SLAB_SHIFT;
            if (end > to) {
                end = to;
            }
            if (block < blocks.length && blocks.ptr[block] !is null) {
                giveBack(blocks.ptr[block], (from & SLAB_MASK) * T.sizeof, (end - (block << SLAB_SHIFT)) * T.sizeof);
            }
            from = end;
        }
    }

    // Marks the pages holding items freed under one index of a pool that hands out `per` items per index, to be
    // checked by discardNoted.
    void note(size_t index, size_t per) {
        size_t page = pageSize();
        foreach (candidate; index * per * T.sizeof / page .. ((index + 1) * per * T.sizeof - 1) / page + 1) {
            size_t word = candidate >> WORD_SHIFT;
            if (noted.length <= word) {
                noted.resize(word + 1);
            }
            ulong bit = 1UL << (candidate & WORD_MASK);
            notedCount += (noted.ptr[word] & bit) == 0;
            noted.ptr[word] |= bit;
        }
    }

    // Once enough pages are noted, gives back those whose items all belong to free indices, counting indices from
    // `limit` on as free. Each give-back makes every thread flush its address cache, so pages wait to go back in runs
    // of neighbors, and a pass spends at most `calls` give-backs before carrying on in a later call. Pages are checked
    // now rather than when noted, since an index may have been taken again since.
    void discardNoted(ref const FreeIndices free, size_t limit, size_t per, ref uint calls) {
        isDiscarding = isDiscarding || notedCount >= NOTED_PAGES_PER_DISCARD;
        size_t page = pageSize();
        size_t runStart = 0;
        size_t runEnd = 0;
        while (isDiscarding && calls > 0) {
            ulong* bits = &noted.ptr[notedCursor];
            while (*bits != 0 && calls > 0) {
                size_t candidate = (notedCursor << WORD_SHIFT) + bsf(*bits);
                *bits &= *bits - 1;
                notedCount -= 1;
                if (isPageFree(candidate, page, free, limit, per)) {
                    if (candidate != runEnd) {
                        calls -= discardPages(runStart, runEnd, page);
                        runStart = candidate;
                    }
                    runEnd = candidate + 1;
                }
            }
            if (*bits == 0) {
                notedCursor += 1;
            }
            if (notedCursor == noted.length) {
                notedCursor = 0;
                isDiscarding = false;
            }
        }
        uint spent = discardPages(runStart, runEnd, page);
        calls = calls > spent ? calls - spent : 0;
    }

    bool isPageFree(size_t candidate, size_t page, ref const FreeIndices free, size_t limit, size_t per) const {
        size_t first = candidate * page / T.sizeof / per;
        size_t end = (((candidate + 1) * page + T.sizeof - 1) / T.sizeof + per - 1) / per;
        return first >= limit || free.containsAll(first, end < limit ? end : limit);
    }

    uint discardPages(size_t first, size_t end, size_t page) {
        if (end > first) {
            discard(first * page / T.sizeof, (end * page + T.sizeof - 1) / T.sizeof);
        }
        return end > first;
    }

    T* touch(size_t index) {
        size_t block = index >> SLAB_SHIFT;
        while (blocks.length <= block) {
            blocks.append(null);
        }
        if (blocks.ptr[block] is null) {
            blocks.ptr[block] = allocateBlock();
        }
        return at(index);
    }

    T* allocateBlock() {
        T* block = cast(T*) mapPages(SLAB_SIZE * T.sizeof);
        static if (!__traits(isZeroInit, T)) {
            foreach (i; 0 .. SLAB_SIZE) {
                block[i] = T.init;
            }
        }
        return block;
    }

    void unmapBlock(T* block) {
        if (block !is null) {
            unmapPages(block, SLAB_SIZE * T.sizeof);
        }
    }

    void release() {
        foreach (block; blocks.slice()) {
            unmapBlock(block);
        }
        blocks.release();
        noted.release();
        notedCount = 0;
        notedCursor = 0;
        isDiscarding = false;
    }
}

struct Run {
    uint start;
    uint length;
}

struct RunPool(T) {
    Slab!T items;
    Array!uint[RUN_CLASSES] free;
    uint end;

    inout(T)[] slice(Run run) inout {
        return run.length == 0 ? null : items.at(run.start)[0 .. run.length];
    }

    Run reserve(uint length) {
        if (length == 0) {
            return Run(0, 0);
        } else {
            assert(length <= SLAB_SIZE);
            uint size = runClass(length);
            if (free[size].length > 0) {
                free[size].length -= 1;
                return Run(free[size].ptr[free[size].length], length);
            } else {
                uint span = 1u << size;
                uint start = (end + span - 1) & ~(span - 1);
                keepGap(end, start);
                end = start + span;
                items.ensure(end);
                return Run(start, length);
            }
        }
    }

    void release(Run run) {
        if (run.length > 0) {
            free[runClass(run.length)].append(run.start);
        }
    }

    void keepGap(uint from, uint to) {
        while (from < to) {
            uint size = bsf(from) < SLAB_SHIFT ? bsf(from) : SLAB_SHIFT;
            while ((1u << size) > to - from) {
                size -= 1;
            }
            free[size].append(from);
            from += 1u << size;
        }
    }

    void release() {
        items.release();
        foreach (ref list; free) {
            list.release();
        }
        end = 0;
    }
}

// Free indices handed out lowest first, so live ones pack toward zero and the top of a pool can be given back.
struct FreeIndices {
    Array!ulong words;
    Array!ulong summary;
    size_t lowestWord;
    size_t count;

    bool isEmpty() const {
        return count == 0;
    }

    bool contains(uint index) const {
        size_t word = index >> WORD_SHIFT;
        return word < words.length && (words.ptr[word] & (1UL << (index & WORD_MASK))) != 0;
    }

    bool containsAll(size_t from, size_t to) const {
        bool isAll = true;
        while (isAll && from < to) {
            size_t word = from >> WORD_SHIFT;
            size_t end = (word + 1) << WORD_SHIFT;
            if (end > to) {
                end = to;
            }
            size_t span = end - from;
            ulong mask = (span == WORD_MASK + 1 ? ulong.max : (1UL << span) - 1) << (from & WORD_MASK);
            isAll = word < words.length && (words.ptr[word] & mask) == mask;
            from = end;
        }
        return isAll;
    }

    void add(uint index) {
        size_t word = index >> WORD_SHIFT;
        if (words.length <= word) {
            words.resize(word + 1);
        }
        if (summary.length <= word >> WORD_SHIFT) {
            summary.resize((word >> WORD_SHIFT) + 1);
        }
        words.ptr[word] |= 1UL << (index & WORD_MASK);
        summary.ptr[word >> WORD_SHIFT] |= 1UL << (word & WORD_MASK);
        if (word < lowestWord) {
            lowestWord = word;
        }
        count += 1;
    }

    void drop(uint index) {
        size_t word = index >> WORD_SHIFT;
        words.ptr[word] &= ~(1UL << (index & WORD_MASK));
        if (words.ptr[word] == 0) {
            summary.ptr[word >> WORD_SHIFT] &= ~(1UL << (word & WORD_MASK));
        }
        count -= 1;
    }

    uint takeLowest() {
        assert(count > 0);
        size_t group = lowestWord >> WORD_SHIFT;
        while (summary.ptr[group] == 0) {
            group += 1;
        }
        size_t word = (group << WORD_SHIFT) + bsf(summary.ptr[group]);
        uint index = cast(uint)((word << WORD_SHIFT) + bsf(words.ptr[word]));
        lowestWord = word;
        drop(index);
        return index;
    }

    void release() {
        words.release();
        summary.release();
        lowestWord = 0;
        count = 0;
    }
}

uint runClass(uint length) {
    return length <= 1 ? 0 : bsr(length - 1) + 1;
}

unittest {
    Slab!uint slab;
    slab.ensure(SLAB_SIZE + 1);
    uint* first = slab.at(0);
    *slab.at(SLAB_SIZE) = SLAB_SIZE;
    slab.ensure(SLAB_SIZE * 3);
    assert(slab.at(0) is first);
    assert(*slab.at(SLAB_SIZE) == SLAB_SIZE);
    assert(*slab.at(SLAB_SIZE * 3 - 1) == 0);
    slab.release();
    Slab!uint sparse;
    *sparse.touch(SLAB_SIZE * 5) = 7;
    assert(sparse.blocks.ptr[0] is null);
    assert(*sparse.touch(SLAB_SIZE * 5) == 7);
    sparse.release();
}

struct TestRecord {
    uint[3] values;
}

// Records straddle pages; a page shared with a live record must stay.
unittest {
    Slab!TestRecord slab;
    FreeIndices free;
    size_t count = (NOTED_PAGES_PER_DISCARD + 2) * pageSize() / TestRecord.sizeof;
    size_t straddling = pageSize() / TestRecord.sizeof;
    size_t inside = count / 2;
    slab.ensure(count);
    foreach (index; 0 .. count) {
        slab.at(index).values[0] = cast(uint) index + 1;
    }
    foreach (index; 0 .. count) {
        if (index != straddling && index != inside) {
            *slab.at(index) = TestRecord.init;
            free.add(cast(uint) index);
            slab.note(index, 1);
        }
    }
    do {
        uint calls = 1;
        slab.discardNoted(free, count, 1, calls);
    } while (slab.isDiscarding);
    assert(slab.notedCount == 0);
    assert(slab.at(straddling).values[0] == straddling + 1 && slab.at(inside).values[0] == inside + 1);
    foreach (index; 0 .. count) {
        assert(index == straddling || index == inside || slab.at(index).values[0] == 0);
    }
    slab.release();
    free.release();
}

enum uint TEST_RUNS = 3000;

unittest {
    RunPool!uint pool;
    Array!Run runs;
    foreach (index; 0 .. TEST_RUNS) {
        Run run = pool.reserve(index % 37 + 1);
        assert(run.start >> SLAB_SHIFT == (run.start + run.length - 1) >> SLAB_SHIFT);
        foreach (ref item; pool.slice(run)) {
            item = index;
        }
        runs.append(run);
    }
    foreach (index, run; runs.slice()) {
        foreach (item; pool.slice(run)) {
            assert(item == index);
        }
    }
    uint end = pool.end;
    foreach (run; runs.slice()) {
        pool.release(run);
    }
    foreach (run; runs.slice()) {
        pool.reserve(run.length);
    }
    assert(pool.end == end);
    runs.release();
    pool.release();
}

enum uint TEST_INDICES = 10000;
enum uint TEST_INDEX_STRIDE = 7;

unittest {
    FreeIndices free;
    foreach (step; 0 .. TEST_INDICES) {
        free.add(step * TEST_INDEX_STRIDE % TEST_INDICES);
    }
    foreach (expected; 0 .. TEST_INDICES / 2) {
        assert(free.takeLowest() == expected);
    }
    free.add(TEST_INDEX_STRIDE);
    assert(free.contains(TEST_INDEX_STRIDE) && !free.contains(TEST_INDEX_STRIDE + 1));
    assert(free.containsAll(TEST_INDICES / 2, TEST_INDICES) && !free.containsAll(TEST_INDICES / 2 - 1, TEST_INDICES));
    assert(free.containsAll(TEST_INDEX_STRIDE, TEST_INDEX_STRIDE + 1) && !free.containsAll(0, TEST_INDEX_STRIDE + 1));
    assert(free.takeLowest() == TEST_INDEX_STRIDE);
    free.drop(TEST_INDICES / 2);
    assert(free.takeLowest() == TEST_INDICES / 2 + 1);
    assert(free.count == TEST_INDICES / 2 - 2);
    free.release();
}
