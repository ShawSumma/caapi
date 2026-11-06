module client.cocoa;

version (OSX):

import base.maybe : Maybe;
import bindings.platform : CAMetalLayer;

alias id = void*;
alias SEL = void*;
alias KeySym = uint;

enum KeySym XK_space = 0x20;
enum KeySym XK_1 = 0x31;
enum KeySym XK_9 = 0x39;
enum KeySym XK_bracketleft = 0x5b;
enum KeySym XK_bracketright = 0x5d;
enum KeySym XK_a = 0x61;
enum KeySym XK_d = 0x64;
enum KeySym XK_e = 0x65;
enum KeySym XK_f = 0x66;
enum KeySym XK_n = 0x6e;
enum KeySym XK_o = 0x6f;
enum KeySym XK_p = 0x70;
enum KeySym XK_s = 0x73;
enum KeySym XK_v = 0x76;
enum KeySym XK_w = 0x77;
enum KeySym XK_Escape = 0xff1b;
enum KeySym XK_Left = 0xff51;
enum KeySym XK_Up = 0xff52;
enum KeySym XK_Right = 0xff53;
enum KeySym XK_Down = 0xff54;
enum KeySym XK_Shift_L = 0xffe1;
enum uint Button1 = 1;
enum uint Button3 = 3;

enum ulong NS_WINDOW_TITLED = 1 << 0;
enum ulong NS_WINDOW_CLOSABLE = 1 << 1;
enum ulong NS_WINDOW_MINIATURIZABLE = 1 << 2;
enum ulong NS_WINDOW_RESIZABLE = 1 << 3;
enum ulong NS_BACKING_STORE_BUFFERED = 2;
enum long NS_ACTIVATION_POLICY_REGULAR = 0;
enum ulong NS_EVENT_MASK_ANY = ulong.max;
enum ulong NS_EVENT_LEFT_MOUSE_DOWN = 1;
enum ulong NS_EVENT_RIGHT_MOUSE_DOWN = 3;
enum ulong NS_EVENT_MOUSE_MOVED = 5;
enum ulong NS_EVENT_LEFT_MOUSE_DRAGGED = 6;
enum ulong NS_EVENT_RIGHT_MOUSE_DRAGGED = 7;
enum ulong NS_EVENT_KEY_DOWN = 10;
enum ulong NS_EVENT_KEY_UP = 11;
enum ulong NS_EVENT_FLAGS_CHANGED = 12;
enum ulong NS_EVENT_OTHER_MOUSE_DRAGGED = 27;
enum ulong LEFT_SHIFT_DEVICE_MASK = 1 << 1;
enum ushort LEFT_SHIFT_KEYCODE = 0x38;

struct CGPoint {
    double x = 0;
    double y = 0;
}

struct CGSize {
    double width = 0;
    double height = 0;
}

struct CGRect {
    CGPoint origin;
    CGSize size;
}

struct KeyCode {
    ushort code;
    KeySym symbol;
}

immutable KeyCode[27] KEY_CODES = [
    KeyCode(0x0E, XK_e),
    KeyCode(0x03, XK_f),
    KeyCode(0x1F, XK_o),
    KeyCode(0x21, XK_bracketleft),
    KeyCode(0x1E, XK_bracketright),
    KeyCode(0x0D, XK_w),
    KeyCode(0x00, XK_a),
    KeyCode(0x01, XK_s),
    KeyCode(0x02, XK_d),
    KeyCode(0x09, XK_v),
    KeyCode(0x2D, XK_n),
    KeyCode(0x23, XK_p),
    KeyCode(0x12, XK_1),
    KeyCode(0x13, XK_1 + 1),
    KeyCode(0x14, XK_1 + 2),
    KeyCode(0x15, XK_1 + 3),
    KeyCode(0x17, XK_1 + 4),
    KeyCode(0x16, XK_1 + 5),
    KeyCode(0x1A, XK_1 + 6),
    KeyCode(0x1C, XK_1 + 7),
    KeyCode(0x19, XK_9),
    KeyCode(0x31, XK_space),
    KeyCode(0x35, XK_Escape),
    KeyCode(0x7B, XK_Left),
    KeyCode(0x7C, XK_Right),
    KeyCode(0x7E, XK_Up),
    KeyCode(0x7D, XK_Down),
];

extern (C) nothrow @nogc {
    id objc_getClass(const(char)* name);
    SEL sel_registerName(const(char)* name);
    void objc_msgSend();
    void* objc_autoreleasePoolPush();
    void objc_autoreleasePoolPop(void* pool);
    int CGAssociateMouseAndMouseCursorPosition(int isConnected);
    extern __gshared id NSDefaultRunLoopMode;
}

R send(R = id, Args...)(id receiver, const(char)* selector, Args args) {
    alias Method = extern (C) R function(id, SEL, Args) nothrow @nogc;
    return (cast(Method) &objc_msgSend)(receiver, sel_registerName(selector), args);
}

Maybe!KeySym keySymOf(ushort code) {
    uint index = 0;
    while (index < KEY_CODES.length && KEY_CODES[index].code != code) {
        index += 1;
    }
    if (index < KEY_CODES.length) {
        return Maybe!KeySym.of(KEY_CODES[index].symbol);
    } else {
        return Maybe!KeySym.init;
    }
}

enum KeyAction : ubyte {
    released,
    pressed,
    repeated,
}

struct KeyEvent {
    KeySym symbol;
    KeyAction action;
}

struct WindowEvents {
    void delegate(KeyEvent key) onKey;
    void delegate(uint button) onButton;
    void delegate(double dx, double dy) onMotion;
}

struct CocoaWindow {
    id application;
    id window;
    id view;
    id layer;

    bool open(uint width, uint height) {
        void* pool = objc_autoreleasePoolPush();
        application = send(objc_getClass("NSApplication"), "sharedApplication");
        send!void(application, "setActivationPolicy:", NS_ACTIVATION_POLICY_REGULAR);
        send!void(application, "finishLaunching");
        CGRect frame = CGRect(CGPoint(0, 0), CGSize(width, height));
        ulong style = NS_WINDOW_TITLED | NS_WINDOW_CLOSABLE | NS_WINDOW_MINIATURIZABLE | NS_WINDOW_RESIZABLE;
        window = send(send(objc_getClass("NSWindow"), "alloc"), "initWithContentRect:styleMask:backing:defer:", frame, style, NS_BACKING_STORE_BUFFERED, false);
        if (window !is null) {
            send!void(window, "setReleasedWhenClosed:", false);
            send!void(window, "setAcceptsMouseMovedEvents:", true);
            send!void(window, "center");
            view = send(window, "contentView");
            layer = send(send(objc_getClass("CAMetalLayer"), "layer"), "retain");
            send!void(view, "setLayer:", layer);
            send!void(view, "setWantsLayer:", true);
            send!void(window, "makeKeyAndOrderFront:", null);
            send!void(application, "activateIgnoringOtherApps:", true);
        }
        objc_autoreleasePoolPop(pool);
        return window !is null;
    }

    const(CAMetalLayer)* metalLayer() const {
        return cast(const(CAMetalLayer)*) layer;
    }

    bool isOpen() {
        return send!bool(window, "isVisible");
    }

    bool isFocused() {
        return send!bool(window, "isKeyWindow");
    }

    void setTitle(const(char)* title) {
        void* pool = objc_autoreleasePoolPush();
        send!void(window, "setTitle:", send(objc_getClass("NSString"), "stringWithUTF8String:", title));
        objc_autoreleasePoolPop(pool);
    }

    void capturePointer() {
        CGAssociateMouseAndMouseCursorPosition(0);
        send!void(objc_getClass("NSCursor"), "hide");
    }

    void releasePointer() {
        CGAssociateMouseAndMouseCursorPosition(1);
        send!void(objc_getClass("NSCursor"), "unhide");
    }

    void poll(WindowEvents events) {
        void* pool = objc_autoreleasePoolPush();
        id past = send(objc_getClass("NSDate"), "distantPast");
        id event = send(application, "nextEventMatchingMask:untilDate:inMode:dequeue:", NS_EVENT_MASK_ANY, past, NSDefaultRunLoopMode, true);
        while (event !is null) {
            bool handled = handle(event, events);
            if (!handled) {
                send!void(application, "sendEvent:", event);
            }
            event = send(application, "nextEventMatchingMask:untilDate:inMode:dequeue:", NS_EVENT_MASK_ANY, past, NSDefaultRunLoopMode, true);
        }
        send!void(application, "updateWindows");
        objc_autoreleasePoolPop(pool);
    }

    bool handle(id event, WindowEvents events) {
        ulong type = send!ulong(event, "type");
        bool isKey = type == NS_EVENT_KEY_DOWN || type == NS_EVENT_KEY_UP;
        if (isKey) {
            passKey(event, type, events);
        } else {
            observe(event, type, events);
        }
        return isKey;
    }

    void passKey(id event, ulong type, WindowEvents events) {
        Maybe!KeySym symbol = keySymOf(send!ushort(event, "keyCode"));
        if (symbol.exists) {
            KeyAction action = KeyAction.released;
            if (type == NS_EVENT_KEY_DOWN) {
                bool repeat = send!bool(event, "isARepeat");
                if (repeat) {
                    action = KeyAction.repeated;
                } else {
                    action = KeyAction.pressed;
                }
            }
            events.onKey(KeyEvent(symbol.value, action));
        }
    }

    void observe(id event, ulong type, WindowEvents events) {
        if (type == NS_EVENT_FLAGS_CHANGED) {
            ushort code = send!ushort(event, "keyCode");
            if (code == LEFT_SHIFT_KEYCODE) {
                ulong modifiers = send!ulong(event, "modifierFlags");
                KeyAction action = KeyAction.released;
                if ((modifiers & LEFT_SHIFT_DEVICE_MASK) != 0) {
                    action = KeyAction.pressed;
                }
                events.onKey(KeyEvent(XK_Shift_L, action));
            }
        } else if (type == NS_EVENT_LEFT_MOUSE_DOWN) {
            passButton(event, Button1, events);
        } else if (type == NS_EVENT_RIGHT_MOUSE_DOWN) {
            passButton(event, Button3, events);
        } else if (type == NS_EVENT_MOUSE_MOVED || type == NS_EVENT_LEFT_MOUSE_DRAGGED || type == NS_EVENT_RIGHT_MOUSE_DRAGGED || type == NS_EVENT_OTHER_MOUSE_DRAGGED) {
            events.onMotion(send!double(event, "deltaX"), send!double(event, "deltaY"));
        }
    }

    void passButton(id event, uint button, WindowEvents events) {
        bool inContent = isInContent(event);
        if (inContent) {
            events.onButton(button);
        }
    }

    bool isInContent(id event) {
        id owner = send(event, "window");
        id hit = send(view, "hitTest:", send!CGPoint(event, "locationInWindow"));
        return owner is window && hit is view;
    }

    void close() {
        send!void(window, "close");
        send!void(layer, "release");
        send!void(window, "release");
    }
}
