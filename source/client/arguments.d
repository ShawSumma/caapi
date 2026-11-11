module client.arguments;

import core.stdc.stdio : FILE, fclose, fopen, fprintf, stderr, stdout;
import core.stdc.stdlib : strtof;
import core.stdc.string : strlen;
import base.maybe : Maybe;
import base.names : enumNamed;
import client.plugins : registry;
import common.worldgen.generation : PlaneWorld, STRUCTURE_NAME_CAPACITY, StructureWorld, Worldgen, WorldgenKind, degreesToRadians;

enum string VERSION = "0.0.1";
enum string VERSION_TEXT = "caapi " ~ VERSION ~ "\n";
enum string UNKNOWN_OPTION = "unknown option";
enum string NOT_A_NUMBER = "needs a number, got";
enum string REPORT_UNOPENED = "cannot open the report file";

enum string DEBUG_WORD = "debug";
immutable string[4] WORLDGEN_WORDS = ["terrain", "plane", "structure", DEBUG_WORD];

enum OptionSpec WORLDGEN_OPTION = OptionSpec("--worldgen", "terrain | plane <tilt in degrees> | structure <world> | debug <structure>", "the world to use");
enum OptionSpec OUTPUT_OPTION = OptionSpec("--out", "<file>", "where a tool writes its report (default stdout)");
enum OptionSpec HELP_OPTION = OptionSpec("--help", "", "show this text");
enum OptionSpec VERSION_OPTION = OptionSpec("--version", "", "show the version");

enum ExitStatus : int {
    ok = 0,
    failed = 1,
    usage = 2,
}

ExitStatus exitStatus(bool succeeded) {
    if (succeeded) {
        return ExitStatus.ok;
    } else {
        return ExitStatus.failed;
    }
}

struct StartupError {
    const(string)[] choices;
    const(char)* message;
    const(char)* argument;
    const(char)[] flag;

    bool isPresent() const {
        return message !is null;
    }

    void report(const(char)* program) const {
        fprintf(stderr, "%s: ", program);
        if (flag.length > 0) {
            fprintf(stderr, "%.*s ", cast(int) flag.length, flag.ptr);
        }
        fprintf(stderr, "%s", message);
        if (argument !is null) {
            fprintf(stderr, " '%s'", argument);
        }
        foreach (index, choice; choices) {
            fprintf(stderr, "%s%.*s", choiceSeparator(index), cast(int) choice.length, choice.ptr);
        }
        fprintf(stderr, "\n");
    }
}

immutable(char)* choiceSeparator(size_t index) {
    if (index == 0) {
        return ", expected one of: ";
    } else {
        return ", ";
    }
}

struct OptionSpec {
    string name;
    string value;
    string help;
}

string usageOf()(const(OptionSpec)[] options) {
    string text;
    foreach (option; options) {
        text ~= "  " ~ option.name;
        if (option.value.length > 0) {
            text ~= " " ~ option.value;
        }
        text ~= "  " ~ option.help ~ "\n";
    }
    return text;
}

Maybe!E optionNamed(E)(const(OptionSpec)[] options, const(char)[] name) {
    uint index = 0;
    while (index < options.length && options[index].name != name) {
        index += 1;
    }
    if (index < options.length) {
        return Maybe!E.of(cast(E) index);
    } else {
        return Maybe!E.init;
    }
}

const(char)[] sliceOf(const(char)* text) {
    return text[0 .. strlen(text)];
}

struct ArgumentCursor {
    char** argv;
    int count;
    int index = 1;

    bool hasMore() const {
        return index < count;
    }

    const(char)* next() {
        const(char)* argument = argv[index];
        index += 1;
        return argument;
    }

    void stop() {
        index = count;
    }
}

void parseOptions(E, A)(ref A arguments, const(OptionSpec)[] options, int argc, char** argv) {
    ArgumentCursor cursor = ArgumentCursor(argv, argc);
    while (cursor.hasMore && !arguments.error.isPresent()) {
        const(char)* argument = cursor.next();
        Maybe!E option = optionNamed!E(options, sliceOf(argument));
        if (!option.exists) {
            arguments.applyPositional(argument);
        } else if (options[option.value].value.length > 0 && !cursor.hasMore) {
            arguments.error = StartupError(null, "needs a value", null, options[option.value].name);
        } else {
            arguments.apply(option.value, cursor);
        }
    }
    if (!arguments.error.isPresent()) {
        arguments.error = arguments.usageError();
    }
}

FILE* openReport(const(char)* path) {
    if (path is null) {
        return stdout;
    } else {
        return fopen(path, "w");
    }
}

void closeReport(FILE* report) {
    if (report !is stdout) {
        fclose(report);
    }
}

Maybe!float numberIn(const(char)* text) {
    const(char)* end;
    float value = strtof(text, &end);
    if (end != text && *end == 0) {
        return Maybe!float.of(value);
    } else {
        return Maybe!float.init;
    }
}

struct WorldgenArgument {
    StartupError error;
    Worldgen worldgen;

    static WorldgenArgument from(ref ArgumentCursor cursor) {
        const(char)* kindText = cursor.next();
        Maybe!WorldgenKind kind = enumNamed!WorldgenKind(sliceOf(kindText));
        if (sliceOf(kindText) == DEBUG_WORD) {
            return WorldgenArgument.debugStructure(cursor);
        } else if (!kind.exists) {
            return WorldgenArgument(StartupError(WORLDGEN_WORDS[], "unknown worldgen", kindText), Worldgen.init);
        } else {
            return WorldgenArgument.ofKind(cursor, kind.value);
        }
    }

    static WorldgenArgument ofKind(ref ArgumentCursor cursor, WorldgenKind kind) {
        WorldgenArgument parsed = void;
        final switch (kind) {
            case WorldgenKind.terrain:
                parsed = WorldgenArgument(StartupError.init, Worldgen.makeTerrain());
                break;
            case WorldgenKind.plane:
                parsed = WorldgenArgument.plane(cursor);
                break;
            case WorldgenKind.structure:
                parsed = WorldgenArgument.structure(cursor);
                break;
        }
        return parsed;
    }

    static WorldgenArgument plane(ref ArgumentCursor cursor) {
        if (!cursor.hasMore) {
            return WorldgenArgument(StartupError(null, "plane needs a tilt in degrees"), Worldgen.init);
        } else {
            const(char)* text = cursor.next();
            Maybe!float tilt = numberIn(text);
            if (!tilt.exists) {
                return WorldgenArgument(StartupError(null, "plane tilt in degrees is not a number", text), Worldgen.init);
            } else {
                return WorldgenArgument(StartupError.init, Worldgen.fromPlane(PlaneWorld(degreesToRadians(tilt.value))));
            }
        }
    }

    static WorldgenArgument structure(ref ArgumentCursor cursor) {
        if (!cursor.hasMore) {
            return WorldgenArgument(StartupError(registry().allNames(), "structure needs a world name"), Worldgen.init);
        } else {
            const(char)* text = cursor.next();
            return WorldgenArgument.named(StructureName.ofWorld(sliceOf(text)), text);
        }
    }

    static WorldgenArgument debugStructure(ref ArgumentCursor cursor) {
        if (!cursor.hasMore) {
            return WorldgenArgument(StartupError(registry().allDebugNames(), "debug needs a structure name"), Worldgen.init);
        } else {
            const(char)* text = cursor.next();
            return WorldgenArgument.named(StructureName.ofDebug(sliceOf(text)), text);
        }
    }

    static WorldgenArgument named(StructureName name, const(char)* text) {
        if (name.problem !is null) {
            return WorldgenArgument(StartupError(name.choices, name.problem, text), Worldgen.init);
        } else {
            return WorldgenArgument(StartupError.init, Worldgen.fromStructure(name.world));
        }
    }
}

struct StructureName {
    StructureWorld world;
    const(string)[] choices;
    const(char)* problem;

    static StructureName fromText(const(char)[] text) {
        if (text.length > STRUCTURE_NAME_CAPACITY) {
            return StructureName(StructureWorld.init, null, "structure name is too long");
        } else if (registry().find(text) is null) {
            return StructureName(StructureWorld.init, registry().allNames(), "unknown structure");
        } else {
            return StructureName(StructureWorld.fromName(text), null, null);
        }
    }

    static StructureName ofWorld(const(char)[] text) {
        if (text.length <= STRUCTURE_NAME_CAPACITY && registry().findWorld(text) is null && registry().findDebug(text) !is null) {
            return StructureName(StructureWorld.init, null, "this is a debug structure, so it goes after --worldgen debug:");
        } else if (text.length <= STRUCTURE_NAME_CAPACITY && registry().findWorld(text) is null) {
            return StructureName(StructureWorld.init, registry().allNames(), "unknown world");
        } else {
            return StructureName.fromText(text);
        }
    }

    static StructureName ofDebug(const(char)[] text) {
        if (text.length <= STRUCTURE_NAME_CAPACITY && registry().findDebug(text) is null) {
            return StructureName(StructureWorld.init, registry().allDebugNames(), "unknown debug structure");
        } else {
            return StructureName.fromText(text);
        }
    }
}
