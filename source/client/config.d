module client.config;

import core.stdc.stdlib : strtof;
import core.stdc.string : strlen;
import base.array : Array;
import base.names : ENUM_NAMES, textFor;
import base.numbers : clamped, higherOf;
import base.stdio : FILE, fclose, fgets, fopen, printed;
import base.units : Angle, AngularSpeed, Length, Ratio;
import client.bindings : Action, BINDING_PREFIX, Bindings;

enum size_t CONFIG_LINE_CAPACITY = 256;
enum Length THREAD_SPACING = Length(0.05f);
enum uint DEFAULT_THREAD_BEADS = 0;

enum PitchAxis : ubyte {
    normal,
    inverted,
}

float pitchSign(PitchAxis axis) {
    if (axis == PitchAxis.inverted) {
        return -1.0f;
    } else {
        return 1.0f;
    }
}

struct ClientConfig {
    Bindings bindings = Bindings.defaults();
    Angle mouseTurnPerCount = Angle(0.001f);
    AngularSpeed keyTurnRate = AngularSpeed(1.5f);
    Length reach = Length(0.5f);
    Ratio comfort = Ratio(1);
    Length threadSpacing = THREAD_SPACING;
    uint threadBeads = DEFAULT_THREAD_BEADS;
    PitchAxis pitchAxis;

    static ClientConfig fromFile(const(char)* path) {
        ClientConfig config;
        FILE* file = fopen(path, "r");
        if (file is null) {
            return config;
        } else {
            char[CONFIG_LINE_CAPACITY] line;
            const(char)* read = fgets(line.ptr, cast(int) line.length, file);
            while (read !is null) {
                config.apply(ConfigEntry.fromLine(line[0 .. strlen(line.ptr)]));
                read = fgets(line.ptr, cast(int) line.length, file);
            }
            fclose(file);
            return config;
        }
    }

    static ClientConfig fromText(const(char)[] text) {
        ClientConfig config;
        size_t start = 0;
        while (start < text.length) {
            size_t end = start;
            while (end < text.length && text[end] != '\n') {
                end += 1;
            }
            config.apply(ConfigEntry.fromLine(text[start .. end]));
            start = end + 1;
        }
        return config;
    }

    void write(ref Array!char text) const {
        char[CONFIG_LINE_CAPACITY] line;
        text.appendAll(printed(line[], "mouse_sensitivity = %g\n", cast(double) mouseTurnPerCount.value));
        text.appendAll(printed(line[], "turn_speed = %g\n", cast(double) keyTurnRate.value));
        text.appendAll(printed(line[], "reach = %g\n", cast(double) reach.value));
        text.appendAll(printed(line[], "comfort = %g\n", cast(double) comfort.value));
        text.appendAll(printed(line[], "thread_spacing = %g\n", cast(double) threadSpacing.value));
        text.appendAll(printed(line[], "thread_beads = %u\n", threadBeads));
        text.appendAll(printed(line[], "invert_y = %s\n", textFor(pitchAxis == PitchAxis.inverted, "yes", "no")));
        foreach (index, ref key; bindings.keys) {
            string action = ENUM_NAMES!Action[index];
            text.appendAll(printed(line[], "%s%.*s = %.*s\n", BINDING_PREFIX.ptr, cast(int) action.length, action.ptr, cast(int) key.length, key.text.ptr));
        }
    }

    void apply(ConfigEntry entry) {
        bindings.apply(entry);
        if (entry.key == "mouse_sensitivity") {
            mouseTurnPerCount = Angle(strtof(entry.value.ptr, null));
        } else if (entry.key == "turn_speed") {
            keyTurnRate = AngularSpeed(strtof(entry.value.ptr, null));
        } else if (entry.key == "reach") {
            reach = Length(strtof(entry.value.ptr, null));
        } else if (entry.key == "comfort") {
            comfort = Ratio(clamped(strtof(entry.value.ptr, null), 0.0f, 1.0f));
        } else if (entry.key == "thread_spacing") {
            threadSpacing = Length(strtof(entry.value.ptr, null));
        } else if (entry.key == "thread_beads") {
            threadBeads = cast(uint) higherOf(strtof(entry.value.ptr, null), 0.0f);
        } else if (entry.key == "invert_y") {
            pitchAxis = PitchAxis.normal;
            if (entry.value == "1" || entry.value == "true" || entry.value == "yes" || entry.value == "on") {
                pitchAxis = PitchAxis.inverted;
            }
        }
    }
}

struct ConfigEntry {
    const(char)[] key;
    const(char)[] value;

    static ConfigEntry fromLine(const(char)[] line) {
        const(char)[] trimmed = trim(line);
        size_t equals = 0;
        while (equals < trimmed.length && trimmed[equals] != '=') {
            equals += 1;
        }
        if (equals < trimmed.length && trimmed[0] != '#') {
            return ConfigEntry(trim(trimmed[0 .. equals]), trim(trimmed[equals + 1 .. $]));
        } else {
            return ConfigEntry.init;
        }
    }
}

bool isSpace(char c) {
    return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}

const(char)[] trim(const(char)[] text) {
    size_t start = 0;
    size_t end = text.length;
    while (start < end && isSpace(text[start])) {
        start += 1;
    }
    while (end > start && isSpace(text[end - 1])) {
        end -= 1;
    }
    return text[start .. end];
}
