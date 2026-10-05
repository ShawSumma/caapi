module headless;

import core.stdc.stdio : FILE, fclose, fopen, fprintf;
import core.stdc.string : strcmp;
import client.arguments : StartupError, FlagValue, NumberArgument, WorldgenArgument;
import client.config : ClientConfig;
import client.game : Game;
import client.script : ScriptHost;
import common.array : Array;
import common.settings : SimMeters;
import common.names : ENUM_NAMES;
import common.worldgen.generation : StructureKind, Worldgen, WorldgenKind;
import worldcheck : benchDrive, benchGen, benchMesh, benchNearby, dumpStructure, dumpWorld, printWorldDigest;

enum int EXIT_PASSED = 0;
enum int EXIT_FAILED = 1;
enum int EXIT_USAGE = 2;
enum float DEFAULT_DUMP_RADIUS = 3.0f;
enum float DEFAULT_GEN_RADIUS = 2.5f;
enum float DEFAULT_NEARBY_RADIUS = 4.5f;
enum uint DEFAULT_NEARBY_ITERATIONS = 50;

enum Command : ubyte {
    scripts,
    dumpWorld,
    worldDigest,
    dumpStructure,
    benchGen,
    benchDrive,
    benchNearby,
    benchMesh,
}

struct HeadlessArguments {
    Array!(const(char)*) scripts;
    StartupError error;
    const(char)* outputPath;
    Worldgen worldgen;
    NumberArgument radius;
    NumberArgument iterations;
    Command command;

    static HeadlessArguments fromArgv(int argc, char** argv) {
        HeadlessArguments arguments;
        int index = 1;
        while (index < argc && !arguments.error.isPresent()) {
            index = arguments.parseAt(argc, argv, index);
        }
        if (!arguments.error.isPresent()) {
            arguments.error = arguments.usageError();
        }
        return arguments;
    }

    int parseAt(int argc, char** argv, int index) {
        const(char)* argument = argv[index];
        NumberArgument number = NumberArgument.fromText(argument);
        if (strcmp(argument, "--out") == 0) {
            FlagValue value = FlagValue.fromArgv(argc, argv, index);
            outputPath = value.text;
            error = value.error;
            return index + 2;
        } else if (strcmp(argument, "--worldgen") == 0) {
            WorldgenArgument parsed = WorldgenArgument.fromArgv(argc, argv, index);
            worldgen = parsed.worldgen;
            error = parsed.error;
            return index + parsed.consumed;
        } else if (strcmp(argument, "--dump-world") == 0) {
            command = Command.dumpWorld;
            return index + 1;
        } else if (strcmp(argument, "--world-digest") == 0) {
            command = Command.worldDigest;
            return index + 1;
        } else if (strcmp(argument, "--dump-structure") == 0) {
            command = Command.dumpStructure;
            return index + 1;
        } else if (strcmp(argument, "--bench-gen") == 0) {
            command = Command.benchGen;
            return index + 1;
        } else if (strcmp(argument, "--bench-drive") == 0) {
            command = Command.benchDrive;
            return index + 1;
        } else if (strcmp(argument, "--bench-nearby") == 0) {
            command = Command.benchNearby;
            return index + 1;
        } else if (strcmp(argument, "--bench-mesh") == 0) {
            command = Command.benchMesh;
            return index + 1;
        } else if (number.isPresent && !radius.isPresent) {
            radius = number;
            return index + 1;
        } else if (number.isPresent && !iterations.isPresent) {
            iterations = number;
            return index + 1;
        } else if (number.isPresent) {
            error = StartupError(null, "too many numbers, unexpected", argument);
            return index + 1;
        } else if (argument[0] == '-') {
            error = StartupError(null, "unknown option", argument);
            return index + 1;
        } else {
            scripts.append(argument);
            return index + 1;
        }
    }

    StartupError usageError() const {
        if (outputPath is null) {
            return StartupError(null, "needs a report file", "--out");
        } else if (command == Command.scripts && scripts.length == 0) {
            return StartupError(null, "nothing to do: give scripts or a command after", "--out");
        } else if (command != Command.scripts && scripts.length > 0) {
            return StartupError(null, "scripts and a command do not mix, unexpected", scripts.ptr[0]);
        } else if (command == Command.dumpStructure && worldgen.kind != WorldgenKind.structure) {
            return StartupError(ENUM_NAMES!StructureKind[], "needs --worldgen structure <name>", "--dump-structure");
        } else {
            return StartupError.init;
        }
    }

    float commandRadius() const {
        if (radius.isPresent) {
            return radius.value;
        } else if (command == Command.dumpWorld || command == Command.worldDigest) {
            return DEFAULT_DUMP_RADIUS;
        } else if (command == Command.benchNearby) {
            return DEFAULT_NEARBY_RADIUS;
        } else {
            return DEFAULT_GEN_RADIUS;
        }
    }

    uint iterationCount() const {
        if (iterations.isPresent) {
            return cast(uint) iterations.value;
        } else {
            return DEFAULT_NEARBY_ITERATIONS;
        }
    }

}

bool runScriptFile(const(char)* path, Worldgen worldgen, FILE* report) {
    ClientConfig config;
    Game game = Game.make(worldgen, config.reachMeters);
    game.isSettlingWorldgenEachFrame = true;
    ScriptHost host = ScriptHost.make(&game, report);
    fprintf(report, "== %s\n", path);
    immutable bool isCompleted = host.run(path);
    host.close();
    fprintf(report, "session: steps=%u time=%.2f traveled=%.2f%s\n", host.steps, cast(double) game.simTime, cast(double)(game.traveled / game.simConfig.metersToAbsolute), sessionSuffix(isCompleted));
    game.release();
    return isCompleted;
}

immutable(char)* sessionSuffix(bool isCompleted) {
    if (isCompleted) {
        return "";
    } else {
        return " error";
    }
}

int runScripts(ref const HeadlessArguments arguments, FILE* report) {
    uint failed = 0;
    foreach (path; arguments.scripts.slice()) {
        immutable bool isPassed = runScriptFile(path, arguments.worldgen, report);
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

void runWorldCommand(ref const HeadlessArguments arguments, FILE* output) {
    SimMeters meters;
    float radius = arguments.commandRadius();
    if (arguments.command == Command.dumpWorld) {
        dumpWorld(output, radius, meters.chunkSize);
    } else if (arguments.command == Command.worldDigest) {
        printWorldDigest(output, radius, meters.chunkSize);
    } else if (arguments.command == Command.dumpStructure) {
        dumpStructure(output, meters.chunkSize, arguments.worldgen.structure);
    } else if (arguments.command == Command.benchGen) {
        benchGen(output, radius, meters.chunkSize);
    } else if (arguments.command == Command.benchDrive) {
        benchDrive(output, radius, meters.chunkSize);
    } else if (arguments.command == Command.benchMesh) {
        benchMesh(output, radius, meters.chunkSize);
    } else {
        benchNearby(output, radius, arguments.iterationCount(), meters.chunkSize);
    }
}

int runCommand(ref const HeadlessArguments arguments, FILE* output) {
    if (arguments.command == Command.scripts) {
        return runScripts(arguments, output);
    } else {
        runWorldCommand(arguments, output);
        return EXIT_PASSED;
    }
}

int runWithOutput(ref const HeadlessArguments arguments, const(char)* program) {
    FILE* output = fopen(arguments.outputPath, "w");
    if (output is null) {
        StartupError(null, "cannot open the report file", arguments.outputPath).report(program);
        return EXIT_FAILED;
    } else {
        int status = runCommand(arguments, output);
        fclose(output);
        return status;
    }
}

int startCommand(ref const HeadlessArguments arguments, const(char)* program) {
    if (arguments.error.isPresent()) {
        arguments.error.report(program);
        return EXIT_USAGE;
    } else {
        return runWithOutput(arguments, program);
    }
}

extern (C) int main(int argc, char** argv) {
    HeadlessArguments arguments = HeadlessArguments.fromArgv(argc, argv);
    int status = startCommand(arguments, argv[0]);
    arguments.scripts.release();
    return status;
}
