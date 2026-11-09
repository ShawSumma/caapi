module common.content.settings;

import core.stdc.stdlib : strtod;
import core.stdc.string : memcpy;
import base.stdio : printed;
import base.maybe : MaybeIndex;
import common.content.graph : ContentGraph, PROBLEM_CAPACITY;
import common.content.lexer : Parsing, isBlank;
import plugins.api.content : ContentRef, Holder;

enum string MOD_KIND = "mod";
enum size_t PATH_CAPACITY = 256;
enum size_t WORD_CAPACITY = 256;
enum char PATH_SEPARATOR = '.';

enum Targets : ubyte {
    fixed,
    byMod,
}

struct SettingsParser {
    char[PATH_CAPACITY] path;
    char[WORD_CAPACITY] word;
    const(char)[] text;
    const(char)[] failure;
    ContentGraph* graph;
    ContentRef target;
    size_t at;
    size_t pathLength;
    uint depth;
    uint line = 1;
    uint failedLine;
    Parsing parsing;
    Targets targets;

    bool isGoing() const {
        return parsing == Parsing.going;
    }

    void fail(const(char)[] message) {
        if (isGoing()) {
            failure = message;
            failedLine = line;
            parsing = Parsing.failed;
        }
    }

    bool isAtEnd() const {
        return at >= text.length;
    }

    char here() const {
        return text[at];
    }

    void skipBlank() {
        while (!isAtEnd() && (isBlank(here()) || here() == '#')) {
            if (here() == '#') {
                while (!isAtEnd() && here() != '\n') {
                    at += 1;
                }
            } else {
                if (here() == '\n') {
                    line += 1;
                }
                at += 1;
            }
        }
    }

    void skipSpaces() {
        while (!isAtEnd() && (here() == ' ' || here() == '\t')) {
            at += 1;
        }
    }

    size_t push(const(char)[] segment) {
        size_t before = pathLength;
        size_t separator = 0;
        if (pathLength > 0) {
            separator = 1;
        }
        if (pathLength + separator + segment.length > path.length) {
            fail("a key path is too long");
        } else {
            if (separator > 0) {
                path[pathLength] = PATH_SEPARATOR;
            }
            memcpy(path.ptr + pathLength + separator, segment.ptr, segment.length);
            pathLength += separator + segment.length;
        }
        return before;
    }

    void members(char closing) {
        uint outer = depth;
        if (closing != '\0') {
            depth += 1;
        }
        skipBlank();
        while (isGoing() && !isAtEnd() && here() != closing) {
            member();
            skipBlank();
        }
        if (isGoing() && closing != '\0') {
            if (isAtEnd()) {
                fail("a '{' is never closed");
            } else {
                at += 1;
            }
        }
        depth = outer;
    }

    void member() {
        const(char)[] key;
        if (here() == '"') {
            key = quoted();
        } else {
            size_t start = at;
            while (!isAtEnd() && here() != ':' && here() != '\n') {
                at += 1;
            }
            key = trimmed(text[start .. at]);
        }
        skipSpaces();
        if (!isGoing()) {
            return;
        } else if (isAtEnd() || here() != ':' || key.length == 0) {
            fail("a setting needs a key, a colon and a value");
        } else if (targets == Targets.byMod && depth == 0) {
            at += 1;
            MaybeIndex!uint mod = graph.nodeNamed(key);
            if (!mod.exists || !graph.isKind(mod.value, MOD_KIND)) {
                fail("names a mod that is not loaded");
            } else {
                target = ContentRef(mod.value, Holder.node);
                value();
            }
        } else {
            at += 1;
            size_t before = push(key);
            value();
            pathLength = before;
        }
    }

    void value() {
        skipBlank();
        if (isAtEnd()) {
            fail("a key has no value");
        } else if (here() == '{') {
            at += 1;
            members('}');
        } else if (here() == '[') {
            at += 1;
            list();
        } else if (here() == '"') {
            const(char)[] made = quoted();
            if (isGoing()) {
                graph.setText(target, path[0 .. pathLength], made);
            }
        } else {
            bare();
        }
    }

    void list() {
        uint index = 0;
        skipBlank();
        while (isGoing() && !isAtEnd() && here() != ']') {
            char[WORD_CAPACITY] digits;
            size_t before = push(printed(digits[], "%u", index));
            value();
            pathLength = before;
            index += 1;
            skipBlank();
        }
        if (isGoing() && isAtEnd()) {
            fail("a '[' is never closed");
        } else if (isGoing()) {
            at += 1;
        }
    }

    const(char)[] quoted() {
        at += 1;
        size_t length = 0;
        while (isGoing() && !isAtEnd() && here() != '"') {
            char c = here();
            if (c == '\\' && at + 1 < text.length) {
                at += 1;
                c = escaped(here());
            } else if (c == '\n') {
                fail("a string runs past the end of its line");
            }
            if (length == word.length) {
                fail("a string is too long");
            } else {
                word[length] = c;
                length += 1;
            }
            at += 1;
        }
        if (isGoing() && isAtEnd()) {
            fail("a string is never closed");
        } else if (isGoing()) {
            at += 1;
        }
        return word[0 .. length];
    }

    void bare() {
        size_t start = at;
        while (!isAtEnd() && !isBlank(here()) && here() != ']' && here() != '}' && here() != '#') {
            at += 1;
        }
        const(char)[] found = text[start .. at];
        if (found.length == 0) {
            fail("a value is missing");
        } else if (found.length >= word.length) {
            fail("a value is too long");
        } else {
            memcpy(word.ptr, found.ptr, found.length);
            word[found.length] = '\0';
            char* end;
            double number = strtod(word.ptr, &end);
            if (end == word.ptr + found.length) {
                graph.setNumber(target, path[0 .. pathLength], number);
            } else {
                graph.setText(target, path[0 .. pathLength], found);
            }
        }
    }
}

char escaped(char c) {
    if (c == 'n') {
        return '\n';
    } else if (c == 't') {
        return '\t';
    } else {
        return c;
    }
}

const(char)[] trimmed(const(char)[] text) {
    size_t start = 0;
    size_t end = text.length;
    while (start < end && (text[start] == ' ' || text[start] == '\t')) {
        start += 1;
    }
    while (end > start && (text[end - 1] == ' ' || text[end - 1] == '\t')) {
        end -= 1;
    }
    return text[start .. end];
}

void parseSettings(ref ContentGraph graph, ContentRef target, const(char)[] text, const(char)[] source) {
    SettingsParser parser;
    parser.text = text;
    parser.graph = &graph;
    parser.target = target;
    parser.run(source);
}

void parseOverrides(ref ContentGraph graph, const(char)[] text, const(char)[] source) {
    SettingsParser parser;
    parser.text = text;
    parser.graph = &graph;
    parser.targets = Targets.byMod;
    parser.run(source);
}

void run(ref SettingsParser parser, const(char)[] source) {
    ContentGraph* graph = parser.graph;
    parser.members('\0');
    if (!parser.isGoing()) {
        char[PROBLEM_CAPACITY] buffer;
        graph.report(graph.owner, printed(buffer[], "%.*s, line %u: %.*s", cast(int) source.length, source.ptr, parser.failedLine,cast(int) parser.failure.length, parser.failure.ptr));
    }
}
