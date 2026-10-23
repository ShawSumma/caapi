module main;

import core.bitop : bsf;
import core.stdc.math : asinf, coshf, floorf, sinhf, tanf;
import core.stdc.stdio : FILE, fclose, fflush, fopen, fprintf, fscanf, snprintf;
import core.stdc.stdlib : free, malloc;
import core.stdc.string : strcmp;
import core.sys.posix.time : nanosleep, timespec;
import bindings.platform : VkExtent2D;
import base.array : Array;
import base.clock : MILLISECONDS_PER_SECOND, NANOSECONDS_PER_SECOND, PhaseTimes, nowSeconds, threadCpuMilliseconds;
import base.crash : reportCrashes, reportHangAfter;
import base.hashmap : HashMap, HashSlot;
import base.names : ENUM_NAMES;
import base.numbers : higherOf, lowerOf;
import base.parallel : ConcurrentQueue, QueueCell;
import base.slab : RunPool, SLAB_SIZE, Slab;
import base.units : Angle, AngularSpeed, Time;
import client.arguments : EXIT_FAILED, EXIT_USAGE, FlagValue, NumberArgument, StartupError, WorldgenArgument, exitStatus;
import client.config : ClientConfig;
import client.game : FrameInput, Game, KEY_COUNT, Key, MATERIAL_PALETTE, axisValue;
import client.graphics.core : SurfaceSource;
import client.graphics.renderer : FrameTimes, HALF_VERTICAL_FOV, Renderer;
import client.graphics.voxels.meshes : ChunkMeshes;
import client.meshing : Mesher;
import client.png : writePng;
import client.sampler : Sampler;
import client.script : ScriptHost, ScriptRecorder;
import client.streaming : Streamer;
import client.structures : StructureHost, StructureProblem, growthProblem, placeStructure, tileCounts;
import client.tasks : TaskQueues;
import client.tiles : PlanOutputs, TileHost, TilePainter, TileWork;
import client.world : LocalWorld, RENDER_RADIUS, StepPhases, fogVisibility;
import common.character.controller : MovementMode;
import common.graph : Graph, NO_SLOT, Node, childParentFaces;
import common.neighbors : chunkNeighborSlot, needsMesh;
import common.node : Chunk, ChunkSlot, ChunkState, cellCount;
import common.settings : CHUNK_DIMENSION;
import common.traversal : Collected, NOT_COLLECTED, NearbyNode, NearbyScratch;
import common.view : GraphView;
import common.worldgen.blueprint : Blueprint, Brush, LineRun, RunRef;
import common.worldgen.building : Building;
import common.worldgen.generation : NodeState, Worldgen;
import common.worldgen.horospheres : Horospheres, NodeHorospheres, NodeRises;
import common.worldgen.store : NodeStructure, StructureStore;
import common.worldgen.structure : nodeToNode;
import geometry.cube : DIRECTIONS;
import geometry.honeycomb : CORNER_COUNT, CUBE_RADIUS, Corner, FACE_COUNT, Face, NODE_RADIUS, cubeCenter, mirror;
import geometry.lorentz : Motion, Point;
import plugins.api.api : Material;

enum uint WINDOW_WIDTH = 1280;
enum uint WINDOW_HEIGHT = 720;
enum uint SCREENSHOT_WIDTH = 640;
enum uint SCREENSHOT_HEIGHT = 360;
enum double BENCH_FRAME_SECONDS = 1.0 / 60.0;
enum uint BENCH_MOVE_FRAMES = 300;
enum uint BENCH_FLIGHT_LEGS = 6;
enum uint BENCH_SETTLE_FRAMES = 3600;
enum uint BENCH_PROGRESS_FRAMES = 600;
immutable float[2] CENSUS_RADII = [2.0f, 4.0f];
enum uint CENSUS_INTERVAL = 10;
enum uint STALE_MESHES_SHOWN = 8;
enum uint BENCH_TIME_LIMIT_SECONDS = 300;
enum double TITLE_INTERVAL_SECONDS = 1.0;
enum double MAX_STEP_SECONDS = 0.1;
enum size_t TEXT_CAPACITY = 256;
enum size_t BYTES_PER_MEGABYTE = 1024 * 1024;

version (OSX) {
    import client.cocoa : Button1, Button3, CocoaWindow, KeyEvent, KeySym, WindowEvents, XK_1, XK_9, XK_Escape, XK_Down, XK_Left, XK_Right, XK_Shift_L, XK_Up, XK_a, XK_d, XK_n, XK_s, XK_space, XK_v, XK_w;

    enum string WINDOW_REQUIREMENT = "cannot open a window";
    enum int MACH_TASK_BASIC_INFO = 20;

    struct MachTaskBasicInfo {
        ulong virtualSize;
        ulong residentSize;
        ulong residentSizeMax;
        int[2] userTime;
        int[2] systemTime;
        int policy;
        int suspendCount;
    }

    extern (C) nothrow @nogc {
        extern __gshared uint mach_task_self_;
        int task_info(uint task, int flavor, int* info, uint* count);
    }

    MachTaskBasicInfo taskInfo() {
        MachTaskBasicInfo info;
        uint count = MachTaskBasicInfo.sizeof / int.sizeof;
        task_info(mach_task_self_, MACH_TASK_BASIC_INFO, cast(int*) &info, &count);
        return info;
    }

    size_t residentBytes() {
        return cast(size_t) taskInfo().residentSize;
    }

    size_t peakResidentBytes() {
        return cast(size_t) taskInfo().residentSizeMax;
    }

    struct MallocStatistics {
        uint blocksInUse;
        size_t sizeInUse;
        size_t maxSizeInUse;
        size_t sizeAllocated;
    }

    extern (C) void malloc_zone_statistics(void* zone, MallocStatistics* statistics) nothrow @nogc;

    HeapBytes heapBytes() {
        MallocStatistics statistics;
        malloc_zone_statistics(null, &statistics);
        return HeapBytes(statistics.sizeInUse, statistics.sizeAllocated - statistics.sizeInUse);
    }
} else {
    import core.sys.posix.sys.resource : RUSAGE_SELF, getrusage, rusage;
    import bindings.platform : Atom, Button1, Button3, ButtonPress, ClientMessage, CurrentTime, Cursor, Display, False, FocusOut, GenericEvent, GrabModeAsync, GrabSuccess, KeyPress, KeyRelease, KeySym, Pixmap, Success, True, UnmapNotify, Window, XBlackPixel, XCloseDisplay, XColor, XCreateBitmapFromData, XCreatePixmapCursor, XCreateSimpleWindow, XDefaultScreen, XDestroyWindow, XDisplayHeight, XDisplayWidth, XEvent, XFlush, XFreeCursor, XFreeEventData, XFreePixmap, XGenericEventCookie, XGetEventData, XGrabPointer, XIAllMasterDevices, XIDeviceInfo, XIEventMask, XIFreeDeviceInfo, XIModeAbsolute, XIQueryDevice, XIQueryVersion, XIRawEvent, XISelectEvents, XIValuatorClass, XIValuatorClassInfo, XI_DeviceChanged, XI_RawMotion, XInternAtom, XK_1, XK_9, XK_Escape, XK_Down, XK_Left, XK_Right, XK_Shift_L, XK_Up, XK_a, XK_d, XK_n, XK_s, XK_space, XK_v, XK_w, XLookupKeysym, XMapWindow, XNextEvent, XOpenDisplay, XPending, XQueryExtension, XRootWindow, XSelectInput, XSetWMProtocols, XStoreName, XUngrabPointer, XkbSetDetectableAutoRepeat;
    import base.pages : pageSize;

    enum string WINDOW_REQUIREMENT = "cannot open a window: needs an X display with XInput 2.1";
    enum size_t BYTES_PER_KILOBYTE = 1024;
    enum uint KEYCODE_COUNT = 256;
    enum uint CURSOR_BITMAP_SIZE = 8;
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

    bool isXInputVersionSufficient(int major, int minor) {
        return major > XI_REQUIRED_MAJOR || (major == XI_REQUIRED_MAJOR && minor >= XI_REQUIRED_MINOR);
    }

    void setEventBit(ubyte[] mask, int event) {
        mask[event / BITS_PER_BYTE] |= cast(ubyte)(1 << (event % BITS_PER_BYTE));
    }

    bool isEventBitSet(const(ubyte)* mask, int event) {
        return (mask[event / BITS_PER_BYTE] & (1 << (event % BITS_PER_BYTE))) != 0;
    }

    size_t residentBytes() {
        FILE* statm = fopen("/proc/self/statm", "r");
        size_t total = 0;
        size_t resident = 0;
        if (statm !is null) {
            fscanf(statm, "%zu %zu", &total, &resident);
            fclose(statm);
        }
        return resident * pageSize();
    }

    size_t peakResidentBytes() {
        rusage usage;
        getrusage(RUSAGE_SELF, &usage);
        return cast(size_t) usage.ru_maxrss * BYTES_PER_KILOBYTE;
    }

    struct MallInfo2 {
        size_t arena;
        size_t ordblks;
        size_t smblks;
        size_t hblks;
        size_t hblkhd;
        size_t usmblks;
        size_t fsmblks;
        size_t uordblks;
        size_t fordblks;
        size_t keepcost;
    }

    extern (C) MallInfo2 mallinfo2() nothrow @nogc;

    HeapBytes heapBytes() {
        MallInfo2 info = mallinfo2();
        return HeapBytes(info.uordblks + info.hblkhd, info.fordblks);
    }
}

struct HeapBytes {
    size_t used;
    size_t held;
}

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
    float renderRadius = RENDER_RADIUS;
    bool hasSensitivity;
    bool isYInverted;
    bool isBenchLoad;
    bool isProfiled;

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
        } else if (strcmp(argument, "--render-radius") == 0) {
            parseRenderRadius(value);
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
        } else if (strcmp(argument, "--profile") == 0) {
            isProfiled = true;
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

    void parseRenderRadius(FlagValue value) {
        if (value.error.isPresent()) {
            error = value.error;
        } else {
            NumberArgument number = NumberArgument.fromText(value.text);
            if (number.isPresent && number.value > 0) {
                renderRadius = number.value;
            } else {
                error = StartupError(null, "render radius is not a positive number", value.text);
            }
        }
    }

    StartupError usageError() const {
        if (isBenchLoad && reportPath is null) {
            return StartupError(null, "needs --out", "--bench-load");
        } else if (isProfiled && !isBenchLoad) {
            return StartupError(null, "is only for --bench-load", "--profile");
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

struct Session {
    Game game;
    Renderer renderer;
    ScriptRecorder recorder;
    version (OSX) {
        CocoaWindow window;
    } else {
        Display* display;
        Window window;
        Cursor invisibleCursor;
        Atom deleteAtom;
        RawPointer pointer;
        int screen;
        bool[KEYCODE_COUNT] isKeyDown;
    }
    double mouseDx = 0;
    double mouseDy = 0;
    ClientConfig config;
    float fps = 0;
    bool[KEY_COUNT] isHeld;
    bool isCaptured;
    bool isRecording;
    bool isRunning = true;
    bool isTitleDirty = true;

    int run(Arguments arguments) {
        if (arguments.recordPath is null) {
            return runWindow(arguments);
        } else {
            bool isOpened = recorder.open(arguments.recordPath);
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
        bool isWindowOpen = openWindow();
        if (!isWindowOpen) {
            StartupError(null, WINDOW_REQUIREMENT, null).report(arguments.program);
            return EXIT_FAILED;
        } else {
            renderer.setup(surfaceSource(), CHUNK_DIMENSION);
            game = Game.make(arguments.worldgen, config.reach);
            game.world.renderRadius = arguments.renderRadius;
            bool isPlaced = isStructurePlaced(game, arguments);
            if (isPlaced) {
                runLoop();
            }
            bool isGrown = isPlaced && isStructureGrown(game, arguments);
            game.release();
            renderer.cleanup();
            closeWindow();
            return exitStatus(isGrown);
        }
    }

    version (OSX) {
        bool openWindow() {
            return window.open(WINDOW_WIDTH, WINDOW_HEIGHT);
        }

        SurfaceSource surfaceSource() const {
            return SurfaceSource(window.metalLayer());
        }

        void closeWindow() {
            releasePointer();
            window.close();
        }

        void capturePointer() {
            window.capturePointer();
            isCaptured = true;
            isTitleDirty = true;
        }

        void releasePointer() {
            if (isCaptured) {
                window.releasePointer();
                isCaptured = false;
                isTitleDirty = true;
            }
            isHeld[] = false;
        }

        void handleKey(KeyEvent key) {
            if (key.isPressed) {
                handleKeyPress(key.symbol, key.isRepeat);
            } else {
                setMovementKey(key.symbol, false);
            }
        }

        void handleMotion(double dx, double dy) {
            if (isCaptured) {
                mouseDx += dx;
                mouseDy += dy;
            }
        }

        void pollEvents() {
            window.poll(WindowEvents(&handleKey, &handleButton, &handleMotion));
            if (!window.isOpen()) {
                isRunning = false;
            } else if (isCaptured && !window.isFocused()) {
                releasePointer();
            }
        }

        void storeTitle(const(char)* title) {
            window.setTitle(title);
        }
    } else {
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
                bool isPointerSelected = selectRawPointer();
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

        SurfaceSource surfaceSource() {
            return SurfaceSource(display, window);
        }

        bool selectRawPointer() {
            int firstEvent;
            int firstError;
            int hasExtension = XQueryExtension(display, "XInputExtension", &pointer.opcode, &firstEvent, &firstError);
            if (hasExtension == 0) {
                return false;
            } else {
                int major = XI_REQUIRED_MAJOR;
                int minor = XI_REQUIRED_MINOR;
                int versionStatus = XIQueryVersion(display, &major, &minor);
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
            int grab = XGrabPointer(display, window, True, POINTER_GRAB_MASK, GrabModeAsync, GrabModeAsync, window, invisibleCursor, CurrentTime);
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
                int hasData = XGetEventData(display, cookie);
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

        void pollEvents() {
            while (XPending(display) > 0) {
                XEvent event;
                XNextEvent(display, &event);
                processEvent(&event);
            }
        }

        void storeTitle(const(char)* title) {
            XStoreName(display, window, title);
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
        storeTitle(title.ptr);
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
            Time dt = Time(cast(float) lowerOf(now - lastTime, MAX_STEP_SECONDS));
            lastTime = now;
            mouseDx = 0;
            mouseDy = 0;
            pollEvents();
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

float pitchSign(bool isYInverted) {
    if (isYInverted) {
        return -1.0f;
    } else {
        return 1.0f;
    }
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

immutable(char)* settledText(bool isSettled) {
    if (isSettled) {
        return "settled";
    } else {
        return "still loading";
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
        game.world.renderRadius = arguments.renderRadius;
        game.isGeneratingOnDemand = true;
        bool isPlaced = isStructurePlaced(game, arguments);
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
    bool isCompleted = host.run(arguments.scriptPath);
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

    void print(FILE* report) const {
        fprintf(report, "  fence wait avg=%.2fms worst=%.2fms, chunk update avg=%.2fms worst=%.2fms\n", fenceWait.averageMs(), fenceWait.worstMs, chunkUpdate.averageMs(), chunkUpdate.worstMs);
        fprintf(report, "  gpu frame avg=%.2fms worst=%.2fms, gpu cull avg=%.3fms worst=%.3fms\n", gpuFrame.averageMs(), gpuFrame.worstMs, gpuCull.averageMs(), gpuCull.worstMs);
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
        game.world.renderRadius = arguments.renderRadius;
        bool isPlaced = isStructurePlaced(game, arguments);
        Sampler sampler;
        if (isPlaced) {
            if (arguments.isProfiled) {
                sampler.start();
            }
            reportHangAfter(BENCH_TIME_LIMIT_SECONDS);
            measureLoad(report, *renderer, game);
            if (arguments.isProfiled) {
                sampler.report(report, "load");
                sampler.start();
            }
            fflush(report);
            measureFlight(report, *renderer, game);
            if (arguments.isProfiled) {
                sampler.report(report, "flight");
            }
        }
        sampler.release();
        bool isGrown = isPlaced && isStructureGrown(game, arguments);
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
    game.world.phases = StepPhases.init;
    PhaseTimes stepCpu;
    double start = nowSeconds();
    do {
        double frameStart = nowSeconds();
        double cpuStart = threadCpuMilliseconds();
        game.step(FrameInput.init, Time(cast(float) BENCH_FRAME_SECONDS));
        stepCpu.add(threadCpuMilliseconds() - cpuStart);
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
        if (frames % BENCH_PROGRESS_FRAMES == 0) {
            fprintf(report, "loading: frame %u at %.1fs, nearby %zu nodes, %u chunks in flight, %u meshes queued\n", frames, nowSeconds() - start, game.world.cachedNodes.length, game.world.streamer.inFlight, renderer.meshBacklog());
            fflush(report);
        }
        pauseUntilFrameEnd(frameStart);
    } while (renderer.meshBacklog() > 0 || !game.world.isWorldgenSettled());
    double elapsed = nowSeconds() - start;
    uint dense = 0;
    foreach (index; 0 .. cast(size_t) game.world.graph.chunks.blockCount * CORNER_COUNT) {
        if (!game.world.graph.chunks.records.at(index).voxels.isUniform()) {
            dense += 1;
        }
    }
    fprintf(report, "bench-load frames=%u wall=%.2fs nodes=%u dense_chunks=%u meshed=%u faces=%u\n", frames, elapsed, game.world.graph.slotCount, dense, renderer.meshes.meshedChunks, renderer.meshes.allocator.used());
    fprintf(report, "nearby set complete at frame %u, worldgen settled at frame %u, meshing done at frame %u\n", nearbyFrame, generatedFrame, frames);
    checkMeshes(report, renderer, game.world.graph);
    printMemory(report, game.world);
    printMemoryParts(report, game.world, renderer);
    printShells(report, game.world, renderer);
    printWorldStats(report, game.world);
    fprintf(report, "frame avg=%.2fms worst=%.2fms\n", frame.averageMs(), frame.worstMs);
    fprintf(report, "step avg=%.2fms worst=%.2fms, of which main thread cpu avg=%.2fms\n", step.averageMs(), step.worstMs, stepCpu.averageMs());
    fprintf(report, "render avg=%.2fms worst=%.2fms\n", render.averageMs(), render.worstMs);
    breakdown.print(report);
}

void checkMeshes(FILE* report, ref const Renderer renderer, ref const Graph graph) {
    Mesher mesher;
    mesher.setup(graph.layout.dimension);
    uint checked = 0;
    uint stale = 0;
    foreach (slot; 0 .. graph.slotCount) {
        if (graph.isLive(slot) && graph.chunks.has(slot)) {
            foreach (index; 0 .. CORNER_COUNT) {
                ChunkSlot chunk = ChunkSlot(slot, cast(Corner) index);
                if (graph.chunks.at(chunk).state == ChunkState.populated && !graph.isBesideDropped(chunk)) {
                    size_t expected = 0;
                    if (graph.needsMesh(chunk)) {
                        expected = mesher.mesh(graph, chunk).length;
                    }
                    uint drawn = renderer.meshes.faceCountOf(graph.chunks.blockOf(slot), chunk.corner);
                    checked += 1;
                    if (drawn != expected) {
                        if (stale < STALE_MESHES_SHOWN) {
                            fprintf(report, "  stale mesh: slot %u corner %u draws %u faces, should draw %zu\n", slot, index, drawn, expected);
                        }
                        stale += 1;
                    }
                }
            }
        }
    }
    fprintf(report, "meshes checked=%u stale=%u\n", checked, stale);
    mesher.release();
}

bool isSettledSolid(const(Chunk)* chunk) {
    return chunk.state == ChunkState.populated && chunk.voxels.isOpaqueFill() && !chunk.isEdited && !chunk.isQueued;
}

bool isBesideDropped(ref const Graph graph, ChunkSlot chunk) {
    bool isBeside = false;
    foreach (direction; DIRECTIONS) {
        ChunkSlot neighbor = graph.chunkNeighborSlot(chunk, direction);
        isBeside = isBeside || (neighbor.slot != NO_SLOT && graph.chunks.at(neighbor).state == ChunkState.dropped);
    }
    return isBeside;
}

void measureFlight(FILE* report, ref Renderer renderer, ref Game game) {
    game.mode = MovementMode.noclip;
    foreach (leg; 0 .. BENCH_FLIGHT_LEGS) {
        fprintf(report, "flight leg %u from depth %u:\n", leg + 1, game.world.graph.depthOf(game.world.graph.slotOf(game.characterState.position.node)));
        measureLeg(report, renderer, game);
        fflush(report);
    }
    measureSettle(report, renderer, game);
}

void measureSettle(FILE* report, ref Renderer renderer, ref Game game) {
    uint frames = 0;
    do {
        double frameStart = nowSeconds();
        game.step(FrameInput.init, Time(cast(float) BENCH_FRAME_SECONDS));
        renderer.render(game.world);
        frames += 1;
        pauseUntilFrameEnd(frameStart);
    } while (frames < BENCH_SETTLE_FRAMES && (renderer.meshBacklog() > 0 || !game.world.isWorldgenSettled()));
    LoadedAround around;
    around.count(game.world);
    fprintf(report, "stopped after the flight for %u frames (at most %u): %s, nearby %zu nodes reaching %.2f\n", frames, BENCH_SETTLE_FRAMES, settledText(game.world.isWorldgenSettled()), game.world.cachedNodes.length, cast(double)(game.world.loadRadius() - game.world.radiusCut));
    around.print(report);
    around.release();
    printMemory(report, game.world);
    printMemoryParts(report, game.world, renderer);
    printShells(report, game.world, renderer);
}

enum Shortfall : ubyte {
    generating,
    building,
    unscanned,
    scanned,
    unlisted,
    unmade,
}

struct LoadedAround {
    Array!NearbyNode queue;
    Array!uint seen;
    uint generation;
    ulong[CENSUS_RADII.length] total;
    uint[CENSUS_RADII.length] least = uint.max;
    ulong[Shortfall.max + 1] missed;
    uint samples;

    void count(ref const LocalWorld world) {
        const(Graph)* graph = &world.graph;
        generation += 1;
        if (seen.length < graph.slotCount) {
            seen.resize(graph.slotCount);
        }
        Point!float eye = world.cameraPosition.local * Point!float.origin();
        float nodeReach = coshf(CENSUS_RADII[$ - 1] + NODE_RADIUS + CUBE_RADIUS);
        float outer = coshf(CENSUS_RADII[$ - 1]);
        uint[CENSUS_RADII.length] loaded;
        queue.clear();
        uint first = graph.slotOf(world.cameraPosition.node);
        queue.append(NearbyNode(Motion!float.identity(), first));
        seen.ptr[first] = generation;
        size_t head = 0;
        while (head < queue.length) {
            NearbyNode current = queue.ptr[head];
            head += 1;
            Shortfall waiting = Shortfall.unlisted;
            if (graph.structures.at(current.slot).isBuildingQueued) {
                waiting = Shortfall.building;
            } else if (world.nearby[world.published].indexOf(current.slot) != NOT_COLLECTED) {
                waiting = Shortfall.scanned;
                if (world.streamer.isScanPending(current.slot)) {
                    waiting = Shortfall.unscanned;
                }
            }
            foreach (index; 0 .. CORNER_COUNT) {
                Corner corner = cast(Corner) index;
                ChunkState state = graph.chunks.at(ChunkSlot(current.slot, corner)).state;
                float product = eye.coshDistance(current.transform * corner.cubeCenter);
                bool isLoaded = state == ChunkState.populated || state == ChunkState.dropped;
                foreach (radius, distance; CENSUS_RADII) {
                    if (isLoaded && !(product > coshf(distance))) {
                        loaded[radius] += 1;
                    }
                }
                if (!isLoaded && !(product > outer)) {
                    Shortfall reason = waiting;
                    if (state == ChunkState.generating) {
                        reason = Shortfall.generating;
                    }
                    missed[reason] += 1;
                }
            }
            foreach (index; 0 .. FACE_COUNT) {
                Face face = cast(Face) index;
                uint neighbor = graph.neighborSlot(current.slot, face);
                Motion!float transform = current.transform * face.mirror;
                if (neighbor == NO_SLOT && bsf(childParentFaces(graph.nodeAt(current.slot).parentFaces, face)) == index) {
                    foreach (corner; 0 .. CORNER_COUNT) {
                        if (!(eye.coshDistance(transform * (cast(Corner) corner).cubeCenter) > outer)) {
                            missed[Shortfall.unmade] += 1;
                        }
                    }
                } else if (neighbor != NO_SLOT && seen.ptr[neighbor] != generation && !(eye.coshDistance(transform * Point!float.origin()) > nodeReach)) {
                    seen.ptr[neighbor] = generation;
                    queue.append(NearbyNode(transform, neighbor));
                }
            }
        }
        foreach (radius; 0 .. CENSUS_RADII.length) {
            total[radius] += loaded[radius];
            least[radius] = lowerOf(loaded[radius], least[radius]);
        }
        samples += 1;
    }

    void print(FILE* report) const {
        fprintf(report, "  chunks loaded around the camera:");
        foreach (radius, distance; CENSUS_RADII) {
            fprintf(report, " within %.0f avg %.0f least %u", cast(double) distance, cast(double) total[radius] / samples, least[radius]);
        }
        fprintf(report, "\n  not loaded within %.0f avg:", cast(double) CENSUS_RADII[$ - 1]);
        foreach (kind, name; ENUM_NAMES!Shortfall) {
            fprintf(report, " %.*s %.0f", cast(int) name.length, name.ptr, cast(double) missed[kind] / samples);
        }
        fprintf(report, "\n");
    }

    void release() {
        queue.release();
        seen.release();
    }
}

void measureLeg(FILE* report, ref Renderer renderer, ref Game game) {
    PhaseTimes moving;
    PhaseTimes movingStep;
    PhaseTimes movingRender;
    RenderBreakdown breakdown;
    LoadedAround around;
    uint backloggedFrames = 0;
    FrameInput forward;
    forward.isHeld[Key.fwd] = true;
    game.world.phases = StepPhases.init;
    PhaseTimes stepCpu;
    foreach (frame; 0 .. BENCH_MOVE_FRAMES) {
        double frameStart = nowSeconds();
        double cpuStart = threadCpuMilliseconds();
        game.step(forward, Time(cast(float) BENCH_FRAME_SECONDS));
        stepCpu.add(threadCpuMilliseconds() - cpuStart);
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
        if (frame % CENSUS_INTERVAL == 0) {
            around.count(game.world);
        }
        pauseUntilFrameEnd(frameStart);
    }
    fprintf(report, "moving noclip: frame avg=%.2fms worst=%.2fms, %u of %u frames with loading pending\n", moving.averageMs(), moving.worstMs, backloggedFrames, BENCH_MOVE_FRAMES);
    fprintf(report, "moving step avg=%.2fms worst=%.2fms (main thread cpu avg=%.2fms), render avg=%.2fms worst=%.2fms\n", movingStep.averageMs(), movingStep.worstMs, stepCpu.averageMs(), movingRender.averageMs(), movingRender.worstMs);
    around.print(report);
    around.release();
    breakdown.print(report);
    fprintf(report, "  drawable chunks %u, %zu of them waiting for their node\n", renderer.meshes.drawableCount, renderer.meshes.unlisted.length);
    printMemory(report, game.world);
    printWorldStats(report, game.world);
}

void printWorldStats(FILE* report, ref const LocalWorld world) {
    fprintf(report, "evicted %u nodes, dropped %u far chunks and %u tiles\n", world.evictor.evicted, world.evictor.dropped, world.evictor.droppedTiles);
    fprintf(report, "step phases avg/worst: paint ahead %.2f/%.2fms ", world.phases.paint.averageMs(), world.phases.paint.worstMs);
    fprintf(report, "nearby %.2f/%.2fms (cpu %.2f) ", world.phases.nearby.averageMs(), world.phases.nearby.worstMs, world.phases.nearbyCpu.averageMs());
    fprintf(report, "streamer %.2f/%.2fms (cpu %.2f) ", world.phases.streamer.averageMs(), world.phases.streamer.worstMs, world.phases.streamerCpu.averageMs());
    fprintf(report, "evict %.2f/%.2fms\n", world.phases.evict.averageMs(), world.phases.evict.worstMs);
    fprintf(report, "parallel jobs %u, main waited %.0fms for other threads to finish them\n", world.streamer.pool.runs, world.streamer.pool.waitedMs);
    uint[2] tiles = tileCounts(world.graph);
    fprintf(report, "tiles painted ahead on all threads %u, painted when needed %u\n", tiles[0], tiles[1]);
    fprintf(report, "nearby %zu nodes, %u published, %u recoveries (%.0fms), %.0fms sliced\n", world.cachedNodes.length, world.nearbyStats.publishes, world.nearbyStats.recoveries, world.nearbyStats.recoveryMilliseconds, world.nearbyStats.slicedMilliseconds);
    fprintf(report, "nearby sets grown from the last %u, keeping %zu nodes as they were and expanding %zu again; %u moved to the camera\n", world.nearbyStats.grown, world.nearby[0].keptNodes + world.nearby[1].keptNodes, world.nearby[0].reexpandedNodes + world.nearby[1].reexpandedNodes, world.nearbyStats.rebases);
    fprintf(report, "nearby rebuilds restarted after the camera outran them %u, now reaching %.2f of %.2f\n", world.nearbyStats.restarts, cast(double)(world.loadRadius() - world.radiusCut), cast(double) world.loadRadius());
}

void printMemory(FILE* report, ref const LocalWorld world) {
    const(Graph)* graph = &world.graph;
    size_t buildings = 0;
    size_t buildingBytes = 0;
    size_t holding = 0;
    size_t stated = 0;
    size_t touched = 0;
    size_t referenced = 0;
    size_t parents = 0;
    size_t recent = 0;
    foreach (slot; 0 .. graph.slotCount) {
        const(Node)* node = graph.nodeAt(slot);
        const(Building)* building = graph.structures.buildingAt(slot);
        if (building !is null) {
            buildings += 1;
            buildingBytes += building.paintBytes();
        }
        if (graph.chunks.has(slot)) {
            holding += 1;
        }
        if (node.hasState) {
            stated += 1;
        }
        if (graph.structures.touchesAt(slot).length > 0) {
            touched += 1;
        }
        if (node.references > 0) {
            referenced += 1;
        }
        if (node.liveChildren > 0) {
            parents += 1;
        }
        if (slot < world.evictor.isRecent.length && world.evictor.isRecent.ptr[slot]) {
            recent += 1;
        }
    }
    size_t denseBytes = 0;
    foreach (index; 0 .. cast(size_t) graph.chunks.blockCount * CORNER_COUNT) {
        if (!graph.chunks.records.at(index).voxels.isUniform()) {
            denseBytes += cellCount(graph.layout.dimension) * Material.sizeof;
        }
    }
    size_t solidBlocks = 0;
    foreach (slot; 0 .. graph.slotCount) {
        if (graph.isLive(slot) && graph.chunks.has(slot)) {
            uint corner = 0;
            while (corner < CORNER_COUNT && isSettledSolid(graph.chunks.at(ChunkSlot(slot, cast(Corner) corner)))) {
                corner += 1;
            }
            if (corner == CORNER_COUNT) {
                solidBlocks += 1;
            }
        }
    }
    fprintf(report, "chunk blocks whose chunks are all settled and filled with something opaque: %zu\n", solidBlocks);
    fprintf(report, "nodes holding chunks=%zu with state=%zu, structure-touched=%zu referenced=%zu with children=%zu recent=%zu\n", holding, stated, touched, referenced, parents, recent);
    size_t nodeBytes = cast(size_t) graph.slotCount * (Node.sizeof + NodeState.sizeof + NodeStructure.sizeof + NodeHorospheres.sizeof + NodeRises.sizeof + uint.sizeof);
    size_t chunkBytes = cast(size_t) graph.chunks.blockCount * CORNER_COUNT * Chunk.sizeof;
    HeapBytes heap = heapBytes();
    fprintf(report, "memory: rss now=%zuMB peak=%zuMB, malloc in use %zuMB and free but held %zuMB, nodes=%u of %u slots (%zuMB), %u chunk blocks (%zuMB) buildings=%zu (%zuMB) dense voxels %zuMB\n", residentBytes() / BYTES_PER_MEGABYTE, peakResidentBytes() / BYTES_PER_MEGABYTE, heap.used / BYTES_PER_MEGABYTE, heap.held / BYTES_PER_MEGABYTE, graph.liveCount, graph.slotCount, nodeBytes / BYTES_PER_MEGABYTE, graph.chunks.blockCount, chunkBytes / BYTES_PER_MEGABYTE, buildings, buildingBytes / BYTES_PER_MEGABYTE, denseBytes / BYTES_PER_MEGABYTE);
    const(Blueprint)* blueprint = &graph.structures.blueprint;
    size_t brushBytes = blueprint.placed.brushes.capacity * Brush.sizeof + blueprint.placed.runs.capacity * LineRun.sizeof;
    foreach (ref tile; blueprint.tiles.slice()) {
        brushBytes += tile.painted.brushes.capacity * Brush.sizeof + tile.painted.runs.capacity * LineRun.sizeof;
    }
    size_t runBytes = 0;
    foreach (ref listed; blueprint.runsOn.slice()) {
        runBytes += listed.capacity * RunRef.sizeof;
    }
    fprintf(report, "blueprint: %zu lines, %zu brushes (%zuMB, line runs %zuMB), %zu tiles, %u painted again\n", blueprint.lines.length, blueprint.brushTotal(), brushBytes / BYTES_PER_MEGABYTE, runBytes / BYTES_PER_MEGABYTE, blueprint.tiles.length, blueprint.restoredTiles);
}

size_t bytesIn(T)(ref const Array!T array) {
    return array.capacity * T.sizeof;
}

size_t bytesIn(K, V)(ref const HashMap!(K, V) map) {
    return (map.current.capacity + map.previous.capacity) * (HashSlot!(K, V).sizeof + 1);
}

size_t bytesIn(T)(ref const Slab!T slab) {
    size_t blocks = 0;
    foreach (block; slab.blocks.slice()) {
        if (block !is null) {
            blocks += 1;
        }
    }
    return blocks * SLAB_SIZE * T.sizeof + bytesIn(slab.blocks) + bytesIn(slab.noted);
}

size_t bytesIn(T)(ref const RunPool!T pool) {
    size_t bytes = bytesIn(pool.items);
    foreach (ref list; pool.free) {
        bytes += bytesIn(list);
    }
    return bytes;
}

size_t bytesIn(T)(ref const ConcurrentQueue!T queue) {
    return (queue.mask + 1) * QueueCell!T.sizeof;
}

size_t bytesIn(ref const NearbyScratch scratch) {
    size_t bytes = bytesIn(scratch.nodes) + bytesIn(scratch.collected) + bytesIn(scratch.candidates) + bytesIn(scratch.kinds) + bytesIn(scratch.blocks) + bytesIn(scratch.around) + bytesIn(scratch.chain) + bytesIn(scratch.claimed) + bytesIn(scratch.isRederived) + bytesIn(scratch.derived) + bytesIn(scratch.outputs);
    foreach (ref batch; scratch.derived.slice()) {
        bytes += bytesIn(batch);
    }
    foreach (ref output; scratch.outputs.slice()) {
        bytes += bytesIn(output.found) + bytesIn(output.unknown) + bytesIn(output.missing);
    }
    return bytes + bytesIn(scratch.serial.found) + bytesIn(scratch.serial.unknown) + bytesIn(scratch.serial.missing);
}

size_t bytesIn(ref const GraphView view) {
    return bytesIn(view.nodes) + bytesIn(view.wanted) + bytesIn(view.wantedPaths) + bytesIn(view.virtualIds) + bytesIn(view.missingChildren) + bytesIn(view.statesOfSlots) + bytesIn(view.refs) + bytesIn(view.refsOfNodes) + bytesIn(view.risingFound) + bytesIn(view.rising) + bytesIn(view.choices) + bytesIn(view.storedSlots) + bytesIn(view.risingKeys) + bytesIn(view.choiceKeys);
}

size_t bytesIn(ref const TileWork work) {
    size_t bytes = bytesIn(work.hosts) + bytesIn(work.tasks) + bytesIn(work.paths) + bytesIn(work.outputOf) + bytesIn(work.lineIndices) + bytesIn(work.covered) + bytesIn(work.planning) + bytesIn(work.blocked) + bytesIn(work.taskOf);
    foreach (host; work.hosts.slice()) {
        const(TilePainter)* painter = &host.painter;
        const(PlanOutputs)* plan = &host.plan;
        bytes += TileHost.sizeof + bytesIn(painter.known) + bytesIn(painter.lines) + bytesIn(painter.brushes) + bytesIn(painter.touches) + bytesIn(painter.stops) + bytesIn(painter.strokes) + bytesIn(painter.paths) + bytesIn(painter.outputs);
        bytes += bytesIn(plan.tiles) + bytesIn(plan.paths) + bytesIn(plan.results) + bytesIn(plan.usedRecords) + bytesIn(plan.measures);
    }
    return bytes;
}

size_t megabytes(size_t bytes) {
    return bytes / BYTES_PER_MEGABYTE;
}

void printMemoryParts(FILE* report, ref const LocalWorld world, ref const Renderer renderer) {
    const(Graph)* graph = &world.graph;
    const(StructureStore)* structures = &graph.structures;
    const(Horospheres)* horospheres = &graph.horospheres;
    const(Blueprint)* blueprint = &structures.blueprint;
    size_t perSlot = bytesIn(graph.nodes) + bytesIn(graph.states) + bytesIn(structures.nodes) + bytesIn(horospheres.nodes) + bytesIn(horospheres.rises) + bytesIn(graph.chunks.blocks);
    size_t denseBytes = 0;
    foreach (index; 0 .. cast(size_t) graph.chunks.blockCount * CORNER_COUNT) {
        if (!graph.chunks.records.at(index).voxels.isUniform()) {
            denseBytes += cellCount(graph.layout.dimension) * Material.sizeof;
        }
    }
    fprintf(report, "memory by part (MB):\n");
    fprintf(report, "  graph: per-slot records %zu, id map %zu, free slots %zu, chunk records %zu, dense voxels %zu, chunk queues %zu\n", megabytes(perSlot), megabytes(bytesIn(graph.slots)), megabytes(bytesIn(graph.freeSlots.words) + bytesIn(graph.freeSlots.summary)), megabytes(bytesIn(graph.chunks.records)), megabytes(denseBytes), megabytes(bytesIn(graph.chunks.changed) + bytesIn(graph.chunks.restores)));
    size_t reachBytes = bytesIn(structures.strokes.lists) + bytesIn(structures.strokes.reaches) + bytesIn(structures.strokes.freeLists) + bytesIn(structures.strokes.visits) + bytesIn(structures.strokes.seen);
    foreach (ref list; structures.strokes.reaches.slice()) {
        reachBytes += bytesIn(list);
    }
    size_t buildingBytes = bytesIn(structures.buildings) + bytesIn(structures.freeBuildings);
    size_t builtStrokeBytes = 0;
    foreach (slot; 0 .. graph.slotCount) {
        const(Building)* building = structures.buildingAt(slot);
        if (building !is null) {
            buildingBytes += building.paintBytes() + bytesIn(building.materials);
            builtStrokeBytes += bytesIn(building.strokes);
        }
    }
    size_t brushBytes = bytesIn(blueprint.placed.brushes) + bytesIn(blueprint.placed.runs);
    size_t paintedStrokeBytes = bytesIn(blueprint.placed.strokes) + bytesIn(blueprint.placed.strokeRuns) + bytesIn(blueprint.placed.reached);
    foreach (ref tile; blueprint.tiles.slice()) {
        brushBytes += bytesIn(tile.painted.brushes) + bytesIn(tile.painted.runs);
        paintedStrokeBytes += bytesIn(tile.painted.strokes) + bytesIn(tile.painted.strokeRuns) + bytesIn(tile.painted.reached);
    }
    fprintf(report, "  structures: touches %zu, pending touches %zu, tiled faces %zu, buildings %zu; strokes in tiles %zu, reach index %zu, in buildings %zu\n", megabytes(bytesIn(structures.touches)), megabytes(bytesIn(structures.pending) + bytesIn(structures.pendingHeads)), megabytes(bytesIn(structures.tiledFaces)), megabytes(buildingBytes), megabytes(paintedStrokeBytes), megabytes(reachBytes), megabytes(builtStrokeBytes));
    size_t runBytes = bytesIn(blueprint.runsOn);
    foreach (ref listed; blueprint.runsOn.slice()) {
        runBytes += bytesIn(listed);
    }
    fprintf(report, "  blueprint: brushes %zu, runs on lines %zu, lines %zu, tiles %zu, line index %zu, touched edges %zu, claims %zu\n", megabytes(brushBytes), megabytes(runBytes), megabytes(bytesIn(blueprint.lines)), megabytes(bytesIn(blueprint.tiles)), megabytes(bytesIn(blueprint.lineIndex)), megabytes(bytesIn(blueprint.touchedEdges)), megabytes(bytesIn(blueprint.claims)));
    fprintf(report, "  horospheres: refs %zu, horospheres %zu, rising %zu, others %zu\n", megabytes(bytesIn(horospheres.refs)), megabytes(bytesIn(horospheres.horospheres)), megabytes(bytesIn(horospheres.risingFrom) + bytesIn(horospheres.rising)), megabytes(bytesIn(horospheres.forced) + bytesIn(horospheres.horosphereOf) + bytesIn(horospheres.freeHorospheres)));
    size_t viewBytes = bytesIn(graph.ownView);
    foreach (ref view; graph.threadViews.views.slice()) {
        viewBytes += bytesIn(view);
    }
    size_t tileBytes = 0;
    if (structures.grower.context !is null) {
        tileBytes = bytesIn((cast(const(StructureHost)*) structures.grower.context).tiles);
    }
    fprintf(report, "  scratch: nearby sets %zu and %zu, graph views %zu, tile painting %zu\n", megabytes(bytesIn(world.nearby[0])), megabytes(bytesIn(world.nearby[1])), megabytes(viewBytes), megabytes(tileBytes));
    const(Streamer)* streamer = &world.streamer;
    size_t streamBytes = bytesIn(streamer.requests) + bytesIn(streamer.urgentRequests) + bytesIn(streamer.buildingSlots) + bytesIn(streamer.urgentBuildingSlots) + bytesIn(streamer.planned) + bytesIn(streamer.made) + bytesIn(streamer.facts) + bytesIn(streamer.waiting) + bytesIn(streamer.nearCamera) + bytesIn(streamer.integrator.arrivals);
    const(TaskQueues)* queues = streamer.queues;
    size_t queueBytes = bytesIn(queues.generations) + bytesIn(queues.urgent) + bytesIn(queues.buildings) + bytesIn(queues.urgentBuildings) + bytesIn(queues.generated) + bytesIn(queues.built);
    fprintf(report, "  streaming: rescan marks %zu, work lists %zu, task queues %zu, eviction marks %zu\n", megabytes(bytesIn(streamer.rescanAt)), megabytes(streamBytes), megabytes(queueBytes), megabytes(bytesIn(world.evictor.isRecent) + bytesIn(world.evictor.stack)));
    const(ChunkMeshes)* meshes = &renderer.meshes;
    size_t drawBytes = bytesIn(meshes.renderBlocks) + bytesIn(meshes.freeRenderBlocks) + bytesIn(meshes.drawableChunks) + bytesIn(meshes.drawableRecords) + bytesIn(meshes.placedVersions) + bytesIn(meshes.unlisted);
    size_t allocatorBytes = bytesIn(meshes.allocator.ranges) + bytesIn(meshes.allocator.spare) + bytesIn(meshes.allocator.starts) + bytesIn(meshes.allocator.ends);
    size_t mappedBytes = cast(size_t)(meshes.staging.size + meshes.cubeFrames.size + meshes.nodes.size + meshes.drawables.size);
    fprintf(report, "  rendering: chunk records %zu, draw lists %zu, face allocator %zu, mapped buffers %zu; on the device faces %zu, draw buffers %zu\n", megabytes(bytesIn(meshes.chunks)), megabytes(drawBytes), megabytes(allocatorBytes), megabytes(mappedBytes), megabytes(cast(size_t) meshes.faces.size), megabytes(cast(size_t)(meshes.transforms.size + meshes.commands.size)));
}

enum uint SHELL_COUNT = 14;
enum uint OUTSIDE_SHELLS = SHELL_COUNT;

struct Shell {
    size_t nodes;
    size_t holding;
    size_t singleFill;
    size_t dense;
    size_t faces;
    size_t buildings;
    size_t buildingBytes;
    size_t tiles;
    size_t unlistedTiles;
    size_t brushes;
}

uint shellAt(Point!float eye, Point!float center) {
    return lowerOf(cast(uint) floorf(eye.distance(center)), SHELL_COUNT - 1);
}

bool isSingleFill(ref const Graph graph, uint slot) {
    const(Chunk)* first = graph.chunks.at(ChunkSlot(slot, Corner.c0));
    uint corner = 0;
    while (corner < CORNER_COUNT && isFilledLike(graph.chunks.at(ChunkSlot(slot, cast(Corner) corner)), first)) {
        corner += 1;
    }
    return corner == CORNER_COUNT;
}

bool isFilledLike(const(Chunk)* chunk, const(Chunk)* first) {
    bool isSettled = chunk.state == ChunkState.populated && chunk.voxels.isUniform() && !chunk.isEdited && !chunk.isQueued;
    return isSettled && chunk.voxels.bits == first.voxels.bits && chunk.hasDeferredMaterials == first.hasDeferredMaterials;
}

void printShells(FILE* report, ref const LocalWorld world, ref const Renderer renderer) {
    const(Graph)* graph = &world.graph;
    const(NearbyScratch)* nearby = &world.nearby[world.published];
    Point!float eye = world.cameraInNearbyFrame() * Point!float.origin();
    Shell[SHELL_COUNT + 1] shells;
    foreach (ref node; nearby.nodes.slice()) {
        Shell* shell = &shells[shellAt(eye, node.transform * Point!float.origin())];
        shell.nodes += 1;
        if (graph.chunks.has(node.slot)) {
            shell.holding += 1;
            if (isSingleFill(*graph, node.slot)) {
                shell.singleFill += 1;
            }
            foreach (index; 0 .. CORNER_COUNT) {
                Corner corner = cast(Corner) index;
                if (!graph.chunks.at(ChunkSlot(node.slot, corner)).voxels.isUniform()) {
                    shell.dense += 1;
                }
                shell.faces += renderer.meshes.faceCountOf(graph.chunks.blockOf(node.slot), corner);
            }
        }
        const(Building)* building = graph.structures.buildingAt(node.slot);
        if (building !is null) {
            shell.buildings += 1;
            shell.buildingBytes += building.paintBytes();
        }
    }
    shells[OUTSIDE_SHELLS].nodes = graph.liveCount - nearby.nodes.length;
    uint cameraSlot = graph.slotOf(world.cameraPosition.node);
    Point!float cameraEye = world.cameraPosition.local * Point!float.origin();
    foreach (ref tile; graph.structures.blueprint.tiles.slice()) {
        if (!tile.isDropped) {
            uint slot = graph.slotOf(tile.face);
            uint shell = OUTSIDE_SHELLS;
            if (slot != NO_SLOT) {
                shell = shellAt(cameraEye, graph.ownView.nodeToNode(slot, cameraSlot) * Point!float.origin());
                if (nearby.indexOf(slot) == NOT_COLLECTED) {
                    shells[shell].unlistedTiles += 1;
                }
            }
            shells[shell].tiles += 1;
            shells[shell].brushes += tile.painted.brushes.length;
        }
    }
    size_t nodeBytes = Node.sizeof + NodeState.sizeof + NodeStructure.sizeof + NodeHorospheres.sizeof + NodeRises.sizeof + uint.sizeof + 2 * (NearbyNode.sizeof + Collected.sizeof);
    float pixelAngle = 2 * tanf(HALF_VERTICAL_FOV.value) / WINDOW_HEIGHT;
    fprintf(report, "world by distance from the camera (node bytes count slot records and both nearby sets; tiles by their face node, outside the set or gone at the end):\n");
    foreach (index, ref shell; shells) {
        size_t bytes = shell.nodes * nodeBytes + shell.holding * CORNER_COUNT * Chunk.sizeof + shell.dense * cellCount(graph.layout.dimension) + shell.buildingBytes + shell.brushes * Brush.sizeof;
        if (index == OUTSIDE_SHELLS) {
            fprintf(report, "  outside the nearby set, or no longer a node:");
        } else {
            float inner = cast(float) index;
            float chunkPixels = 2 * asinf(lowerOf(1.0f, sinhf(CUBE_RADIUS) / sinhf(higherOf(inner, CUBE_RADIUS)))) / pixelAngle;
            fprintf(report, "  %u-%u: fog leaves %.3f, chunk %.1fpx:", cast(uint) index, cast(uint) index + 1, cast(double) fogVisibility(inner, world.renderRadius), cast(double) chunkPixels);
        }
        fprintf(report, " nodes %zu holding chunks %zu (one uniform fill %zu), dense chunks %zu, faces %zu, buildings %zu (%zuMB), tiles %zu (%zu outside the set), brushes %zu, about %zuMB\n", shell.nodes, shell.holding, shell.singleFill, shell.dense, shell.faces, shell.buildings, megabytes(shell.buildingBytes), shell.tiles, shell.unlistedTiles, shell.brushes, megabytes(bytes));
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
    reportCrashes();
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
