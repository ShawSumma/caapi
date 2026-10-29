module client.drive;

import core.stdc.stdio : FILE, fflush, fprintf;
import core.stdc.string : strlen;
import lua : luaL_checkinteger, luaL_checklstring, luaL_checknumber, luaL_checktype, luaL_error, luaL_loadfilex, luaL_ref, luaL_traceback, lua_CFunction, lua_State, lua_close, lua_createtable, lua_gettop, lua_newthread, lua_pcallk, lua_pushboolean, lua_pushcclosure, lua_pushinteger, lua_pushvalue, lua_rawgeti, lua_resume, lua_settop, lua_toboolean, lua_tolstring, lua_touserdata, lua_type, lua_xmove, lua_yieldk;
import base.array : Array;
import base.clock : MILLISECONDS_PER_SECOND;
import client.frames : FrameRecord, FrameSummary, MouseMotion, RenderTimes, cameraStep;
import client.images : RGBA_BYTES, copyAsRgba, differenceOf;
import client.lua : LUA_FIRST_UPVALUE, LUA_NO_REF, LUA_REGISTRY, LUA_STATUS_OK, LUA_STATUS_YIELD, LUA_TOP, LUA_TYPE_FUNCTION, LUA_TYPE_TABLE, LuaLookup, SELF, TRACEBACK_INDEX, luaTraceback, newSafeState, registerMethod, setPackagePath;
import client.png : writePng;
import common.graph : Graph;
import common.position : Position;

enum int CHUNK_RESULTS = 1;
enum int DRIVE_ARGUMENTS = 1;
enum int FUNCTION_BELOW_THREAD = LUA_TOP - 1;
enum uint LEFT_BUTTON = 1;
enum uint RIGHT_BUTTON = 3;

// Keys by their name on the keyboard; the game binds them to actions, the driver only presses them.
enum DriveKey : ubyte {
    w,
    a,
    s,
    d,
    space,
    shift,
    v,
    n,
    left,
    right,
    up,
    down,
    bracketLeft,
    bracketRight,
    escape,
    digit1,
    digit2,
    digit3,
    digit4,
    digit5,
    digit6,
    digit7,
    digit8,
    digit9,
}

enum DriveEventKind : ubyte {
    press,
    release,
    click,
}

struct DriveEvent {
    DriveEventKind kind;
    DriveKey key;
    uint button;
}

struct DriveInput {
    const(DriveEvent)[] events;
    double dx = 0;
    double dy = 0;
}

// The script runs as a coroutine. Calls that let frames pass yield back to the window's frame loop, which resumes the
// script once those frames are done, so the script plays the game the way the window runs it.
struct DriveHost {
    lua_State* lua;
    lua_State* thread;
    FILE* report;
    Array!DriveEvent events;
    Array!DriveEvent later;
    Array!char capturePath;
    Array!char summaryTitle;
    Array!char drawnPath;
    Array!char waitingPath;
    Array!ubyte previous;
    Array!ubyte current;
    MouseMotion motion;
    Position lastCamera;
    FrameRecord drawn;
    FrameRecord waiting;
    FrameSummary summary;
    double lastNow = 0;
    int driveRef = LUA_NO_REF;
    int resumeArguments;
    uint pendingFrames;
    uint frame;
    uint summaryFrame;
    bool isWatching;
    bool isLogging;
    bool isCaptureAsked;
    bool isSummaryAsked;
    bool isSettling;
    bool hasDrawn;
    bool isDrawnImaged;
    bool isWaitingImage;
    bool hasLast;
    bool isFinished;
    bool isFailed;

    bool start(const(char)* path, FILE* output, float sensitivity) {
        report = output;
        fprintf(report, "drive: %s, the mouse turns %g radians per count\n", path, cast(double) sensitivity);
        lua = newSafeState();
        lua.setPackagePath(path[0 .. strlen(path)]);
        createDrive();
        lua_pushcclosure(lua, cast(lua_CFunction) &luaTraceback, 0);
        bool isLoaded = luaL_loadfilex(lua, path, null) == LUA_STATUS_OK && lua_pcallk(lua, 0, CHUNK_RESULTS, TRACEBACK_INDEX, 0, null) == LUA_STATUS_OK;
        if (!isLoaded) {
            fail(lua_tolstring(lua, LUA_TOP, null));
        } else if (lua_type(lua, LUA_TOP) != LUA_TYPE_FUNCTION) {
            fail("the script does not return a function of the drive");
        } else {
            thread = lua_newthread(lua);
            lua_pushvalue(lua, FUNCTION_BELOW_THREAD);
            lua_xmove(lua, thread, 1);
            lua_rawgeti(thread, LUA_REGISTRY, driveRef);
            resumeArguments = DRIVE_ARGUMENTS;
        }
        return !isFailed;
    }

    void createDrive() {
        lua_createtable(lua, 0, 0);
        lua.registerMethod(&this, "frames", &driveFrames);
        lua.registerMethod(&this, "move", &driveMove);
        lua.registerMethod(&this, "hold", &driveHold);
        lua.registerMethod(&this, "release", &driveRelease);
        lua.registerMethod(&this, "tap", &driveTap);
        lua.registerMethod(&this, "click", &driveClick);
        lua.registerMethod(&this, "settle", &driveSettle);
        lua.registerMethod(&this, "capture", &driveCapture);
        lua.registerMethod(&this, "watch", &driveWatch);
        lua.registerMethod(&this, "log", &driveLog);
        lua.registerMethod(&this, "summary", &driveSummary);
        lua.registerMethod(&this, "frame", &driveFrameCount);
        driveRef = luaL_ref(lua, LUA_REGISTRY);
    }

    void fail(const(char)* message) {
        fprintf(report, "drive error: %s\n", message);
        isFailed = true;
        isFinished = true;
    }

    // Called once a frame before the game steps; `isLoaded` says whether everything around the camera is drawn.
    DriveInput next(bool isLoaded) {
        events.clear();
        events.appendAll(later.slice());
        later.clear();
        if (isSettling && isLoaded) {
            finishSettling(true);
        }
        while (pendingFrames == 0 && !isFinished) {
            resume();
        }
        DriveInput input;
        if (pendingFrames > 0) {
            pendingFrames -= 1;
            if (motion.isActive()) {
                double[2] share = motion.next();
                input.dx = share[0];
                input.dy = share[1];
            }
            if (pendingFrames == 0 && isSettling) {
                finishSettling(false);
            }
        }
        input.events = events.slice();
        return input;
    }

    void finishSettling(bool isSettled) {
        pendingFrames = 0;
        isSettling = false;
        lua_pushboolean(thread, isSettled);
        resumeArguments = 1;
    }

    void resume() {
        int results = 0;
        int status = lua_resume(thread, lua, resumeArguments, &results);
        resumeArguments = 0;
        if (status == LUA_STATUS_OK) {
            isFinished = true;
        } else if (status == LUA_STATUS_YIELD) {
            lua_settop(thread, -results - 1);
        } else {
            luaL_traceback(lua, thread, lua_tolstring(thread, LUA_TOP, null), 0);
            fail(lua_tolstring(lua, LUA_TOP, null));
        }
    }

    // Called once a frame after the game stepped and before it is drawn, with the frame clock's reading.
    void record(double now, double dt, double stepMs, DriveInput input, Position camera, ref const Graph graph) {
        if (!isFinished) {
            FrameRecord made;
            made.frame = frame;
            made.dtMs = dt * MILLISECONDS_PER_SECOND;
            made.stepMs = stepMs;
            made.dx = input.dx;
            made.dy = input.dy;
            if (hasLast) {
                made.intervalMs = (now - lastNow) * MILLISECONDS_PER_SECOND;
                made.hasInterval = true;
                made.step = graph.cameraStep(lastCamera, camera);
            }
            lastNow = now;
            lastCamera = camera;
            hasLast = true;
            frame += 1;
            drawnPath.clear();
            if (isCaptureAsked) {
                drawnPath.appendAll(capturePath.slice());
                isCaptureAsked = false;
            }
            drawn = made;
            hasDrawn = true;
            isDrawnImaged = isWatching || drawnPath.length > 0;
        }
    }

    // Whether the frame about to be drawn should be copied out.
    bool wantsImage() const {
        return hasDrawn && isDrawnImaged;
    }

    bool isDone() const {
        return isFinished && !hasDrawn && !isWaitingImage;
    }

    // Called once a frame after drawing. A frame's image comes back with the next frame, so `image` belongs to the frame
    // that waits for it, and is null if that frame was not drawn or cannot be read back.
    void finishFrame(RenderTimes render, const(ubyte)[] image, uint width, uint height, bool isBgra) {
        if (isWaitingImage) {
            takeImage(image, width, height, isBgra);
            print(waiting);
            isWaitingImage = false;
        }
        if (hasDrawn) {
            drawn.render = render;
            if (isDrawnImaged) {
                waiting = drawn;
                Array!char swapped = waitingPath;
                waitingPath = drawnPath;
                drawnPath = swapped;
                isWaitingImage = true;
            } else {
                print(drawn);
            }
            hasDrawn = false;
        }
    }

    void takeImage(const(ubyte)[] image, uint width, uint height, bool isBgra) {
        if (image is null) {
            if (waitingPath.length > 0) {
                fprintf(report, "frame %u: not captured, the frame was not drawn or cannot be read back\n", waiting.frame);
            }
        } else {
            size_t pixels = cast(size_t) width * height;
            current.resize(pixels * RGBA_BYTES);
            copyAsRgba(current.slice(), image, isBgra);
            if (isWatching && previous.length == current.length) {
                waiting.image = differenceOf(previous.slice(), current.slice(), RGBA_BYTES, pixels);
                waiting.hasImage = true;
            }
            if (waitingPath.length > 0) {
                waitingPath.append('\0');
                bool isWritten = writePng(waitingPath.ptr, width, height, current.slice());
                fprintf(report, "frame %u: %s %s\n", waiting.frame, capturedText(isWritten), waitingPath.ptr);
            }
            Array!ubyte swapped = previous;
            previous = current;
            current = swapped;
        }
    }

    void print(ref const FrameRecord made) {
        if (isSummaryAsked && made.frame >= summaryFrame) {
            printSummary();
        }
        if (isLogging) {
            made.print(report);
        }
        summary.add(made);
    }

    // A summary covers the frames recorded before it was asked for, so it waits for the last of them to be printed.
    void askSummary(const(char)[] title) {
        if (isSummaryAsked) {
            printSummary();
        }
        summaryTitle.clear();
        summaryTitle.appendAll(title);
        summaryFrame = frame;
        isSummaryAsked = true;
    }

    void printSummary() {
        fprintf(report, "== %.*s\n", cast(int) summaryTitle.length, summaryTitle.ptr);
        summary.print(report);
        summary = FrameSummary.init;
        isSummaryAsked = false;
    }

    void finish() {
        if (isSummaryAsked) {
            printSummary();
        }
        fprintf(report, "== after the last summary\n");
        summary.print(report);
        summaryTitle.release();
        fflush(report);
        if (lua !is null) {
            lua_close(lua);
            lua = null;
        }
        events.release();
        later.release();
        capturePath.release();
        drawnPath.release();
        waitingPath.release();
        previous.release();
        current.release();
    }
}

immutable(char)* capturedText(bool isWritten) {
    if (isWritten) {
        return "captured";
    } else {
        return "could not write";
    }
}

DriveHost* driveHost(lua_State* lua) {
    luaL_checktype(lua, SELF, LUA_TYPE_TABLE);
    return cast(DriveHost*) lua_touserdata(lua, LUA_FIRST_UPVALUE);
}

int yieldFrames(lua_State* lua, DriveHost* host, uint frames) {
    host.pendingFrames = frames;
    if (frames == 0) {
        return 0;
    } else {
        return lua_yieldk(lua, 0, 0, null);
    }
}

uint frameCount(lua_State* lua, int index) {
    long count = luaL_checkinteger(lua, index);
    if (count < 0) {
        luaL_error(lua, "a frame count cannot be negative");
    }
    return cast(uint) count;
}

extern (C) int driveFrames(lua_State* lua) {
    DriveHost* host = driveHost(lua);
    return yieldFrames(lua, host, frameCount(lua, SELF + 1));
}

extern (C) int driveMove(lua_State* lua) {
    DriveHost* host = driveHost(lua);
    double dx = luaL_checknumber(lua, SELF + 1);
    double dy = luaL_checknumber(lua, SELF + 2);
    uint frames = frameCount(lua, SELF + 3);
    if (frames == 0) {
        luaL_error(lua, "mouse motion needs at least one frame");
    }
    host.motion = MouseMotion([dx, dy], [0, 0], frames, 0);
    return yieldFrames(lua, host, frames);
}

void queueKeys(lua_State* lua, ref Array!DriveEvent queue, DriveEventKind kind) {
    foreach (index; SELF + 1 .. lua_gettop(lua) + 1) {
        const(char)* name = luaL_checklstring(lua, index, null);
        LuaLookup!DriveKey lookup = LuaLookup!DriveKey.fromName(name[0 .. strlen(name)]);
        if (!lookup.isFound) {
            luaL_error(lua, "unknown key '%s'", name);
        }
        queue.append(DriveEvent(kind, lookup.value, 0));
    }
}

extern (C) int driveHold(lua_State* lua) {
    queueKeys(lua, driveHost(lua).events, DriveEventKind.press);
    return 0;
}

extern (C) int driveRelease(lua_State* lua) {
    queueKeys(lua, driveHost(lua).events, DriveEventKind.release);
    return 0;
}

extern (C) int driveTap(lua_State* lua) {
    DriveHost* host = driveHost(lua);
    queueKeys(lua, host.events, DriveEventKind.press);
    queueKeys(lua, host.later, DriveEventKind.release);
    return 0;
}

extern (C) int driveClick(lua_State* lua) {
    long button = luaL_checkinteger(lua, SELF + 1);
    if (button != LEFT_BUTTON && button != RIGHT_BUTTON) {
        luaL_error(lua, "the button is %d (left) or %d (right)", cast(int) LEFT_BUTTON, cast(int) RIGHT_BUTTON);
    }
    driveHost(lua).events.append(DriveEvent(DriveEventKind.click, DriveKey.init, cast(uint) button));
    return 0;
}

extern (C) int driveSettle(lua_State* lua) {
    DriveHost* host = driveHost(lua);
    uint limit = frameCount(lua, SELF + 1);
    if (limit == 0) {
        luaL_error(lua, "settling needs at least one frame");
    }
    host.isSettling = true;
    return yieldFrames(lua, host, limit);
}

extern (C) int driveCapture(lua_State* lua) {
    DriveHost* host = driveHost(lua);
    const(char)* path = luaL_checklstring(lua, SELF + 1, null);
    host.capturePath.clear();
    host.capturePath.appendAll(path[0 .. strlen(path)]);
    host.isCaptureAsked = true;
    return 0;
}

extern (C) int driveWatch(lua_State* lua) {
    DriveHost* host = driveHost(lua);
    host.isWatching = lua_toboolean(lua, SELF + 1) != 0;
    if (!host.isWatching) {
        host.previous.clear();
    }
    return 0;
}

extern (C) int driveLog(lua_State* lua) {
    driveHost(lua).isLogging = lua_toboolean(lua, SELF + 1) != 0;
    return 0;
}

// Prints the summary of the frames since the last one and starts a new one, so a script can measure its parts apart.
extern (C) int driveSummary(lua_State* lua) {
    const(char)* title = luaL_checklstring(lua, SELF + 1, null);
    driveHost(lua).askSummary(title[0 .. strlen(title)]);
    return 0;
}

extern (C) int driveFrameCount(lua_State* lua) {
    lua_pushinteger(lua, driveHost(lua).frame);
    return 1;
}
