module client.arguments;

import core.stdc.stdio : FILE, fclose, fopen, fprintf, stderr;
import core.stdc.stdlib : strtof;
import core.stdc.string : memcpy, strlen;
import base.names : ENUM_NAMES, NameLookup;
import common.worldgen.embedded : EMBEDDED_STRUCTURES, EMBEDDED_STRUCTURE_NAMES, embeddedIndex, isLuaPath;
import common.worldgen.generation : PlaneWorld, STRUCTURE_NAME_CAPACITY, StructureWorld, Worldgen, WorldgenKind, degreesToRadians;

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
        } else if (!isLuaPath(text)) {
            return StructureName.fromEmbedded(text);
        } else if (!isReadable(text)) {
            return StructureName(StructureWorld.init, null, "cannot open the structure file");
        } else {
            return StructureName(StructureWorld.fromName(text), null, null);
        }
    }

    static StructureName fromEmbedded(const(char)[] text) {
        if (embeddedIndex(text) == EMBEDDED_STRUCTURES.length) {
            return StructureName(StructureWorld.init, EMBEDDED_STRUCTURE_NAMES[], "unknown structure (or a path ending in .lua)");
        } else {
            return StructureName(StructureWorld.fromName(text), null, null);
        }
    }
}

bool isReadable(const(char)[] path) {
    char[STRUCTURE_NAME_CAPACITY + 1] terminated = 0;
    memcpy(terminated.ptr, path.ptr, path.length);
    FILE* file = fopen(terminated.ptr, "r");
    if (file is null) {
        return false;
    } else {
        fclose(file);
        return true;
    }
}
