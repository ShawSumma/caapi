module headless;

import core.stdc.stdio : FILE, fflush, fprintf, printf;
import base.array : Array;
import base.clock : nowSeconds;
import base.crash : reportCrashes, reportHangAfter;
import base.maybe : Maybe;
import client.arguments : ArgumentCursor, ExitStatus, HELP_OPTION, OUTPUT_OPTION, OptionSpec, StartupError, VERSION, VERSION_OPTION, WORLDGEN_OPTION, WorldgenArgument, closeReport, exitStatus, numberIn, openReport, optionNamed, parseOptions, sliceOf, usageOf;
import client.config : ClientConfig;
import client.game : ChunkSupply, Game;
import client.plugins : registry;
import client.script : NamedScript, Script;
import client.structures : StructureProblem, placeStructure;
import common.settings : CHUNK_DIMENSION;
import common.worldgen.generation : Worldgen, WorldgenKind;
import scripts.films : FILMS;
import scripts.tests : TESTS;
import scripts.views : VIEWS;
import worldcheck : benchDrive, benchGen, benchHashMap, benchMesh, benchNearby, checkForget, checkRepaint, dumpStructure, dumpWorld, printMaterialCensus, printSlices, printSurfaceCensus, printWorldDigest;

enum float DEFAULT_DUMP_RADIUS = 3.0f;
enum float DEFAULT_GEN_RADIUS = 2.5f;
enum float DEFAULT_NEARBY_RADIUS = 4.5f;
enum uint DEFAULT_NEARBY_ITERATIONS = 50;
enum int DEFAULT_SLICE_HEIGHT = 1;
enum uint TEST_HANG_SECONDS = 120;
enum string USAGE = "usage: mined-headless [options] <command> [name prefix ...]\noptions:\n" ~ usageOf(OPTIONS[]) ~ "commands:\n" ~ usageOf(COMMANDS[]);

enum Option : ubyte {
    worldgen,
    output,
    radius,
    iterations,
    height,
    help,
    showVersion,
}

immutable OptionSpec[Option.max + 1] OPTIONS = [
    Option.worldgen: WORLDGEN_OPTION,
    Option.output: OUTPUT_OPTION,
    Option.radius: OptionSpec("--radius", "<units>", "how far a census, dump or benchmark reaches"),
    Option.iterations: OptionSpec("--iterations", "<count>", "how many times bench-nearby runs"),
    Option.height: OptionSpec("--height", "<cells>", "the height slice prints"),
    Option.help: HELP_OPTION,
    Option.showVersion: VERSION_OPTION,
];

enum Command : ubyte {
    tests,
    views,
    films,
    worldDigest,
    dumpWorld,
    materialCensus,
    surfaceCensus,
    dumpStructure,
    slice,
    checkRepaint,
    checkForget,
    benchGen,
    benchMesh,
    benchDrive,
    benchNearby,
    benchHashMap,
}

immutable OptionSpec[Command.max + 1] COMMANDS = [
    Command.tests: OptionSpec("tests", "", "run the behavior tests (all, or those whose names start with a prefix)"),
    Command.views: OptionSpec("views", "", "run the screenshot view scripts without rendering, to check they still run"),
    Command.films: OptionSpec("films", "", "run the film shots without rendering, to check they still run"),
    Command.worldDigest: OptionSpec("world-digest", "", "hash the terrain world"),
    Command.dumpWorld: OptionSpec("dump-world", "", "print the terrain world"),
    Command.materialCensus: OptionSpec("material-census", "", "count the terrain world's materials"),
    Command.surfaceCensus: OptionSpec("surface-census", "", "count the terrain world's surfaces"),
    Command.dumpStructure: OptionSpec("dump-structure", "", "print a structure world"),
    Command.slice: OptionSpec("slice", "", "print slices of a structure world"),
    Command.checkRepaint: OptionSpec("check-repaint", "", "check a dropped tile repaints identically"),
    Command.checkForget: OptionSpec("check-forget", "", "check evicted structure state regenerates identically"),
    Command.benchGen: OptionSpec("bench-gen", "", "benchmark generation"),
    Command.benchMesh: OptionSpec("bench-mesh", "", "benchmark meshing"),
    Command.benchDrive: OptionSpec("bench-drive", "", "benchmark driving through the world"),
    Command.benchNearby: OptionSpec("bench-nearby", "", "benchmark the nearby traversal"),
    Command.benchHashMap: OptionSpec("bench-hashmap", "", "benchmark the hash map"),
];

enum RunKind : ubyte {
    command,
    help,
    showVersion,
}

struct HeadlessArguments {
    Array!(const(char)*) prefixes;
    StartupError error;
    const(char)* outputPath;
    Worldgen worldgen;
    Maybe!float radius;
    Maybe!float iterations;
    Maybe!float height;
    Maybe!Command command;
    RunKind kind;

    static HeadlessArguments fromArgv(int argc, char** argv) {
        HeadlessArguments arguments;
        arguments.parseOptions!Option(OPTIONS[], argc, argv);
        return arguments;
    }

    void apply(Option option, ref ArgumentCursor cursor) {
        final switch (option) {
            case Option.worldgen:
                parseWorldgen(cursor);
                break;
            case Option.output:
                outputPath = cursor.next();
                break;
            case Option.radius:
                radius = number(option, cursor.next());
                break;
            case Option.iterations:
                iterations = number(option, cursor.next());
                break;
            case Option.height:
                height = number(option, cursor.next());
                break;
            case Option.help:
                kind = RunKind.help;
                cursor.stop();
                break;
            case Option.showVersion:
                kind = RunKind.showVersion;
                cursor.stop();
                break;
        }
    }

    void applyPositional(const(char)* argument) {
        if (argument[0] == '-') {
            error = StartupError(null, "unknown option", argument);
        } else if (!command.exists) {
            command = optionNamed!Command(COMMANDS[], sliceOf(argument));
            if (!command.exists) {
                error = StartupError(null, "unknown command", argument);
            }
        } else if (takesPrefixes()) {
            prefixes.append(argument);
        } else {
            error = StartupError(null, "unexpected", argument);
        }
    }

    void parseWorldgen(ref ArgumentCursor cursor) {
        WorldgenArgument parsed = WorldgenArgument.from(cursor);
        worldgen = parsed.worldgen;
        error = parsed.error;
    }

    Maybe!float number(Option option, const(char)* text) {
        Maybe!float parsed = numberIn(text);
        if (!parsed.exists) {
            error = StartupError(null, "needs a number, got", text, OPTIONS[option].name);
        }
        return parsed;
    }

    bool takesPrefixes() const {
        return command.value == Command.tests || command.value == Command.views || command.value == Command.films;
    }

    bool needsStructure() const {
        return command.value == Command.dumpStructure || command.value == Command.slice || command.value == Command.checkRepaint || command.value == Command.checkForget;
    }

    StartupError usageError() const {
        if (kind != RunKind.command) {
            return StartupError.init;
        } else if (!command.exists) {
            return StartupError(null, "nothing to do: give a command");
        } else if (needsStructure() && worldgen.kind != WorldgenKind.structure) {
            return StartupError(registry().allNames(), "needs a structure world", null, COMMANDS[command.value].name);
        } else {
            return StartupError.init;
        }
    }

    float commandRadius() const {
        if (radius.exists) {
            return radius.value;
        } else if (command.value == Command.dumpWorld || command.value == Command.worldDigest || command.value == Command.materialCensus || command.value == Command.surfaceCensus) {
            return DEFAULT_DUMP_RADIUS;
        } else if (command.value == Command.benchNearby) {
            return DEFAULT_NEARBY_RADIUS;
        } else {
            return DEFAULT_GEN_RADIUS;
        }
    }

    int sliceHeight() const {
        if (height.exists) {
            return cast(int) height.value;
        } else {
            return DEFAULT_SLICE_HEIGHT;
        }
    }

    uint iterationCount() const {
        if (iterations.exists) {
            return cast(uint) iterations.value;
        } else {
            return DEFAULT_NEARBY_ITERATIONS;
        }
    }
}

bool isChosen(ref const HeadlessArguments arguments, string name) {
    size_t index = 0;
    while (index < arguments.prefixes.length && !isPrefixOf(sliceOf(arguments.prefixes.ptr[index]), name)) {
        index += 1;
    }
    return arguments.prefixes.length == 0 || index < arguments.prefixes.length;
}

bool isPrefixOf(const(char)[] prefix, string name) {
    return prefix.length <= name.length && name[0 .. prefix.length] == prefix;
}

ExitStatus runTest(ref const NamedScript test, Worldgen worldgen, FILE* report) {
    double start = nowSeconds();
    fprintf(report, "== %.*s\n", cast(int) test.name.length, test.name.ptr);
    fflush(report);
    reportHangAfter(TEST_HANG_SECONDS);
    ClientConfig config;
    Game game = Game.make(worldgen, config.reach);
    game.supply = ChunkSupply.onDemand;
    StructureProblem problem = game.placeStructure();
    ExitStatus status = ExitStatus.failed;
    if (problem.isPresent) {
        fprintf(report, "%s\n", problem.text.ptr);
    } else {
        Script script = Script.make(&game, report);
        status = script.run(test.run);
        fprintf(report, "session: steps=%u time=%.2f traveled=%.2f wall=%.1fs%s\n", script.steps, cast(double) game.time.value, cast(double) game.traveled.value, nowSeconds() - start, sessionSuffix(status));
    }
    fflush(report);
    game.release();
    return status;
}

immutable(char)* sessionSuffix(ExitStatus status) {
    if (status == ExitStatus.ok) {
        return "";
    } else {
        return " error";
    }
}

ExitStatus runFilms(ref const HeadlessArguments arguments, FILE* report) {
    ExitStatus status = ExitStatus.ok;
    foreach (ref film; FILMS) {
        ExitStatus ran = runScripts(arguments, film.shots, report);
        if (ran != ExitStatus.ok) {
            status = ExitStatus.failed;
        }
    }
    return status;
}

ExitStatus runScripts(ref const HeadlessArguments arguments, const(NamedScript)[] scripts, FILE* report) {
    uint passed = 0;
    uint failed = 0;
    foreach (ref test; scripts) {
        if (arguments.isChosen(test.name)) {
            ExitStatus ran = runTest(test, arguments.worldgen, report);
            if (ran == ExitStatus.ok) {
                passed += 1;
            } else {
                failed += 1;
            }
        }
    }
    fprintf(report, "%u passed, %u failed\n", passed, failed);
    return exitStatus(failed == 0);
}

ExitStatus runCommand(ref const HeadlessArguments arguments, FILE* output) {
    float radius = arguments.commandRadius();
    ExitStatus status = ExitStatus.ok;
    final switch (arguments.command.value) {
        case Command.tests:
            status = runScripts(arguments, TESTS, output);
            break;
        case Command.views:
            status = runScripts(arguments, VIEWS, output);
            break;
        case Command.films:
            status = runFilms(arguments, output);
            break;
        case Command.worldDigest:
            printWorldDigest(output, radius, CHUNK_DIMENSION);
            break;
        case Command.dumpWorld:
            dumpWorld(output, radius, CHUNK_DIMENSION);
            break;
        case Command.materialCensus:
            printMaterialCensus(output, radius, CHUNK_DIMENSION);
            break;
        case Command.surfaceCensus:
            printSurfaceCensus(output, radius, CHUNK_DIMENSION);
            break;
        case Command.dumpStructure:
            status = dumpStructure(output, CHUNK_DIMENSION, arguments.worldgen);
            break;
        case Command.slice:
            status = printSlices(output, CHUNK_DIMENSION, arguments.worldgen, arguments.sliceHeight());
            break;
        case Command.checkRepaint:
            status = checkRepaint(output, CHUNK_DIMENSION, arguments.worldgen);
            break;
        case Command.checkForget:
            status = checkForget(output, CHUNK_DIMENSION, arguments.worldgen);
            break;
        case Command.benchGen:
            benchGen(output, radius, CHUNK_DIMENSION);
            break;
        case Command.benchMesh:
            benchMesh(output, radius, CHUNK_DIMENSION);
            break;
        case Command.benchDrive:
            benchDrive(output, radius, CHUNK_DIMENSION);
            break;
        case Command.benchNearby:
            benchNearby(output, radius, arguments.iterationCount(), CHUNK_DIMENSION);
            break;
        case Command.benchHashMap:
            benchHashMap(output);
            break;
    }
    return status;
}

ExitStatus runWithOutput(ref const HeadlessArguments arguments, const(char)* program) {
    FILE* output = openReport(arguments.outputPath);
    if (output is null) {
        StartupError(null, "cannot open the report file", arguments.outputPath).report(program);
        return ExitStatus.failed;
    } else {
        ExitStatus status = runCommand(arguments, output);
        closeReport(output);
        return status;
    }
}

ExitStatus startCommand(ref const HeadlessArguments arguments, const(char)* program) {
    if (arguments.error.isPresent()) {
        arguments.error.report(program);
        return ExitStatus.usage;
    } else if (arguments.kind == RunKind.help) {
        printf("%.*s", cast(int) USAGE.length, USAGE.ptr);
        return ExitStatus.ok;
    } else if (arguments.kind == RunKind.showVersion) {
        printf("mined %s\n", VERSION.ptr);
        return ExitStatus.ok;
    } else {
        return runWithOutput(arguments, program);
    }
}

extern (C) int main(int argc, char** argv) {
    reportCrashes();
    HeadlessArguments arguments = HeadlessArguments.fromArgv(argc, argv);
    ExitStatus status = startCommand(arguments, argv[0]);
    arguments.prefixes.release();
    return status;
}
