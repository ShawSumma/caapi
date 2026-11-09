module common.content.data;

import core.stdc.string : memcpy;
import base.array : Array;
import base.stdio : printed;
import common.content.graph : ContentGraph, PROBLEM_CAPACITY, ValueKind;
import common.content.lexer : Lexing, TOKEN_CAPACITY, Token;
import plugins.api.content : ContentRef, Need;

enum size_t NAME_CAPACITY = 128;
enum size_t MOST_TARGETS = 64;

struct Spelled(size_t capacity) {
    char[capacity] text;
    size_t length;

    const(char)[] slice() const return {
        return text[0 .. length];
    }
}

alias Name = Spelled!NAME_CAPACITY;

struct DataParser {
    mixin Lexing;
    ContentGraph* graph;

    Name word() {
        Name made;
        if (token != Token.word) {
            fail("a name is expected here");
        } else if (length > NAME_CAPACITY) {
            fail("a name is too long");
        } else {
            memcpy(made.text.ptr, spelling.ptr, length);
            made.length = length;
            advance();
        }
        return made;
    }

    void file() {
        advance();
        while (isGoing() && token != Token.end) {
            if (isWord("remove")) {
                advance();
                Name name = word();
                if (isGoing()) {
                    graph.removeNode(name.slice());
                }
            } else if (isWord("unlink")) {
                advance();
                Name from = word();
                Name kind = word();
                expect("->");
                Name to = word();
                if (isGoing()) {
                    graph.removeEdges(kind.slice(), from.slice(), to.slice());
                }
            } else {
                Name kind = word();
                Name name = word();
                if (isGoing()) {
                    ContentRef node = graph.defineNode(kind.slice(), name.slice());
                    expect("{");
                    while (isGoing() && token != Token.end && !isSymbol("}")) {
                        entry(node, name);
                    }
                    expect("}");
                }
            }
        }
    }

    void entry(ContentRef node, ref const Name from) {
        Name key = word();
        if (!isGoing()) {
            return;
        } else if (isSymbol(":")) {
            advance();
            value(node, key.slice());
        } else if (isSymbol("->") || isSymbol("?->")) {
            Need need = Need.required;
            if (isSymbol("?->")) {
                need = Need.optional;
            }
            advance();
            Name[MOST_TARGETS] targets;
            size_t count = 0;
            if (isSymbol("[")) {
                advance();
                while (isGoing() && token == Token.word && count < targets.length) {
                    targets[count] = word();
                    count += 1;
                }
                expect("]");
            } else {
                targets[0] = word();
                count = 1;
            }
            Array!Value values;
            if (isGoing() && isSymbol("{")) {
                advance();
                while (isGoing() && token != Token.end && !isSymbol("}")) {
                    Value made;
                    made.key = word();
                    expect(":");
                    value(made);
                    values.append(made);
                }
                expect("}");
            }
            foreach (index; 0 .. count) {
                ContentRef edge = graph.defineEdge(key.slice(), from.slice(), targets[index].slice(), need);
                foreach (ref made; values.slice()) {
                    made.apply(*graph, edge);
                }
            }
            values.release();
        } else {
            fail("an entry is 'key: value' or 'edge -> target'");
        }
    }

    void value(ref Value made) {
        if (token == Token.number) {
            made.number = number();
            made.kind = ValueKind.number;
        } else if (token == Token.text || token == Token.word) {
            memcpy(made.text.text.ptr, spelling.ptr, length);
            made.text.length = length;
            made.kind = ValueKind.text;
            advance();
        } else {
            fail("a value is a number, a string or a word");
        }
    }

    void value(ContentRef target, const(char)[] key) {
        Value made;
        value(made);
        if (isGoing()) {
            (*graph).setValue(target, key, made);
        }
    }
}

struct Value {
    Name key;
    Spelled!TOKEN_CAPACITY text;
    double number = 0;
    ValueKind kind;

    void apply(ref ContentGraph graph, ContentRef target) const {
        graph.setValue(target, key.slice(), this);
    }
}

void setValue(ref ContentGraph graph, ContentRef target, const(char)[] key, ref const Value made) {
    final switch (made.kind) {
        case ValueKind.number:
            graph.setNumber(target, key, made.number);
            break;
        case ValueKind.text:
            graph.setText(target, key, made.text.slice());
            break;
    }
}

void loadData(ref ContentGraph graph, const(char)[] text, const(char)[] source) {
    DataParser parser;
    parser.text = text;
    parser.graph = &graph;
    parser.file();
    if (!parser.isGoing()) {
        char[PROBLEM_CAPACITY] buffer;
        graph.report(graph.owner, printed(buffer[], "%.*s, line %u: %.*s", cast(int) source.length, source.ptr, parser.failedLine, cast(int) parser.failure.length, parser.failure.ptr));
    }
}
