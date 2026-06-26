module client.config;

import std.conv : to;
import std.file : exists, readText;
import std.stdio : writefln;
import std.string : indexOf, splitLines, strip;

struct ClientConfig {
    string serverAddress = "localhost";
    ushort serverPort = 1234;
    string playerName = "Player";

    float mouseSensitivity = 0.003f;
    bool invertY = false;
    float moveSpeed = 1.0f;
    float turnSpeed = 1.5f;
    float reach = 5.0f;

    /// Loads `key = value` lines from path; missing file or bad lines fall
    /// back to defaults so a partial config is always usable.
    static ClientConfig load(string path) {
        ClientConfig cfg;
        if (!exists(path)) {
            return cfg;
        }
        foreach (line; readText(path).splitLines()) {
            string trimmed = line.strip();
            if (trimmed.length == 0 || trimmed[0] == '#') {
                continue;
            }
            ptrdiff_t eq = trimmed.indexOf('=');
            if (eq < 0) {
                continue;
            }
            string key = trimmed[0 .. eq].strip();
            string value = trimmed[eq + 1 .. $].strip();
            try {
                switch (key) {
                    case "mouse_sensitivity": cfg.mouseSensitivity = value.to!float; break;
                    case "invert_y": cfg.invertY = parseBool(value); break;
                    case "move_speed": cfg.moveSpeed = value.to!float; break;
                    case "turn_speed": cfg.turnSpeed = value.to!float; break;
                    case "reach": cfg.reach = value.to!float; break;
                    case "server_address": cfg.serverAddress = value; break;
                    case "server_port": cfg.serverPort = value.to!ushort; break;
                    case "player_name": cfg.playerName = value; break;
                    default:
                        writefln("config: unknown key '%s'", key);
                        break;
                }
            }
            catch (Exception) {
                writefln("config: bad value for '%s': %s", key, value);
            }
        }
        return cfg;
    }
}

private bool parseBool(string value) {
    return value == "1" || value == "true" || value == "yes" || value == "on";
}
