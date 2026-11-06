module main;

import core.bitop : bsf;
import core.stdc.math : asinf, coshf, floorf, sinhf, tanf;
import core.stdc.stdio : FILE, fclose, fflush, fopen, fprintf, fscanf, printf, snprintf, stderr;
import core.stdc.stdlib : free, malloc;
import core.sys.posix.sys.stat : mkdir;
import core.sys.posix.time : nanosleep, timespec;
import bindings.platform : VkExtent2D;
import base.array : Array;
import base.clock : FrameClock, MILLISECONDS_PER_SECOND, NANOSECONDS_PER_SECOND, PhaseTimes, nowSeconds, threadCpuMilliseconds;
import base.crash : reportCrashes, reportHangAfter;
import base.flags : Bits, Readiness;
import base.hashmap : HashMap, HashSlot;
import base.maybe : Maybe, MaybeIndex;
import base.names : ENUM_NAMES, textFor;
import base.numbers : higherOf, lowerOf;
import base.parallel : ConcurrentQueue, QueueCell;
import base.slab : RunPool, SLAB_SIZE, Slab;
import base.units : Angle, Speed, Time;
import client.arguments : ArgumentCursor, ExitStatus, HELP_OPTION, NOT_A_NUMBER, OUTPUT_OPTION, OptionSpec, REPORT_UNOPENED, StartupError, UNKNOWN_OPTION, VERSION_OPTION, VERSION_TEXT, WORLDGEN_OPTION, WorldgenArgument, closeReport, exitStatus, numberIn, openReport, parseOptions, sliceOf, usageOf;
import client.config : ClientConfig, PitchAxis;
import client.drive : DIRECTORY_MODE, DriveEventKind, DriveHost, DriveInput, DriveKey, LEFT_BUTTON, NamedDrive;
import client.frames : RenderTimes;
import client.game : ChunkSupply, Command, CommandBinding, FrameInput, Game, Key, KeyBinding, KeyStroke, MAX_STEP_SECONDS, commandOf, frameInputOf, holdBound, letGoBound;
import client.graphics.core : SurfaceSource;
import client.graphics.renderer : CaptureMark, FrameTimes, Renderer;
import client.graphics.uniforms : HALF_VERTICAL_FOV;
import client.graphics.voxels.meshes : ChunkMeshes;
import client.hud : FrameMeter, Hud, MouseCapture, STATUS_CAPACITY, statusLine;
import client.meshing : Mesher;
import client.png : writePng;
import client.sampler : Sampler;
import client.save : SaveData, Writer, applyEdits, applyState, readFile, readGame, writeFile, writeGame;
import client.script : NamedScript, Script, ScriptRecorder, StepHook, named;
import client.streaming : Pacing, Streamer;
import client.plugins : gatherWorlds, registry;
import client.structures : StructureHost, StructureProblem, TileCounts, WorldStep, growthProblem, placeStructure, restartGame, steppedWorld, tileCounts, worldgenAt;
import client.tasks : TaskQueues;
import client.tiles : PlanOutputs, TileHost, TilePainter, TileWork;
import client.world : LocalWorld, NearbyStage, NearbyStats, RENDER_RADIUS, StepPhases, fogVisibility;
import common.character.controller : MovementMode;
import common.graph : Graph, Node, childParentFaces;
import common.neighbors : chunkNeighborSlot, needsMesh;
import common.node : Chunk, ChunkSlot, ChunkState, cellCount;
import common.settings : CHUNK_DIMENSION;
import common.traversal : Collected, NearbyNode, NearbyScratch;
import common.view : GraphView;
import common.worldgen.blueprint : Blueprint, Brush, LineRun, RunRef;
import common.worldgen.building : Building;
import common.worldgen.generation : NodeState, StructureWorld, Worldgen, WorldgenKind;
import common.worldgen.horospheres : HorosphereStage, Horospheres, NodeHorospheres, NodeRises;
import common.worldgen.store : NodeStructure, StructureStore;
import common.worldgen.structure : nodeToNode;
import geometry.cube : DIRECTIONS;
import geometry.honeycomb : CORNER_COUNT, CUBE_RADIUS, Corner, FACE_COUNT, Face, NODE_RADIUS, cubeCenter, mirror;
import geometry.lorentz : Motion, Point;
import plugins.api.api : Material;
import plugins.api.flags : Flags;
import scripts.drives : DRIVES;
import scripts.films : FILMS, NamedFilm;
import scripts.views : VIEWS;

enum uint WINDOW_WIDTH = 1280;
enum uint WINDOW_HEIGHT = 720;
enum uint SCREENSHOT_WIDTH = 640;
enum uint SCREENSHOT_HEIGHT = 360;
enum uint FILM_WIDTH = 1280;
enum uint FILM_HEIGHT = 720;
enum size_t PATH_CAPACITY = 4096;
enum double BENCH_FRAME_SECONDS = 1.0 / 60.0;
enum uint BENCH_MOVE_FRAMES = 300;
enum uint BENCH_FLIGHT_LEGS = 6;
enum uint BENCH_SETTLE_FRAMES = 3600;
enum uint BENCH_PROGRESS_FRAMES = 600;
immutable float[2] CENSUS_RADII = [2.0f, 4.0f];
enum uint CENSUS_INTERVAL = 10;
enum uint STALE_MESHES_SHOWN = 8;
enum double FRAME_DEADLINE_MS = 1000.0 / 60.0;
enum uint SLOW_FRAMES_SHOWN = 6;
enum uint BENCH_TIME_LIMIT_SECONDS = 300;
enum size_t BYTES_PER_MEGABYTE = 1024 * 1024;
enum string DEFAULT_CONFIG = "mined.cfg";
enum string USAGE = "usage: mined [options] [view or film]\n" ~ usageOf(OPTIONS[]);

enum Option : ubyte {
    worldgen,
    config,
    sensitivity,
    invertY,
    renderRadius,
    record,
    screenshot,
    film,
    drive,
    benchLoad,
    profile,
    flightSpeed,
    output,
    save,
    help,
    showVersion,
}

immutable OptionSpec[Option.max + 1] OPTIONS = [
    Option.worldgen: WORLDGEN_OPTION,
    Option.config: OptionSpec("--config", "<file>", "settings file (default " ~ DEFAULT_CONFIG ~ " in the working directory)"),
    Option.sensitivity: OptionSpec("--sensitivity", "<number>", "mouse turn in radians per count"),
    Option.invertY: OptionSpec("--invert-y", "", "invert vertical mouse look"),
    Option.renderRadius: OptionSpec("--render-radius", "<units>", "how far to draw"),
    Option.record: OptionSpec("--record", "<file>", "record the session as a D script body"),
    Option.screenshot: OptionSpec("--screenshot", "<png>", "run the named view (scripts/views.d) and render it offscreen"),
    Option.film: OptionSpec("--film", "<directory>", "render every step of the named film (scripts/films.d) offscreen to numbered PNGs"),
    Option.drive: OptionSpec("--drive", "<name>", "play a drive (scripts/drives.d) in the window"),
    Option.benchLoad: OptionSpec("--bench-load", "", "load and flight benchmark"),
    Option.profile: OptionSpec("--profile", "", "sample the threads during the benchmark"),
    Option.flightSpeed: OptionSpec("--flight-speed", "<units/s>", "how fast the benchmark flies"),
    Option.output: OUTPUT_OPTION,
    Option.save: OptionSpec("--save", "<file>", "load this save if it exists, and write it on quit"),
    Option.help: HELP_OPTION,
    Option.showVersion: VERSION_OPTION,
];

version (OSX) {
    import client.cocoa : Button1, Button3, CocoaWindow, KeyAction, KeyEvent, KeySym, WindowEvents, XK_1, XK_9, XK_bracketleft, XK_bracketright, XK_Escape, XK_Down, XK_Left, XK_Right, XK_Shift_L, XK_Up, XK_a, XK_d, XK_e, XK_f, XK_n, XK_o, XK_p, XK_s, XK_space, XK_v, XK_w;

    enum string WINDOW_REQUIREMENT = "cannot open a window";
    enum int MACH_TASK_BASIC_INFO = 20;
    enum CommandBinding!KeySym[] PLATFORM_COMMANDS = [];

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
    import bindings.platform : Atom, Button1, Button3, ButtonPress, ClientMessage, CurrentTime, Cursor, Display, False, FocusOut, GenericEvent, GrabModeAsync, GrabSuccess, KeyPress, KeyRelease, KeySym, Pixmap, Success, True, UnmapNotify, Window, XBlackPixel, XCloseDisplay, XColor, XCreateBitmapFromData, XCreatePixmapCursor, XCreateSimpleWindow, XDefaultScreen, XDestroyWindow, XDisplayHeight, XDisplayWidth, XEvent, XFlush, XFreeCursor, XFreeEventData, XFreePixmap, XGenericEventCookie, XGetEventData, XGrabPointer, XIAllMasterDevices, XIDeviceInfo, XIEventMask, XIFreeDeviceInfo, XIModeAbsolute, XIQueryDevice, XIQueryVersion, XIRawEvent, XISelectEvents, XIValuatorClass, XIValuatorClassInfo, XI_DeviceChanged, XI_RawMotion, XInternAtom, XK_1, XK_9, XK_bracketleft, XK_bracketright, XK_Escape, XK_Down, XK_Left, XK_Right, XK_Shift_L, XK_Up, XK_a, XK_d, XK_e, XK_f, XK_n, XK_o, XK_p, XK_s, XK_space, XK_t, XK_v, XK_w, XLookupKeysym, XMapWindow, XNextEvent, XOpenDisplay, XPending, XQueryExtension, XRootWindow, XSelectInput, XSetWMProtocols, XStoreName, XUngrabPointer, XkbSetDetectableAutoRepeat, BUTTON_PRESS_EVENTS, FOCUS_EVENTS, KEY_PRESS_EVENTS, KEY_RELEASE_EVENTS, STRUCTURE_EVENTS, mallinfo2;
    import base.pages : pageSize;

    enum string WINDOW_REQUIREMENT = "cannot open a window: needs an X display with XInput 2.1";
    enum CommandBinding!KeySym[] PLATFORM_COMMANDS = [CommandBinding!KeySym(XK_t, Command.throwBlock)];
    enum string STATM_PATH = "/proc/self/statm";
    enum string DELETE_WINDOW_ATOM = "WM_DELETE_WINDOW";
    enum string XINPUT_EXTENSION = "XInputExtension";
    enum size_t BYTES_PER_KILOBYTE = 1024;
    enum uint KEYCODE_COUNT = 256;
    enum uint CURSOR_BITMAP_SIZE = 8;
    enum long INPUT_EVENT_MASK = KEY_PRESS_EVENTS | KEY_RELEASE_EVENTS | BUTTON_PRESS_EVENTS | STRUCTURE_EVENTS | FOCUS_EVENTS;
    enum uint POINTER_GRAB_MASK = BUTTON_PRESS_EVENTS;
    enum int XI_REQUIRED_MAJOR = 2;
    enum int XI_REQUIRED_MINOR = 1;
    enum size_t XI_MASK_BYTES = (XI_RawMotion >> 3) + 1;
    enum uint POINTER_AXES = 2;
    enum uint BITS_PER_BYTE = 8;

    enum AxisMode : ubyte {
        relative,
        absolute,
    }

    struct PointerAxis {
        double countsPerValue = 1;
        Maybe!double last;
        AxisMode mode;

        double delta(double value) {
            if (mode == AxisMode.absolute) {
                Maybe!double previous = last;
                last = Maybe!double.of(value);
                if (previous.exists) {
                    return (value - previous.value) * countsPerValue;
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
        Maybe!int deviceId;
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
        FILE* statm = fopen(STATM_PATH, "r");
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

    HeapBytes heapBytes() {
        auto info = mallinfo2();
        return HeapBytes(info.uordblks + info.hblkhd, info.fordblks);
    }
}

struct HeapBytes {
    size_t used;
    size_t held;
}

enum RunKind : ubyte {
    play,
    help,
    showVersion,
    benchLoad,
}

enum Profiling : ubyte {
    off,
    on,
}

enum Saved : ubyte {
    absent,
    present,
}

enum SessionMark : ubyte {
    recording,
    driven,
    stopped,
    titleStale,
}

struct Arguments {
    StartupError error;
    const(char)* program;
    const(char)* configPath = DEFAULT_CONFIG;
    const(char)* recordPath;
    const(char)* screenshotPath;
    const(char)* filmPath;
    const(char)* reportPath;
    const(char)* savePath;
    const(char)* viewName;
    const(NamedScript)* view;
    const(NamedFilm)* film;
    const(NamedDrive)* drive;
    Worldgen worldgen;
    Maybe!float sensitivity;
    float renderRadius = RENDER_RADIUS;
    float flightSpeed = 0;
    PitchAxis pitchAxis;
    RunKind kind;
    Profiling profiling;

    static Arguments fromArgv(int argc, char** argv) {
        Arguments arguments = Arguments(StartupError.init, argv[0]);
        arguments.parseOptions!Option(OPTIONS[], argc, argv);
        return arguments;
    }

    void apply(Option option, ref ArgumentCursor cursor) {
        final switch (option) {
            case Option.worldgen:
                parseWorldgen(cursor);
                break;
            case Option.config:
                configPath = cursor.next();
                break;
            case Option.sensitivity:
                parseSensitivity(cursor.next());
                break;
            case Option.invertY:
                pitchAxis = PitchAxis.inverted;
                break;
            case Option.renderRadius:
                parsePositive(renderRadius, option, cursor.next());
                break;
            case Option.record:
                recordPath = cursor.next();
                break;
            case Option.screenshot:
                screenshotPath = cursor.next();
                break;
            case Option.film:
                filmPath = cursor.next();
                break;
            case Option.drive:
                parseDrive(cursor.next());
                break;
            case Option.benchLoad:
                kind = RunKind.benchLoad;
                break;
            case Option.profile:
                profiling = Profiling.on;
                break;
            case Option.flightSpeed:
                parsePositive(flightSpeed, option, cursor.next());
                break;
            case Option.output:
                reportPath = cursor.next();
                break;
            case Option.save:
                savePath = cursor.next();
                break;
            case Option.help:
                kind = RunKind.help;
                cursor.stop();
                break;
            case Option.showVersion:
                kind = RunKind.showVersion;
                cursor.stop();
                break;
        }
    }

    void applyPositional(const(char)* argument) {
        if (argument[0] == '-') {
            error = StartupError(null, UNKNOWN_OPTION, argument);
        } else if (viewName !is null) {
            error = StartupError(null, "only one view is rendered, unexpected", argument);
        } else {
            viewName = argument;
            view = named(VIEWS, sliceOf(argument));
            film = named(FILMS, sliceOf(argument));
            if (view is null && film is null) {
                error = StartupError(null, "unknown view or film", argument);
            }
        }
    }

    void parseWorldgen(ref ArgumentCursor cursor) {
        WorldgenArgument parsed = WorldgenArgument.from(cursor);
        worldgen = parsed.worldgen;
        error = parsed.error;
    }

    void parseDrive(const(char)* text) {
        drive = named(DRIVES, sliceOf(text));
        if (drive is null) {
            error = StartupError(null, "unknown drive", text);
        }
    }

    void parseSensitivity(const(char)* text) {
        sensitivity = numberIn(text);
        if (!sensitivity.exists) {
            error = StartupError(null, NOT_A_NUMBER, text, OPTIONS[Option.sensitivity].name);
        }
    }

    void parsePositive(ref float into, Option option, const(char)* text) {
        Maybe!float number = numberIn(text);
        if (number.exists && number.value > 0) {
            into = number.value;
        } else {
            error = StartupError(null, "needs a positive number, got", text, OPTIONS[option].name);
        }
    }

    StartupError onlyFor(Option option, Option tool) const {
        return StartupError(null, "is only for", OPTIONS[tool].name.ptr, OPTIONS[option].name);
    }

    StartupError mixed(Option other) const {
        return StartupError(null, "does not mix with", OPTIONS[other].name.ptr, OPTIONS[Option.drive].name);
    }

    bool isTool() const {
        return screenshotPath !is null || filmPath !is null || drive !is null || kind == RunKind.benchLoad;
    }

    StartupError usageError() const {
        if (kind == RunKind.help || kind == RunKind.showVersion) {
            return StartupError.init;
        } else if (profiling == Profiling.on && kind != RunKind.benchLoad) {
            return onlyFor(Option.profile, Option.benchLoad);
        } else if (flightSpeed > 0 && kind != RunKind.benchLoad) {
            return onlyFor(Option.flightSpeed, Option.benchLoad);
        } else if (drive !is null && screenshotPath !is null) {
            return mixed(Option.screenshot);
        } else if (drive !is null && kind == RunKind.benchLoad) {
            return mixed(Option.benchLoad);
        } else if (drive !is null && recordPath !is null) {
            return mixed(Option.record);
        } else if (screenshotPath !is null && view is null) {
            return StartupError(null, "needs a view", null, OPTIONS[Option.screenshot].name);
        } else if (filmPath !is null && film is null) {
            return StartupError(null, "needs a film", null, OPTIONS[Option.film].name);
        } else if (screenshotPath is null && filmPath is null && viewName !is null) {
            return StartupError(null, "nothing was asked to render this view or film", viewName);
        } else if (!isTool() && reportPath !is null) {
            return StartupError(null, "is only for a tool, not for playing", null, OPTIONS[Option.output].name);
        } else if (isTool() && savePath !is null) {
            return StartupError(null, "is only for playing, not for a tool", null, OPTIONS[Option.save].name);
        } else {
            return StartupError.init;
        }
    }
}

immutable KeyBinding!KeySym[Key.max + 1] KEY_BINDINGS = [
    KeyBinding!KeySym(XK_w, Key.fwd),
    KeyBinding!KeySym(XK_s, Key.back),
    KeyBinding!KeySym(XK_a, Key.left),
    KeyBinding!KeySym(XK_d, Key.right),
    KeyBinding!KeySym(XK_space, Key.up),
    KeyBinding!KeySym(XK_Shift_L, Key.down),
    KeyBinding!KeySym(XK_Left, Key.yawLeft),
    KeyBinding!KeySym(XK_Right, Key.yawRight),
    KeyBinding!KeySym(XK_Up, Key.pitchUp),
    KeyBinding!KeySym(XK_Down, Key.pitchDown),
];

immutable CommandBinding!KeySym[] COMMAND_BINDINGS = [
    CommandBinding!KeySym(XK_v, Command.walkMode),
    CommandBinding!KeySym(XK_n, Command.noclipMode),
    CommandBinding!KeySym(XK_bracketleft, Command.previousWorld),
    CommandBinding!KeySym(XK_bracketright, Command.nextWorld),
    CommandBinding!KeySym(XK_p, Command.nextPreset),
    CommandBinding!KeySym(XK_o, Command.dose),
    CommandBinding!KeySym(XK_e, Command.use),
    CommandBinding!KeySym(XK_f, Command.eat),
] ~ PLATFORM_COMMANDS;

immutable KeySym[DriveKey.max + 1] DRIVE_KEYSYMS = [
    DriveKey.w: XK_w,
    DriveKey.a: XK_a,
    DriveKey.s: XK_s,
    DriveKey.d: XK_d,
    DriveKey.space: XK_space,
    DriveKey.shift: XK_Shift_L,
    DriveKey.v: XK_v,
    DriveKey.n: XK_n,
    DriveKey.left: XK_Left,
    DriveKey.right: XK_Right,
    DriveKey.up: XK_Up,
    DriveKey.down: XK_Down,
    DriveKey.bracketLeft: XK_bracketleft,
    DriveKey.bracketRight: XK_bracketright,
    DriveKey.escape: XK_Escape,
    DriveKey.digit1: XK_1,
    DriveKey.digit2: XK_1 + 1,
    DriveKey.digit3: XK_1 + 2,
    DriveKey.digit4: XK_1 + 3,
    DriveKey.digit5: XK_1 + 4,
    DriveKey.digit6: XK_1 + 5,
    DriveKey.digit7: XK_1 + 6,
    DriveKey.digit8: XK_1 + 7,
    DriveKey.digit9: XK_9,
];

uint driveButton(uint button) {
    if (button == LEFT_BUTTON) {
        return Button1;
    } else {
        return Button3;
    }
}

struct Session {
    Game game;
    Renderer renderer;
    Hud hud;
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
        Bits keysDown;
    }
    double mouseDx = 0;
    double mouseDy = 0;
    ClientConfig config;
    DriveHost drive;
    FrameMeter meter;
    uint worldIndex;
    Flags!Key held;
    Flags!SessionMark marks;
    MouseCapture mouse;

    bool isCaptured() const {
        return mouse == MouseCapture.captured;
    }

    bool isRecording() const {
        return marks.has(SessionMark.recording);
    }

    bool isDriven() const {
        return marks.has(SessionMark.driven);
    }

    bool isRunning() const {
        return !marks.has(SessionMark.stopped);
    }

    ExitStatus run(Arguments arguments) {
        if (arguments.drive !is null) {
            return runDriven(arguments);
        } else if (arguments.recordPath is null) {
            return runWindow(arguments);
        } else {
            ExitStatus opened = exitStatus(recorder.open(arguments.recordPath));
            if (opened != ExitStatus.ok) {
                StartupError(null, "cannot open the recording file", arguments.recordPath).report(arguments.program);
                return ExitStatus.failed;
            } else {
                marks.set(SessionMark.recording);
                ExitStatus status = runWindow(arguments);
                recorder.close();
                return status;
            }
        }
    }

    ExitStatus runDriven(Arguments arguments) {
        FILE* report = openReport(arguments.reportPath);
        if (report is null) {
            StartupError(null, REPORT_UNOPENED, arguments.reportPath).report(arguments.program);
            return ExitStatus.failed;
        } else {
            marks.set(SessionMark.driven);
            mouse = MouseCapture.captured;
            drive.start(arguments.drive.name.ptr, arguments.drive.actions, report, config.mouseTurnPerCount.value);
            ExitStatus status = runWindow(arguments);
            drive.finish();
            closeReport(report);
            if (drive.isFailed) {
                return ExitStatus.failed;
            } else {
                return status;
            }
        }
    }

    Readiness worldReadiness() const {
        if (game.world.isWorldgenSettled() && renderer.meshBacklog() == 0) {
            return Readiness.ready;
        } else {
            return Readiness.pending;
        }
    }

    DriveInput driveFrame() {
        DriveInput input = drive.next(worldReadiness());
        foreach (event; input.events) {
            final switch (event.kind) {
                case DriveEventKind.press:
                    handleKeyPress(DRIVE_KEYSYMS[event.key], KeyStroke.first);
                    break;
                case DriveEventKind.release:
                    held.letGoBound(KEY_BINDINGS[], DRIVE_KEYSYMS[event.key]);
                    break;
                case DriveEventKind.click:
                    handleButton(driveButton(event.button));
                    break;
            }
        }
        if (isCaptured) {
            mouseDx += input.dx;
            mouseDy += input.dy;
        }
        return input;
    }

    ExitStatus runWindow(Arguments arguments) {
        ExitStatus opened = openWindow();
        if (opened != ExitStatus.ok) {
            StartupError(null, WINDOW_REQUIREMENT, null).report(arguments.program);
            return ExitStatus.failed;
        } else {
            const(char)* problem = renderer.setup(surfaceSource(), CHUNK_DIMENSION);
            ExitStatus status = ExitStatus.failed;
            if (problem !is null) {
                StartupError(null, problem, null).report(arguments.program);
            } else {
                status = runGame(arguments);
                renderer.cleanup();
            }
            closeWindow();
            return status;
        }
    }

    ExitStatus runGame(Arguments arguments) {
        if (isDriven) {
            fprintf(drive.report, "drive: frames %s for the display\n", textFor(renderer.core.isPresentWaitable(), "wait", "cannot wait"));
        }
        game = Game.make(arguments.worldgen, config.reach);
        game.comfort = config.comfort;
        game.world.graph.bindView();
        worldIndex = worldIndexOf(arguments.worldgen);
        game.world.renderRadius = arguments.renderRadius;
        SaveData saved;
        Saved loaded = Saved.absent;
        ExitStatus status = ExitStatus.ok;
        if (arguments.savePath !is null) {
            Maybe!(Array!ubyte) bytes = readFile(arguments.savePath);
            if (bytes.exists) {
                const(char)* problem = readGame(bytes.value.slice(), game, saved);
                bytes.value.release();
                if (problem !is null) {
                    StartupError(null, problem, arguments.savePath).report(arguments.program);
                    status = ExitStatus.failed;
                } else {
                    applyEdits(game, saved);
                    loaded = Saved.present;
                }
            }
        }
        if (status == ExitStatus.ok) {
            status = placedStatus(game, arguments);
        }
        if (status == ExitStatus.ok) {
            if (loaded == Saved.present) {
                applyState(game, saved);
            }
            runLoop();
            status = grownStatus(game, arguments);
            if (arguments.savePath !is null) {
                Writer writer;
                writeGame(game, writer);
                if (!writeFile(arguments.savePath, writer.bytes.slice())) {
                    StartupError(null, "cannot write the save", arguments.savePath).report(arguments.program);
                    status = ExitStatus.failed;
                }
                writer.bytes.release();
            }
        }
        saved.release();
        hud.release();
        game.release();
        return status;
    }

    version (OSX) {
        ExitStatus openWindow() {
            return exitStatus(window.open(WINDOW_WIDTH, WINDOW_HEIGHT));
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
            mouse = MouseCapture.captured;
            marks.set(SessionMark.titleStale);
        }

        void releasePointer() {
            if (isCaptured) {
                window.releasePointer();
                mouse = MouseCapture.released;
                marks.set(SessionMark.titleStale);
            }
            held = Flags!Key.init;
        }

        void handleKey(KeyEvent key) {
            if (!isDriven) {
                final switch (key.action) {
                    case KeyAction.pressed:
                        handleKeyPress(key.symbol, KeyStroke.first);
                        break;
                    case KeyAction.repeated:
                        handleKeyPress(key.symbol, KeyStroke.repeated);
                        break;
                    case KeyAction.released:
                        held.letGoBound(KEY_BINDINGS[], key.symbol);
                        break;
                }
            }
        }

        void handleWindowButton(uint button) {
            if (!isDriven) {
                handleButton(button);
            }
        }

        void handleMotion(double dx, double dy) {
            if (isCaptured && !isDriven) {
                mouseDx += dx;
                mouseDy += dy;
            }
        }

        void pollEvents() {
            window.poll(WindowEvents(&handleKey, &handleWindowButton, &handleMotion));
            bool open = window.isOpen();
            bool focused = window.isFocused();
            if (!open) {
                marks.set(SessionMark.stopped);
            } else if (isCaptured && !isDriven && !focused) {
                releasePointer();
            }
        }

        void storeTitle(const(char)* title) {
            window.setTitle(title);
        }
    } else {
        ExitStatus openWindow() {
            display = XOpenDisplay(null);
            if (display is null) {
                return ExitStatus.failed;
            } else {
                screen = XDefaultScreen(display);
                window = XCreateSimpleWindow(display, XRootWindow(display, screen), 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, 0, XBlackPixel(display, screen), XBlackPixel(display, screen));
                XSelectInput(display, window, INPUT_EVENT_MASK);
                deleteAtom = XInternAtom(display, DELETE_WINDOW_ATOM, False);
                XSetWMProtocols(display, window, &deleteAtom, 1);
                XkbSetDetectableAutoRepeat(display, True, null);
                char[CURSOR_BITMAP_SIZE] blank = 0;
                Pixmap bitmap = XCreateBitmapFromData(display, window, blank.ptr, CURSOR_BITMAP_SIZE, CURSOR_BITMAP_SIZE);
                XColor black;
                invisibleCursor = XCreatePixmapCursor(display, bitmap, bitmap, &black, &black, 0, 0);
                XFreePixmap(display, bitmap);
                keysDown.cover(KEYCODE_COUNT);
                ExitStatus selected = selectRawPointer();
                if (selected != ExitStatus.ok) {
                    closeWindow();
                } else {
                    XMapWindow(display, window);
                    XFlush(display);
                }
                return selected;
            }
        }

        SurfaceSource surfaceSource() {
            return SurfaceSource(display, window);
        }

        ExitStatus selectRawPointer() {
            int firstEvent;
            int firstError;
            int found = XQueryExtension(display, XINPUT_EXTENSION, &pointer.opcode, &firstEvent, &firstError);
            if (found == 0) {
                return ExitStatus.failed;
            } else {
                int major = XI_REQUIRED_MAJOR;
                int minor = XI_REQUIRED_MINOR;
                int versionStatus = XIQueryVersion(display, &major, &minor);
                if (versionStatus != Success || !isXInputVersionSufficient(major, minor)) {
                    return ExitStatus.failed;
                } else {
                    ubyte[XI_MASK_BYTES] mask = 0;
                    setEventBit(mask[], XI_RawMotion);
                    setEventBit(mask[], XI_DeviceChanged);
                    XIEventMask eventMask = XIEventMask(XIAllMasterDevices, cast(int) mask.length, mask.ptr);
                    XISelectEvents(display, XRootWindow(display, screen), &eventMask, 1);
                    return ExitStatus.ok;
                }
            }
        }

        void closeWindow() {
            XFreeCursor(display, invisibleCursor);
            XDestroyWindow(display, window);
            XCloseDisplay(display);
            keysDown.release();
        }

        void capturePointer() {
            int grab = XGrabPointer(display, window, True, POINTER_GRAB_MASK, GrabModeAsync, GrabModeAsync, window, invisibleCursor, CurrentTime);
            if (grab == GrabSuccess) {
                mouse = MouseCapture.captured;
                marks.set(SessionMark.titleStale);
            }
        }

        void releasePointer() {
            if (isCaptured) {
                XUngrabPointer(display, CurrentTime);
                mouse = MouseCapture.released;
                marks.set(SessionMark.titleStale);
            }
            held = Flags!Key.init;
        }

        void loadPointerAxes(int deviceId) {
            pointer.axes = PointerAxis.init;
            pointer.deviceId = Maybe!int.of(deviceId);
            double[POINTER_AXES] screenExtent = [XDisplayWidth(display, screen), XDisplayHeight(display, screen)];
            int count = 0;
            XIDeviceInfo* devices = XIQueryDevice(display, deviceId, &count);
            if (devices !is null) {
                foreach (device; devices[0 .. count]) {
                    foreach (info; device.classes[0 .. device.num_classes]) {
                        if (info.type == XIValuatorClass) {
                            XIValuatorClassInfo* valuator = cast(XIValuatorClassInfo*) info;
                            if (valuator.number >= 0 && valuator.number < POINTER_AXES && valuator.mode == XIModeAbsolute && valuator.max > valuator.min) {
                                pointer.axes[valuator.number].mode = AxisMode.absolute;
                                pointer.axes[valuator.number].countsPerValue = screenExtent[valuator.number] / (valuator.max - valuator.min);
                            }
                        }
                    }
                }
                XIFreeDeviceInfo(devices);
            }
        }

        void handleRawMotion(const(XIRawEvent)* raw) {
            if (pointer.deviceId != Maybe!int.of(raw.deviceid)) {
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
                int loaded = XGetEventData(display, cookie);
                if (loaded != 0) {
                    if (cookie.evtype == XI_RawMotion) {
                        handleRawMotion(cast(const(XIRawEvent)*) cookie.data);
                    } else if (cookie.evtype == XI_DeviceChanged) {
                        pointer.deviceId = Maybe!int.init;
                    }
                    XFreeEventData(display, cookie);
                }
            }
        }

        void processEvent(XEvent* event) {
            if (event.type == KeyPress) {
                uint keycode = event.xkey.keycode % KEYCODE_COUNT;
                if (keysDown.has(keycode)) {
                    handleKeyPress(XLookupKeysym(&event.xkey, 0), KeyStroke.repeated);
                } else {
                    handleKeyPress(XLookupKeysym(&event.xkey, 0), KeyStroke.first);
                }
                keysDown.set(keycode);
            } else if (event.type == KeyRelease) {
                keysDown.clear(event.xkey.keycode % KEYCODE_COUNT);
                held.letGoBound(KEY_BINDINGS[], XLookupKeysym(&event.xkey, 0));
            } else if (event.type == GenericEvent) {
                handleGenericEvent(&event.xcookie);
            } else if (event.type == ButtonPress) {
                handleButton(event.xbutton.button);
            } else if (event.type == FocusOut) {
                releasePointer();
                keysDown.clearAll();
            } else if (event.type == UnmapNotify) {
                releasePointer();
            } else if (event.type == ClientMessage && cast(Atom) event.xclient.data.l[0] == deleteAtom) {
                marks.set(SessionMark.stopped);
            }
        }

        void pollEvents() {
            int pending = XPending(display);
            while (pending > 0) {
                XEvent event;
                XNextEvent(display, &event);
                if (!isDriven || event.type == ClientMessage) {
                    processEvent(&event);
                }
                pending = XPending(display);
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
        marks.set(SessionMark.titleStale);
    }

    void handleKeyPress(KeySym symbol, KeyStroke press) {
        if (symbol == XK_Escape) {
            releasePointer();
        } else if (isCaptured) {
            handleGameKey(symbol, press);
        }
    }

    void handleGameKey(KeySym symbol, KeyStroke press) {
        Maybe!Command command = COMMAND_BINDINGS.commandOf(symbol, press);
        if (command.exists) {
            run(command.value);
        } else if (symbol >= XK_1 && symbol <= XK_9) {
            selectMaterial(cast(uint)(symbol - XK_1));
        } else {
            held.holdBound(KEY_BINDINGS[], symbol);
        }
    }

    void run(Command command) {
        final switch (command) {
            case Command.walkMode:
                game.toggleMode(MovementMode.walk);
                recordModeChange();
                break;
            case Command.noclipMode:
                game.toggleMode(MovementMode.noclip);
                recordModeChange();
                break;
            case Command.previousWorld:
                if (!isRecording) {
                    switchWorld(WorldStep.previous);
                }
                break;
            case Command.nextWorld:
                if (!isRecording) {
                    switchWorld(WorldStep.next);
                }
                break;
            case Command.throwBlock:
                game.throwBlock();
                break;
            case Command.nextPreset:
                game.nextPreset();
                if (isRecording) {
                    recorder.recordPreset(game.preset);
                }
                marks.set(SessionMark.titleStale);
                break;
            case Command.dose:
                game.doseNext();
                recordCall("dose");
                break;
            case Command.use:
                game.use();
                recordCall("use");
                break;
            case Command.eat:
                game.eat();
                recordCall("eat");
                break;
        }
    }

    void selectMaterial(uint index) {
        bool changed = game.inventory.select(index);
        if (changed) {
            if (isRecording) {
                recorder.recordMaterial(index + 1);
            }
            marks.set(SessionMark.titleStale);
        }
    }

    void handleButton(uint button) {
        if (!isCaptured && isDriven) {
            mouse = MouseCapture.captured;
            marks.set(SessionMark.titleStale);
        } else if (!isCaptured) {
            capturePointer();
        } else if (button == Button1) {
            game.breakBlock();
            recordCall("breakBlock");
        } else if (button == Button3) {
            game.placeBlock();
            recordCall("placeBlock");
        }
    }

    void updateWindowTitle() {
        char[STATUS_CAPACITY] title = statusLine(game, mouse, meter);
        storeTitle(title.ptr);
        marks.clear(SessionMark.titleStale);
    }

    void switchWorld(WorldStep direction) {
        worldIndex = steppedWorld(worldIndex, direction);
        StructureProblem problem = restartGame(game, worldgenAt(worldIndex));
        if (problem.isPresent) {
            fprintf(stderr, "%s\n", problem.text.ptr);
            marks.set(SessionMark.stopped);
        }
        marks.set(SessionMark.titleStale);
    }

    void runLoop() {
        marks.set(SessionMark.titleStale);
        double started = nowSeconds();
        FrameClock clock = FrameClock.startingAt(started);
        meter = FrameMeter.startingAt(started);
        while (isRunning) {
            renderer.waitForDisplay();
            double now = nowSeconds();
            Time dt = Time(cast(float) clock.tick(now, MAX_STEP_SECONDS));
            mouseDx = 0;
            mouseDy = 0;
            pollEvents();
            DriveInput driven;
            if (isDriven && isRunning) {
                driven = driveFrame();
            }
            if (isRunning) {
                FrameInput frame = frameInputOf(config, held, mouseDx, mouseDy, dt);
                if (isRecording) {
                    recorder.recordFrame(frame, dt);
                }
                double stepStart = nowSeconds();
                game.step(frame, dt);
                double renderStart = nowSeconds();
                if (isDriven) {
                    drive.record(now, dt.value, (renderStart - stepStart) * MILLISECONDS_PER_SECOND, driven, game.world.cameraPosition, game.world.graph);
                    renderer.captureMarks.put(CaptureMark.wanted, drive.wantsImage());
                }
                hud.buildMarkers(game);
                hud.build(game, renderer.swapchain.extent.width, renderer.swapchain.extent.height);
                renderer.hudVertices = hud.vertices.slice();
                renderer.markers = hud.markers.slice();
                renderer.atlas = &hud.atlas;
                renderer.render(game.world);
                if (isDriven) {
                    FrameTimes times = renderer.frameTimes;
                    RenderTimes rendered = RenderTimes((nowSeconds() - renderStart) * MILLISECONDS_PER_SECOND, times.fenceWaitMs, times.chunkUpdateMs, times.acquireMs, times.presentMs, times.gpu.frameMs);
                    drive.finishFrame(rendered, renderer.capturedImage(), renderer.capturedExtent.width, renderer.capturedExtent.height, renderer.capturedOrder());
                    if (drive.isDone()) {
                        marks.set(SessionMark.stopped);
                    }
                }
                bool refreshed = meter.tick(now, clock);
                if (refreshed) {
                    marks.set(SessionMark.titleStale);
                }
                if (marks.has(SessionMark.titleStale)) {
                    updateWindowTitle();
                }
            }
        }
    }
}

uint worldIndexOf(Worldgen worldgen) {
    const(string)[] names = registry().allNames();
    uint index = 0;
    while (worldgen.kind == WorldgenKind.structure && index < names.length && names[index] != worldgen.structureName()) {
        index += 1;
    }
    if (worldgen.kind == WorldgenKind.structure && index < names.length) {
        return index + 1;
    } else {
        return 0;
    }
}

void pauseUntilFrameEnd(double frameStart) {
    double remaining = BENCH_FRAME_SECONDS - (nowSeconds() - frameStart);
    if (remaining > 0) {
        timespec pause = timespec(0, cast(long)(remaining * NANOSECONDS_PER_SECOND));
        nanosleep(&pause, null);
    }
}

ExitStatus withOffscreen(alias work)(Arguments arguments, uint width, uint height) {
    FILE* report = openReport(arguments.reportPath);
    if (report is null) {
        StartupError(null, REPORT_UNOPENED, arguments.reportPath).report(arguments.program);
        return ExitStatus.failed;
    } else {
        Renderer* renderer = cast(Renderer*) malloc(Renderer.sizeof);
        *renderer = Renderer.init;
        const(char)* problem = renderer.setupOffscreen(VkExtent2D(width, height), CHUNK_DIMENSION);
        ExitStatus status = ExitStatus.failed;
        if (problem !is null) {
            StartupError(null, problem, null).report(arguments.program);
        } else {
            status = work(report, *renderer);
            renderer.cleanup();
        }
        free(renderer);
        closeReport(report);
        return status;
    }
}

ExitStatus withOnDemandGame(alias work)(Arguments arguments, uint width, uint height) {
    ExitStatus onRenderer(FILE* report, ref Renderer renderer) {
        ClientConfig config;
        Game game = Game.make(arguments.worldgen, config.reach);
        game.world.renderRadius = arguments.renderRadius;
        game.supply = ChunkSupply.onDemand;
        ExitStatus status = placedStatus(game, arguments);
        if (status == ExitStatus.ok) {
            status = work(report, renderer, game);
        }
        game.release();
        return status;
    }
    return withOffscreen!onRenderer(arguments, width, height);
}

ExitStatus renderScreenshot(Arguments arguments) {
    ExitStatus work(FILE* report, ref Renderer renderer, ref Game game) {
        return captureScreenshot(arguments, report, renderer, game);
    }
    return withOnDemandGame!work(arguments, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT);
}

ExitStatus captureScreenshot(Arguments arguments, FILE* report, ref Renderer renderer, ref Game game) {
    Script script = Script.make(&game, report);
    ExitStatus ran = script.run(arguments.view.run);
    if (ran != ExitStatus.ok) {
        fprintf(report, "screenshot: not taken, the view failed\n");
        return ExitStatus.failed;
    } else {
        return renderSettled(arguments, report, renderer, game);
    }
}

ExitStatus renderSettled(Arguments arguments, FILE* report, ref Renderer renderer, ref Game game) {
    SettledFrame frame = SettledFrame.of(renderer, game, report, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT);
    ExitStatus settled = frame.render();
    ExitStatus written = exitStatus(writePng(arguments.screenshotPath, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT, renderer.capture()));
    fprintf(report, "screenshot: %s after %u frames (%u chunks meshed, %u faces)\n", textFor(written == ExitStatus.ok, "written", "failed"), frame.frames, renderer.meshes.meshedChunks, renderer.meshes.allocator.used());
    frame.release();
    return exitStatus(written == ExitStatus.ok && settled == ExitStatus.ok);
}

struct SettledFrame {
    Hud hud;
    Renderer* renderer;
    Game* game;
    FILE* report;
    uint width;
    uint height;
    uint frames;

    static SettledFrame of(ref Renderer renderer, ref Game game, FILE* report, uint width, uint height) {
        SettledFrame frame;
        frame.renderer = &renderer;
        frame.game = &game;
        frame.report = report;
        frame.width = width;
        frame.height = height;
        return frame;
    }

    ExitStatus render() {
        while (!game.world.isWorldgenSettled()) {
            game.world.update(Pacing.unbudgeted);
            game.world.streamer.settle(game.world.graph);
        }
        StructureProblem grown = growthProblem(game.world.graph);
        if (grown.isPresent) {
            fprintf(report, "%s\n", grown.text.ptr);
        }
        hud.buildMarkers(*game);
        hud.build(*game, width, height);
        renderer.hudVertices = hud.vertices.slice();
        renderer.markers = hud.markers.slice();
        renderer.atlas = &hud.atlas;
        frames = 0;
        do {
            renderer.render(game.world);
            frames += 1;
        } while (renderer.meshBacklog() > 0);
        return exitStatus(!grown.isPresent);
    }

    void release() {
        hud.release();
    }
}

struct FilmRoll {
    SettledFrame frame;
    const(char)* directory;
    uint written;
    uint failures;
}

void filmFrame(ref Script script, void* context) {
    FilmRoll* roll = cast(FilmRoll*) context;
    ExitStatus settled = roll.frame.render();
    if (settled != ExitStatus.ok) {
        roll.failures += 1;
    }
    char[PATH_CAPACITY] path;
    snprintf(path.ptr, path.length, "%s/frame%05u.png", roll.directory, roll.written);
    ExitStatus written = exitStatus(writePng(path.ptr, FILM_WIDTH, FILM_HEIGHT, roll.frame.renderer.capture()));
    if (written != ExitStatus.ok) {
        fprintf(roll.frame.report, "film: could not write %s\n", path.ptr);
        roll.failures += 1;
    }
    roll.written += 1;
}

ExitStatus renderFilm(Arguments arguments) {
    mkdir(arguments.filmPath, DIRECTORY_MODE);
    ExitStatus work(FILE* report, ref Renderer renderer, ref Game game) {
        return filmShots(arguments, report, renderer, game);
    }
    return withOnDemandGame!work(arguments, FILM_WIDTH, FILM_HEIGHT);
}

ExitStatus filmShots(Arguments arguments, FILE* report, ref Renderer renderer, ref Game game) {
    FilmRoll roll = FilmRoll(SettledFrame.of(renderer, game, report, FILM_WIDTH, FILM_HEIGHT), arguments.filmPath);
    foreach (ref shot; arguments.film.shots) {
        size_t before = roll.written;
        Script script = Script.make(&game, report);
        script.camera = StepHook(&filmFrame, &roll);
        ExitStatus ran = script.run(shot.run);
        if (ran != ExitStatus.ok) {
            roll.failures += 1;
        }
        fprintf(report, "%.*s: %zu frames\n", cast(int) shot.name.length, shot.name.ptr, roll.written - before);
        fflush(report);
    }
    fprintf(report, "film: %u frames in %s\n", roll.written, arguments.filmPath);
    roll.frame.release();
    return exitStatus(roll.failures == 0);
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

ExitStatus benchLoad(Arguments arguments) {
    ExitStatus work(FILE* report, ref Renderer renderer) {
        return benchLoadWith(arguments, report, renderer);
    }
    return withOffscreen!work(arguments, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT);
}

ExitStatus benchLoadWith(Arguments arguments, FILE* report, ref Renderer renderer) {
    ClientConfig config;
    Game game = Game.make(arguments.worldgen, config.reach);
    game.world.renderRadius = arguments.renderRadius;
    ExitStatus status = placedStatus(game, arguments);
    Sampler sampler;
    if (status == ExitStatus.ok) {
        if (arguments.profiling == Profiling.on) {
            sampler.start();
        }
        reportHangAfter(BENCH_TIME_LIMIT_SECONDS);
        measureLoad(report, renderer, game);
        if (arguments.profiling == Profiling.on) {
            sampler.report(report, "load");
            sampler.start();
        }
        fflush(report);
        if (arguments.flightSpeed > 0) {
            game.character.noclipSpeed = Speed(arguments.flightSpeed);
        }
        measureFlight(report, renderer, game);
        if (arguments.profiling == Profiling.on) {
            sampler.report(report, "flight");
            sampler.start();
        }
        measureSettle(report, renderer, game);
        if (arguments.profiling == Profiling.on) {
            sampler.report(report, "settle");
        }
    }
    sampler.release();
    if (status == ExitStatus.ok) {
        status = grownStatus(game, arguments);
    }
    game.release();
    return status;
}

ExitStatus placedStatus(ref Game game, Arguments arguments) {
    StructureProblem problem = game.placeStructure();
    if (problem.isPresent) {
        StartupError(null, problem.text.ptr, null).report(arguments.program);
    }
    return exitStatus(!problem.isPresent);
}

ExitStatus grownStatus(ref const Game game, Arguments arguments) {
    StructureProblem problem = growthProblem(game.world.graph);
    if (problem.isPresent) {
        StartupError(null, problem.text.ptr, null).report(arguments.program);
    }
    return exitStatus(!problem.isPresent);
}

uint reachedBy(Maybe!uint seen, uint lastFrame) {
    if (seen.exists) {
        return seen.value;
    } else {
        return lastFrame;
    }
}

void measureLoad(FILE* report, ref Renderer renderer, ref Game game) {
    PhaseTimes step;
    PhaseTimes render;
    PhaseTimes frame;
    RenderBreakdown breakdown;
    uint frames = 0;
    Maybe!uint nearbyFrame;
    Maybe!uint generatedFrame;
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
        if (!nearbyFrame.exists && game.world.nearbyStage != NearbyStage.initial) {
            nearbyFrame = Maybe!uint.of(frames);
        }
        if (!generatedFrame.exists && game.world.isWorldgenSettled()) {
            generatedFrame = Maybe!uint.of(frames);
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
    fprintf(report, "nearby set complete at frame %u, worldgen settled at frame %u, meshing done at frame %u\n", reachedBy(nearbyFrame, frames), reachedBy(generatedFrame, frames), frames);
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
    foreach (direction; DIRECTIONS) {
        Maybe!ChunkSlot neighbor = graph.chunkNeighborSlot(chunk, direction);
        if (neighbor.exists && graph.chunks.at(neighbor.value).state == ChunkState.dropped) {
            return true;
        }
    }
    return false;
}

bool isResident(ChunkState state) {
    return state == ChunkState.populated || state == ChunkState.dropped;
}

void measureFlight(FILE* report, ref Renderer renderer, ref Game game) {
    game.mode = MovementMode.noclip;
    foreach (leg; 0 .. BENCH_FLIGHT_LEGS) {
        fprintf(report, "flight leg %u from depth %u:\n", leg + 1, game.world.graph.depthOf(game.world.graph.slotOf(game.characterState.position.node).value));
        measureLeg(report, renderer, game);
        fflush(report);
    }
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
    fprintf(report, "stopped after the flight for %u frames (at most %u): %s, nearby %zu nodes reaching %.2f\n", frames, BENCH_SETTLE_FRAMES, textFor(game.world.isWorldgenSettled(), "settled", "still loading"), game.world.cachedNodes.length, cast(double)(game.world.loadRadius() - game.world.radiusCut));
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
    Maybe!uint[CENSUS_RADII.length] least;
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
        uint first = graph.slotOf(world.cameraPosition.node).value;
        queue.append(NearbyNode(Motion!float.identity(), first));
        seen.ptr[first] = generation;
        size_t head = 0;
        while (head < queue.length) {
            NearbyNode current = queue.ptr[head];
            head += 1;
            Shortfall waiting = Shortfall.unlisted;
            if (graph.structures.at(current.slot).isBuildingQueued) {
                waiting = Shortfall.building;
            } else if (world.nearby[world.published].indexOf(current.slot).exists) {
                waiting = Shortfall.scanned;
                if (world.streamer.isScanPending(current.slot)) {
                    waiting = Shortfall.unscanned;
                }
            }
            foreach (index; 0 .. CORNER_COUNT) {
                Corner corner = cast(Corner) index;
                ChunkState state = graph.chunks.at(ChunkSlot(current.slot, corner)).state;
                float product = eye.coshDistance(current.transform * corner.cubeCenter);
                foreach (radius, distance; CENSUS_RADII) {
                    if (isResident(state) && !(product > coshf(distance))) {
                        loaded[radius] += 1;
                    }
                }
                if (!isResident(state) && !(product > outer)) {
                    Shortfall reason = waiting;
                    if (state == ChunkState.generating) {
                        reason = Shortfall.generating;
                    }
                    missed[reason] += 1;
                }
            }
            foreach (index; 0 .. FACE_COUNT) {
                Face face = cast(Face) index;
                MaybeIndex!uint neighbor = graph.neighborSlot(current.slot, face);
                Motion!float transform = current.transform * face.mirror;
                if (!neighbor.exists && bsf(childParentFaces(graph.nodeAt(current.slot).parentFaces, face)) == index) {
                    foreach (corner; 0 .. CORNER_COUNT) {
                        if (!(eye.coshDistance(transform * (cast(Corner) corner).cubeCenter) > outer)) {
                            missed[Shortfall.unmade] += 1;
                        }
                    }
                } else if (neighbor.exists && seen.ptr[neighbor.value] != generation && !(eye.coshDistance(transform * Point!float.origin()) > nodeReach)) {
                    seen.ptr[neighbor.value] = generation;
                    queue.append(NearbyNode(transform, neighbor.value));
                }
            }
        }
        foreach (radius; 0 .. CENSUS_RADII.length) {
            total[radius] += loaded[radius];
            if (!least[radius].exists || loaded[radius] < least[radius].value) {
                least[radius] = Maybe!uint.of(loaded[radius]);
            }
        }
        samples += 1;
    }

    void print(FILE* report) const {
        fprintf(report, "  chunks loaded around the camera:");
        foreach (radius, distance; CENSUS_RADII) {
            fprintf(report, " within %.0f avg %.0f least %u", cast(double) distance, cast(double) total[radius] / samples, least[radius].value);
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

struct SlowFrames {
    uint count;
    uint shown;

    void note(FILE* report, uint frame, double stepMs, double renderMs, ref const LocalWorld world, NearbyStats before, FrameTimes times) {
        if (stepMs + renderMs > FRAME_DEADLINE_MS) {
            count += 1;
            if (shown < SLOW_FRAMES_SHOWN) {
                const(StepPhases)* phases = &world.phases;
                double phased = phases.paint.lastMs + phases.nearby.lastMs + phases.streamer.lastMs + phases.evict.lastMs;
                fprintf(report, "  slow frame %u: %.1fms, step %.1f (paint ahead %.1f, nearby %.1f, streamer %.1f, evict %.1f, the rest %.1f), render %.1f (chunk update %.1f)%s%s%s\n", frame, stepMs + renderMs, stepMs, phases.paint.lastMs, phases.nearby.lastMs, phases.streamer.lastMs, phases.evict.lastMs, stepMs - phased, renderMs, times.chunkUpdateMs, textFor(world.nearbyStats.rebases != before.rebases, " rebased", ""), textFor(world.nearbyStats.publishes != before.publishes, " published", ""), textFor(world.nearbyStats.grown != before.grown, " started a rebuild", ""));
                shown += 1;
            }
        }
    }
}

void measureLeg(FILE* report, ref Renderer renderer, ref Game game) {
    PhaseTimes moving;
    PhaseTimes movingStep;
    PhaseTimes movingRender;
    RenderBreakdown breakdown;
    LoadedAround around;
    SlowFrames slow;
    uint backloggedFrames = 0;
    FrameInput forward;
    forward.held.set(Key.fwd);
    game.world.phases = StepPhases.init;
    PhaseTimes stepCpu;
    NearbyStats start = game.world.nearbyStats;
    foreach (frame; 0 .. BENCH_MOVE_FRAMES) {
        double frameStart = nowSeconds();
        double cpuStart = threadCpuMilliseconds();
        NearbyStats before = game.world.nearbyStats;
        game.step(forward, Time(cast(float) BENCH_FRAME_SECONDS));
        stepCpu.add(threadCpuMilliseconds() - cpuStart);
        double stepped = nowSeconds();
        renderer.render(game.world);
        double rendered = nowSeconds();
        moving.add((rendered - frameStart) * MILLISECONDS_PER_SECOND);
        movingStep.add((stepped - frameStart) * MILLISECONDS_PER_SECOND);
        movingRender.add((rendered - stepped) * MILLISECONDS_PER_SECOND);
        slow.note(report, frame, (stepped - frameStart) * MILLISECONDS_PER_SECOND, (rendered - stepped) * MILLISECONDS_PER_SECOND, game.world, before, renderer.frameTimes);
        breakdown.add(renderer.frameTimes);
        if (renderer.meshBacklog() > 0 || !game.world.isWorldgenSettled()) {
            backloggedFrames += 1;
        }
        if (frame % CENSUS_INTERVAL == 0) {
            around.count(game.world);
        }
        pauseUntilFrameEnd(frameStart);
    }
    fprintf(report, "moving noclip: frame avg=%.2fms worst=%.2fms, %u of %u frames with loading pending, %u over %.1fms\n", moving.averageMs(), moving.worstMs, backloggedFrames, BENCH_MOVE_FRAMES, slow.count, FRAME_DEADLINE_MS);
    fprintf(report, "moving step avg=%.2fms worst=%.2fms (main thread cpu avg=%.2fms), render avg=%.2fms worst=%.2fms\n", movingStep.averageMs(), movingStep.worstMs, stepCpu.averageMs(), movingRender.averageMs(), movingRender.worstMs);
    around.print(report);
    around.release();
    printRebuilds(report, start, game.world.nearbyStats);
    breakdown.print(report);
    fprintf(report, "  drawable chunks %u, %zu of them waiting for their node\n", renderer.meshes.drawableCount, renderer.meshes.unlisted.length);
    printMemory(report, game.world);
    printWorldStats(report, game.world);
}

void printRebuilds(FILE* report, NearbyStats start, NearbyStats end) {
    uint rebuilt = end.publishes - end.recoveries - end.abandons - (start.publishes - start.recoveries - start.abandons);
    uint abandoned = end.abandons - start.abandons;
    if (rebuilt == 0) {
        fprintf(report, "  no rebuild published, %u abandoned, %u frames pending and %.0fms of nearby time\n", abandoned, end.pendingFrames - start.pendingFrames, end.slicedMilliseconds - start.slicedMilliseconds);
    } else {
        fprintf(report, "  rebuilds published %u and abandoned %u, each published one %.0f frames pending and %.1fms of nearby time while the camera moved %.2f\n", rebuilt, abandoned, cast(double)(end.pendingFrames - start.pendingFrames) / rebuilt, (end.slicedMilliseconds - start.slicedMilliseconds) / rebuilt, (end.pendingTravel - start.pendingTravel) / rebuilt);
    }
}

void printWorldStats(FILE* report, ref const LocalWorld world) {
    fprintf(report, "evicted %u nodes, dropped %u far chunks and %u tiles, forgot %u tiles\n", world.evictor.evicted, world.evictor.dropped, world.evictor.droppedTiles, world.evictor.forgottenTiles);
    fprintf(report, "step phases avg/worst: paint ahead %.2f/%.2fms ", world.phases.paint.averageMs(), world.phases.paint.worstMs);
    fprintf(report, "nearby %.2f/%.2fms (cpu %.2f) ", world.phases.nearby.averageMs(), world.phases.nearby.worstMs, world.phases.nearbyCpu.averageMs());
    fprintf(report, "streamer %.2f/%.2fms (cpu %.2f) ", world.phases.streamer.averageMs(), world.phases.streamer.worstMs, world.phases.streamerCpu.averageMs());
    fprintf(report, "evict %.2f/%.2fms\n", world.phases.evict.averageMs(), world.phases.evict.worstMs);
    fprintf(report, "parallel jobs %u, main waited %.0fms for other threads to finish them\n", world.streamer.pool.runs, world.streamer.pool.waitedMs);
    TileCounts tiles = tileCounts(world.graph);
    fprintf(report, "tiles painted ahead on all threads %u, painted when needed %u\n", tiles.prepared, tiles.fallback);
    fprintf(report, "nearby %zu nodes, %u published, %u recoveries (%.0fms), %.0fms sliced\n", world.cachedNodes.length, world.nearbyStats.publishes, world.nearbyStats.recoveries, world.nearbyStats.recoveryMilliseconds, world.nearbyStats.slicedMilliseconds);
    fprintf(report, "nearby sets grown from the last %u, keeping %zu nodes as they were and expanding %zu again; %u moved to the camera\n", world.nearbyStats.grown, world.nearby[0].keptNodes + world.nearby[1].keptNodes, world.nearby[0].reexpandedNodes + world.nearby[1].reexpandedNodes, world.nearbyStats.rebases);
    fprintf(report, "nearby rebuilds narrowed after the camera outran them %u, abandoned for a fresh set at the camera %u, now reaching %.2f of %.2f\n", world.nearbyStats.narrowings, world.nearbyStats.abandons, cast(double)(world.loadRadius() - world.radiusCut), cast(double) world.loadRadius());
}

void printMemory(FILE* report, ref const LocalWorld world) {
    const(Graph)* graph = &world.graph;
    size_t buildings = 0;
    size_t buildingBytes = 0;
    size_t holding = 0;
    size_t unknownHorospheres = 0;
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
            if (!graph.horospheres.hasHorospheresAt(slot)) {
                unknownHorospheres += 1;
            }
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
        if (slot < world.evictor.recent.count && world.evictor.recent.has(slot)) {
            recent += 1;
        }
    }
    size_t denseBytes = 0;
    foreach (index; 0 .. cast(size_t) graph.chunks.blockCount * CORNER_COUNT) {
        if (!graph.chunks.records.at(index).voxels.isUniform()) {
            denseBytes += cellCount(graph.layout.dimension) * Material.sizeof;
        }
    }
    size_t liveHorospheres = 0;
    size_t tiledHorospheres = 0;
    foreach (ref horosphere; graph.horospheres.horospheres.slice()) {
        if (horosphere.stage != HorosphereStage.free) {
            liveHorospheres += 1;
        }
        if (horosphere.tiles > 0) {
            tiledHorospheres += 1;
        }
    }
    fprintf(report, "horospheres live=%zu with tiles=%zu\n", liveHorospheres, tiledHorospheres);
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
    fprintf(report, "nodes holding chunks=%zu (horospheres never stored %zu) with state=%zu, structure-touched=%zu referenced=%zu with children=%zu recent=%zu\n", holding, unknownHorospheres, stated, touched, referenced, parents, recent);
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
    fprintf(report, "blueprint: %zu lines (%zu free), %zu brushes (%zuMB, line runs %zuMB), %zu edges, tiles %zu live %zu dropped %zu free, %u painted again\n", blueprint.lines.length, blueprint.freeLines.length, blueprint.brushTotal(), brushBytes / BYTES_PER_MEGABYTE, runBytes / BYTES_PER_MEGABYTE, blueprint.edgeCount(), blueprint.liveTiles.length, blueprint.droppedTiles.length, blueprint.freeTiles.length, blueprint.restoredTiles);
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
    size_t bytes = bytesIn(scratch.nodes) + bytesIn(scratch.collected) + bytesIn(scratch.candidates) + bytesIn(scratch.kinds) + bytesIn(scratch.blocks) + bytesIn(scratch.around) + bytesIn(scratch.chain) + bytesIn(scratch.claimed) + bytesIn(scratch.rederived.words) + bytesIn(scratch.derived) + bytesIn(scratch.outputs);
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
    size_t recordBytes = bytesIn(blueprint.tiles) + bytesIn(blueprint.liveTiles) + bytesIn(blueprint.droppedTiles) + bytesIn(blueprint.freeTiles);
    foreach (ref tile; blueprint.tiles.slice()) {
        brushBytes += bytesIn(tile.painted.brushes) + bytesIn(tile.painted.runs);
        paintedStrokeBytes += bytesIn(tile.painted.strokes) + bytesIn(tile.painted.strokeRuns) + bytesIn(tile.painted.reached);
        recordBytes += bytesIn(tile.edges);
    }
    size_t pendingBytes = bytesIn(structures.pending);
    foreach (ref const id, ref const list; structures.pending) {
        pendingBytes += bytesIn(list);
    }
    fprintf(report, "  structures: touches %zu, pending touches %zu, tiled faces %zu, buildings %zu; strokes in tiles %zu, reach index %zu, in buildings %zu\n", megabytes(bytesIn(structures.touches)), megabytes(pendingBytes), megabytes(bytesIn(structures.tiledFaces)), megabytes(buildingBytes), megabytes(paintedStrokeBytes), megabytes(reachBytes), megabytes(builtStrokeBytes));
    size_t runBytes = bytesIn(blueprint.runsOn);
    foreach (ref listed; blueprint.runsOn.slice()) {
        runBytes += bytesIn(listed);
    }
    fprintf(report, "  blueprint: brushes %zu, runs on lines %zu, lines %zu, tiles %zu, line index %zu, touched edges %zu, claims %zu\n", megabytes(brushBytes), megabytes(runBytes), megabytes(bytesIn(blueprint.lines) + bytesIn(blueprint.lineStates) + bytesIn(blueprint.freeLines)), megabytes(recordBytes), megabytes(bytesIn(blueprint.lineIndex)), megabytes(bytesIn(blueprint.touchedEdges)), megabytes(bytesIn(blueprint.claims)));
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
    fprintf(report, "  streaming: rescan marks %zu, work lists %zu, task queues %zu, eviction marks %zu\n", megabytes(bytesIn(streamer.rescanAt)), megabytes(streamBytes), megabytes(queueBytes), megabytes(bytesIn(world.evictor.recent.words) + bytesIn(world.evictor.stack)));
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
    const(Chunk)* first = graph.chunks.at(ChunkSlot(slot, Corner.first));
    uint corner = 0;
    while (corner < CORNER_COUNT && isFilledLike(graph.chunks.at(ChunkSlot(slot, cast(Corner) corner)), first)) {
        corner += 1;
    }
    return corner == CORNER_COUNT;
}

bool isFilledLike(const(Chunk)* chunk, const(Chunk)* first) {
    return chunk.state == ChunkState.populated && chunk.voxels.isUniform() && !chunk.isEdited && !chunk.isQueued && chunk.voxels.bits == first.voxels.bits && chunk.hasDeferredMaterials == first.hasDeferredMaterials;
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
    uint cameraSlot = graph.slotOf(world.cameraPosition.node).value;
    Point!float cameraEye = world.cameraPosition.local * Point!float.origin();
    foreach (ref tile; graph.structures.blueprint.tiles.slice()) {
        if (!tile.isDropped) {
            MaybeIndex!uint slot = graph.slotOf(tile.face);
            uint shell = OUTSIDE_SHELLS;
            if (slot.exists) {
                shell = shellAt(cameraEye, graph.ownView.nodeToNode(slot.value, cameraSlot) * Point!float.origin());
                if (!nearby.indexOf(slot.value).exists) {
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
            fprintf(report, "  %u-%u: fog leaves %.3f, chunk %.1fpx:", cast(uint) index, cast(uint) index + 1, cast(double) fogVisibility(inner, world.viewRadius()), cast(double) chunkPixels);
        }
        fprintf(report, " nodes %zu holding chunks %zu (one uniform fill %zu), dense chunks %zu, faces %zu, buildings %zu (%zuMB), tiles %zu (%zu outside the set), brushes %zu, about %zuMB\n", shell.nodes, shell.holding, shell.singleFill, shell.dense, shell.faces, shell.buildings, megabytes(shell.buildingBytes), shell.tiles, shell.unlistedTiles, shell.brushes, megabytes(bytes));
    }
}

ExitStatus runWindowed(Arguments arguments) {
    Session* session = cast(Session*) malloc(Session.sizeof);
    *session = Session.init;
    session.config = ClientConfig.fromFile(arguments.configPath);
    if (arguments.sensitivity.exists) {
        session.config.mouseTurnPerCount = Angle(arguments.sensitivity.value);
    }
    if (arguments.pitchAxis == PitchAxis.inverted) {
        session.config.pitchAxis = PitchAxis.inverted;
    }
    ExitStatus status = session.run(arguments);
    free(session);
    return status;
}

extern (C) int main(int argc, char** argv) {
    reportCrashes();
    gatherWorlds();
    Arguments arguments = Arguments.fromArgv(argc, argv);
    if (arguments.error.isPresent()) {
        arguments.error.report(argv[0]);
        return ExitStatus.usage;
    } else if (arguments.kind == RunKind.help) {
        printf("%.*s", cast(int) USAGE.length, USAGE.ptr);
        return ExitStatus.ok;
    } else if (arguments.kind == RunKind.showVersion) {
        printf("%s", VERSION_TEXT.ptr);
        return ExitStatus.ok;
    } else if (arguments.kind == RunKind.benchLoad) {
        return benchLoad(arguments);
    } else if (arguments.screenshotPath !is null) {
        return renderScreenshot(arguments);
    } else if (arguments.filmPath !is null) {
        return renderFilm(arguments);
    } else {
        return runWindowed(arguments);
    }
}
