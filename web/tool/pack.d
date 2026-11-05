module pack;

import core.stdc.stdio : fprintf, stderr;
import base.array : Array;
import base64 : encodeInto;
import files : readFile, writeFile;

enum string WASM_FILE = "obj/web/mined.wasm";
enum string CHECK_PAGE = "obj/web/check.html";
enum string GAME_PAGE = "mined.html";
enum string SHELL_FILE = "web/shell.html";
enum string GLUE_FILE = "web/glue.js";
enum string PLAY_FILE = "web/play.js";
enum string CHECK_FILE = "web/check.js";
enum string SCRIPTS_MARK = "__SCRIPTS__";
enum string WASM_START = "const MINED_WASM = \"";
enum string WASM_END = "\";\n";

enum ExitStatus : int {
    ok,
    failed,
}

size_t markIn(const(ubyte)[] shell) {
    size_t at = 0;
    while (at + SCRIPTS_MARK.length <= shell.length && cast(const(char)[]) shell[at .. at + SCRIPTS_MARK.length] != SCRIPTS_MARK) {
        at += 1;
    }
    return at;
}

bool packPage(const(char)[] path, const(ubyte)[] shell, const(ubyte)[] encoded, const(char)[] script) {
    size_t mark = markIn(shell);
    assert(mark + SCRIPTS_MARK.length <= shell.length);
    Array!ubyte page;
    page.appendAll(shell[0 .. mark]);
    page.appendAll(cast(const(ubyte)[]) WASM_START);
    page.appendAll(encoded);
    page.appendAll(cast(const(ubyte)[]) WASM_END);
    if (readFile(GLUE_FILE, page) && readFile(script, page)) {
        page.appendAll(shell[mark + SCRIPTS_MARK.length .. $]);
        return writeFile(path, page.slice());
    } else {
        return false;
    }
}

extern (C) int main() {
    Array!ubyte wasm;
    Array!ubyte shell;
    Array!ubyte encoded;
    if (!readFile(WASM_FILE, wasm) || !readFile(SHELL_FILE, shell)) {
        fprintf(stderr, "cannot read the wasm file or the page shell\n");
        return ExitStatus.failed;
    } else {
        encodeInto(wasm.slice(), encoded);
        if (!packPage(GAME_PAGE, shell.slice(), encoded.slice(), PLAY_FILE) || !packPage(CHECK_PAGE, shell.slice(), encoded.slice(), CHECK_FILE)) {
            fprintf(stderr, "cannot write the pages\n");
            return ExitStatus.failed;
        } else {
            return ExitStatus.ok;
        }
    }
}
