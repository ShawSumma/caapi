module client.config;

import core.stdc.stdio : FILE, fclose, fgets, fopen;
import core.stdc.stdlib : strtof;
import core.stdc.string : strlen;

enum size_t CONFIG_LINE_CAPACITY = 256;

struct ClientConfig {
    float mouseRadiansPerCount = 0.001f;
    float turnSpeed = 1.5f;
    float reachMeters = 10.0f;
    bool isYInverted;

    static ClientConfig load(const(char)* path) {
        ClientConfig config;
        FILE* file = fopen(path, "r");
        if (file is null) {
            return config;
        } else {
            char[CONFIG_LINE_CAPACITY] line;
            while (fgets(line.ptr, cast(int) line.length, file) !is null) {
                config.apply(ConfigEntry.parse(line[0 .. strlen(line.ptr)]));
            }
            fclose(file);
            return config;
        }
    }

    void apply(ConfigEntry entry) {
        if (entry.key == "mouse_sensitivity") {
            mouseRadiansPerCount = strtof(entry.value.ptr, null);
        } else if (entry.key == "turn_speed") {
            turnSpeed = strtof(entry.value.ptr, null);
        } else if (entry.key == "reach") {
            reachMeters = strtof(entry.value.ptr, null);
        } else if (entry.key == "invert_y") {
            isYInverted = entry.value == "1" || entry.value == "true" || entry.value == "yes" || entry.value == "on";
        }
    }
}

struct ConfigEntry {
    const(char)[] key;
    const(char)[] value;

    static ConfigEntry parse(const(char)[] line) {
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
