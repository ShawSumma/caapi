module headless;

import core.stdc.stdio : FILE, fclose, fopen, fprintf;
import core.stdc.stdlib : strtof;
import core.stdc.string : strcmp;
import client.config : ClientConfig;
import client.game : Game;
import client.script : ScriptHost;
import common.array : Array;
import common.sim_config : SimConfigRaw;
import worldcheck : benchDrive, benchGen, benchMesh, benchNearby, dumpWorld;

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
    BenchMesh,
}

struct NumberArgument {
    float value;
    bool isPresent;
}

struct HeadlessArguments {
    Array!(const(char)*) scripts;
    const(char)* outputPath;
    NumberArgument radius;
    NumberArgument iterations;
    Command command;
    bool isFlat;
    bool isValid = true;

    float radiusOr(float fallback) const {
        if (radius.isPresent) {
            return radius.value;
        } else {
            return fallback;
        }
    }

    bool isUsable() const {
        return isValid && outputPath !is null && (command != Command.Scripts || scripts.length > 0);
    }
}

NumberArgument parseNumber(const(char)* text) {
    const(char)* end;
    NumberArgument result;
    result.value = strtof(text, &end);
    result.isPresent = end != text && *end == 0;
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
            arguments.isFlat = true;
        } else if (strcmp(argument, "--dump-world") == 0) {
            arguments.command = Command.DumpWorld;
        } else if (strcmp(argument, "--bench-gen") == 0) {
            arguments.command = Command.BenchGen;
        } else if (strcmp(argument, "--bench-drive") == 0) {
            arguments.command = Command.BenchDrive;
        } else if (strcmp(argument, "--bench-nearby") == 0) {
            arguments.command = Command.BenchNearby;
        } else if (strcmp(argument, "--bench-mesh") == 0) {
            arguments.command = Command.BenchMesh;
        } else if (parseNumber(argument).isPresent && !arguments.radius.isPresent) {
            arguments.radius = parseNumber(argument);
        } else if (parseNumber(argument).isPresent) {
            arguments.iterations = parseNumber(argument);
        } else if (argument[0] == '-') {
            arguments.isValid = false;
        } else {
            arguments.scripts.append(argument);
        }
    }
    return arguments;
}

bool runScriptFile(const(char)* path, bool isFlat, FILE* report) {
    ClientConfig config;
    Game game = Game.make(isFlat, config.reachMeters);
    game.isSettlingWorldgenEachFrame = true;
    ScriptHost host;
    host.game = &game;
    host.report = report;
    fprintf(report, "== %s\n", path);
    immutable bool isCompleted = host.run(path);
    host.close();
    fprintf(report, "session: frames=%u time=%.2f traveled=%.2f failures=%u%s\n", host.frames, cast(double) game.simTime, cast(double)(game.traveled / game.simConfig.metersToAbsolute), host.failures, sessionSuffix(isCompleted));
    game.release();
    return isCompleted && host.failures == 0;
}

immutable(char)* sessionSuffix(bool isCompleted) {
    if (isCompleted) {
        return "";
    } else {
        return " error";
    }
}

int runScripts(const(HeadlessArguments)* arguments, FILE* report) {
    uint failed = 0;
    foreach (path; arguments.scripts.slice()) {
        immutable bool isPassed = runScriptFile(path, arguments.isFlat, report);
        if (!isPassed) {
            failed += 1;
        }
    }
    fprintf(report, "%u passed, %u failed\n", cast(uint) arguments.scripts.length - failed, failed);
    if (failed > 0) {
        return EXIT_FAILED;
    } else {
        return EXIT_PASSED;
    }
}

void runWorldCommand(const(HeadlessArguments)* arguments, FILE* output) {
    SimConfigRaw raw;
    if (arguments.command == Command.DumpWorld) {
        dumpWorld(output, arguments.radiusOr(DEFAULT_DUMP_RADIUS), raw.chunkSize);
    } else if (arguments.command == Command.BenchGen) {
        benchGen(output, arguments.radiusOr(DEFAULT_GEN_RADIUS), raw.chunkSize);
    } else if (arguments.command == Command.BenchDrive) {
        benchDrive(output, arguments.radiusOr(DEFAULT_GEN_RADIUS), raw.chunkSize);
    } else if (arguments.command == Command.BenchMesh) {
        benchMesh(output, arguments.radiusOr(DEFAULT_GEN_RADIUS), raw.chunkSize);
    } else if (arguments.iterations.isPresent) {
        benchNearby(output, arguments.radiusOr(DEFAULT_NEARBY_RADIUS), cast(uint) arguments.iterations.value, raw.chunkSize);
    } else {
        benchNearby(output, arguments.radiusOr(DEFAULT_NEARBY_RADIUS), DEFAULT_NEARBY_ITERATIONS, raw.chunkSize);
    }
}

int runCommand(const(HeadlessArguments)* arguments, FILE* output) {
    if (arguments.command == Command.Scripts) {
        return runScripts(arguments, output);
    } else {
        runWorldCommand(arguments, output);
        return EXIT_PASSED;
    }
}

int runWithOutput(const(HeadlessArguments)* arguments) {
    FILE* output = fopen(arguments.outputPath, "w");
    if (output is null) {
        return EXIT_FAILED;
    } else {
        immutable int status = runCommand(arguments, output);
        fclose(output);
        return status;
    }
}

extern (C) int main(int argc, char** argv) {
    HeadlessArguments arguments = parseArguments(argc, argv);
    immutable int status = startCommand(&arguments);
    arguments.scripts.release();
    return status;
}

int startCommand(const(HeadlessArguments)* arguments) {
    if (!arguments.isUsable()) {
        return EXIT_USAGE;
    } else {
        return runWithOutput(arguments);
    }
}
