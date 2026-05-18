module client.script;

import std.stdio;
import std.conv : to;
import std.string : strip, split, splitLines, startsWith, toStringz;
import std.format : format;
import core.stdc.stdlib : system;

struct ScriptEvent {
    float time;
    string command;
    string arg;
}

/// Deterministic timed-input test driver.
///
/// Script format: one event per line, "<seconds> <command> [args...]".
/// Lines starting with # are comments. Blank lines ignored.
///
/// Commands:
///   screenshot <path>    - capture window to PNG via ImageMagick import
///   quit                 - exit
struct Script {
    ScriptEvent[] events;
    size_t cursor;

    static Script parse(string text) {
        Script s;
        foreach (line; text.splitLines()) {
            auto trimmed = line.strip();
            if (trimmed.length == 0 || trimmed.startsWith("#")) {
                continue;
            }
            auto parts = trimmed.split();
            if (parts.length < 2) {
                continue;
            }
            ScriptEvent e;
            try {
                e.time = parts[0].to!float;
            } catch (Exception) {
                continue;
            }
            e.command = parts[1];
            if (parts.length >= 3) {
                e.arg = parts[2];
            }
            s.events ~= e;
        }
        return s;
    }

    float fwd = 0;
    float strafe = 0;
    float vert = 0;
    float yawRate = 0;
    float pitchRate = 0;

    void tick(float now, ulong xwid, ref bool running) {
        while (cursor < events.length && events[cursor].time <= now) {
            auto e = events[cursor++];
            if (e.command == "screenshot") {
                auto cmd = format("import -window 0x%x %s", xwid, e.arg);
                writefln("[script t=%s] %s", e.time, cmd);
                system(cmd.toStringz);
            } else if (e.command == "quit") {
                running = false;
            } else if (e.command == "key_down" || e.command == "key_up") {
                float val = (e.command == "key_down") ? 1.0f : 0.0f;
                if (e.arg == "W") {
                    fwd = -val;
                } else if (e.arg == "S") {
                    fwd = val;
                } else if (e.arg == "A") {
                    strafe = -val;
                } else if (e.arg == "D") {
                    strafe = val;
                } else if (e.arg == "SPACE") {
                    vert = val;
                } else if (e.arg == "LSHIFT") {
                    vert = -val;
                } else if (e.arg == "UP") {
                    pitchRate = -val * 1.5f;
                } else if (e.arg == "DOWN") {
                    pitchRate = val * 1.5f;
                } else if (e.arg == "LEFT") {
                    yawRate = -val * 1.5f;
                } else if (e.arg == "RIGHT") {
                    yawRate = val * 1.5f;
                }
            }
        }
    }
}
