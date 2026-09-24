module headless;

import core.stdc.stdio : FILE, fclose, fopen, fprintf;
import core.stdc.stdlib : strtof;
import core.stdc.string : strcmp;
import client.config : ClientConfig;
import client.game : Game, createGame, releaseGame;
import client.script : ScriptHost, closeScript, runScript;
import common.array : Array;
import common.sim_config : SimConfigRaw;
import worldcheck : benchDrive, benchGen, benchNearby, dumpWorld;

enum int EXIT_PASSED = 0;
enum int EXIT_FAILED = 1;
enum int EXIT_USAGE = 2;
enum float DEFAULT_DUMP_RADIUS = 3.0f;
enum float DEFAULT_GEN_RADIUS = 2.5f;
enum float DEFAULT_NEARBY_RADIUS = 4.5f;
enum uint DEFAULT_NEARBY_ITERATIONS = 50;

enum Command : ubyte {
    Scripts,
    DumpWorld,
    BenchGen,
    BenchDrive,
    BenchNearby,
}

struct NumberArgument {
    float value;
    bool present;
}

struct HeadlessArguments {
    Array!(const(char)*) scripts;
    const(char)* outputPath;
    NumberArgument radius;
    NumberArgument iterations;
    Command command;
    bool flatWorldgen;
    bool valid = true;
}

NumberArgument parseNumber(const(char)* text) {
    const(char)* end;
    NumberArgument result;
    result.value = strtof(text, &end);
    result.present = end != text && *end == 0;
    return result;
}

HeadlessArguments parseArguments(int argc, char** argv) {
    HeadlessArguments arguments;
    int index = 1;
    while (index < argc) {
        const(char)* argument = argv[index];
        index += 1;
        if (strcmp(argument, "--out") == 0 && index < argc) {
            arguments.outputPath = argv[index];
            index += 1;
        } else if (strcmp(argument, "--flat") == 0) {
            arguments.flatWorldgen = true;
        } else if (strcmp(argument, "--dump-world") == 0) {
            arguments.command = Command.DumpWorld;
        } else if (strcmp(argument, "--bench-gen") == 0) {
            arguments.command = Command.BenchGen;
        } else if (strcmp(argument, "--bench-drive") == 0) {
            arguments.command = Command.BenchDrive;
        } else if (strcmp(argument, "--bench-nearby") == 0) {
            arguments.command = Command.BenchNearby;
        } else if (parseNumber(argument).present && !arguments.radius.present) {
            arguments.radius = parseNumber(argument);
        } else if (parseNumber(argument).present) {
            arguments.iterations = parseNumber(argument);
        } else if (argument[0] == '-') {
            arguments.valid = false;
        } else {
            arguments.scripts.append(argument);
        }
    }
    return arguments;
}

float radiusOr(HeadlessArguments arguments, float fallback) {
    float result = fallback;
    if (arguments.radius.present) {
        result = arguments.radius.value;
    }
    return result;
}

bool runScriptFile(const(char)* path, bool flatWorldgen, FILE* report) {
    ClientConfig config;
    Game game = createGame(flatWorldgen, config.reachMeters);
    game.settleWorldgenEachFrame = true;
    ScriptHost host;
    host.game = &game;
    host.report = report;
    if (report !is null) {
        fprintf(report, "== %s\n", path);
    }
    bool ok = runScript(&host, path);
    closeScript(&host);
    if (report !is null) {
        const(char)* suffix = "";
        if (!ok) {
            suffix = " error";
        }
        fprintf(report, "session: frames=%u time=%.2f traveled=%.2f failures=%u%s\n", host.frames, cast(double) game.simTime, cast(double)(game.traveled / game.simConfig.metersToAbsolute), host.failures, suffix);
    }
    releaseGame(&game);
    return ok && host.failures == 0;
}

int runScripts(HeadlessArguments arguments, FILE* report) {
    uint failed = 0;
    foreach (path; arguments.scripts.slice()) {
        if (!runScriptFile(path, arguments.flatWorldgen, report)) {
            failed += 1;
        }
    }
    if (report !is null) {
        fprintf(report, "%u passed, %u failed\n", cast(uint) arguments.scripts.length - failed, failed);
    }
    int status = EXIT_PASSED;
    if (failed > 0) {
        status = EXIT_FAILED;
    }
    return status;
}

int runWorldCommand(HeadlessArguments arguments, FILE* output) {
    SimConfigRaw raw;
    if (arguments.command == Command.DumpWorld) {
        dumpWorld(output, radiusOr(arguments, DEFAULT_DUMP_RADIUS), raw.chunkSize);
    } else if (arguments.command == Command.BenchGen) {
        benchGen(output, radiusOr(arguments, DEFAULT_GEN_RADIUS), raw.chunkSize);
    } else if (arguments.command == Command.BenchDrive) {
        benchDrive(output, radiusOr(arguments, DEFAULT_GEN_RADIUS), raw.chunkSize);
    } else {
        uint iterations = DEFAULT_NEARBY_ITERATIONS;
        if (arguments.iterations.present) {
            iterations = cast(uint) arguments.iterations.value;
        }
        benchNearby(output, radiusOr(arguments, DEFAULT_NEARBY_RADIUS), iterations, raw.chunkSize);
    }
    return EXIT_PASSED;
}

extern (C) int main(int argc, char** argv) {
    HeadlessArguments arguments = parseArguments(argc, argv);
    FILE* output = null;
    if (arguments.outputPath !is null) {
        output = fopen(arguments.outputPath, "w");
    }
    int status = EXIT_USAGE;
    if (arguments.valid && arguments.command == Command.Scripts && arguments.scripts.length > 0) {
        status = runScripts(arguments, output);
    } else if (arguments.valid && arguments.command != Command.Scripts && output !is null) {
        status = runWorldCommand(arguments, output);
    }
    if (output !is null) {
        fclose(output);
    }
    arguments.scripts.release();
    return status;
}
