module base.flags;

import base.array : Array;

enum Readiness : ubyte {
    pending,
    ready,
}

enum uint WORD_SHIFT = 6;
enum uint WORD_MASK = (1u << WORD_SHIFT) - 1;

struct Bits {
    Array!ulong words;

    void cover(size_t count) {
        size_t wanted = (count + WORD_MASK) >> WORD_SHIFT;
        if (words.length < wanted) {
            words.resize(wanted);
        }
    }

    void clearAll() {
        words.slice()[] = 0;
    }

    size_t count() const {
        return words.length << WORD_SHIFT;
    }

    bool has(size_t index) const {
        return (words.ptr[index >> WORD_SHIFT] & (1UL << (index & WORD_MASK))) != 0;
    }

    void set(size_t index) {
        words.ptr[index >> WORD_SHIFT] |= 1UL << (index & WORD_MASK);
    }

    void clear(size_t index) {
        words.ptr[index >> WORD_SHIFT] &= ~(1UL << (index & WORD_MASK));
    }

    void release() {
        words.release();
    }
}
