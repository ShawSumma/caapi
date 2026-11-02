module base.flags;

import base.array : Array;

enum Readiness : ubyte {
    pending,
    ready,
}

enum uint BITS_WORD_SHIFT = 6;
enum uint BITS_WORD_MASK = (1u << BITS_WORD_SHIFT) - 1;

struct Bits {
    Array!ulong words;

    void cover(size_t count) {
        size_t wanted = (count + BITS_WORD_MASK) >> BITS_WORD_SHIFT;
        if (words.length < wanted) {
            words.resize(wanted);
        }
    }

    void clearAll() {
        words.slice()[] = 0;
    }

    size_t count() const {
        return words.length << BITS_WORD_SHIFT;
    }

    bool has(size_t index) const {
        return (words.ptr[index >> BITS_WORD_SHIFT] & (1UL << (index & BITS_WORD_MASK))) != 0;
    }

    void set(size_t index) {
        words.ptr[index >> BITS_WORD_SHIFT] |= 1UL << (index & BITS_WORD_MASK);
    }

    void clear(size_t index) {
        words.ptr[index >> BITS_WORD_SHIFT] &= ~(1UL << (index & BITS_WORD_MASK));
    }

    void release() {
        words.release();
    }
}
