module common.array;

import core.stdc.stdlib : free, realloc;
import core.stdc.string : memcpy, memset;

size_t grownCapacity(size_t current, size_t needed) {
    if (current * 2 > needed) {
        return current * 2;
    } else {
        return needed;
    }
}

struct Array(T) {
    T* ptr;
    size_t length;
    size_t capacity;

    void reserve(size_t wanted) {
        if (wanted > capacity) {
            capacity = grownCapacity(capacity, wanted);
            ptr = cast(T*) realloc(ptr, capacity * T.sizeof);
        }
    }

    void append(T value) {
        reserve(length + 1);
        ptr[length] = value;
        length += 1;
    }

    void appendAll(const(T)[] values) {
        reserve(length + values.length);
        memcpy(ptr + length, values.ptr, values.length * T.sizeof);
        length += values.length;
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

    inout(T)[] slice() inout {
        return ptr[0 .. length];
    }

    void release() {
        free(ptr);
        ptr = null;
        length = 0;
        capacity = 0;
    }
}
