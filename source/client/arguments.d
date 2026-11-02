module client.arguments;

import core.stdc.stdio : fprintf, stderr;
import core.stdc.stdlib : strtof;
import core.stdc.string : strlen;
import base.maybe : Maybe;
import base.names : ENUM_NAMES, enumNamed;
import client.plugins : registry;
import common.worldgen.generation : PlaneWorld, STRUCTURE_NAME_CAPACITY, StructureWorld, Worldgen, WorldgenKind, degreesToRadians;

enum string VERSION = "0.0.1";

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

    bool isPresent() const {
        return message !is null;
    }

    void report(const(char)* program) const {
        fprintf(stderr, "%s: %s", program, message);
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

struct FlagValue {
    StartupError error;
    const(char)* text;

    static FlagValue fromArgv(int argc, char** argv, int flagIndex) {
        if (flagIndex + 1 < argc) {
            return FlagValue(StartupError.init, argv[flagIndex + 1]);
        } else {
            return FlagValue(StartupError(null, "missing a value after", argv[flagIndex]), null);
        }
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
    int consumed;

    static WorldgenArgument fromArgv(int argc, char** argv, int flagIndex) {
        FlagValue kindText = FlagValue.fromArgv(argc, argv, flagIndex);
        if (kindText.error.isPresent()) {
            return WorldgenArgument(kindText.error, Worldgen.init, 1);
        } else {
            Maybe!WorldgenKind kind = enumNamed!WorldgenKind(kindText.text[0 .. strlen(kindText.text)]);
            if (!kind.exists) {
                return WorldgenArgument(StartupError(ENUM_NAMES!WorldgenKind[], "unknown worldgen", kindText.text), Worldgen.init, 2);
            } else {
                return WorldgenArgument.ofKind(argc, argv, flagIndex + 1, kind.value);
            }
        }
    }

    static WorldgenArgument ofKind(int argc, char** argv, int kindIndex, WorldgenKind kind) {
        WorldgenArgument parsed = void;
        final switch (kind) {
            case WorldgenKind.terrain:
                parsed = WorldgenArgument(StartupError.init, Worldgen.makeTerrain(), 2);
                break;
            case WorldgenKind.plane:
                parsed = WorldgenArgument.plane(argc, argv, kindIndex);
                break;
            case WorldgenKind.structure:
                parsed = WorldgenArgument.structure(argc, argv, kindIndex);
                break;
        }
        return parsed;
    }

    static WorldgenArgument plane(int argc, char** argv, int kindIndex) {
        FlagValue text = FlagValue.fromArgv(argc, argv, kindIndex);
        if (text.error.isPresent()) {
            return WorldgenArgument(text.error, Worldgen.init, 2);
        } else {
            Maybe!float tilt = numberIn(text.text);
            if (!tilt.exists) {
                return WorldgenArgument(StartupError(null, "plane tilt in degrees is not a number", text.text), Worldgen.init, 3);
            } else {
                return WorldgenArgument(StartupError.init, Worldgen.fromPlane(PlaneWorld(degreesToRadians(tilt.value))), 3);
            }
        }
    }

    static WorldgenArgument structure(int argc, char** argv, int kindIndex) {
        FlagValue text = FlagValue.fromArgv(argc, argv, kindIndex);
        if (text.error.isPresent()) {
            return WorldgenArgument(text.error, Worldgen.init, 2);
        } else {
            StructureName name = StructureName.fromText(text.text[0 .. strlen(text.text)]);
            if (name.problem !is null) {
                return WorldgenArgument(StartupError(name.choices, name.problem, text.text), Worldgen.init, 3);
            } else {
                return WorldgenArgument(StartupError.init, Worldgen.fromStructure(name.world), 3);
            }
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
}
