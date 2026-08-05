module common.text;

import core.stdc.stdio : FILE, SEEK_END, SEEK_SET;
import core.stdc.stdio : fclose, fopen, fread, fseek, ftell;
import core.stdc.stdlib : free, malloc, strtof, strtol, strtoul;
import core.stdc.string : strcmp, strlen, strncmp;
import common.array : Array;

// Whole-file text kept as one malloc'd, NUL-terminated block. collectLines
// carves it into C strings in place, so the line pointers stay valid for as
// long as this does.
struct FileText {
    char* data;
    size_t length;

    void release() {
        if (data !is null) {
            free(data);
        }
        data = null;
        length = 0;
    }
}

FileText readWholeFile(const(char)* path) {
    FileText result;
    FILE* handle = fopen(path, "rb");
    if (handle is null) {
        return result;
    }
    scope(exit) {
        fclose(handle);
    }
    if (fseek(handle, 0, SEEK_END) != 0) {
        return result;
    }
    long size = ftell(handle);
    if (size < 0) {
        return result;
    }
    if (fseek(handle, 0, SEEK_SET) != 0) {
        return result;
    }
    char* buffer = cast(char*) malloc(cast(size_t) size + 1);
    if (buffer is null) {
        return result;
    }
    size_t got = fread(buffer, 1, cast(size_t) size, handle);
    buffer[got] = '\0';
    result.data = buffer;
    result.length = got;
    return result;
}

bool isBlank(char c) {
    return c == ' ' || c == '\t' || c == '\r';
}

// Splits in place by overwriting the newlines. Trims surrounding blanks and,
// when skipComments is set, drops blank lines and ones starting with '#'.
void collectLines(ref FileText text, ref Array!(char*) lines, bool skipComments) {
    if (text.data is null) {
        return;
    }
    size_t start = 0;
    foreach (i; 0 .. text.length + 1) {
        bool atEnd = i == text.length;
        if (!atEnd && text.data[i] != '\n') {
            continue;
        }
        text.data[i] = '\0';

        size_t from = start;
        while (from < i && isBlank(text.data[from])) {
            from = from + 1;
        }
        size_t to = i;
        while (to > from && isBlank(text.data[to - 1])) {
            to = to - 1;
        }
        text.data[to] = '\0';

        char* line = text.data + from;
        bool keep = true;
        if (skipComments && (to == from || line[0] == '#')) {
            keep = false;
        }
        if (keep) {
            lines.push(line);
        }
        start = i + 1;
    }
}

// Splits `line` in place at runs of blanks, filling `tokens` with pointers to
// each field. Returns how many were filled; trailing fields beyond the array
// are left joined onto the last token.
size_t splitTokens(char* line, char*[] tokens) {
    if (line is null) {
        return 0;
    }
    size_t count = 0;
    size_t i = 0;
    while (count < tokens.length) {
        while (line[i] != '\0' && isBlank(line[i])) {
            i = i + 1;
        }
        if (line[i] == '\0') {
            break;
        }
        tokens[count] = line + i;
        count = count + 1;
        while (line[i] != '\0' && !isBlank(line[i])) {
            i = i + 1;
        }
        if (line[i] == '\0') {
            break;
        }
        line[i] = '\0';
        i = i + 1;
    }
    return count;
}

bool cstrEq(const(char)* a, const(char)* b) {
    if (a is null || b is null) {
        return false;
    }
    return strcmp(a, b) == 0;
}

bool cstrStartsWith(const(char)* a, const(char)* prefix) {
    if (a is null || prefix is null) {
        return false;
    }
    return strncmp(a, prefix, strlen(prefix)) == 0;
}

// Splits a NUL-terminated line at the first `sep`, writing a NUL over it.
// Returns null when the separator is absent, leaving the line untouched.
char* splitAt(char* line, char sep) {
    if (line is null) {
        return null;
    }
    size_t i = 0;
    while (line[i] != '\0') {
        if (line[i] == sep) {
            line[i] = '\0';
            return trimInPlace(line + i + 1);
        }
        i = i + 1;
    }
    return null;
}

char* trimInPlace(char* s) {
    if (s is null) {
        return null;
    }
    char* from = s;
    while (isBlank(*from)) {
        from = from + 1;
    }
    size_t len = strlen(from);
    while (len > 0 && isBlank(from[len - 1])) {
        from[len - 1] = '\0';
        len = len - 1;
    }
    return from;
}

// The `ok` flag distinguishes a genuine zero from an unparseable value, which
// is what lets callers keep their default instead of silently zeroing it.
struct ParsedFloat {
    float value;
    bool ok;
}

ParsedFloat parseFloat(const(char)* s) {
    ParsedFloat result;
    if (s is null || s[0] == '\0') {
        return result;
    }
    const(char)* stop;
    result.value = strtof(s, &stop);
    result.ok = *stop == '\0';
    return result;
}

struct ParsedInt {
    long value;
    bool ok;
}

ParsedInt parseInt(const(char)* s, int base) {
    ParsedInt result;
    if (s is null || s[0] == '\0') {
        return result;
    }
    const(char)* stop;
    result.value = strtol(s, &stop, base);
    result.ok = *stop == '\0';
    return result;
}

// Fixed-capacity string field. Config and name values are short and live as
// long as the struct holding them, so they are copied rather than referenced
// into a buffer that gets freed.
struct FixedString(size_t N) {
    char[N] chars = '\0';

    static FixedString!N from(const(char)* s) {
        FixedString!N result;
        result.assign(s);
        return result;
    }

    // CTFE cannot read the NUL past a string literal, so compile-time
    // defaults go through the slice form instead of the pointer form.
    static FixedString!N fromSlice(const(char)[] s) {
        FixedString!N result;
        result.assignSlice(s);
        return result;
    }

    void assignSlice(const(char)[] s) {
        chars[] = '\0';
        size_t len = s.length;
        if (len > N - 1) {
            len = N - 1;
        }
        foreach (i; 0 .. len) {
            chars[i] = s[i];
        }
    }

    // Hand-rolled instead of strlen so default field initialisers, which run
    // at compile time, can call this.
    void assign(const(char)* s) {
        chars[] = '\0';
        if (s is null) {
            return;
        }
        size_t i = 0;
        while (i < N - 1 && s[i] != '\0') {
            chars[i] = s[i];
            i = i + 1;
        }
    }

    const(char)* ptr() const return {
        return chars.ptr;
    }

    size_t length() const {
        size_t i = 0;
        while (i < N && chars[i] != '\0') {
            i = i + 1;
        }
        return i;
    }
}

unittest {
    FixedString!8 s = FixedString!8.from("hello");
    assert(s.length() == 5);
    assert(cstrEq(s.ptr(), "hello"));

    // Overlong input must truncate rather than run off the end.
    FixedString!8 t = FixedString!8.from("abcdefghijkl");
    assert(t.length() == 7);
    assert(cstrEq(t.ptr(), "abcdefg"));

    ParsedFloat f = parseFloat("2.5");
    assert(f.ok);
    assert(f.value == 2.5f);

    ParsedFloat bad = parseFloat("2.5x");
    assert(!bad.ok);

    ParsedFloat zero = parseFloat("0");
    assert(zero.ok);
    assert(zero.value == 0);

    ParsedInt n = parseInt("ff", 16);
    assert(n.ok);
    assert(n.value == 255);

    char[32] line = '\0';
    const(char)[] src = "  4.5   key_down   W  ";
    foreach (i; 0 .. src.length) {
        line[i] = src[i];
    }
    char*[3] tokens;
    assert(splitTokens(line.ptr, tokens) == 3);
    assert(cstrEq(tokens[0], "4.5"));
    assert(cstrEq(tokens[1], "key_down"));
    assert(cstrEq(tokens[2], "W"));
}
