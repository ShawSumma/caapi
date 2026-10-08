module main;

import core.stdc.stdio : FILE, fclose, fopen, fprintf, snprintf;
import core.stdc.stdlib : free, malloc;
import core.stdc.string : strcmp;
import core.sys.posix.time : nanosleep, timespec;
import bindings.platform : Atom, Button1, Button3, ButtonPress, ClientMessage, CurrentTime, Cursor, Display, False, FocusOut, GenericEvent, GrabModeAsync, GrabSuccess, KeyPress, KeyRelease, KeySym, Pixmap, Success, True, UnmapNotify, VkExtent2D, Window, XBlackPixel, XCloseDisplay, XColor, XCreateBitmapFromData, XCreatePixmapCursor, XCreateSimpleWindow, XDefaultScreen, XDestroyWindow, XDisplayHeight, XDisplayWidth, XEvent, XFlush, XFreeCursor, XFreeEventData, XFreePixmap, XGenericEventCookie, XGetEventData, XGrabPointer, XIAllMasterDevices, XIDeviceInfo, XIEventMask, XIFreeDeviceInfo, XIModeAbsolute, XIQueryDevice, XIQueryVersion, XIRawEvent, XISelectEvents, XIValuatorClass, XIValuatorClassInfo, XI_DeviceChanged, XI_RawMotion, XInternAtom, XK_1, XK_9, XK_Escape, XK_Down, XK_Left, XK_Right, XK_Shift_L, XK_Up, XK_a, XK_d, XK_n, XK_s, XK_space, XK_v, XK_w, XLookupKeysym, XMapWindow, XNextEvent, XOpenDisplay, XPending, XQueryExtension, XRootWindow, XSelectInput, XSetWMProtocols, XStoreName, XUngrabPointer, XkbSetDetectableAutoRepeat;
import client.arguments : StartupError, FlagValue, NumberArgument, WorldgenArgument;
import client.config : ClientConfig;
import client.game : FrameInput, Game, KEY_COUNT, Key, MATERIAL_PALETTE, axisValue;
import client.graphics.renderer : FrameTimes, Renderer;
import client.png : writePng;
import client.script : ScriptHost, ScriptRecorder;
import client.structures : StructureProblem, growthProblem, placeStructure;
import common.character.controller : MovementMode;
import common.clock : MILLISECONDS_PER_SECOND, NANOSECONDS_PER_SECOND, nowSeconds;
import common.dodeca : VERTEX_COUNT;
import common.names : ENUM_NAMES;
import common.settings : CHUNK_DIMENSION;
import common.units : Angle, AngularSpeed, Time;
import common.worldgen.generation : Worldgen;

enum uint WINDOW_WIDTH = 1280;
enum uint WINDOW_HEIGHT = 720;
enum uint SCREENSHOT_WIDTH = 640;
enum uint SCREENSHOT_HEIGHT = 360;
enum double BENCH_FRAME_SECONDS = 1.0 / 60.0;
enum uint BENCH_MOVE_FRAMES = 300;
enum double TITLE_INTERVAL_SECONDS = 1.0;
enum size_t TEXT_CAPACITY = 256;
enum uint KEYCODE_COUNT = 256;
enum uint CURSOR_BITMAP_SIZE = 8;
enum int EXIT_OK = 0;
enum int EXIT_FAILED = 1;
enum int EXIT_USAGE = 2;
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
    StartupError error;
    const(char)* program;
    const(char)* configPath = "mined.cfg";
    const(char)* recordPath;
    const(char)* screenshotPath;
    const(char)* reportPath;
    const(char)* scriptPath;
    Worldgen worldgen;
    float sensitivity = 0;
    bool hasSensitivity;
    bool isYInverted;
    bool isBenchLoad;

    static Arguments fromArgv(int argc, char** argv) {
        Arguments arguments = Arguments(StartupError.init, argv[0]);
        int index = 1;
        while (index < argc && !arguments.error.isPresent()) {
            index = arguments.parseAt(argc, argv, index);
        }
        if (!arguments.error.isPresent()) {
            arguments.error = arguments.usageError();
        }
        return arguments;
    }

    int parseAt(int argc, char** argv, int index) {
        const(char)* argument = argv[index];
        FlagValue value = FlagValue.fromArgv(argc, argv, index);
        if (strcmp(argument, "--config") == 0) {
            configPath = value.text;
            error = value.error;
            return index + 2;
        } else if (strcmp(argument, "--record") == 0) {
            recordPath = value.text;
            error = value.error;
            return index + 2;
        } else if (strcmp(argument, "--sensitivity") == 0) {
            parseSensitivity(value);
            return index + 2;
        } else if (strcmp(argument, "--invert-y") == 0) {
            isYInverted = true;
            return index + 1;
        } else if (strcmp(argument, "--worldgen") == 0) {
            WorldgenArgument parsed = WorldgenArgument.fromArgv(argc, argv, index);
            worldgen = parsed.worldgen;
            error = parsed.error;
            return index + parsed.consumed;
        } else if (strcmp(argument, "--screenshot") == 0) {
            screenshotPath = value.text;
            error = value.error;
            return index + 2;
        } else if (strcmp(argument, "--bench-load") == 0) {
            isBenchLoad = true;
            return index + 1;
        } else if (strcmp(argument, "--out") == 0) {
            reportPath = value.text;
            error = value.error;
            return index + 2;
        } else if (argument[0] == '-') {
            error = StartupError(null, "unknown option", argument);
            return index + 1;
        } else if (scriptPath !is null) {
            error = StartupError(null, "only one script is run, unexpected", argument);
            return index + 1;
        } else {
            scriptPath = argument;
            return index + 1;
        }
    }

    void parseSensitivity(FlagValue value) {
        if (value.error.isPresent()) {
            error = value.error;
        } else {
            NumberArgument number = NumberArgument.fromText(value.text);
            if (number.isPresent) {
                sensitivity = number.value;
                hasSensitivity = true;
            } else {
                error = StartupError(null, "sensitivity is not a number", value.text);
            }
        }
    }

    StartupError usageError() const {
        if (isBenchLoad && reportPath is null) {
            return StartupError(null, "needs --out", "--bench-load");
        } else if (screenshotPath !is null && (reportPath is null || scriptPath is null)) {
            return StartupError(null, "needs --out and a script", "--screenshot");
        } else if (screenshotPath is null && !isBenchLoad && (reportPath !is null || scriptPath !is null)) {
            return StartupError(null, "--out and a script are only for --screenshot, unexpected", firstOf(reportPath, scriptPath));
        } else {
            return StartupError.init;
        }
    }
}

const(char)* firstOf(const(char)* first, const(char)* second) {
    if (first !is null) {
        return first;
    } else {
        return second;
    }
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
    bool isAbsolute;
    bool hasLast;

    double delta(double value) {
        if (isAbsolute) {
            double previous = last;
            bool hadLast = hasLast;
            last = value;
            hasLast = true;
            if (hadLast) {
                return (value - previous) * countsPerValue;
            } else {
                return 0;
            }
        } else {
            return value * countsPerValue;
        }
    }
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
    bool[KEYCODE_COUNT] isKeyDown;
    bool[KEY_COUNT] isHeld;
    bool isCaptured;
    bool isRecording;
    bool isRunning = true;
    bool isTitleDirty = true;

    int run(Arguments arguments) {
        if (arguments.recordPath is null) {
            return runWindow(arguments);
        } else {
            immutable bool isOpened = recorder.open(arguments.recordPath);
            if (!isOpened) {
                StartupError(null, "cannot open the recording file", arguments.recordPath).report(arguments.program);
                return EXIT_FAILED;
            } else {
                isRecording = true;
                int status = runWindow(arguments);
                recorder.close();
                return status;
            }
        }
    }

    int runWindow(Arguments arguments) {
        immutable bool isWindowOpen = openWindow();
        if (!isWindowOpen) {
            StartupError(null, "cannot open a window: needs an X display with XInput 2.1", null).report(arguments.program);
            return EXIT_FAILED;
        } else {
            renderer.setup(display, window, CHUNK_DIMENSION);
            game = Game.make(arguments.worldgen, config.reach);
            immutable bool isPlaced = isStructurePlaced(game, arguments);
            if (isPlaced) {
                runLoop();
            }
            immutable bool isGrown = isPlaced && isStructureGrown(game, arguments);
            game.release();
            renderer.cleanup();
            closeWindow();
            return exitStatus(isGrown);
        }
    }

    bool openWindow() {
        display = XOpenDisplay(null);
        if (display is null) {
            return false;
        } else {
            screen = XDefaultScreen(display);
            window = XCreateSimpleWindow(display, XRootWindow(display, screen), 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, 0, XBlackPixel(display, screen), XBlackPixel(display, screen));
            XSelectInput(display, window, INPUT_EVENT_MASK);
            deleteAtom = XInternAtom(display, "WM_DELETE_WINDOW", False);
            XSetWMProtocols(display, window, &deleteAtom, 1);
            XkbSetDetectableAutoRepeat(display, True, null);
            char[CURSOR_BITMAP_SIZE] blank = 0;
            Pixmap bitmap = XCreateBitmapFromData(display, window, blank.ptr, CURSOR_BITMAP_SIZE, CURSOR_BITMAP_SIZE);
            XColor black;
            invisibleCursor = XCreatePixmapCursor(display, bitmap, bitmap, &black, &black, 0, 0);
            XFreePixmap(display, bitmap);
            immutable bool isPointerSelected = selectRawPointer();
            if (!isPointerSelected) {
                closeWindow();
                return false;
            } else {
                XMapWindow(display, window);
                XFlush(display);
                return true;
            }
        }
    }

    bool selectRawPointer() {
        int firstEvent;
        int firstError;
        immutable int hasExtension = XQueryExtension(display, "XInputExtension", &pointer.opcode, &firstEvent, &firstError);
        if (hasExtension == 0) {
            return false;
        } else {
            int major = XI_REQUIRED_MAJOR;
            int minor = XI_REQUIRED_MINOR;
            immutable int versionStatus = XIQueryVersion(display, &major, &minor);
            if (versionStatus != Success || !isXInputVersionSufficient(major, minor)) {
                return false;
            } else {
                ubyte[XI_MASK_BYTES] mask = 0;
                setEventBit(mask[], XI_RawMotion);
                setEventBit(mask[], XI_DeviceChanged);
                XIEventMask eventMask = XIEventMask(XIAllMasterDevices, cast(int) mask.length, mask.ptr);
                XISelectEvents(display, XRootWindow(display, screen), &eventMask, 1);
                return true;
            }
        }
    }

    void closeWindow() {
        XFreeCursor(display, invisibleCursor);
        XDestroyWindow(display, window);
        XCloseDisplay(display);
    }

    void capturePointer() {
        immutable int grab = XGrabPointer(display, window, True, POINTER_GRAB_MASK, GrabModeAsync, GrabModeAsync, window, invisibleCursor, CurrentTime);
        if (grab == GrabSuccess) {
            isCaptured = true;
            isTitleDirty = true;
        }
    }

    void releasePointer() {
        if (isCaptured) {
            XUngrabPointer(display, CurrentTime);
            isCaptured = false;
            isTitleDirty = true;
        }
        isHeld[] = false;
    }

    void loadPointerAxes(int deviceId) {
        pointer.axes = PointerAxis.init;
        pointer.deviceId = deviceId;
        double[POINTER_AXES] screenExtent = [XDisplayWidth(display, screen), XDisplayHeight(display, screen)];
        int count = 0;
        XIDeviceInfo* devices = XIQueryDevice(display, deviceId, &count);
        if (devices !is null) {
            foreach (device; devices[0 .. count]) {
                foreach (info; device.classes[0 .. device.num_classes]) {
                    if (info.type == XIValuatorClass) {
                        XIValuatorClassInfo* valuator = cast(XIValuatorClassInfo*) info;
                        if (valuator.number >= 0 && valuator.number < POINTER_AXES && valuator.mode == XIModeAbsolute && valuator.max > valuator.min) {
                            pointer.axes[valuator.number].isAbsolute = true;
                            pointer.axes[valuator.number].countsPerValue = screenExtent[valuator.number] / (valuator.max - valuator.min);
                        }
                    }
                }
            }
            XIFreeDeviceInfo(devices);
        }
    }

    void handleRawMotion(const(XIRawEvent)* raw) {
        if (raw.deviceid != pointer.deviceId) {
            loadPointerAxes(raw.deviceid);
        }
        double[POINTER_AXES] delta = [0, 0];
        int valueIndex = 0;
        foreach (valuator; 0 .. raw.valuators.mask_len * BITS_PER_BYTE) {
            if (isEventBitSet(raw.valuators.mask, valuator)) {
                if (valuator < POINTER_AXES) {
                    delta[valuator] = pointer.axes[valuator].delta(raw.raw_values[valueIndex]);
                }
                valueIndex += 1;
            }
        }
        if (isCaptured) {
            mouseDx += delta[0];
            mouseDy += delta[1];
        }
    }

    void handleGenericEvent(XGenericEventCookie* cookie) {
        if (cookie.extension == pointer.opcode) {
            immutable int hasData = XGetEventData(display, cookie);
            if (hasData != 0) {
                if (cookie.evtype == XI_RawMotion) {
                    handleRawMotion(cast(const(XIRawEvent)*) cookie.data);
                } else if (cookie.evtype == XI_DeviceChanged) {
                    pointer.deviceId = NO_DEVICE;
                }
                XFreeEventData(display, cookie);
            }
        }
    }

    void recordCall(const(char)* call) {
        if (isRecording) {
            recorder.recordCall(call);
        }
    }

    void recordModeChange() {
        if (isRecording) {
            recorder.recordMode(game.mode);
        }
        isTitleDirty = true;
    }

    void setMovementKey(KeySym symbol, bool isPressed) {
        foreach (binding; KEY_BINDINGS) {
            if (binding.symbol == symbol) {
                isHeld[binding.key] = isPressed;
            }
        }
    }

    void handleKeyPress(KeySym symbol, bool isRepeat) {
        if (symbol == XK_Escape) {
            releasePointer();
        } else if (isCaptured) {
            handleGameKey(symbol, isRepeat);
        }
    }

    void handleGameKey(KeySym symbol, bool isRepeat) {
        if (symbol == XK_v && !isRepeat) {
            game.toggleMode(MovementMode.walk);
            recordModeChange();
        } else if (symbol == XK_n && !isRepeat) {
            game.toggleMode(MovementMode.noclip);
            recordModeChange();
        } else if (symbol >= XK_1 && symbol <= XK_9) {
            selectMaterial(cast(uint)(symbol - XK_1));
        } else {
            setMovementKey(symbol, true);
        }
    }

    void selectMaterial(uint index) {
        if (index < MATERIAL_PALETTE.length && index != game.materialIndex) {
            game.materialIndex = index;
            if (isRecording) {
                recorder.recordMaterial(index + 1);
            }
            isTitleDirty = true;
        }
    }

    void handleButton(uint button) {
        if (!isCaptured) {
            capturePointer();
        } else if (button == Button1) {
            game.breakBlock();
            recordCall("break_block");
        } else if (button == Button3) {
            game.placeBlock();
            recordCall("place_block");
        }
    }

    void processEvent(XEvent* event) {
        if (event.type == KeyPress) {
            uint keycode = event.xkey.keycode % KEYCODE_COUNT;
            handleKeyPress(XLookupKeysym(&event.xkey, 0), isKeyDown[keycode]);
            isKeyDown[keycode] = true;
        } else if (event.type == KeyRelease) {
            isKeyDown[event.xkey.keycode % KEYCODE_COUNT] = false;
            setMovementKey(XLookupKeysym(&event.xkey, 0), false);
        } else if (event.type == GenericEvent) {
            handleGenericEvent(&event.xcookie);
        } else if (event.type == ButtonPress) {
            handleButton(event.xbutton.button);
        } else if (event.type == FocusOut) {
            releasePointer();
            isKeyDown[] = false;
        } else if (event.type == UnmapNotify) {
            releasePointer();
        } else if (event.type == ClientMessage && cast(Atom) event.xclient.data.l[0] == deleteAtom) {
            isRunning = false;
        }
    }

    void updateWindowTitle() {
        char[TEXT_CAPACITY] title;
        string mode = ENUM_NAMES!MovementMode[game.mode];
        char[TEXT_CAPACITY] modes;
        snprintf(modes.ptr, modes.length, "%.*s (V)", cast(int) mode.length, mode.ptr);
        if (isCaptured) {
            snprintf(title.ptr, title.length, "mined - %s - [%u] - Esc to release mouse - FPS %.0f", modes.ptr, game.materialIndex + 1, cast(double) fps);
        } else {
            snprintf(title.ptr, title.length, "mined - %s - click to capture mouse - FPS %.0f", modes.ptr, cast(double) fps);
        }
        XStoreName(display, window, title.ptr);
        isTitleDirty = false;
    }

    FrameInput buildFrameInput(Time dt) {
        AngularSpeed yawRate = config.keyTurnRate * (axisValue(isHeld[Key.yawRight]) - axisValue(isHeld[Key.yawLeft]));
        AngularSpeed pitchRate = config.keyTurnRate * (axisValue(isHeld[Key.pitchDown]) - axisValue(isHeld[Key.pitchUp]));
        Angle yaw = yawRate * dt + config.mouseTurnPerCount * cast(float) mouseDx;
        Angle pitch = pitchRate * dt + config.mouseTurnPerCount * cast(float) mouseDy * pitchSign(config.isYInverted);
        return FrameInput(yaw, pitch, isHeld);
    }

    void runLoop() {
        double lastTime = nowSeconds();
        double lastTitleTime = lastTime;
        uint framesSinceTitle = 0;
        while (isRunning) {
            double now = nowSeconds();
            Time dt = Time(cast(float)(now - lastTime));
            lastTime = now;
            mouseDx = 0;
            mouseDy = 0;
            while (XPending(display) > 0) {
                XEvent event;
                XNextEvent(display, &event);
                processEvent(&event);
            }
            if (isRunning) {
                FrameInput frame = buildFrameInput(dt);
                if (isRecording) {
                    recorder.recordFrame(frame, dt);
                }
                game.step(frame, dt);
                renderer.render(game.world);
                framesSinceTitle += 1;
                if (now - lastTitleTime >= TITLE_INTERVAL_SECONDS) {
                    fps = cast(float)(framesSinceTitle / (now - lastTitleTime));
                    framesSinceTitle = 0;
                    lastTitleTime = now;
                    isTitleDirty = true;
                }
                if (isTitleDirty) {
                    updateWindowTitle();
                }
            }
        }
    }
}

bool isXInputVersionSufficient(int major, int minor) {
    return major > XI_REQUIRED_MAJOR || (major == XI_REQUIRED_MAJOR && minor >= XI_REQUIRED_MINOR);
}

float pitchSign(bool isYInverted) {
    if (isYInverted) {
        return -1.0f;
    } else {
        return 1.0f;
    }
}

void setEventBit(ubyte[] mask, int event) {
    mask[event / BITS_PER_BYTE] |= cast(ubyte)(1 << (event % BITS_PER_BYTE));
}

bool isEventBitSet(const(ubyte)* mask, int event) {
    return (mask[event / BITS_PER_BYTE] & (1 << (event % BITS_PER_BYTE))) != 0;
}

void pauseUntilFrameEnd(double frameStart) {
    double remaining = BENCH_FRAME_SECONDS - (nowSeconds() - frameStart);
    if (remaining > 0) {
        timespec pause = timespec(0, cast(long)(remaining * NANOSECONDS_PER_SECOND));
        nanosleep(&pause, null);
    }
}

immutable(char)* writtenText(bool isWritten) {
    if (isWritten) {
        return "written";
    } else {
        return "failed";
    }
}

bool renderScreenshot(Arguments arguments) {
    FILE* report = fopen(arguments.reportPath, "w");
    if (report is null) {
        StartupError(null, "cannot open the report file", arguments.reportPath).report(arguments.program);
        return false;
    } else {
        ClientConfig config;
        Renderer* renderer = cast(Renderer*) malloc(Renderer.sizeof);
        *renderer = Renderer.init;
        renderer.setupOffscreen(VkExtent2D(SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT), CHUNK_DIMENSION);
        Game game = Game.make(arguments.worldgen, config.reach);
        game.isGeneratingOnDemand = true;
        immutable bool isPlaced = isStructurePlaced(game, arguments);
        bool isWritten = isPlaced && captureScreenshot(arguments, report, *renderer, game);
        renderer.cleanup();
        free(renderer);
        game.release();
        fclose(report);
        return isWritten;
    }
}

bool captureScreenshot(Arguments arguments, FILE* report, ref Renderer renderer, ref Game game) {
    ScriptHost host = ScriptHost.make(&game, report);
    immutable bool isCompleted = host.run(arguments.scriptPath);
    host.close();
    if (!isCompleted) {
        fprintf(report, "screenshot: not taken, the script failed\n");
        return false;
    } else {
        while (!game.world.isWorldgenSettled()) {
            game.world.update(true);
            game.world.streamer.settle(game.world.graph);
        }
        StructureProblem grown = growthProblem(game.world.graph);
        if (grown.isPresent) {
            fprintf(report, "%s\n", grown.text.ptr);
        }
        uint frames = 0;
        do {
            renderer.render(game.world);
            frames += 1;
        } while (renderer.meshBacklog() > 0);
        bool isWritten = writePng(arguments.screenshotPath, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT, renderer.capture());
        fprintf(report, "screenshot: %s after %u frames (%u chunks meshed, %u faces)\n", writtenText(isWritten), frames, renderer.meshes.meshedChunks, renderer.meshes.allocator.used());
        return isWritten && !grown.isPresent;
    }
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

struct RenderBreakdown {
    PhaseTimes fenceWait;
    PhaseTimes chunkUpdate;
    PhaseTimes gpuFrame;
    PhaseTimes gpuCull;

    void add(FrameTimes times) {
        fenceWait.add(times.fenceWaitMs);
        chunkUpdate.add(times.chunkUpdateMs);
        gpuFrame.add(times.gpu.frameMs);
        gpuCull.add(times.gpu.cullMs);
    }

    void print(FILE* report, uint frames) const {
        fprintf(report, "  fence wait avg=%.2fms worst=%.2fms, chunk update avg=%.2fms worst=%.2fms\n", fenceWait.totalMs / frames, fenceWait.worstMs, chunkUpdate.totalMs / frames, chunkUpdate.worstMs);
        fprintf(report, "  gpu frame avg=%.2fms worst=%.2fms, gpu cull avg=%.3fms worst=%.3fms\n", gpuFrame.totalMs / frames, gpuFrame.worstMs, gpuCull.totalMs / frames, gpuCull.worstMs);
    }
}

bool benchLoad(Arguments arguments) {
    FILE* report = fopen(arguments.reportPath, "w");
    if (report is null) {
        StartupError(null, "cannot open the report file", arguments.reportPath).report(arguments.program);
        return false;
    } else {
        ClientConfig config;
        Renderer* renderer = cast(Renderer*) malloc(Renderer.sizeof);
        *renderer = Renderer.init;
        renderer.setupOffscreen(VkExtent2D(SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT), CHUNK_DIMENSION);
        Game game = Game.make(arguments.worldgen, config.reach);
        immutable bool isPlaced = isStructurePlaced(game, arguments);
        if (isPlaced) {
            measureLoad(report, *renderer, game);
            measureFlight(report, *renderer, game);
        }
        immutable bool isGrown = isPlaced && isStructureGrown(game, arguments);
        renderer.cleanup();
        free(renderer);
        game.release();
        fclose(report);
        return isGrown;
    }
}

bool isStructurePlaced(ref Game game, Arguments arguments) {
    StructureProblem problem = game.placeStructure();
    if (problem.isPresent) {
        StartupError(null, problem.text.ptr, null).report(arguments.program);
    }
    return !problem.isPresent;
}

bool isStructureGrown(ref const Game game, Arguments arguments) {
    StructureProblem problem = growthProblem(game.world.graph);
    if (problem.isPresent) {
        StartupError(null, problem.text.ptr, null).report(arguments.program);
    }
    return !problem.isPresent;
}

void measureLoad(FILE* report, ref Renderer renderer, ref Game game) {
    PhaseTimes step;
    PhaseTimes render;
    PhaseTimes frame;
    RenderBreakdown breakdown;
    uint frames = 0;
    uint nearbyFrame = 0;
    uint generatedFrame = 0;
    double start = nowSeconds();
    do {
        double frameStart = nowSeconds();
        game.step(FrameInput.init, Time(cast(float) BENCH_FRAME_SECONDS));
        double stepped = nowSeconds();
        renderer.render(game.world);
        double rendered = nowSeconds();
        step.add((stepped - frameStart) * MILLISECONDS_PER_SECOND);
        render.add((rendered - stepped) * MILLISECONDS_PER_SECOND);
        frame.add((rendered - frameStart) * MILLISECONDS_PER_SECOND);
        breakdown.add(renderer.frameTimes);
        frames += 1;
        if (nearbyFrame == 0 && game.world.hasNearby) {
            nearbyFrame = frames;
        }
        if (generatedFrame == 0 && game.world.isWorldgenSettled()) {
            generatedFrame = frames;
        }
        pauseUntilFrameEnd(frameStart);
    } while (renderer.meshBacklog() > 0 || !game.world.isWorldgenSettled());
    double elapsed = nowSeconds() - start;
    uint dense = 0;
    foreach (index; 0 .. cast(size_t) game.world.graph.nodeCount * VERTEX_COUNT) {
        if (!game.world.graph.chunks.at(index).voxels.isSolid()) {
            dense += 1;
        }
    }
    fprintf(report, "bench-load frames=%u wall=%.2fs nodes=%u dense_chunks=%u meshed=%u faces=%u\n", frames, elapsed, game.world.graph.nodeCount, dense, renderer.meshes.meshedChunks, renderer.meshes.allocator.used());
    fprintf(report, "nearby set complete at frame %u, worldgen settled at frame %u, meshing done at frame %u\n", nearbyFrame, generatedFrame, frames);
    fprintf(report, "frame avg=%.2fms worst=%.2fms\n", frame.totalMs / frames, frame.worstMs);
    fprintf(report, "step avg=%.2fms worst=%.2fms\n", step.totalMs / frames, step.worstMs);
    fprintf(report, "render avg=%.2fms worst=%.2fms\n", render.totalMs / frames, render.worstMs);
    breakdown.print(report, frames);
}

void measureFlight(FILE* report, ref Renderer renderer, ref Game game) {
    PhaseTimes moving;
    PhaseTimes movingStep;
    PhaseTimes movingRender;
    RenderBreakdown breakdown;
    uint backloggedFrames = 0;
    game.mode = MovementMode.noclip;
    FrameInput forward;
    forward.isHeld[Key.fwd] = true;
    foreach (_; 0 .. BENCH_MOVE_FRAMES) {
        double frameStart = nowSeconds();
        game.step(forward, Time(cast(float) BENCH_FRAME_SECONDS));
        double stepped = nowSeconds();
        renderer.render(game.world);
        double rendered = nowSeconds();
        moving.add((rendered - frameStart) * MILLISECONDS_PER_SECOND);
        movingStep.add((stepped - frameStart) * MILLISECONDS_PER_SECOND);
        movingRender.add((rendered - stepped) * MILLISECONDS_PER_SECOND);
        breakdown.add(renderer.frameTimes);
        if (renderer.meshBacklog() > 0 || !game.world.isWorldgenSettled()) {
            backloggedFrames += 1;
        }
        pauseUntilFrameEnd(frameStart);
    }
    fprintf(report, "moving noclip: frame avg=%.2fms worst=%.2fms, %u of %u frames with loading pending\n", moving.totalMs / BENCH_MOVE_FRAMES, moving.worstMs, backloggedFrames, BENCH_MOVE_FRAMES);
    fprintf(report, "moving step avg=%.2fms worst=%.2fms, render avg=%.2fms worst=%.2fms\n", movingStep.totalMs / BENCH_MOVE_FRAMES, movingStep.worstMs, movingRender.totalMs / BENCH_MOVE_FRAMES, movingRender.worstMs);
    breakdown.print(report, BENCH_MOVE_FRAMES);
}

int exitStatus(bool isSucceeded) {
    if (isSucceeded) {
        return EXIT_OK;
    } else {
        return EXIT_FAILED;
    }
}

int runWindowed(Arguments arguments) {
    Session* session = cast(Session*) malloc(Session.sizeof);
    *session = Session.init;
    session.config = ClientConfig.fromFile(arguments.configPath);
    if (arguments.hasSensitivity) {
        session.config.mouseTurnPerCount = Angle(arguments.sensitivity);
    }
    if (arguments.isYInverted) {
        session.config.isYInverted = true;
    }
    int status = session.run(arguments);
    free(session);
    return status;
}

extern (C) int main(int argc, char** argv) {
    Arguments arguments = Arguments.fromArgv(argc, argv);
    if (arguments.error.isPresent()) {
        arguments.error.report(argv[0]);
        return EXIT_USAGE;
    } else if (arguments.isBenchLoad) {
        return exitStatus(benchLoad(arguments));
    } else if (arguments.screenshotPath !is null) {
        return exitStatus(renderScreenshot(arguments));
    } else {
        return runWindowed(arguments);
    }
}
