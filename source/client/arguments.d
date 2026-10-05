module client.arguments;

import core.stdc.stdio : fprintf, stderr;
import core.stdc.stdlib : strtof;
import core.stdc.string : strlen;
import common.names : ENUM_NAMES, NameLookup;
import common.graph : NodeId;
import common.worldgen.generation : PlaneWorld, StructureKind, StructureWorld, Worldgen, WorldgenKind, degreesToRadians;

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

struct NumberArgument {
    float value;
    bool isPresent;

    static NumberArgument fromText(const(char)* text) {
        const(char)* end;
        float value = strtof(text, &end);
        return NumberArgument(value, end != text && *end == 0);
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
            NameLookup!WorldgenKind kind = NameLookup!WorldgenKind.fromName(kindText.text[0 .. strlen(kindText.text)]);
            if (!kind.isFound) {
                return WorldgenArgument(StartupError(ENUM_NAMES!WorldgenKind[], "unknown worldgen", kindText.text), Worldgen.init, 2);
            } else {
                return WorldgenArgument.ofKind(argc, argv, flagIndex + 1, kind.value);
            }
        }
    }

    static WorldgenArgument ofKind(int argc, char** argv, int kindIndex, WorldgenKind kind) {
        WorldgenArgument parsed;
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
            NumberArgument tilt = NumberArgument.fromText(text.text);
            if (!tilt.isPresent) {
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
            NameLookup!StructureKind kind = NameLookup!StructureKind.fromName(text.text[0 .. strlen(text.text)]);
            if (!kind.isFound) {
                return WorldgenArgument(StartupError(ENUM_NAMES!StructureKind[], "unknown structure", text.text), Worldgen.init, 3);
            } else {
                return WorldgenArgument(StartupError.init, Worldgen.fromStructure(StructureWorld(NodeId.init, kind.value)), 3);
            }
        }
    }
}
