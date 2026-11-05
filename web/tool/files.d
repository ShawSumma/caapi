module files;

import core.stdc.stdio : FILE, SEEK_END, SEEK_SET, fclose, fopen, fread, fseek, ftell, fwrite;
import core.stdc.string : memcpy;
import base.array : Array;

enum size_t PATH_CAPACITY = 1024;

enum Outcome : int {
    done,
    failed,
}

Outcome outcomeOf(bool succeeded) {
    if (succeeded) {
        return Outcome.done;
    } else {
        return Outcome.failed;
    }
}

char[PATH_CAPACITY] zeroTerminated(const(char)[] text) {
    assert(text.length < PATH_CAPACITY);
    char[PATH_CAPACITY] terminated = 0;
    memcpy(terminated.ptr, text.ptr, text.length);
    return terminated;
}

Outcome readFile(const(char)[] path, ref Array!ubyte into) {
    char[PATH_CAPACITY] name = zeroTerminated(path);
    FILE* file = fopen(name.ptr, "rb");
    if (file is null) {
        return Outcome.failed;
    } else {
        fseek(file, 0, SEEK_END);
        size_t size = cast(size_t) ftell(file);
        fseek(file, 0, SEEK_SET);
        size_t start = into.length;
        into.resize(start + size);
        size_t got = fread(into.ptr + start, 1, size, file);
        fclose(file);
        return outcomeOf(got == size);
    }
}

Outcome writeFile(const(char)[] path, const(ubyte)[] bytes) {
    char[PATH_CAPACITY] name = zeroTerminated(path);
    FILE* file = fopen(name.ptr, "wb");
    if (file is null) {
        return Outcome.failed;
    } else {
        size_t put = fwrite(bytes.ptr, 1, bytes.length, file);
        fclose(file);
        return outcomeOf(put == bytes.length);
    }
}
