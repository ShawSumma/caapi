module client.config;

import core.stdc.stdio : FILE, fclose, fgets, fopen;
import core.stdc.stdlib : strtof;
import core.stdc.string : strlen;

enum size_t CONFIG_LINE_CAPACITY = 256;

struct ClientConfig {
    float mouseRadiansPerPixel = 0.001f;
    float turnSpeed = 1.5f;
    float reachMeters = 10.0f;
    bool invertY;
}

struct ConfigEntry {
    const(char)[] key;
    const(char)[] value;
}

ClientConfig loadClientConfig(const(char)* path) {
    ClientConfig config;
    FILE* file = fopen(path, "r");
    if (file !is null) {
        char[CONFIG_LINE_CAPACITY] line;
        while (fgets(line.ptr, cast(int) line.length, file) !is null) {
            applyConfigEntry(&config, parseConfigLine(line[0 .. strlen(line.ptr)]));
        }
        fclose(file);
    }
    return config;
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

ConfigEntry parseConfigLine(const(char)[] line) {
    const(char)[] trimmed = trim(line);
    ConfigEntry entry;
    size_t equals = 0;
    while (equals < trimmed.length && trimmed[equals] != '=') {
        equals += 1;
    }
    if (equals < trimmed.length && trimmed[0] != '#') {
        entry.key = trim(trimmed[0 .. equals]);
        entry.value = trim(trimmed[equals + 1 .. $]);
    }
    return entry;
}

void applyConfigEntry(ClientConfig* config, ConfigEntry entry) {
    if (entry.key == "mouse_sensitivity") {
        config.mouseRadiansPerPixel = strtof(entry.value.ptr, null);
    } else if (entry.key == "turn_speed") {
        config.turnSpeed = strtof(entry.value.ptr, null);
    } else if (entry.key == "reach") {
        config.reachMeters = strtof(entry.value.ptr, null);
    } else if (entry.key == "invert_y") {
        config.invertY = entry.value == "1" || entry.value == "true" || entry.value == "yes" || entry.value == "on";
    }
}
