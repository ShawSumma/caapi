module headless;

import core.stdc.stdio : FILE, fclose, fopen, fprintf, snprintf;
import core.stdc.stdlib : free, malloc;
import core.stdc.string : strcmp, strlen;
import core.sys.posix.dirent : DIR, closedir, dirent, opendir, readdir;
import core.sys.posix.sys.stat : S_IFDIR, S_IFMT, stat, stat_t;
import client.arguments : StartupError, FlagValue, NumberArgument, WorldgenArgument;
import client.config : ClientConfig;
import client.game : Game;
import client.script : ScriptHost;
import base.array : Array;
import base.crash : reportCrashes;
import client.structures : StructureProblem, placeStructure;
import common.settings : CHUNK_DIMENSION;
import common.worldgen.embedded : EMBEDDED_STRUCTURE_NAMES, isLuaPath;
import common.worldgen.generation : Worldgen, WorldgenKind;
import worldcheck : benchDrive, benchGen, benchMesh, benchNearby, checkRepaint, dumpStructure, dumpWorld, printMaterialCensus, printSlices, printWorldDigest;

enum int EXIT_PASSED = 0;
enum int EXIT_FAILED = 1;
enum int EXIT_USAGE = 2;
enum float DEFAULT_DUMP_RADIUS = 3.0f;
enum float DEFAULT_GEN_RADIUS = 2.5f;
enum float DEFAULT_NEARBY_RADIUS = 4.5f;
enum uint DEFAULT_NEARBY_ITERATIONS = 50;
enum int DEFAULT_SLICE_HEIGHT = 1;

immutable string[2] SKIPPED_NAMES = ["lib", "visual"];

enum Command : ubyte {
    scripts,
    dumpWorld,
    worldDigest,
    materialCensus,
    dumpStructure,
    slices,
    checkRepaint,
    benchGen,
    benchDrive,
    benchNearby,
    benchMesh,
}

struct HeadlessArguments {
    Array!(const(char)*) scripts;
    Array!(char*) ownedPaths;
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
            appendScripts(argument);
            return index + 1;
        }
    }

    void appendScripts(const(char)* path) {
        if (isDirectory(path)) {
            Array!(char*) entries = directoryEntries(path);
            foreach (entry; entries.slice()) {
                ownedPaths.append(entry);
                if (isDirectory(entry) || isLuaPath(entry[0 .. strlen(entry)])) {
                    appendScripts(entry);
                }
            }
            entries.release();
        } else {
            scripts.append(path);
        }
    }

    void release() {
        foreach (path; ownedPaths.slice()) {
            free(path);
        }
        ownedPaths.release();
        scripts.release();
    }

    StartupError usageError() const {
        if (outputPath is null) {
            return StartupError(null, "needs a report file", "--out");
        } else if (command == Command.scripts && scripts.length == 0) {
            return StartupError(null, "nothing to do: give scripts or a command after", "--out");
        } else if (command != Command.scripts && scripts.length > 0) {
            return StartupError(null, "scripts and a command do not mix, unexpected", scripts.ptr[0]);
        } else if (command == Command.dumpStructure && worldgen.kind != WorldgenKind.structure) {
            return StartupError(EMBEDDED_STRUCTURE_NAMES[], "needs --worldgen structure <name or file.lua>", "--dump-structure");
        } else if (command == Command.checkRepaint && worldgen.kind != WorldgenKind.structure) {
            return StartupError(EMBEDDED_STRUCTURE_NAMES[], "needs --worldgen structure <name or file.lua>", "--check-repaint");
        } else if (command == Command.slices && worldgen.kind != WorldgenKind.structure) {
            return StartupError(EMBEDDED_STRUCTURE_NAMES[], "needs --worldgen structure <name or file.lua>", "--slice");
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

bool runScriptFile(const(char)* path, Worldgen worldgen, FILE* report) {
    ClientConfig config;
    Game game = Game.make(worldgen, config.reach);
    game.isGeneratingOnDemand = true;
    fprintf(report, "== %s\n", path);
    StructureProblem problem = game.placeStructure();
    bool isCompleted = false;
    if (problem.isPresent) {
        fprintf(report, "%s\n", problem.text.ptr);
    } else {
        ScriptHost host = ScriptHost.make(&game, report);
        isCompleted = host.run(path);
        host.close();
        fprintf(report, "session: steps=%u time=%.2f traveled=%.2f%s\n", host.steps, cast(double) game.time.value, cast(double) game.traveled.value, sessionSuffix(isCompleted));
    }
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

bool runWorldCommand(ref const HeadlessArguments arguments, FILE* output) {
    if (arguments.command == Command.dumpStructure) {
        return dumpStructure(output, CHUNK_DIMENSION, arguments.worldgen);
    } else if (arguments.command == Command.slices) {
        return printSlices(output, CHUNK_DIMENSION, arguments.worldgen, arguments.sliceHeight());
    } else if (arguments.command == Command.checkRepaint) {
        return checkRepaint(output, CHUNK_DIMENSION, arguments.worldgen);
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
    } else {
        benchNearby(output, radius, arguments.iterationCount(), CHUNK_DIMENSION);
    }
}

int runCommand(ref const HeadlessArguments arguments, FILE* output) {
    if (arguments.command == Command.scripts) {
        return runScripts(arguments, output);
    } else {
        immutable bool isSucceeded = runWorldCommand(arguments, output);
        if (isSucceeded) {
            return EXIT_PASSED;
        } else {
            return EXIT_FAILED;
        }
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
    reportCrashes();
    HeadlessArguments arguments = HeadlessArguments.fromArgv(argc, argv);
    int status = startCommand(arguments, argv[0]);
    arguments.release();
    return status;
}

bool isDirectory(const(char)* path) {
    stat_t status;
    immutable int result = stat(path, &status);
    return result == 0 && (status.st_mode & S_IFMT) == S_IFDIR;
}

bool isSkippedName(const(char)* name) {
    uint index = 0;
    while (index < SKIPPED_NAMES.length && strcmp(name, SKIPPED_NAMES[index].ptr) != 0) {
        index += 1;
    }
    return name[0] == '.' || index < SKIPPED_NAMES.length;
}

Array!(char*) directoryEntries(const(char)* directory) {
    Array!(char*) entries;
    DIR* stream = opendir(directory);
    if (stream !is null) {
        dirent* entry = readdir(stream);
        while (entry !is null) {
            if (!isSkippedName(entry.d_name.ptr)) {
                entries.append(joinedPath(directory, entry.d_name.ptr));
            }
            entry = readdir(stream);
        }
        closedir(stream);
    }
    sortPaths(entries.slice());
    return entries;
}

char* joinedPath(const(char)* directory, const(char)* name) {
    size_t length = strlen(directory) + strlen(name) + 2;
    char* path = cast(char*) malloc(length);
    snprintf(path, length, "%s/%s", directory, name);
    return path;
}

void sortPaths(char*[] paths) {
    foreach (index; 1 .. paths.length) {
        char* held = paths[index];
        size_t slot = index;
        while (slot > 0 && strcmp(paths[slot - 1], held) > 0) {
            paths[slot] = paths[slot - 1];
            slot -= 1;
        }
        paths[slot] = held;
    }
}
