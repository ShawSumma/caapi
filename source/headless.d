module headless;

import core.stdc.stdio : FILE, fclose, fopen, fprintf;
import core.stdc.stdlib : strtof, strtoul;
import core.stdc.string : strcmp, strlen;
import client.config : ClientConfig;
import client.game : Game;
import client.script : ScriptHost;
import common.array : Array;
import common.settings : SimMeters;
import common.worldgen.generation : WorldgenLookup, WorldgenSettings;
import worldcheck : benchDrive, benchGen, benchMesh, benchNearby, dumpStructure, dumpWorld, printWorldDigest;

enum int DECIMAL = 10;
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

struct NumberArgument {
    float value;
    bool isPresent;

    static NumberArgument fromText(const(char)* text) {
        const(char)* end;
        float value = strtof(text, &end);
        return NumberArgument(value, end != text && *end == 0);
    }
}

struct HeadlessArguments {
    Array!(const(char)*) scripts;
    const(char)* outputPath;
    WorldgenSettings worldgen;
    NumberArgument radius;
    NumberArgument iterations;
    Command command;
    bool isValid = true;

    static HeadlessArguments fromArgv(int argc, char** argv) {
        HeadlessArguments arguments;
        int index = 1;
        while (index < argc) {
            const(char)* argument = argv[index];
            NumberArgument number = NumberArgument.fromText(argument);
            index += 1;
            if (strcmp(argument, "--out") == 0 && index < argc) {
                arguments.outputPath = argv[index];
                index += 1;
            } else if (strcmp(argument, "--worldgen") == 0 && index < argc) {
                WorldgenLookup lookup = WorldgenLookup.fromName(argv[index][0 .. strlen(argv[index])]);
                arguments.worldgen.kind = lookup.kind;
                arguments.isValid = arguments.isValid && lookup.isFound;
                index += 1;
            } else if (strcmp(argument, "--seed") == 0 && index < argc) {
                arguments.worldgen.seed = cast(uint) strtoul(argv[index], null, DECIMAL);
                index += 1;
            } else if (strcmp(argument, "--dump-world") == 0) {
                arguments.command = Command.dumpWorld;
            } else if (strcmp(argument, "--world-digest") == 0) {
                arguments.command = Command.worldDigest;
            } else if (strcmp(argument, "--dump-structure") == 0) {
                arguments.command = Command.dumpStructure;
            } else if (strcmp(argument, "--bench-gen") == 0) {
                arguments.command = Command.benchGen;
            } else if (strcmp(argument, "--bench-drive") == 0) {
                arguments.command = Command.benchDrive;
            } else if (strcmp(argument, "--bench-nearby") == 0) {
                arguments.command = Command.benchNearby;
            } else if (strcmp(argument, "--bench-mesh") == 0) {
                arguments.command = Command.benchMesh;
            } else if (number.isPresent && !arguments.radius.isPresent) {
                arguments.radius = number;
            } else if (number.isPresent) {
                arguments.iterations = number;
            } else if (argument[0] == '-') {
                arguments.isValid = false;
            } else {
                arguments.scripts.append(argument);
            }
        }
        return arguments;
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

    bool isUsable() const {
        return isValid && outputPath !is null && (command != Command.scripts || scripts.length > 0);
    }
}

bool runScriptFile(const(char)* path, WorldgenSettings worldgen, FILE* report) {
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
        dumpStructure(output, meters.chunkSize, arguments.worldgen.seed);
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

int runWithOutput(ref const HeadlessArguments arguments) {
    FILE* output = fopen(arguments.outputPath, "w");
    if (output is null) {
        return EXIT_FAILED;
    } else {
        int status = runCommand(arguments, output);
        fclose(output);
        return status;
    }
}

int startCommand(ref const HeadlessArguments arguments) {
    if (!arguments.isUsable()) {
        return EXIT_USAGE;
    } else {
        return runWithOutput(arguments);
    }
}

extern (C) int main(int argc, char** argv) {
    HeadlessArguments arguments = HeadlessArguments.fromArgv(argc, argv);
    int status = startCommand(arguments);
    arguments.scripts.release();
    return status;
}
