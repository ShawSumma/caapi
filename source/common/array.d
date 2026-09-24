module common.array;

import core.stdc.stdlib : free, realloc;
import core.stdc.string : memset;

struct Array(T) {
    T* ptr;
    size_t length;
    size_t capacity;

    void reserve(size_t wanted) {
        if (wanted > capacity) {
            size_t grown = capacity * 2;
            if (grown < wanted) {
                grown = wanted;
            }
            ptr = cast(T*) realloc(ptr, grown * T.sizeof);
            capacity = grown;
        }
    }

    void append(T value) {
        reserve(length + 1);
        ptr[length] = value;
        length += 1;
    }

    void resize(size_t newLength) {
        reserve(newLength);
        if (newLength > length) {
            memset(ptr + length, 0, (newLength - length) * T.sizeof);
        }
        length = newLength;
    }

    void clear() {
        length = 0;
    }

    T[] slice() {
        return ptr[0 .. length];
    }

    void release() {
        free(ptr);
        ptr = null;
        length = 0;
        capacity = 0;
    }
}
