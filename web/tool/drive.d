module drive;

import core.stdc.stdio : fprintf, printf, snprintf, stderr;
import core.stdc.stdlib : strtoul;
import core.stdc.string : memcpy, strlen, strstr;
import core.sys.posix.arpa.inet : htons, inet_addr;
import core.sys.posix.netinet.in_ : AF_INET, IPPROTO_TCP, sockaddr_in;
import core.sys.posix.sys.socket : SOCK_STREAM, connect, recv, send, sockaddr, socket;
import core.sys.posix.time : nanosleep, timespec;
import core.sys.posix.unistd : close, getcwd;
import base.array : Array;
import base.maybe : Maybe;
import base64 : decodeInto;
import files : Outcome, PATH_CAPACITY, writeFile;

enum ushort MARIONETTE_PORT = 2828;
enum string LOOPBACK = "127.0.0.1";
enum string GAME_PAGE = "mined.html";
enum string CHECK_PAGE = "obj/web/check.html";
enum string PLAY_COMMAND = "play";
enum string CHECK_COMMAND = "check";
enum string HELP_OPTION = "--help";
immutable string[6] CHECK_MODES = ["run", "actions", "tour", "flight", "world", "bench"];
enum string MODE_QUERY = "?mode=%s";
enum string VALUE_QUERY = "&%s";
enum string USAGE = "usage: drive <command>\n  " ~ PLAY_COMMAND ~ "  drive " ~ GAME_PAGE ~ " with real input\n  " ~ CHECK_COMMAND ~ " <mode> [name=value ...]  report a run of " ~ CHECK_PAGE ~ "\n    modes: run actions tour flight world bench\n    values: width height frames worlds shots index pitch\n  " ~ HELP_OPTION ~ "  show this text\nFirefox must be running with --marionette.\n";
enum int USAGE_STATUS = 2;
enum uint CONNECT_ATTEMPTS = 120;
enum uint CONNECT_PAUSE_MILLISECONDS = 500;
enum uint LOAD_MILLISECONDS = 6000;
enum uint WORLD_MILLISECONDS = 3000;
enum uint SETTLE_MILLISECONDS = 500;
enum uint WALK_MILLISECONDS = 2000;
enum uint TAP_MILLISECONDS = 50;
enum int LOOK_RIGHT_COUNTS = 200;
enum int LOOK_DOWN_COUNTS = 150;
enum int LEFT_BUTTON = 0;
enum int RIGHT_BUTTON = 2;
enum int CENTER_X = 640;
enum int CENTER_Y = 360;
enum long NANOSECONDS_PER_MILLISECOND = 1_000_000;
enum uint MILLISECONDS_PER_SECOND = 1000;
enum size_t RECEIVE_BYTES = 65536;
enum size_t PARAMETERS_CAPACITY = 2048;
enum size_t REQUEST_CAPACITY = 4096;
enum size_t LENGTH_DIGITS = 32;
enum uint RADIX = 10;
enum string NEW_SESSION = "WebDriver:NewSession";
enum string SET_TIMEOUTS = "WebDriver:SetTimeouts";
enum string SET_WINDOW_RECT = "WebDriver:SetWindowRect";
enum string NAVIGATE = "WebDriver:Navigate";
enum string EXECUTE_SCRIPT = "WebDriver:ExecuteScript";
enum string TAKE_SCREENSHOT = "WebDriver:TakeScreenshot";
enum string PERFORM_ACTIONS = "WebDriver:PerformActions";
enum string QUIT = "Marionette:Quit";
enum string NO_PARAMETERS = "{}";
enum string REQUEST_FORMAT = "[0,%u,\"%s\",%s]";
enum string SCRIPT_FORMAT = "{\"script\":\"%.*s\",\"args\":[]}";
enum string NAVIGATE_FORMAT = "{\"url\":\"file://%s/%s%s\"}";
enum string CLICK_FORMAT = `{"actions":[{"type":"pointer","id":"mouse","parameters":{"pointerType":"mouse"},"actions":[{"type":"pointerMove","x":%d,"y":%d,"duration":0,"origin":"viewport"},{"type":"pointerDown","button":%d},{"type":"pointerUp","button":%d}]}]}`;
enum string MOVE_FORMAT = `{"actions":[{"type":"pointer","id":"mouse","parameters":{"pointerType":"mouse"},"actions":[{"type":"pointerMove","x":%d,"y":%d,"duration":200,"origin":"pointer"}]}]}`;
enum string HOLD_FORMAT = `{"actions":[{"type":"key","id":"keyboard","actions":[{"type":"keyDown","value":"%s"},{"type":"pause","duration":%u},{"type":"keyUp","value":"%s"}]}]}`;
enum string NO_TIMEOUTS = `{"script":3600000,"pageLoad":3600000,"implicit":0}`;
enum string WIDE_WINDOW = `{"x":0,"y":0,"width":1280,"height":800}`;
enum string SMALL_WINDOW = `{"x":0,"y":0,"width":900,"height":600}`;
enum string SHEET_WINDOW = `{"x":0,"y":0,"width":1940,"height":1200}`;
enum string STATE_SCRIPT = "return document.getElementById('status').textContent + ' | failure: ' + document.getElementById('failure').textContent + ' | locked: ' + (document.pointerLockElement !== null)";
enum string RESULT_SCRIPT = "return document.getElementById('status').textContent + ' | failure: ' + document.getElementById('failure').textContent";
enum string CANVAS_SCRIPT = "const c = document.getElementById('game'); return c.width + 'x' + c.height";
enum string RELEASE_SCRIPT = "document.exitPointerLock(); return 'released'";
enum string SHOT_START = "{\"full\":false,\"hash\":false}";
enum string SHOT_DIRECTORY = ".firefox-check/";
enum string VALUE_MARK = "\"value\":\"";

void pause(uint milliseconds) {
    timespec wanted = timespec(milliseconds / MILLISECONDS_PER_SECOND, (milliseconds % MILLISECONDS_PER_SECOND) * NANOSECONDS_PER_MILLISECOND);
    nanosleep(&wanted, null);
}

struct Marionette {
    Array!char pending;
    Array!char reply;
    int connection;
    uint nextId = 1;

    Outcome connectTo(ref sockaddr_in address) {
        connection = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
        int status = connect(connection, cast(sockaddr*) &address, address.sizeof);
        if (status == 0) {
            return Outcome.done;
        } else {
            close(connection);
            return Outcome.failed;
        }
    }

    Outcome open() {
        sockaddr_in address;
        address.sin_family = AF_INET;
        address.sin_port = htons(MARIONETTE_PORT);
        address.sin_addr.s_addr = inet_addr(LOOPBACK.ptr);
        Outcome linked = connectTo(address);
        uint attempt = 1;
        while (linked == Outcome.failed && attempt < CONNECT_ATTEMPTS) {
            pause(CONNECT_PAUSE_MILLISECONDS);
            linked = connectTo(address);
            attempt += 1;
        }
        if (linked == Outcome.done) {
            return receive();
        } else {
            return linked;
        }
    }

    Outcome start() {
        Outcome status = open();
        if (status == Outcome.done) {
            status = call(NEW_SESSION, NO_PARAMETERS);
        }
        if (status == Outcome.done) {
            status = call(SET_TIMEOUTS, NO_TIMEOUTS);
        }
        return status;
    }

    size_t colonInPending() const {
        size_t colon = 0;
        while (colon < pending.length && pending.ptr[colon] != ':') {
            colon += 1;
        }
        return colon;
    }

    Maybe!size_t frameEnd() const {
        size_t colon = colonInPending();
        if (colon == pending.length) {
            return Maybe!size_t.init;
        } else {
            char[LENGTH_DIGITS] digits = 0;
            memcpy(digits.ptr, pending.ptr, colon);
            size_t length = strtoul(digits.ptr, null, RADIX);
            if (pending.length >= colon + 1 + length) {
                return Maybe!size_t.of(colon + 1 + length);
            } else {
                return Maybe!size_t.init;
            }
        }
    }

    Outcome receive() {
        Maybe!size_t end = frameEnd();
        while (!end.exists) {
            char[RECEIVE_BYTES] chunk;
            ptrdiff_t got = recv(connection, chunk.ptr, chunk.length, 0);
            if (got <= 0) {
                return Outcome.failed;
            }
            pending.appendAll(chunk[0 .. got]);
            end = frameEnd();
        }
        size_t colon = colonInPending();
        reply.clear();
        reply.appendAll(pending.ptr[colon + 1 .. end.value]);
        reply.append('\0');
        size_t left = pending.length - end.value;
        foreach (index; 0 .. left) {
            pending.ptr[index] = pending.ptr[end.value + index];
        }
        pending.length = left;
        return Outcome.done;
    }

    Outcome call(const(char)* name, const(char)* parameters) {
        char[REQUEST_CAPACITY] request = 0;
        int written = snprintf(request.ptr, request.length, REQUEST_FORMAT.ptr, nextId, name, parameters);
        char[LENGTH_DIGITS] prefix = 0;
        int prefixLength = snprintf(prefix.ptr, prefix.length, "%d:", written);
        nextId += 1;
        send(connection, prefix.ptr, prefixLength, 0);
        send(connection, request.ptr, written, 0);
        Outcome received = receive();
        if (received == Outcome.failed) {
            return Outcome.failed;
        } else if (hasError()) {
            fprintf(stderr, "%s failed: %s\n", name, reply.ptr);
            return Outcome.failed;
        } else {
            return Outcome.done;
        }
    }

    bool hasError() const {
        size_t at = 0;
        uint commas = 0;
        while (at < reply.length && commas < 2) {
            if (reply.ptr[at] == ',') {
                commas += 1;
            }
            at += 1;
        }
        return !(at + 4 < reply.length && reply.ptr[at] == 'n' && reply.ptr[at + 1] == 'u');
    }

    const(char)[] replyValue() const {
        const(char)* found = strstr(reply.ptr, VALUE_MARK.ptr);
        if (found is null) {
            return null;
        } else {
            const(char)* start = found + VALUE_MARK.length;
            size_t length = 0;
            while (start[length] != '\0' && start[length] != '"') {
                if (start[length] == '\\') {
                    length += 1;
                }
                length += 1;
            }
            return start[0 .. length];
        }
    }

    void printValue() const {
        const(char)[] value = replyValue();
        size_t at = 0;
        while (at < value.length) {
            if (value[at] == '\\' && value[at + 1] == 'n') {
                printf("\n");
                at += 2;
            } else if (value[at] == '\\') {
                printf("%c", value[at + 1]);
                at += 2;
            } else {
                printf("%c", value[at]);
                at += 1;
            }
        }
        printf("\n");
    }

    Outcome script(const(char)[] source) {
        char[PARAMETERS_CAPACITY] parameters = 0;
        snprintf(parameters.ptr, parameters.length, SCRIPT_FORMAT.ptr, cast(int) source.length, source.ptr);
        return call(EXECUTE_SCRIPT, parameters.ptr);
    }

    void report(const(char)* label, const(char)[] source) {
        printf("%s: ", label);
        Outcome ran = script(source);
        if (ran == Outcome.done) {
            printValue();
        }
    }

    void state(const(char)* label) {
        report(label, STATE_SCRIPT);
    }

    Outcome navigate(const(char)* page, const(char)* query) {
        char[PATH_CAPACITY] directory = 0;
        getcwd(directory.ptr, directory.length);
        char[PARAMETERS_CAPACITY] parameters = 0;
        snprintf(parameters.ptr, parameters.length, NAVIGATE_FORMAT.ptr, directory.ptr, page, query);
        return call(NAVIGATE, parameters.ptr);
    }

    void shot(const(char)* name) {
        Outcome taken = call(TAKE_SCREENSHOT, SHOT_START);
        if (taken == Outcome.done) {
            Array!ubyte image;
            decodeInto(replyValue(), image);
            char[PATH_CAPACITY] path = 0;
            int length = snprintf(path.ptr, path.length, "%s%s.png", SHOT_DIRECTORY.ptr, name);
            writeFile(path[0 .. length], image.slice());
            image.release();
        }
    }

    void click(int button) {
        char[PARAMETERS_CAPACITY] parameters = 0;
        snprintf(parameters.ptr, parameters.length, CLICK_FORMAT.ptr, CENTER_X, CENTER_Y, button, button);
        call(PERFORM_ACTIONS, parameters.ptr);
    }

    void moveBy(int dx, int dy) {
        char[PARAMETERS_CAPACITY] parameters = 0;
        snprintf(parameters.ptr, parameters.length, MOVE_FORMAT.ptr, dx, dy);
        call(PERFORM_ACTIONS, parameters.ptr);
    }

    void hold(const(char)* key, uint milliseconds) {
        char[PARAMETERS_CAPACITY] parameters = 0;
        snprintf(parameters.ptr, parameters.length, HOLD_FORMAT.ptr, key, milliseconds, key);
        call(PERFORM_ACTIONS, parameters.ptr);
    }

    void quit() {
        call(QUIT, NO_PARAMETERS);
    }
}

void playThrough(ref Marionette browser) {
    browser.call(SET_WINDOW_RECT, WIDE_WINDOW);
    browser.state("loaded");
    pause(LOAD_MILLISECONDS);
    browser.state("loaded for a while, nothing pressed");
    browser.shot("play-start");
    browser.click(LEFT_BUTTON);
    pause(SETTLE_MILLISECONDS);
    browser.state("clicked to capture");
    browser.hold("w", WALK_MILLISECONDS);
    browser.state("held W");
    browser.shot("play-walked");
    browser.moveBy(LOOK_RIGHT_COUNTS, LOOK_DOWN_COUNTS);
    pause(SETTLE_MILLISECONDS);
    browser.shot("play-looked");
    browser.click(LEFT_BUTTON);
    pause(SETTLE_MILLISECONDS);
    browser.shot("play-broke");
    browser.click(RIGHT_BUTTON);
    pause(SETTLE_MILLISECONDS);
    browser.shot("play-placed");
    browser.hold("v", TAP_MILLISECONDS);
    browser.state("pressed V");
    browser.hold("]", TAP_MILLISECONDS);
    pause(WORLD_MILLISECONDS);
    browser.state("pressed ]");
    browser.shot("play-next-world");
    browser.report("release", RELEASE_SCRIPT);
    pause(SETTLE_MILLISECONDS);
    browser.state("after release");
    browser.hold("w", SETTLE_MILLISECONDS);
    browser.state("W while released");
    browser.call(SET_WINDOW_RECT, SMALL_WINDOW);
    pause(WORLD_MILLISECONDS);
    browser.state("resized");
    browser.report("canvas", CANVAS_SCRIPT);
    browser.shot("play-resized");
}

enum Task : ubyte {
    play,
    check,
}

const(char)[] sliceOf(const(char)* text) {
    return text[0 .. strlen(text)];
}

bool isCheckMode(const(char)[] name) {
    size_t index = 0;
    while (index < CHECK_MODES.length && CHECK_MODES[index] != name) {
        index += 1;
    }
    return index < CHECK_MODES.length;
}

char[PARAMETERS_CAPACITY] checkQuery(const(char*)[] arguments) {
    char[PARAMETERS_CAPACITY] query = 0;
    int written = snprintf(query.ptr, query.length, MODE_QUERY.ptr, arguments[0]);
    foreach (argument; arguments[1 .. $]) {
        written += snprintf(query.ptr + written, query.length - written, VALUE_QUERY.ptr, argument);
    }
    return query;
}

Outcome driveTo(const(char)* page, const(char)* query, Task task) {
    Marionette browser;
    Outcome started = browser.start();
    if (started == Outcome.failed) {
        fprintf(stderr, "cannot reach Firefox; start it with --marionette\n");
        return Outcome.failed;
    } else {
        Outcome navigated = browser.navigate(page, query);
        if (navigated == Outcome.done) {
            final switch (task) {
                case Task.play:
                    playThrough(browser);
                    break;
                case Task.check:
                    browser.call(SET_WINDOW_RECT, SHEET_WINDOW);
                    browser.report("result", RESULT_SCRIPT);
                    browser.shot("check");
                    break;
            }
            printf("driven to the end\n");
        }
        browser.quit();
        return navigated;
    }
}

extern (C) int main(int count, char** arguments) {
    if (count == 2 && sliceOf(arguments[1]) == HELP_OPTION) {
        printf("%.*s", cast(int) USAGE.length, USAGE.ptr);
        return Outcome.done;
    } else if (count == 2 && sliceOf(arguments[1]) == PLAY_COMMAND) {
        return driveTo(GAME_PAGE, "", Task.play);
    } else if (count >= 3 && sliceOf(arguments[1]) == CHECK_COMMAND && isCheckMode(sliceOf(arguments[2]))) {
        char[PARAMETERS_CAPACITY] query = checkQuery(arguments[2 .. count]);
        return driveTo(CHECK_PAGE, query.ptr, Task.check);
    } else {
        fprintf(stderr, "%.*s", cast(int) USAGE.length, USAGE.ptr);
        return USAGE_STATUS;
    }
}
