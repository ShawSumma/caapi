module client.script;

import core.stdc.stdio : printf, snprintf, sscanf;
import core.stdc.stdlib : system;
import common.array : Array;
import common.text : FileText, ParsedFloat;
import common.text : collectLines, cstrEq, parseFloat, splitTokens;

struct ScriptEvent {
    float time;
    const(char)* command;
    const(char)* arg;
}

struct Script {
    // Commands and args point into the FileText passed to parse, so that text
    // has to outlive the Script.
    Array!ScriptEvent events;
    size_t cursor;

    float fwd = 0;
    float strafe = 0;
    float vert = 0;
    float yawRate = 0;
    float pitchRate = 0;

    // Set by a `resize <W>x<H>` line. The window belongs to main, so the
    // request is handed back rather than acted on here.
    bool resizePending;
    int resizeWidth;
    int resizeHeight;

    static Script parse(ref FileText text) {
        Script s;
        Array!(char*) lines;
        scope(exit) {
            lines.release();
        }
        collectLines(text, lines, true);

        foreach (i; 0 .. lines.length()) {
            char*[3] parts;
            size_t found = splitTokens(lines[i], parts);
            if (found < 2) {
                continue;
            }
            ParsedFloat when = parseFloat(parts[0]);
            if (!when.ok) {
                continue;
            }
            ScriptEvent e;
            e.time = when.value;
            e.command = parts[1];
            if (found >= 3) {
                e.arg = parts[2];
            }
            s.events.push(e);
        }
        return s;
    }

    void release() {
        events.release();
    }

    // Returns false once the script has asked to quit, rather than writing
    // back through a parameter.
    bool tick(float now, ulong xwid) {
        bool keepRunning = true;
        while (cursor < events.length() && events[cursor].time <= now) {
            ScriptEvent e = events[cursor];
            cursor = cursor + 1;

            if (cstrEq(e.command, "screenshot")) {
                char[256] cmd;
                snprintf(
                    cmd.ptr,
                    cmd.length,
                    "import -window 0x%llx %s",
                    xwid,
                    e.arg,
                );
                printf("[script t=%.3f] %s\n", cast(double) e.time, cmd.ptr);
                system(cmd.ptr);
            } else if (cstrEq(e.command, "resize")) {
                int w = 0;
                int h = 0;
                if (e.arg !is null && sscanf(e.arg, "%dx%d", &w, &h) == 2) {
                    resizeWidth = w;
                    resizeHeight = h;
                    resizePending = true;
                    printf("[script t=%.3f] resize %dx%d\n", cast(double) e.time, w, h);
                }
            } else if (cstrEq(e.command, "quit")) {
                keepRunning = false;
            } else if (cstrEq(e.command, "key_down")) {
                applyKey(e, 1.0f);
            } else if (cstrEq(e.command, "key_up")) {
                applyKey(e, 0.0f);
            }
        }
        return keepRunning;
    }

    void applyKey(ref const ScriptEvent e, float val) {
        if (cstrEq(e.arg, "W")) {
            fwd = -val;
        } else if (cstrEq(e.arg, "S")) {
            fwd = val;
        } else if (cstrEq(e.arg, "A")) {
            strafe = -val;
        } else if (cstrEq(e.arg, "D")) {
            strafe = val;
        } else if (cstrEq(e.arg, "SPACE")) {
            vert = val;
        } else if (cstrEq(e.arg, "LSHIFT")) {
            vert = -val;
        } else if (cstrEq(e.arg, "UP")) {
            pitchRate = -val * 1.5f;
        } else if (cstrEq(e.arg, "DOWN")) {
            pitchRate = val * 1.5f;
        } else if (cstrEq(e.arg, "LEFT")) {
            yawRate = -val * 1.5f;
        } else if (cstrEq(e.arg, "RIGHT")) {
            yawRate = val * 1.5f;
        }
    }
}
