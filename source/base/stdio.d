module base.stdio;

version (WebAssembly) {
    struct FILE;

    extern (C) nothrow @nogc {
        extern __gshared FILE* stderr;

        int fprintf(FILE* stream, const(char)* format, ...);
        int snprintf(char* buffer, size_t size, const(char)* format, ...);
        FILE* fopen(const(char)* path, const(char)* mode);
        int fclose(FILE* stream);
        char* fgets(char* buffer, int size, FILE* stream);
    }
} else {
    public import core.stdc.stdio : FILE, fclose, fgets, fopen, fprintf, snprintf, stderr;
}
