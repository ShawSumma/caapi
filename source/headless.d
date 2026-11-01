module headless;

import core.stdc.stdio : FILE, fclose, fopen, fprintf, printf;
import core.stdc.string : strcmp, strlen;
import base.array : Array;
import base.crash : reportCrashes;
import client.arguments : EXIT_FAILED, EXIT_OK, EXIT_USAGE, FlagValue, NumberArgument, StartupError, VERSION, WorldgenArgument, exitStatus;
import client.config : ClientConfig;
import client.game : Game;
import client.plugins : registry;
import client.script : NamedScript, Script;
import client.structures : StructureProblem, placeStructure;
import common.settings : CHUNK_DIMENSION;
import common.worldgen.generation : Worldgen, WorldgenKind;
import scripts.films : FILMS;
import scripts.tests : TESTS;
import scripts.views : VIEWS;
import worldcheck : benchDrive, benchGen, benchHashMap, benchMesh, benchNearby, checkForget, checkRepaint, dumpStructure, dumpWorld, printMaterialCensus, printSlices, printWorldDigest;

enum float DEFAULT_DUMP_RADIUS = 3.0f;
enum float DEFAULT_GEN_RADIUS = 2.5f;
enum float DEFAULT_NEARBY_RADIUS = 4.5f;
enum uint DEFAULT_NEARBY_ITERATIONS = 50;
enum int DEFAULT_SLICE_HEIGHT = 1;
enum string USAGE = "usage: mined-headless --out <report> --tests [name prefix ...]
       mined-headless --out <report> [--worldgen <world>] <command> [radius] [iterations]
  --worldgen terrain | plane <tilt in degrees> | structure <world>
commands:
  --tests [name prefix ...]   run the behavior tests (all, or those whose names start with a prefix)
  --views [name prefix ...]   run the screenshot view scripts without rendering, to check they still run
  --films [name prefix ...]   run the film shots without rendering, to check they still run
  --world-digest, --dump-world, --material-census [radius]
  --dump-structure, --check-repaint, --check-forget, --slice [height]   (need --worldgen structure <world>)
  --bench-gen [radius], --bench-mesh [radius], --bench-drive [radius]
  --bench-nearby [radius] [iterations], --bench-hashmap
  --help, --version
";

enum Command : ubyte {
    none,
    tests,
    views,
    films,
    dumpWorld,
    worldDigest,
    materialCensus,
    dumpStructure,
    slices,
    checkRepaint,
    checkForget,
    benchGen,
    benchDrive,
    benchNearby,
    benchMesh,
    benchHashMap,
}

struct HeadlessArguments {
    Array!(const(char)*) prefixes;
    StartupError error;
    const(char)* outputPath;
    Worldgen worldgen;
    NumberArgument radius;
    NumberArgument iterations;
    Command command;
    bool isHelp;
    bool isVersion;

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
        } else if (strcmp(argument, "--tests") == 0) {
            command = Command.tests;
            return index + 1;
        } else if (strcmp(argument, "--views") == 0) {
            command = Command.views;
            return index + 1;
        } else if (strcmp(argument, "--films") == 0) {
            command = Command.films;
            return index + 1;
        } else if (strcmp(argument, "--dump-world") == 0) {
            command = Command.dumpWorld;
            return index + 1;
        } else if (strcmp(argument, "--world-digest") == 0) {
            command = Command.worldDigest;
            return index + 1;
        } else if (strcmp(argument, "--material-census") == 0) {
            command = Command.materialCensus;
            return index + 1;
        } else if (strcmp(argument, "--dump-structure") == 0) {
            command = Command.dumpStructure;
            return index + 1;
        } else if (strcmp(argument, "--slice") == 0) {
            command = Command.slices;
            return index + 1;
        } else if (strcmp(argument, "--check-repaint") == 0) {
            command = Command.checkRepaint;
            return index + 1;
        } else if (strcmp(argument, "--check-forget") == 0) {
            command = Command.checkForget;
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
        } else if (strcmp(argument, "--bench-hashmap") == 0) {
            command = Command.benchHashMap;
            return index + 1;
        } else if (strcmp(argument, "--help") == 0) {
            isHelp = true;
            return index + 1;
        } else if (strcmp(argument, "--version") == 0) {
            isVersion = true;
            return index + 1;
        } else if ((command == Command.tests || command == Command.views || command == Command.films) && argument[0] != '-') {
            prefixes.append(argument);
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
        } else {
            error = StartupError(null, "unknown argument", argument);
            return index + 1;
        }
    }

    StartupError usageError() const {
        if (isHelp || isVersion) {
            return StartupError.init;
        } else if (outputPath is null) {
            return StartupError(null, "needs a report file", "--out");
        } else if (command == Command.none) {
            return StartupError(null, "nothing to do: give a command after", "--out");
        } else if (command == Command.dumpStructure && worldgen.kind != WorldgenKind.structure) {
            return StartupError(registry().allNames(), "needs --worldgen structure <name>", "--dump-structure");
        } else if (command == Command.checkRepaint && worldgen.kind != WorldgenKind.structure) {
            return StartupError(registry().allNames(), "needs --worldgen structure <name>", "--check-repaint");
        } else if (command == Command.checkForget && worldgen.kind != WorldgenKind.structure) {
            return StartupError(registry().allNames(), "needs --worldgen structure <name>", "--check-forget");
        } else if (command == Command.slices && worldgen.kind != WorldgenKind.structure) {
            return StartupError(registry().allNames(), "needs --worldgen structure <name>", "--slice");
        } else {
            return StartupError.init;
        }
    }

    float commandRadius() const {
        if (radius.isPresent) {
            return radius.value;
        } else if (command == Command.dumpWorld || command == Command.worldDigest || command == Command.materialCensus) {
            return DEFAULT_DUMP_RADIUS;
        } else if (command == Command.benchNearby) {
            return DEFAULT_NEARBY_RADIUS;
        } else {
            return DEFAULT_GEN_RADIUS;
        }
    }

    int sliceHeight() const {
        if (radius.isPresent) {
            return cast(int) radius.value;
        } else {
            return DEFAULT_SLICE_HEIGHT;
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

bool isChosen(ref const HeadlessArguments arguments, string name) {
    size_t index = 0;
    while (index < arguments.prefixes.length && !isPrefixOf(arguments.prefixes.ptr[index], name)) {
        index += 1;
    }
    return arguments.prefixes.length == 0 || index < arguments.prefixes.length;
}

bool isPrefixOf(const(char)* prefix, string name) {
    size_t length = strlen(prefix);
    return length <= name.length && name[0 .. length] == prefix[0 .. length];
}

bool runTest(ref const NamedScript test, Worldgen worldgen, FILE* report) {
    ClientConfig config;
    Game game = Game.make(worldgen, config.reach);
    game.isGeneratingOnDemand = true;
    fprintf(report, "== %.*s\n", cast(int) test.name.length, test.name.ptr);
    StructureProblem problem = game.placeStructure();
    bool isPassed = false;
    if (problem.isPresent) {
        fprintf(report, "%s\n", problem.text.ptr);
    } else {
        Script script = Script.make(&game, report);
        isPassed = script.run(test.run);
        fprintf(report, "session: steps=%u time=%.2f traveled=%.2f%s\n", script.steps, cast(double) game.time.value, cast(double) game.traveled.value, sessionSuffix(isPassed));
    }
    game.release();
    return isPassed;
}

immutable(char)* sessionSuffix(bool isPassed) {
    if (isPassed) {
        return "";
    } else {
        return " error";
    }
}

bool runFilms(ref const HeadlessArguments arguments, FILE* report) {
    bool isPassed = true;
    foreach (ref film; FILMS) {
        isPassed = runScripts(arguments, film.shots, report) && isPassed;
    }
    return isPassed;
}

bool runScripts(ref const HeadlessArguments arguments, const(NamedScript)[] scripts, FILE* report) {
    uint passed = 0;
    uint failed = 0;
    foreach (ref test; scripts) {
        if (arguments.isChosen(test.name)) {
            if (runTest(test, arguments.worldgen, report)) {
                passed += 1;
            } else {
                failed += 1;
            }
        }
    }
    fprintf(report, "%u passed, %u failed\n", passed, failed);
    return failed == 0;
}

bool runWorldCommand(ref const HeadlessArguments arguments, FILE* output) {
    if (arguments.command == Command.tests) {
        return runScripts(arguments, TESTS, output);
    } else if (arguments.command == Command.views) {
        return runScripts(arguments, VIEWS, output);
    } else if (arguments.command == Command.films) {
        return runFilms(arguments, output);
    } else if (arguments.command == Command.dumpStructure) {
        return dumpStructure(output, CHUNK_DIMENSION, arguments.worldgen);
    } else if (arguments.command == Command.slices) {
        return printSlices(output, CHUNK_DIMENSION, arguments.worldgen, arguments.sliceHeight());
    } else if (arguments.command == Command.checkRepaint) {
        return checkRepaint(output, CHUNK_DIMENSION, arguments.worldgen);
    } else if (arguments.command == Command.checkForget) {
        return checkForget(output, CHUNK_DIMENSION, arguments.worldgen);
    } else {
        runMeasurement(arguments, output);
        return true;
    }
}

void runMeasurement(ref const HeadlessArguments arguments, FILE* output) {
    float radius = arguments.commandRadius();
    if (arguments.command == Command.dumpWorld) {
        dumpWorld(output, radius, CHUNK_DIMENSION);
    } else if (arguments.command == Command.worldDigest) {
        printWorldDigest(output, radius, CHUNK_DIMENSION);
    } else if (arguments.command == Command.materialCensus) {
        printMaterialCensus(output, radius, CHUNK_DIMENSION);
    } else if (arguments.command == Command.benchGen) {
        benchGen(output, radius, CHUNK_DIMENSION);
    } else if (arguments.command == Command.benchDrive) {
        benchDrive(output, radius, CHUNK_DIMENSION);
    } else if (arguments.command == Command.benchMesh) {
        benchMesh(output, radius, CHUNK_DIMENSION);
    } else if (arguments.command == Command.benchHashMap) {
        benchHashMap(output);
    } else {
        benchNearby(output, radius, arguments.iterationCount(), CHUNK_DIMENSION);
    }
}

int runWithOutput(ref const HeadlessArguments arguments, const(char)* program) {
    FILE* output = fopen(arguments.outputPath, "w");
    if (output is null) {
        StartupError(null, "cannot open the report file", arguments.outputPath).report(program);
        return EXIT_FAILED;
    } else {
        int status = exitStatus(runWorldCommand(arguments, output));
        fclose(output);
        return status;
    }
}

int startCommand(ref const HeadlessArguments arguments, const(char)* program) {
    if (arguments.error.isPresent()) {
        arguments.error.report(program);
        return EXIT_USAGE;
    } else if (arguments.isHelp) {
        printf("%s", USAGE.ptr);
        return EXIT_OK;
    } else if (arguments.isVersion) {
        printf("mined %s\n", VERSION.ptr);
        return EXIT_OK;
    } else {
        return runWithOutput(arguments, program);
    }
}

extern (C) int main(int argc, char** argv) {
    reportCrashes();
    HeadlessArguments arguments = HeadlessArguments.fromArgv(argc, argv);
    int status = startCommand(arguments, argv[0]);
    arguments.prefixes.release();
    return status;
}
