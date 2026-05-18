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

    void tick(float now, ulong xwid, ref bool running) {
        while (cursor < events.length && events[cursor].time <= now) {
            auto e = events[cursor++];
            if (e.command == "screenshot") {
                auto cmd = format("import -window 0x%x %s", xwid, e.arg);
                writefln("[script t=%s] %s", e.time, cmd);
                system(cmd.toStringz);
            } else if (e.command == "quit") {
                running = false;
            }
        }
    }
}
