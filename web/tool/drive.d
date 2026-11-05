module drive;

import core.stdc.stdio : fprintf, printf, snprintf, stderr;
import core.stdc.stdlib : strtoul;
import core.stdc.string : memcpy, strstr;
import core.sys.posix.arpa.inet : htons, inet_addr;
import core.sys.posix.netinet.in_ : AF_INET, IPPROTO_TCP, sockaddr_in;
import core.sys.posix.sys.socket : SOCK_STREAM, connect, recv, send, sockaddr, socket;
import core.sys.posix.time : nanosleep, timespec;
import core.sys.posix.unistd : close, getcwd;
import base.array : Array;
import base64 : decodeInto;
import files : PATH_CAPACITY, writeFile;

enum ushort MARIONETTE_PORT = 2828;
enum string LOOPBACK = "127.0.0.1";
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

enum ExitStatus : int {
    ok,
    failed,
}

void pause(uint milliseconds) {
    timespec wanted = timespec(milliseconds / MILLISECONDS_PER_SECOND, (milliseconds % MILLISECONDS_PER_SECOND) * NANOSECONDS_PER_MILLISECOND);
    nanosleep(&wanted, null);
}

struct Marionette {
    Array!char pending;
    Array!char reply;
    int connection = -1;
    uint nextId = 1;

    bool connectedTo(ref sockaddr_in address) {
        connection = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
        if (connect(connection, cast(sockaddr*) &address, address.sizeof) == 0) {
            return true;
        } else {
            close(connection);
            pause(CONNECT_PAUSE_MILLISECONDS);
            return false;
        }
    }

    bool open() {
        sockaddr_in address;
        address.sin_family = AF_INET;
        address.sin_port = htons(MARIONETTE_PORT);
        address.sin_addr.s_addr = inet_addr(LOOPBACK.ptr);
        uint attempt = 0;
        while (attempt < CONNECT_ATTEMPTS && !connectedTo(address)) {
            attempt += 1;
        }
        return attempt < CONNECT_ATTEMPTS && receive();
    }

    size_t frameEnd() const {
        size_t colon = 0;
        while (colon < pending.length && pending.ptr[colon] != ':') {
            colon += 1;
        }
        if (colon == pending.length) {
            return 0;
        } else {
            char[LENGTH_DIGITS] digits = 0;
            memcpy(digits.ptr, pending.ptr, colon);
            size_t length = strtoul(digits.ptr, null, RADIX);
            if (pending.length >= colon + 1 + length) {
                return colon + 1 + length;
            } else {
                return 0;
            }
        }
    }

    bool receive() {
        size_t end = frameEnd();
        while (end == 0) {
            char[RECEIVE_BYTES] chunk;
            ptrdiff_t got = recv(connection, chunk.ptr, chunk.length, 0);
            if (got <= 0) {
                return false;
            }
            pending.appendAll(chunk[0 .. got]);
            end = frameEnd();
        }
        size_t colon = 0;
        while (pending.ptr[colon] != ':') {
            colon += 1;
        }
        reply.clear();
        reply.appendAll(pending.ptr[colon + 1 .. end]);
        reply.append('\0');
        size_t left = pending.length - end;
        foreach (index; 0 .. left) {
            pending.ptr[index] = pending.ptr[end + index];
        }
        pending.length = left;
        return true;
    }

    bool call(const(char)* name, const(char)* parameters) {
        char[REQUEST_CAPACITY] request = 0;
        int written = snprintf(request.ptr, request.length, "[0,%u,\"%s\",%s]", nextId, name, parameters);
        char[LENGTH_DIGITS] prefix = 0;
        int prefixLength = snprintf(prefix.ptr, prefix.length, "%d:", written);
        nextId += 1;
        send(connection, prefix.ptr, prefixLength, 0);
        send(connection, request.ptr, written, 0);
        if (!receive()) {
            return false;
        } else if (hasError()) {
            fprintf(stderr, "%s failed: %s\n", name, reply.ptr);
            return false;
        } else {
            return true;
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

    bool script(const(char)[] source) {
        char[PARAMETERS_CAPACITY] parameters = 0;
        snprintf(parameters.ptr, parameters.length, "{\"script\":\"%.*s\",\"args\":[]}", cast(int) source.length, source.ptr);
        return call("WebDriver:ExecuteScript", parameters.ptr);
    }

    void state(const(char)* label) {
        printf("%s: ", label);
        if (script(STATE_SCRIPT)) {
            printValue();
        }
    }

    void report(const(char)* label, const(char)[] source) {
        printf("%s: ", label);
        if (script(source)) {
            printValue();
        }
    }

    bool navigate(const(char)* page, const(char)* query) {
        char[PATH_CAPACITY] directory = 0;
        getcwd(directory.ptr, directory.length);
        char[PARAMETERS_CAPACITY] parameters = 0;
        snprintf(parameters.ptr, parameters.length, "{\"url\":\"file://%s/%s%s\"}", directory.ptr, page, query);
        return call("WebDriver:Navigate", parameters.ptr);
    }

    void shot(const(char)* name) {
        if (call("WebDriver:TakeScreenshot", SHOT_START.ptr)) {
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
        snprintf(parameters.ptr, parameters.length, `{"actions":[{"type":"pointer","id":"mouse","parameters":{"pointerType":"mouse"},"actions":[{"type":"pointerMove","x":%d,"y":%d,"duration":0,"origin":"viewport"},{"type":"pointerDown","button":%d},{"type":"pointerUp","button":%d}]}]}`, CENTER_X, CENTER_Y, button, button);
        call("WebDriver:PerformActions", parameters.ptr);
    }

    void moveBy(int dx, int dy) {
        char[PARAMETERS_CAPACITY] parameters = 0;
        snprintf(parameters.ptr, parameters.length, `{"actions":[{"type":"pointer","id":"mouse","parameters":{"pointerType":"mouse"},"actions":[{"type":"pointerMove","x":%d,"y":%d,"duration":200,"origin":"pointer"}]}]}`, dx, dy);
        call("WebDriver:PerformActions", parameters.ptr);
    }

    void hold(const(char)* key, uint milliseconds) {
        char[PARAMETERS_CAPACITY] parameters = 0;
        snprintf(parameters.ptr, parameters.length, `{"actions":[{"type":"key","id":"keyboard","actions":[{"type":"keyDown","value":"%s"},{"type":"pause","duration":%u},{"type":"keyUp","value":"%s"}]}]}`, key, milliseconds, key);
        call("WebDriver:PerformActions", parameters.ptr);
    }

    void quit() {
        call("Marionette:Quit", "{}");
    }
}

void playThrough(ref Marionette browser) {
    browser.call("WebDriver:SetWindowRect", WIDE_WINDOW.ptr);
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
    browser.call("WebDriver:SetWindowRect", SMALL_WINDOW.ptr);
    pause(WORLD_MILLISECONDS);
    browser.state("resized");
    browser.report("canvas", CANVAS_SCRIPT);
    browser.shot("play-resized");
}

extern (C) int main(int count, char** arguments) {
    const(char)* page = "mined.html";
    const(char)* query = "";
    if (count > 1) {
        page = arguments[1];
    }
    if (count > 2) {
        query = arguments[2];
    }
    Marionette browser;
    if (!browser.open() || !browser.call("WebDriver:NewSession", "{}") || !browser.call("WebDriver:SetTimeouts", NO_TIMEOUTS.ptr)) {
        fprintf(stderr, "cannot reach Firefox; start it with --marionette\n");
        return ExitStatus.failed;
    } else if (!browser.navigate(page, query)) {
        browser.quit();
        return ExitStatus.failed;
    } else {
        if (count > 1) {
            browser.call("WebDriver:SetWindowRect", SHEET_WINDOW.ptr);
            browser.report("result", RESULT_SCRIPT);
            browser.shot("check");
        } else {
            playThrough(browser);
        }
        browser.quit();
        printf("driven to the end\n");
        return ExitStatus.ok;
    }
}
