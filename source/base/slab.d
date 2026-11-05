module base.slab;

import core.bitop : bsf, bsr;
import base.array : Array;
import base.flags : WORD_MASK, WORD_SHIFT;
import base.numbers : lowerOf;
import base.pages : giveBack, mapPages, pageSize, unmapPages;

enum uint SLAB_SHIFT = 12;
enum uint SLAB_SIZE = 2 ^^ SLAB_SHIFT;
enum uint SLAB_MASK = SLAB_SIZE - 1;
enum uint RUN_CLASSES = SLAB_SHIFT + 1;
enum size_t TRIMMED_BLOCKS_PER_CALL = 4;
enum size_t NOTED_PAGES_PER_DISCARD = 512;

enum DiscardPass : ubyte {
    resting,
    sweeping,
}

struct Slab(T) {
    Array!(T*) blocks;
    Array!ulong noted;
    size_t notedCount;
    size_t notedCursor;
    DiscardPass pass;

    inout(T)* at(size_t index) inout {
        return blocks.ptr[index >> SLAB_SHIFT] + (index & SLAB_MASK);
    }

    void ensure(size_t count) {
        while (blocks.length * SLAB_SIZE < count) {
            blocks.append(allocateBlock());
        }
    }

    void trim(size_t count) {
        size_t kept = ((count + SLAB_SIZE - 1) >> SLAB_SHIFT) + 1;
        size_t freed = 0;
        while (blocks.length > kept && freed < TRIMMED_BLOCKS_PER_CALL) {
            unmapBlock(blocks.ptr[blocks.length - 1]);
            blocks.length -= 1;
            freed += 1;
        }
    }

    void discard(size_t from, size_t to) {
        while (from < to) {
            size_t block = from >> SLAB_SHIFT;
            size_t end = lowerOf((block + 1) << SLAB_SHIFT, to);
            if (block < blocks.length && blocks.ptr[block] !is null) {
                giveBack(blocks.ptr[block], (from & SLAB_MASK) * T.sizeof, (end - (block << SLAB_SHIFT)) * T.sizeof);
            }
            from = end;
        }
    }

    void note(size_t index, size_t per) {
        size_t page = pageSize();
        foreach (candidate; index * per * T.sizeof / page .. ((index + 1) * per * T.sizeof - 1) / page + 1) {
            size_t word = candidate >> WORD_SHIFT;
            if (noted.length <= word) {
                noted.resize(word + 1);
            }
            ulong bit = 1UL << (candidate & WORD_MASK);
            if ((noted.ptr[word] & bit) == 0) {
                notedCount += 1;
                noted.ptr[word] |= bit;
            }
        }
    }

    void discardNoted(ref const FreeIndices free, size_t limit, size_t per, ref uint calls) {
        if (notedCount >= NOTED_PAGES_PER_DISCARD) {
            pass = DiscardPass.sweeping;
        }
        size_t page = pageSize();
        size_t runStart = 0;
        size_t runEnd = 0;
        while (pass == DiscardPass.sweeping && calls > 0) {
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
                pass = DiscardPass.resting;
            }
        }
        calls -= lowerOf(calls, discardPages(runStart, runEnd, page));
    }

    bool isPageFree(size_t candidate, size_t page, ref const FreeIndices free, size_t limit, size_t per) const {
        size_t first = candidate * page / T.sizeof / per;
        size_t end = (((candidate + 1) * page + T.sizeof - 1) / T.sizeof + per - 1) / per;
        return first >= limit || free.containsAll(first, lowerOf(end, limit));
    }

    uint discardPages(size_t first, size_t end, size_t page) {
        if (end > first) {
            discard(first * page / T.sizeof, (end * page + T.sizeof - 1) / T.sizeof);
            return 1;
        } else {
            return 0;
        }
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
        pass = DiscardPass.resting;
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
        if (run.length == 0) {
            return null;
        } else {
            return items.at(run.start)[0 .. run.length];
        }
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
            uint size = lowerOf(SLAB_SHIFT, cast(uint) bsf(from));
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
        while (from < to) {
            size_t word = from >> WORD_SHIFT;
            size_t end = lowerOf((word + 1) << WORD_SHIFT, to);
            size_t span = end - from;
            ulong mask = ulong.max;
            if (span <= WORD_MASK) {
                mask = (1UL << span) - 1;
            }
            mask <<= from & WORD_MASK;
            if (word >= words.length || (words.ptr[word] & mask) != mask) {
                return false;
            }
            from = end;
        }
        return true;
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
    if (length <= 1) {
        return 0;
    } else {
        return bsr(length - 1) + 1;
    }
}
