module main;

import core.stdc.stdio : snprintf;
import core.stdc.stdlib : free, malloc, strtof;
import core.stdc.string : strcmp;
import core.sys.posix.time : CLOCK_MONOTONIC, clock_gettime, timespec;
import bindings.platform : Atom, Button1, Button3, ButtonPress, ClientMessage, ConfigureNotify, CurrentTime, Cursor, Display, False, FocusOut, GrabModeAsync, GrabSuccess, KeyPress, KeyRelease, KeySym, MotionNotify, None, Pixmap, True, UnmapNotify, Window, XBlackPixel, XCloseDisplay, XColor, XCreateBitmapFromData, XCreatePixmapCursor, XCreateSimpleWindow, XDefaultScreen, XDestroyWindow, XEvent, XFlush, XFreeCursor, XFreePixmap, XGrabPointer, XInternAtom, XK_1, XK_9, XK_Down, XK_Escape, XK_Left, XK_Right, XK_Shift_L, XK_Up, XK_a, XK_d, XK_n, XK_s, XK_space, XK_v, XK_w, XLookupKeysym, XMapWindow, XNextEvent, XNextRequest, XOpenDisplay, XPending, XRootWindow, XSelectInput, XSetWMProtocols, XStoreName, XUngrabPointer, XWarpPointer, XkbSetDetectableAutoRepeat;
import client.config : ClientConfig, loadClientConfig;
import client.game : FrameInput, Game, KEY_COUNT, Key, MATERIAL_PALETTE, axisValue, createGame, gameBreakBlock, gamePlaceBlock, modeName, releaseGame, stepGame;
import client.graphics.renderer : Renderer;
import client.script : ScriptRecorder, closeScriptRecorder, openScriptRecorder, recordEvent, recordFrame;
import common.sim_config : SimConfigRaw;

enum uint WINDOW_WIDTH = 1280;
enum uint WINDOW_HEIGHT = 720;
enum float MAX_FRAME_SECONDS = 0.1f;
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
enum long POINTER_MOTION_MASK = 1L << 6;
enum long STRUCTURE_NOTIFY_MASK = 1L << 17;
enum long FOCUS_CHANGE_MASK = 1L << 21;
enum long INPUT_EVENT_MASK = KEY_PRESS_MASK | KEY_RELEASE_MASK | BUTTON_PRESS_MASK | POINTER_MOTION_MASK | STRUCTURE_NOTIFY_MASK | FOCUS_CHANGE_MASK;
enum uint POINTER_GRAB_MASK = cast(uint)(BUTTON_PRESS_MASK | POINTER_MOTION_MASK);

struct Arguments {
    const(char)* configPath = "mined.cfg";
    const(char)* recordPath;
    float sensitivity = 0;
    bool hasSensitivity;
    bool invertY;
    bool flatWorldgen;
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
    Display* display;
    Window window;
    Cursor invisibleCursor;
    Atom deleteAtom;
    ulong warpSerial;
    ClientConfig config;
    float mouseDx = 0;
    float mouseDy = 0;
    float fps = 0;
    int width = WINDOW_WIDTH;
    int height = WINDOW_HEIGHT;
    int pointerX;
    int pointerY;
    int warpX;
    int warpY;
    bool[KEYCODE_COUNT] keyDown;
    bool[KEY_COUNT] held;
    bool mouseCaptured;
    bool warpPending;
    bool running = true;
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
        }
        index += 1;
    }
    return arguments;
}

bool openWindow(Session* session) {
    session.display = XOpenDisplay(null);
    bool ok = session.display !is null;
    if (ok) {
        int screen = XDefaultScreen(session.display);
        session.window = XCreateSimpleWindow(session.display, XRootWindow(session.display, screen), 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, 0, XBlackPixel(session.display, screen), XBlackPixel(session.display, screen));
        XSelectInput(session.display, session.window, INPUT_EVENT_MASK);
        session.deleteAtom = XInternAtom(session.display, "WM_DELETE_WINDOW", False);
        XSetWMProtocols(session.display, session.window, &session.deleteAtom, 1);
        XkbSetDetectableAutoRepeat(session.display, True, null);
        char[CURSOR_BITMAP_SIZE] blank = 0;
        Pixmap bitmap = XCreateBitmapFromData(session.display, session.window, blank.ptr, CURSOR_BITMAP_SIZE, CURSOR_BITMAP_SIZE);
        XColor black;
        session.invisibleCursor = XCreatePixmapCursor(session.display, bitmap, bitmap, &black, &black, 0, 0);
        XFreePixmap(session.display, bitmap);
        XMapWindow(session.display, session.window);
        XFlush(session.display);
    }
    return ok;
}

void closeWindow(Session* session) {
    XFreeCursor(session.display, session.invisibleCursor);
    XDestroyWindow(session.display, session.window);
    XCloseDisplay(session.display);
}

void warpToCenter(Session* session) {
    session.warpX = session.width / 2;
    session.warpY = session.height / 2;
    session.warpSerial = cast(ulong) XNextRequest(session.display);
    session.warpPending = true;
    XWarpPointer(session.display, None, session.window, 0, 0, 0, 0, session.warpX, session.warpY);
}

void captureMouse(Session* session, int x, int y) {
    int grab = XGrabPointer(session.display, session.window, True, POINTER_GRAB_MASK, GrabModeAsync, GrabModeAsync, session.window, session.invisibleCursor, CurrentTime);
    if (grab == GrabSuccess) {
        session.mouseCaptured = true;
        session.pointerX = x;
        session.pointerY = y;
        warpToCenter(session);
        session.titleDirty = true;
    }
}

void releaseMouse(Session* session) {
    if (session.mouseCaptured) {
        XUngrabPointer(session.display, CurrentTime);
        session.mouseCaptured = false;
        session.warpPending = false;
        session.titleDirty = true;
    }
}

void recenterPointer(Session* session) {
    if (session.mouseCaptured && !session.warpPending && (session.pointerX != session.width / 2 || session.pointerY != session.height / 2)) {
        warpToCenter(session);
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
        session.game.flyMode = !session.game.flyMode;
        recordModeChange(session);
    } else if (symbol == XK_n && !repeat) {
        session.game.noClip = !session.game.noClip;
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

void handleMotion(Session* session, int x, int y, ulong serial) {
    if (session.mouseCaptured) {
        if (session.warpPending && serial >= session.warpSerial) {
            session.pointerX = session.warpX;
            session.pointerY = session.warpY;
            session.warpPending = false;
        }
        session.mouseDx += x - session.pointerX;
        session.mouseDy += y - session.pointerY;
        session.pointerX = x;
        session.pointerY = y;
    }
}

void handleButton(Session* session, uint button, int x, int y) {
    if (!session.mouseCaptured) {
        captureMouse(session, x, y);
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
    } else if (event.type == MotionNotify) {
        handleMotion(session, event.xmotion.x, event.xmotion.y, cast(ulong) event.xmotion.serial);
    } else if (event.type == ButtonPress) {
        handleButton(session, event.xbutton.button, event.xbutton.x, event.xbutton.y);
    } else if (event.type == FocusOut) {
        releaseMouse(session);
        session.keyDown[] = false;
        session.held[] = false;
    } else if (event.type == UnmapNotify) {
        releaseMouse(session);
    } else if (event.type == ConfigureNotify) {
        session.width = event.xconfigure.width;
        session.height = event.xconfigure.height;
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
    frame.yaw = yawRate * dt + session.mouseDx * session.config.mouseRadiansPerPixel;
    frame.pitch = pitchRate * dt + session.mouseDy * session.config.mouseRadiansPerPixel * invert;
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
        if (dt > MAX_FRAME_SECONDS) {
            dt = MAX_FRAME_SECONDS;
        }
        session.mouseDx = 0;
        session.mouseDy = 0;
        while (XPending(session.display) > 0) {
            XEvent event;
            XNextEvent(session.display, &event);
            processEvent(session, &event);
        }
        recenterPointer(session);
        if (session.running) {
            FrameInput frame = buildFrameInput(session, dt);
            recordFrame(&session.recorder, frame, dt);
            stepGame(&session.game, frame, dt);
            session.renderer.render(&session.game.world, dt);
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

extern (C) int main(int argc, char** argv) {
    Arguments arguments = parseArguments(argc, argv);
    Session* session = cast(Session*) malloc(Session.sizeof);
    *session = Session.init;
    session.config = loadClientConfig(arguments.configPath);
    if (arguments.hasSensitivity) {
        session.config.mouseRadiansPerPixel = arguments.sensitivity;
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
            status = EXIT_OK;
        }
        session.renderer.cleanup();
        closeWindow(session);
    }
    closeScriptRecorder(&session.recorder);
    free(session);
    return status;
}
