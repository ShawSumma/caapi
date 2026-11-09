module pack;

import core.stdc.stdio : fprintf, stderr;
import base.array : Array;
import base64 : encodeInto;
import files : Outcome, readFile, writeFile;

enum string WASM_FILE = "obj/web/caapi.wasm";
enum string CHECK_PAGE = "obj/web/check.html";
enum string GAME_PAGE = "caapi.html";
enum string SHELL_FILE = "web/shell.html";
enum string GLUE_FILE = "web/glue.js";
enum string PLAY_FILE = "web/play.js";
enum string CHECK_FILE = "web/check.js";
enum string SCRIPTS_MARK = "__SCRIPTS__";
enum string WASM_START = "const CAAPI_WASM = \"";
enum string WASM_END = "\";\n";

size_t markIn(const(ubyte)[] shell) {
    size_t at = 0;
    while (at + SCRIPTS_MARK.length <= shell.length && cast(const(char)[]) shell[at .. at + SCRIPTS_MARK.length] != SCRIPTS_MARK) {
        at += 1;
    }
    return at;
}

Outcome packPage(const(char)[] path, const(ubyte)[] shell, const(ubyte)[] encoded, const(char)[] script) {
    size_t mark = markIn(shell);
    assert(mark + SCRIPTS_MARK.length <= shell.length);
    Array!ubyte page;
    page.appendAll(shell[0 .. mark]);
    page.appendAll(cast(const(ubyte)[]) WASM_START);
    page.appendAll(encoded);
    page.appendAll(cast(const(ubyte)[]) WASM_END);
    Outcome status = readFile(GLUE_FILE, page);
    if (status == Outcome.done) {
        status = readFile(script, page);
    }
    if (status == Outcome.done) {
        page.appendAll(shell[mark + SCRIPTS_MARK.length .. $]);
        status = writeFile(path, page.slice());
    }
    return status;
}

extern (C) int main() {
    Array!ubyte wasm;
    Array!ubyte shell;
    Array!ubyte encoded;
    Outcome read = readFile(WASM_FILE, wasm);
    if (read == Outcome.done) {
        read = readFile(SHELL_FILE, shell);
    }
    if (read == Outcome.failed) {
        fprintf(stderr, "cannot read the wasm file or the page shell\n");
        return Outcome.failed;
    } else {
        encodeInto(wasm.slice(), encoded);
        Outcome written = packPage(GAME_PAGE, shell.slice(), encoded.slice(), PLAY_FILE);
        if (written == Outcome.done) {
            written = packPage(CHECK_PAGE, shell.slice(), encoded.slice(), CHECK_FILE);
        }
        if (written == Outcome.failed) {
            fprintf(stderr, "cannot write the pages\n");
        }
        return written;
    }
}
