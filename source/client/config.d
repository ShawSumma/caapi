module client.config;

import core.stdc.stdio : printf;
import common.array : Array;
import common.text : FileText, FixedString, ParsedFloat, ParsedInt;
import common.text : collectLines, cstrEq, parseFloat, parseInt, readWholeFile;
import common.text : splitAt, trimInPlace;

struct ClientConfig {
    FixedString!64 serverAddress = FixedString!64.fromSlice("localhost");
    ushort serverPort = 1234;
    FixedString!64 playerName = FixedString!64.fromSlice("Player");

    float mouseSensitivity = 0.0015f;
    bool invertY = false;
    float moveSpeed = 1.0f;
    float turnSpeed = 1.5f;
    float reach = 10.0f;

    // Loads key and value lines from path. A missing file or a bad line falls
    // back to the default, so a partial config is always usable.
    static ClientConfig load(const(char)* path) {
        ClientConfig cfg;
        FileText text = readWholeFile(path);
        if (text.data is null) {
            return cfg;
        }
        scope(exit) {
            text.release();
        }

        Array!(char*) lines;
        scope(exit) {
            lines.release();
        }
        collectLines(text, lines, true);

        foreach (i; 0 .. lines.length()) {
            char* key = lines[i];
            char* value = splitAt(key, '=');
            if (value is null) {
                continue;
            }
            key = trimInPlace(key);
            cfg.apply(key, value);
        }
        return cfg;
    }

    void apply(const(char)* key, const(char)* value) {
        if (cstrEq(key, "mouse_sensitivity")) {
            assignFloat(mouseSensitivity, key, value);
            return;
        }
        if (cstrEq(key, "invert_y")) {
            invertY = parseBool(value);
            return;
        }
        if (cstrEq(key, "move_speed")) {
            assignFloat(moveSpeed, key, value);
            return;
        }
        if (cstrEq(key, "turn_speed")) {
            assignFloat(turnSpeed, key, value);
            return;
        }
        if (cstrEq(key, "reach")) {
            assignFloat(reach, key, value);
            return;
        }
        if (cstrEq(key, "server_address")) {
            serverAddress.assign(value);
            return;
        }
        if (cstrEq(key, "server_port")) {
            ParsedInt parsed = parseInt(value, 10);
            if (!parsed.ok || parsed.value < 0 || parsed.value > ushort.max) {
                reportBadValue(key, value);
                return;
            }
            serverPort = cast(ushort) parsed.value;
            return;
        }
        if (cstrEq(key, "player_name")) {
            playerName.assign(value);
            return;
        }
        printf("config: unknown key '%s'\n", key);
    }
}

void assignFloat(ref float target, const(char)* key, const(char)* value) {
    ParsedFloat parsed = parseFloat(value);
    if (!parsed.ok) {
        reportBadValue(key, value);
        return;
    }
    target = parsed.value;
}

void reportBadValue(const(char)* key, const(char)* value) {
    printf("config: bad value for '%s': %s\n", key, value);
}

bool parseBool(const(char)* value) {
    return cstrEq(value, "1")
        || cstrEq(value, "true")
        || cstrEq(value, "yes")
        || cstrEq(value, "on");
}
