import std.stdio : writeln, writefln;
import std.algorithm : endsWith;
import std.conv : to;
import std.file : exists;
import client.game : Game;
import client.script : ScriptHost;
import worldcheck : dumpWorld, benchNearby, benchGen, benchDrive;

enum ubyte CHUNK_DIMENSION = 12;
enum float REACH_METERS = 10.0f;

int main(string[] args) {
    string[] scriptPaths;
    bool flatWorldgen = false;
    foreach (i, a; args) {
        if (a == "--dump-world") {
            float radius = (i + 1 < args.length) ? args[i + 1].to!float : 3.0f;
            dumpWorld(radius, CHUNK_DIMENSION);
            return 0;
        }
        if (a == "--bench-gen") {
            float radius = (i + 1 < args.length) ? args[i + 1].to!float : 2.5f;
            benchGen(radius, CHUNK_DIMENSION);
            return 0;
        }
        if (a == "--bench-drive") {
            float radius = (i + 1 < args.length) ? args[i + 1].to!float : 2.5f;
            benchDrive(radius, CHUNK_DIMENSION);
            return 0;
        }
        if (a == "--bench-nearby") {
            float radius = (i + 1 < args.length) ? args[i + 1].to!float : 4.5f;
            int iters = (i + 2 < args.length) ? args[i + 2].to!int : 50;
            benchNearby(radius, iters, CHUNK_DIMENSION);
            return 0;
        }
        if (a == "--flat") {
            flatWorldgen = true;
        }
        if (i > 0 && a.endsWith(".lua")) {
            scriptPaths ~= a;
        }
    }
    if (scriptPaths.length == 0) {
        writeln("usage: mined-headless <script.lua>... [--flat]");
        writeln("       mined-headless --dump-world [r] | --bench-gen [r] | --bench-drive [r] | --bench-nearby [r] [iters]");
        return 2;
    }

    string[] failed;
    foreach (path; scriptPaths) {
        if (scriptPaths.length > 1) {
            writefln("== %s", path);
        }
        if (!runScript(path, flatWorldgen)) {
            failed ~= path;
        }
    }
    if (scriptPaths.length > 1) {
        writefln("%d passed, %d failed", scriptPaths.length - failed.length, failed.length);
        foreach (path; failed) {
            writefln("  FAILED %s", path);
        }
    }
    return failed.length == 0 ? 0 : 1;
}

/// Runs one script in a fresh world; true when it ran to completion with
/// every check passing.
bool runScript(string path, bool flatWorldgen) {
    if (!exists(path)) {
        writefln("script not found: %s", path);
        return false;
    }
    Game game = Game.create(CHUNK_DIMENSION, flatWorldgen, REACH_METERS);
    game.settleWorldgen = true;
    ScriptHost host;
    host.game = &game;
    bool ok = host.run(path);
    host.close();
    game.world.worldgenDriver.stop();

    writefln("session: frames=%d time=%.2f traveled=%.2f failures=%d%s",
        host.frames, game.simTime, game.traveled / game.simCfg.metersToAbsolute,
        host.failures, ok ? "" : " error");
    return ok && host.failures == 0;
}
