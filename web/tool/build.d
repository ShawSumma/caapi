module build;

import std.array : replace;
import std.base64 : Base64;
import std.file : mkdirRecurse, read, readText, write;
import std.process : Config, environment, execute, spawnProcess, wait;
import std.stdio : stderr, writefln;

enum string OBJECT_DIRECTORY = "obj/web";
enum string OBJECT_FILE = OBJECT_DIRECTORY ~ "/mined.o";
enum string WASM_FILE = OBJECT_DIRECTORY ~ "/mined.wasm";
enum string CHECK_PAGE = OBJECT_DIRECTORY ~ "/check.html";
enum string GAME_PAGE = "mined.html";
enum string ZIG_PYTHON = ".venv/bin/python";
enum string STACK_BYTES = "33554432";
enum string MAX_MEMORY_BYTES = "4294901760";

immutable string[] EXPORTS = [
    "web_start", "web_frame", "web_resize", "web_key_down", "web_key_up", "web_button", "web_motion", "web_capture",
    "web_backlog", "web_visible_chunks", "web_drawable_chunks", "web_settled",
];

void run(string[] command, string[string] variables = null) {
    writefln("%-(%s %)", command[0 .. 3]);
    auto process = spawnProcess(command, variables);
    int status = wait(process);
    if (status != 0) {
        stderr.writefln("failed with status %d", status);
        throw new Exception("build step failed");
    }
}

void compile() {
    run(["ldc2", "-mtriple=wasm32-unknown-wasi", "-betterC", "-checkaction=halt", "--enable-asserts", "--boundscheck=on", "-O3", "--mattr=+bulk-memory,+nontrapping-fptoint,+sign-ext,+mutable-globals,+simd128", "-i", "-singleobj", "-c", "-of=" ~ OBJECT_FILE, "--mv=core.stdc.time=web/time.d", "-Isource", "-I.", "web/main.d"]);
}

void link() {
    string[] command = [ZIG_PYTHON, "-m", "ziglang", "cc", "-target", "wasm32-wasi", "-mexec-model=reactor", "-O2", OBJECT_FILE, "-o", WASM_FILE, "-lc", "-Wl,--import-symbols","-Wl,-z,stack-size=" ~ STACK_BYTES, "-Wl,--max-memory=" ~ MAX_MEMORY_BYTES];
    foreach (name; EXPORTS) {
        command ~= "-Wl,--export=" ~ name;
    }
    run(command, ["ZIG_GLOBAL_CACHE_DIR": OBJECT_DIRECTORY ~ "/zig-global", "ZIG_LOCAL_CACHE_DIR": OBJECT_DIRECTORY ~ "/zig-local"]);
}

string scriptsWith(string wasm, string last) {
    return "const MINED_WASM = \"" ~ wasm ~ "\";\n" ~ readText("web/shaders.js") ~ readText("web/glue.js") ~ readText(last);
}

void pack() {
    string shell = readText("web/shell.html");
    string wasm = Base64.encode(cast(const(ubyte)[]) read(WASM_FILE)).idup;
    write(GAME_PAGE, shell.replace("__SCRIPTS__", scriptsWith(wasm, "web/play.js")));
    write(CHECK_PAGE, shell.replace("__SCRIPTS__", scriptsWith(wasm, "web/check.js")));
}

int main() {
    mkdirRecurse(OBJECT_DIRECTORY);
    compile();
    link();
    pack();
    return 0;
}
