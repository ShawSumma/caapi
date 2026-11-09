module common.content.lexer;

enum size_t TOKEN_CAPACITY = 1024;

enum Token : ubyte {
    end,
    word,
    number,
    text,
    symbol,
}

enum Parsing : ubyte {
    going,
    failed,
}

bool isBlank(char c) {
    return c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == ',';
}

bool isDigit(char c) {
    return c >= '0' && c <= '9';
}

bool isWordStart(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

bool isWordPart(char c) {
    return isWordStart(c) || isDigit(c) || c == '-';
}

mixin template Lexing() {
    import core.stdc.stdlib : strtod;
    import core.stdc.string : memcpy;
    import common.content.lexer : Parsing, TOKEN_CAPACITY, Token, isBlank, isDigit, isWordStart, isWordPart;

    char[TOKEN_CAPACITY] spelling;
    const(char)[] text;
    const(char)[] failure;
    size_t at;
    size_t length;
    uint line = 1;
    uint failedLine;
    Token token;
    Parsing parsing;

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

    const(char)[] current() const return {
        return spelling[0 .. length];
    }

    bool isSymbol(const(char)[] symbol) const {
        return token == Token.symbol && current() == symbol;
    }

    bool isWord(const(char)[] word) const {
        return token == Token.word && current() == word;
    }

    void keep(char c) {
        if (length == spelling.length) {
            fail("a token is too long");
        } else {
            spelling[length] = c;
            length += 1;
        }
    }

    void advance() {
        length = 0;
        while (at < text.length && (isBlank(text[at]) || text[at] == '#')) {
            if (text[at] == '#') {
                while (at < text.length && text[at] != '\n') {
                    at += 1;
                }
            } else {
                if (text[at] == '\n') {
                    line += 1;
                }
                at += 1;
            }
        }
        if (at >= text.length) {
            token = Token.end;
        } else if (isWordStart(text[at])) {
            token = Token.word;
            while (at < text.length && (isWordPart(text[at]) || (text[at] == ':' && at + 1 < text.length && isWordStart(text[at + 1])))) {
                keep(text[at]);
                at += 1;
            }
        } else if (isDigit(text[at]) || (text[at] == '-' && at + 1 < text.length && isDigit(text[at + 1]))) {
            token = Token.number;
            keep(text[at]);
            at += 1;
            digits();
            if (at + 1 < text.length && text[at] == '.' && isDigit(text[at + 1])) {
                keep('.');
                at += 1;
                digits();
            }
            if (at + 1 < text.length && (text[at] == 'e' || text[at] == 'E')) {
                keep(text[at]);
                at += 1;
                if (at < text.length && text[at] == '-') {
                    keep('-');
                    at += 1;
                }
                digits();
            }
        } else if (text[at] == '"') {
            token = Token.text;
            at += 1;
            while (at < text.length && text[at] != '"' && text[at] != '\n') {
                char c = text[at];
                if (c == '\\' && at + 1 < text.length) {
                    at += 1;
                    c = text[at];
                }
                keep(c);
                at += 1;
            }
            if (at < text.length && text[at] == '"') {
                at += 1;
            } else {
                fail("a string is never closed");
            }
        } else if (at + 2 < text.length && text[at] == '?' && text[at + 1] == '-' && text[at + 2] == '>') {
            token = Token.symbol;
            keep('?');
            keep('-');
            keep('>');
            at += 3;
        } else if (at + 1 < text.length && ((text[at] == '-' && text[at + 1] == '>') || (text[at] == '.' && text[at + 1] == '.'))) {
            token = Token.symbol;
            keep(text[at]);
            keep(text[at + 1]);
            at += 2;
        } else {
            token = Token.symbol;
            keep(text[at]);
            at += 1;
        }
    }

    void digits() {
        while (at < text.length && isDigit(text[at])) {
            keep(text[at]);
            at += 1;
        }
    }

    void expect(const(char)[] symbol) {
        if (!isSymbol(symbol)) {
            fail("punctuation is missing here");
        } else {
            advance();
        }
    }

    double number() {
        char[TOKEN_CAPACITY + 1] terminated;
        memcpy(terminated.ptr, spelling.ptr, length);
        terminated[length] = '\0';
        double value = strtod(terminated.ptr, null);
        advance();
        return value;
    }
}
