module files;

import core.stdc.stdio : FILE, SEEK_END, SEEK_SET, fclose, fopen, fread, fseek, ftell, fwrite;
import core.stdc.string : memcpy;
import base.array : Array;

enum size_t PATH_CAPACITY = 1024;

char[PATH_CAPACITY] zeroTerminated(const(char)[] text) {
    assert(text.length < PATH_CAPACITY);
    char[PATH_CAPACITY] terminated = 0;
    memcpy(terminated.ptr, text.ptr, text.length);
    return terminated;
}

bool readFile(const(char)[] path, ref Array!ubyte into) {
    char[PATH_CAPACITY] name = zeroTerminated(path);
    FILE* file = fopen(name.ptr, "rb");
    if (file is null) {
        return false;
    } else {
        fseek(file, 0, SEEK_END);
        size_t size = cast(size_t) ftell(file);
        fseek(file, 0, SEEK_SET);
        size_t start = into.length;
        into.resize(start + size);
        size_t got = fread(into.ptr + start, 1, size, file);
        fclose(file);
        return got == size;
    }
}

bool writeFile(const(char)[] path, const(ubyte)[] bytes) {
    char[PATH_CAPACITY] name = zeroTerminated(path);
    FILE* file = fopen(name.ptr, "wb");
    if (file is null) {
        return false;
    } else {
        size_t put = fwrite(bytes.ptr, 1, bytes.length, file);
        fclose(file);
        return put == bytes.length;
    }
}
