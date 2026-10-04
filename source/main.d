module main;

import core.stdc.stdio : FILE, fclose, fopen, fprintf, snprintf;
import core.stdc.stdlib : free, malloc, strtof;
import core.stdc.string : strcmp;
import core.sys.posix.time : CLOCK_MONOTONIC, clock_gettime, nanosleep, timespec;
import bindings.platform : Atom, Button1, Button3, ButtonPress, ClientMessage, CurrentTime, Cursor, Display, False, FocusOut, GenericEvent, GrabModeAsync, GrabSuccess, KeyPress, KeyRelease, KeySym, Pixmap, Success, True, UnmapNotify, VkExtent2D, Window, XBlackPixel, XCloseDisplay, XColor, XCreateBitmapFromData, XCreatePixmapCursor, XCreateSimpleWindow, XDefaultScreen, XDestroyWindow, XDisplayHeight, XDisplayWidth, XEvent, XFlush, XFreeCursor, XFreeEventData, XFreePixmap, XGenericEventCookie, XGetEventData, XGrabPointer, XIAllMasterDevices, XIDeviceInfo, XIEventMask, XIFreeDeviceInfo, XIModeAbsolute, XIQueryDevice, XIQueryVersion, XIRawEvent, XISelectEvents, XIValuatorClass, XIValuatorClassInfo, XI_DeviceChanged, XI_RawMotion, XInternAtom, XK_1, XK_9, XK_Down, XK_Escape, XK_Left, XK_Right, XK_Shift_L, XK_Up, XK_a, XK_d, XK_n, XK_s, XK_space, XK_v, XK_w, XLookupKeysym, XMapWindow, XNextEvent, XOpenDisplay, XPending, XQueryExtension, XRootWindow, XSelectInput, XSetWMProtocols, XStoreName, XUngrabPointer, XkbSetDetectableAutoRepeat;
import client.config : ClientConfig, loadClientConfig;
import client.game : FrameInput, Game, KEY_COUNT, Key, MATERIAL_PALETTE, axisValue, createGame, gameBreakBlock, gamePlaceBlock, modeName, releaseGame, stepGame, toggleMode;
import client.graphics.renderer : Renderer;
import client.local_world : updateLocalWorld, worldgenSettled;
import client.png : writePng;
import client.script : ScriptHost, ScriptRecorder, closeScript, closeScriptRecorder, openScriptRecorder, recordEvent, recordFrame, runScript;
import client.worldgen_driver : settleWorldgen;
import common.proto : MovementMode;
import common.dodeca : VERTEX_COUNT;
import common.proto : MovementMode;
import common.sim_config : SimConfigRaw;

enum uint WINDOW_WIDTH = 1280;
enum uint WINDOW_HEIGHT = 720;
enum uint SCREENSHOT_WIDTH = 640;
enum uint SCREENSHOT_HEIGHT = 360;
enum double BENCH_FRAME_SECONDS = 1.0 / 60.0;
enum uint BENCH_MOVE_FRAMES = 300;
enum double MILLISECONDS_PER_SECOND = 1e3;
enum double TITLE_INTERVAL_SECONDS = 1.0;
enum double NANOSECONDS_PER_SECOND = 1e9;
enum size_t TEXT_CAPACITY = 256;
enum uint KEYCODE_COUNT = 256;
enum uint CURSOR_BITMAP_SIZE = 8;
enum int EXIT_OK = 0;
enum int EXIT_FAILED = 1;
enum long KEY_PRESS_MASK = 1L << 0;
enum long KEY_RELEASE_MASK = 1L << 1;
enum long BUTTON_PRESS_MASK = 1L << 2;
enum long STRUCTURE_NOTIFY_MASK = 1L << 17;
enum long FOCUS_CHANGE_MASK = 1L << 21;
enum long INPUT_EVENT_MASK = KEY_PRESS_MASK | KEY_RELEASE_MASK | BUTTON_PRESS_MASK | STRUCTURE_NOTIFY_MASK | FOCUS_CHANGE_MASK;
enum uint POINTER_GRAB_MASK = cast(uint) BUTTON_PRESS_MASK;
enum int XI_REQUIRED_MAJOR = 2;
enum int XI_REQUIRED_MINOR = 1;
enum size_t XI_MASK_BYTES = (XI_RawMotion >> 3) + 1;
enum uint POINTER_AXES = 2;
enum uint BITS_PER_BYTE = 8;
enum int NO_DEVICE = -1;

struct Arguments {
    const(char)* configPath = "mined.cfg";
    const(char)* recordPath;
    const(char)* screenshotPath;
    const(char)* reportPath;
    const(char)* scriptPath;
    float sensitivity = 0;
    bool hasSensitivity;
    bool invertY;
    bool flatWorldgen;
    bool benchLoad;
}

struct KeyBinding {
    KeySym symbol;
    Key key;
}

immutable KeyBinding[10] KEY_BINDINGS = [
    KeyBinding(XK_w, Key.fwd),
    KeyBinding(XK_s, Key.back),
    KeyBinding(XK_a, Key.left),
    KeyBinding(XK_d, Key.right),
    KeyBinding(XK_space, Key.up),
    KeyBinding(XK_Shift_L, Key.down),
    KeyBinding(XK_Left, Key.yawLeft),
    KeyBinding(XK_Right, Key.yawRight),
    KeyBinding(XK_Up, Key.pitchUp),
    KeyBinding(XK_Down, Key.pitchDown),
];

struct PointerAxis {
    double countsPerValue = 1;
    double last = 0;
    bool absolute;
    bool haveLast;
}

struct RawPointer {
    PointerAxis[POINTER_AXES] axes;
    int opcode;
    int deviceId = NO_DEVICE;
}

struct Session {
    Game game;
    Renderer renderer;
    ScriptRecorder recorder;
    Display* display;
    Window window;
    Cursor invisibleCursor;
    Atom deleteAtom;
    RawPointer pointer;
    double mouseDx = 0;
    double mouseDy = 0;
    ClientConfig config;
    float fps = 0;
    int screen;
    bool[KEYCODE_COUNT] keyDown;
    bool[KEY_COUNT] held;
    bool mouseCaptured;
    bool running = true;
    bool renderFailed;
    bool titleDirty = true;
}

double nowSeconds() {
    timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec + now.tv_nsec / NANOSECONDS_PER_SECOND;
}

Arguments parseArguments(int argc, char** argv) {
    Arguments arguments;
    int index = 1;
    while (index < argc) {
        const(char)* argument = argv[index];
        bool hasValue = index + 1 < argc;
        if (strcmp(argument, "--config") == 0 && hasValue) {
            arguments.configPath = argv[index + 1];
            index += 1;
        } else if (strcmp(argument, "--record") == 0 && hasValue) {
            arguments.recordPath = argv[index + 1];
            index += 1;
        } else if (strcmp(argument, "--sensitivity") == 0 && hasValue) {
            arguments.sensitivity = strtof(argv[index + 1], null);
            arguments.hasSensitivity = true;
            index += 1;
        } else if (strcmp(argument, "--invert-y") == 0) {
            arguments.invertY = true;
        } else if (strcmp(argument, "--flat") == 0) {
            arguments.flatWorldgen = true;
        } else if (strcmp(argument, "--screenshot") == 0 && hasValue) {
            arguments.screenshotPath = argv[index + 1];
            index += 1;
        } else if (strcmp(argument, "--bench-load") == 0) {
            arguments.benchLoad = true;
        } else if (strcmp(argument, "--out") == 0 && hasValue) {
            arguments.reportPath = argv[index + 1];
            index += 1;
        } else if (argument[0] != '-') {
            arguments.scriptPath = argument;
        }
        index += 1;
    }
    return arguments;
}

bool openWindow(Session* session) {
    session.display = XOpenDisplay(null);
    bool ok = session.display !is null;
    if (ok) {
        session.screen = XDefaultScreen(session.display);
        session.window = XCreateSimpleWindow(session.display, XRootWindow(session.display, session.screen), 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, 0, XBlackPixel(session.display, session.screen), XBlackPixel(session.display, session.screen));
        XSelectInput(session.display, session.window, INPUT_EVENT_MASK);
        session.deleteAtom = XInternAtom(session.display, "WM_DELETE_WINDOW", False);
        XSetWMProtocols(session.display, session.window, &session.deleteAtom, 1);
        XkbSetDetectableAutoRepeat(session.display, True, null);
        char[CURSOR_BITMAP_SIZE] blank = 0;
        Pixmap bitmap = XCreateBitmapFromData(session.display, session.window, blank.ptr, CURSOR_BITMAP_SIZE, CURSOR_BITMAP_SIZE);
        XColor black;
        session.invisibleCursor = XCreatePixmapCursor(session.display, bitmap, bitmap, &black, &black, 0, 0);
        XFreePixmap(session.display, bitmap);
        ok = selectRawPointer(session);
        if (ok) {
            XMapWindow(session.display, session.window);
            XFlush(session.display);
        } else {
            closeWindow(session);
        }
    }
    return ok;
}

bool selectRawPointer(Session* session) {
    int firstEvent;
    int firstError;
    bool ok = XQueryExtension(session.display, "XInputExtension", &session.pointer.opcode, &firstEvent, &firstError) != 0;
    if (ok) {
        int major = XI_REQUIRED_MAJOR;
        int minor = XI_REQUIRED_MINOR;
        ok = XIQueryVersion(session.display, &major, &minor) == Success && (major > XI_REQUIRED_MAJOR || (major == XI_REQUIRED_MAJOR && minor >= XI_REQUIRED_MINOR));
    }
    if (ok) {
        ubyte[XI_MASK_BYTES] mask = 0;
        setEventBit(mask[], XI_RawMotion);
        setEventBit(mask[], XI_DeviceChanged);
        XIEventMask eventMask = XIEventMask(XIAllMasterDevices, cast(int) mask.length, mask.ptr);
        XISelectEvents(session.display, XRootWindow(session.display, session.screen), &eventMask, 1);
    }
    return ok;
}

void setEventBit(ubyte[] mask, int event) {
    mask[event / BITS_PER_BYTE] |= cast(ubyte)(1 << (event % BITS_PER_BYTE));
}

bool eventBitSet(const(ubyte)* mask, int event) {
    return (mask[event / BITS_PER_BYTE] & (1 << (event % BITS_PER_BYTE))) != 0;
}

void closeWindow(Session* session) {
    XFreeCursor(session.display, session.invisibleCursor);
    XDestroyWindow(session.display, session.window);
    XCloseDisplay(session.display);
}

void captureMouse(Session* session) {
    int grab = XGrabPointer(session.display, session.window, True, POINTER_GRAB_MASK, GrabModeAsync, GrabModeAsync, session.window, session.invisibleCursor, CurrentTime);
    if (grab == GrabSuccess) {
        session.mouseCaptured = true;
        session.titleDirty = true;
    }
}

void releaseMouse(Session* session) {
    if (session.mouseCaptured) {
        XUngrabPointer(session.display, CurrentTime);
        session.mouseCaptured = false;
        session.titleDirty = true;
    }
}

void loadPointerAxes(Session* session, int deviceId) {
    RawPointer* pointer = &session.pointer;
    pointer.axes = PointerAxis.init;
    pointer.deviceId = deviceId;
    double[POINTER_AXES] screenExtent = [XDisplayWidth(session.display, session.screen), XDisplayHeight(session.display, session.screen)];
    int count = 0;
    XIDeviceInfo* devices = XIQueryDevice(session.display, deviceId, &count);
    if (devices !is null) {
        foreach (device; devices[0 .. count]) {
            foreach (info; device.classes[0 .. device.num_classes]) {
                if (info.type == XIValuatorClass) {
                    XIValuatorClassInfo* valuator = cast(XIValuatorClassInfo*) info;
                    if (valuator.number >= 0 && valuator.number < POINTER_AXES && valuator.mode == XIModeAbsolute && valuator.max > valuator.min) {
                        pointer.axes[valuator.number].absolute = true;
                        pointer.axes[valuator.number].countsPerValue = screenExtent[valuator.number] / (valuator.max - valuator.min);
                    }
                }
            }
        }
        XIFreeDeviceInfo(devices);
    }
}

double axisDelta(PointerAxis* axis, double value) {
    double delta = value * axis.countsPerValue;
    if (axis.absolute) {
        delta = 0;
        if (axis.haveLast) {
            delta = (value - axis.last) * axis.countsPerValue;
        }
        axis.last = value;
        axis.haveLast = true;
    }
    return delta;
}

void handleRawMotion(Session* session, const(XIRawEvent)* raw) {
    if (raw.deviceid != session.pointer.deviceId) {
        loadPointerAxes(session, raw.deviceid);
    }
    double[POINTER_AXES] delta = [0, 0];
    int valueIndex = 0;
    foreach (valuator; 0 .. raw.valuators.mask_len * BITS_PER_BYTE) {
        if (eventBitSet(raw.valuators.mask, valuator)) {
            if (valuator < POINTER_AXES) {
                delta[valuator] = axisDelta(&session.pointer.axes[valuator], raw.raw_values[valueIndex]);
            }
            valueIndex += 1;
        }
    }
    if (session.mouseCaptured) {
        session.mouseDx += delta[0];
        session.mouseDy += delta[1];
    }
}

void handleGenericEvent(Session* session, XGenericEventCookie* cookie) {
    if (cookie.extension == session.pointer.opcode && XGetEventData(session.display, cookie)) {
        if (cookie.evtype == XI_RawMotion) {
            handleRawMotion(session, cast(const(XIRawEvent)*) cookie.data);
        } else if (cookie.evtype == XI_DeviceChanged) {
            session.pointer.deviceId = NO_DEVICE;
        }
        XFreeEventData(session.display, cookie);
    }
}

void recordModeChange(Session* session) {
    char[TEXT_CAPACITY] call;
    snprintf(call.ptr, call.length, "player:mode(\"%s\")", modeName(&session.game));
    recordEvent(&session.recorder, call.ptr);
    session.titleDirty = true;
}

void setMovementKey(Session* session, KeySym symbol, bool held) {
    foreach (binding; KEY_BINDINGS) {
        if (binding.symbol == symbol) {
            session.held[binding.key] = held;
        }
    }
}

void handleKeyPress(Session* session, KeySym symbol, bool repeat) {
    if (symbol == XK_Escape) {
        releaseMouse(session);
    } else if (symbol == XK_v && !repeat) {
        toggleMode(&session.game, MovementMode.walk);
        recordModeChange(session);
    } else if (symbol == XK_n && !repeat) {
        toggleMode(&session.game, MovementMode.noclip);
        recordModeChange(session);
    } else if (symbol >= XK_1 && symbol <= XK_9) {
        uint index = cast(uint)(symbol - XK_1);
        if (index < MATERIAL_PALETTE.length && index != session.game.materialIndex) {
            session.game.materialIndex = index;
            char[TEXT_CAPACITY] call;
            snprintf(call.ptr, call.length, "player:material(%u)", index + 1);
            recordEvent(&session.recorder, call.ptr);
            session.titleDirty = true;
        }
    } else {
        setMovementKey(session, symbol, true);
    }
}

void handleButton(Session* session, uint button) {
    if (!session.mouseCaptured) {
        captureMouse(session);
    } else if (button == Button1) {
        gameBreakBlock(&session.game);
        recordEvent(&session.recorder, "player:break_block()");
    } else if (button == Button3) {
        gamePlaceBlock(&session.game);
        recordEvent(&session.recorder, "player:place_block()");
    }
}

void processEvent(Session* session, XEvent* event) {
    if (event.type == KeyPress) {
        uint keycode = event.xkey.keycode % KEYCODE_COUNT;
        handleKeyPress(session, XLookupKeysym(&event.xkey, 0), session.keyDown[keycode]);
        session.keyDown[keycode] = true;
    } else if (event.type == KeyRelease) {
        session.keyDown[event.xkey.keycode % KEYCODE_COUNT] = false;
        setMovementKey(session, XLookupKeysym(&event.xkey, 0), false);
    } else if (event.type == GenericEvent) {
        handleGenericEvent(session, &event.xcookie);
    } else if (event.type == ButtonPress) {
        handleButton(session, event.xbutton.button);
    } else if (event.type == FocusOut) {
        releaseMouse(session);
        session.keyDown[] = false;
        session.held[] = false;
    } else if (event.type == UnmapNotify) {
        releaseMouse(session);
    } else if (event.type == ClientMessage && cast(Atom) event.xclient.data.l[0] == session.deleteAtom) {
        session.running = false;
    }
}

void updateWindowTitle(Session* session) {
    char[TEXT_CAPACITY] title;
    if (session.mouseCaptured) {
        snprintf(title.ptr, title.length, "mined - %s (V) - [%u] - Esc to release mouse - FPS %.0f", modeName(&session.game), session.game.materialIndex + 1, cast(double) session.fps);
    } else {
        snprintf(title.ptr, title.length, "mined - %s (V) - click to capture mouse - FPS %.0f", modeName(&session.game), cast(double) session.fps);
    }
    XStoreName(session.display, session.window, title.ptr);
    session.titleDirty = false;
}

FrameInput buildFrameInput(Session* session, float dt) {
    float invert = 1.0f;
    if (session.config.invertY) {
        invert = -1.0f;
    }
    float yawRate = (axisValue(session.held[Key.yawRight]) - axisValue(session.held[Key.yawLeft])) * session.config.turnSpeed;
    float pitchRate = (axisValue(session.held[Key.pitchDown]) - axisValue(session.held[Key.pitchUp])) * session.config.turnSpeed;
    FrameInput frame;
    frame.held = session.held;
    frame.yaw = yawRate * dt + cast(float)(session.mouseDx * session.config.mouseRadiansPerCount);
    frame.pitch = pitchRate * dt + cast(float)(session.mouseDy * session.config.mouseRadiansPerCount) * invert;
    return frame;
}

void runLoop(Session* session) {
    double lastTime = nowSeconds();
    double lastTitleTime = lastTime;
    uint framesSinceTitle = 0;
    while (session.running) {
        double now = nowSeconds();
        float dt = cast(float)(now - lastTime);
        lastTime = now;
        session.mouseDx = 0;
        session.mouseDy = 0;
        while (XPending(session.display) > 0) {
            XEvent event;
            XNextEvent(session.display, &event);
            processEvent(session, &event);
        }
        if (session.running) {
            FrameInput frame = buildFrameInput(session, dt);
            recordFrame(&session.recorder, frame, dt);
            stepGame(&session.game, frame, dt);
            if (!session.renderer.render(&session.game.world)) {
                session.running = false;
                session.renderFailed = true;
            }
            framesSinceTitle += 1;
            if (now - lastTitleTime >= TITLE_INTERVAL_SECONDS) {
                session.fps = cast(float)(framesSinceTitle / (now - lastTitleTime));
                framesSinceTitle = 0;
                lastTitleTime = now;
                session.titleDirty = true;
            }
            if (session.titleDirty) {
                updateWindowTitle(session);
            }
        }
    }
}

bool renderScreenshot(Arguments arguments) {
    FILE* report = null;
    if (arguments.reportPath !is null) {
        report = fopen(arguments.reportPath, "w");
    }
    SimConfigRaw raw;
    ClientConfig config;
    Renderer* renderer = cast(Renderer*) malloc(Renderer.sizeof);
    *renderer = Renderer.init;
    bool ok = renderer.setupOffscreen(VkExtent2D(SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT), raw.chunkSize);
    Game game = createGame(arguments.flatWorldgen, config.reachMeters);
    game.settleWorldgenEachFrame = true;
    if (ok && arguments.scriptPath !is null) {
        ScriptHost host;
        host.game = &game;
        host.report = report;
        ok = runScript(&host, arguments.scriptPath) && host.failures == 0;
        closeScript(&host);
    }
    bool rendering = ok;
    uint frames = 0;
    while (!worldgenSettled(&game.world)) {
        updateLocalWorld(&game.world, true);
        settleWorldgen(&game.world.worldgenDriver, &game.world.graph);
    }
    while (rendering) {
        ok = renderer.render(&game.world);
        frames += 1;
        rendering = ok && renderer.meshBacklog() > 0;
    }
    if (ok) {
        ok = writePng(arguments.screenshotPath, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT, renderer.capture());
    }
    if (report !is null) {
        const(char)* outcome = "failed";
        if (ok) {
            outcome = "written";
        }
        fprintf(report, "screenshot: %s after %u frames (%u chunks meshed, %u faces)\n", outcome, frames, renderer.meshes.meshedChunks, renderer.meshes.allocator.used());
        fclose(report);
    }
    renderer.cleanup();
    free(renderer);
    releaseGame(&game);
    return ok;
}

struct PhaseTimes {
    double totalMs = 0;
    double worstMs = 0;

    void add(double ms) {
        totalMs += ms;
        if (ms > worstMs) {
            worstMs = ms;
        }
    }
}

bool benchLoad(Arguments arguments) {
    FILE* report = fopen(arguments.reportPath, "w");
    SimConfigRaw raw;
    ClientConfig config;
    Renderer* renderer = cast(Renderer*) malloc(Renderer.sizeof);
    *renderer = Renderer.init;
    bool ok = report !is null && renderer.setupOffscreen(VkExtent2D(SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT), raw.chunkSize);
    Game game = createGame(arguments.flatWorldgen, config.reachMeters);
    PhaseTimes step;
    PhaseTimes render;
    PhaseTimes frame;
    uint frames = 0;
    uint nearbyFrame = 0;
    uint generatedFrame = 0;
    double start = nowSeconds();
    bool loading = ok;
    while (loading) {
        double frameStart = nowSeconds();
        FrameInput input;
        stepGame(&game, input, cast(float) BENCH_FRAME_SECONDS);
        double stepped = nowSeconds();
        ok = renderer.render(&game.world);
        double rendered = nowSeconds();
        step.add((stepped - frameStart) * MILLISECONDS_PER_SECOND);
        render.add((rendered - stepped) * MILLISECONDS_PER_SECOND);
        frame.add((rendered - frameStart) * MILLISECONDS_PER_SECOND);
        frames += 1;
        if (nearbyFrame == 0 && game.world.hasNearby) {
            nearbyFrame = frames;
        }
        if (generatedFrame == 0 && worldgenSettled(&game.world)) {
            generatedFrame = frames;
        }
        double remaining = BENCH_FRAME_SECONDS - (nowSeconds() - frameStart);
        if (remaining > 0) {
            timespec pause = timespec(0, cast(long)(remaining * NANOSECONDS_PER_SECOND));
            nanosleep(&pause, null);
        }
        loading = ok && (renderer.meshBacklog() > 0 || !worldgenSettled(&game.world));
    }
    double elapsed = nowSeconds() - start;
    if (report !is null) {
        uint dense = 0;
        foreach (slot; 0 .. game.world.graph.nodeCount) {
            foreach (vertexIndex; 0 .. VERTEX_COUNT) {
                if (!game.world.graph.nodeAt(slot).chunks[vertexIndex].voxels.isSolid()) {
                    dense += 1;
                }
            }
        }
        fprintf(report, "bench-load ok=%d frames=%u wall=%.2fs nodes=%u dense_chunks=%u meshed=%u faces=%u\n", cast(int) ok, frames, elapsed, game.world.graph.nodeCount, dense, renderer.meshes.meshedChunks, renderer.meshes.allocator.used());
        fprintf(report, "nearby set complete at frame %u, worldgen settled at frame %u, meshing done at frame %u\n", nearbyFrame, generatedFrame, frames);
        fprintf(report, "frame avg=%.2fms worst=%.2fms\n", frame.totalMs / frames, frame.worstMs);
        fprintf(report, "step avg=%.2fms worst=%.2fms\n", step.totalMs / frames, step.worstMs);
        fprintf(report, "render avg=%.2fms worst=%.2fms\n", render.totalMs / frames, render.worstMs);
    }
    PhaseTimes moving;
    PhaseTimes movingStep;
    PhaseTimes movingRender;
    uint backloggedFrames = 0;
    game.mode = MovementMode.noclip;
    FrameInput forward;
    forward.held[Key.fwd] = true;
    foreach (i; 0 .. BENCH_MOVE_FRAMES) {
        double frameStart = nowSeconds();
        stepGame(&game, forward, cast(float) BENCH_FRAME_SECONDS);
        double stepped = nowSeconds();
        ok = ok && renderer.render(&game.world);
        moving.add((nowSeconds() - frameStart) * MILLISECONDS_PER_SECOND);
        movingStep.add((stepped - frameStart) * MILLISECONDS_PER_SECOND);
        movingRender.add((nowSeconds() - stepped) * MILLISECONDS_PER_SECOND);
        if (renderer.meshBacklog() > 0 || !worldgenSettled(&game.world)) {
            backloggedFrames += 1;
        }
        double remaining = BENCH_FRAME_SECONDS - (nowSeconds() - frameStart);
        if (remaining > 0) {
            timespec pause = timespec(0, cast(long)(remaining * NANOSECONDS_PER_SECOND));
            nanosleep(&pause, null);
        }
    }
    if (report !is null) {
        fprintf(report, "moving noclip: frame avg=%.2fms worst=%.2fms, %u of %u frames with loading pending\n", moving.totalMs / BENCH_MOVE_FRAMES, moving.worstMs, backloggedFrames, BENCH_MOVE_FRAMES);
        fprintf(report, "moving step avg=%.2fms worst=%.2fms, render avg=%.2fms worst=%.2fms\n", movingStep.totalMs / BENCH_MOVE_FRAMES, movingStep.worstMs, movingRender.totalMs / BENCH_MOVE_FRAMES, movingRender.worstMs);
        fclose(report);
    }
    renderer.cleanup();
    free(renderer);
    releaseGame(&game);
    return ok;
}

extern (C) int main(int argc, char** argv) {
    Arguments arguments = parseArguments(argc, argv);
    int status = EXIT_FAILED;
    if (arguments.benchLoad) {
        if (benchLoad(arguments)) {
            status = EXIT_OK;
        }
    } else if (arguments.screenshotPath !is null) {
        if (renderScreenshot(arguments)) {
            status = EXIT_OK;
        }
    } else {
        status = runWindowed(arguments);
    }
    return status;
}

int runWindowed(Arguments arguments) {
    Session* session = cast(Session*) malloc(Session.sizeof);
    *session = Session.init;
    session.config = loadClientConfig(arguments.configPath);
    if (arguments.hasSensitivity) {
        session.config.mouseRadiansPerCount = arguments.sensitivity;
    }
    if (arguments.invertY) {
        session.config.invertY = true;
    }
    if (arguments.recordPath !is null) {
        session.recorder = openScriptRecorder(arguments.recordPath);
    }
    int status = EXIT_FAILED;
    if (openWindow(session)) {
        SimConfigRaw raw;
        if (session.renderer.setup(session.display, session.window, raw.chunkSize)) {
            session.game = createGame(arguments.flatWorldgen, session.config.reachMeters);
            runLoop(session);
            releaseGame(&session.game);
            if (!session.renderFailed) {
                status = EXIT_OK;
            }
        }
        session.renderer.cleanup();
        closeWindow(session);
    }
    closeScriptRecorder(&session.recorder);
    free(session);
    return status;
}
