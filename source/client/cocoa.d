module client.cocoa;

version (OSX):

import base.maybe : Maybe;
import bindings.platform : CAMetalLayer;

alias id = void*;
alias SEL = void*;

enum uint Button1 = 1;
enum uint Button3 = 3;
enum uint Button4 = 4;
enum uint Button5 = 5;

enum ulong NS_WINDOW_TITLED = 1 << 0;
enum ulong NS_WINDOW_CLOSABLE = 1 << 1;
enum ulong NS_WINDOW_MINIATURIZABLE = 1 << 2;
enum ulong NS_WINDOW_RESIZABLE = 1 << 3;
enum ulong NS_BACKING_STORE_BUFFERED = 2;
enum long NS_ACTIVATION_POLICY_REGULAR = 0;
enum ulong NS_EVENT_MASK_ANY = ulong.max;
enum ulong NS_EVENT_LEFT_MOUSE_DOWN = 1;
enum ulong NS_EVENT_LEFT_MOUSE_UP = 2;
enum ulong NS_EVENT_RIGHT_MOUSE_DOWN = 3;
enum ulong NS_EVENT_RIGHT_MOUSE_UP = 4;
enum ulong NS_EVENT_MOUSE_MOVED = 5;
enum ulong NS_EVENT_LEFT_MOUSE_DRAGGED = 6;
enum ulong NS_EVENT_RIGHT_MOUSE_DRAGGED = 7;
enum ulong NS_EVENT_KEY_DOWN = 10;
enum ulong NS_EVENT_KEY_UP = 11;
enum ulong NS_EVENT_FLAGS_CHANGED = 12;
enum ulong NS_EVENT_SCROLL_WHEEL = 22;
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
    string name;
}

immutable KeyCode[32] KEY_CODES = [
    KeyCode(0x0E, "e"),
    KeyCode(0x11, "t"),
    KeyCode(0x30, "Tab"),
    KeyCode(0x03, "f"),
    KeyCode(0x1F, "o"),
    KeyCode(0x21, "bracketleft"),
    KeyCode(0x1E, "bracketright"),
    KeyCode(0x0D, "w"),
    KeyCode(0x00, "a"),
    KeyCode(0x01, "s"),
    KeyCode(0x02, "d"),
    KeyCode(0x09, "v"),
    KeyCode(0x2D, "n"),
    KeyCode(0x23, "p"),
    KeyCode(0x12, "1"),
    KeyCode(0x13, "2"),
    KeyCode(0x14, "3"),
    KeyCode(0x15, "4"),
    KeyCode(0x17, "5"),
    KeyCode(0x16, "6"),
    KeyCode(0x1A, "7"),
    KeyCode(0x1C, "8"),
    KeyCode(0x19, "9"),
    KeyCode(0x1D, "0"),
    KeyCode(0x1B, "minus"),
    KeyCode(0x18, "equal"),
    KeyCode(0x31, "space"),
    KeyCode(0x35, "Escape"),
    KeyCode(0x7B, "Left"),
    KeyCode(0x7C, "Right"),
    KeyCode(0x7E, "Up"),
    KeyCode(0x7D, "Down"),
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

Maybe!string keyNameOf(ushort code) {
    uint index = 0;
    while (index < KEY_CODES.length && KEY_CODES[index].code != code) {
        index += 1;
    }
    if (index < KEY_CODES.length) {
        return Maybe!string.of(KEY_CODES[index].name);
    } else {
        return Maybe!string.init;
    }
}

enum KeyAction : ubyte {
    released,
    pressed,
    repeated,
}

struct KeyEvent {
    string name;
    KeyAction action;
}

struct ButtonEvent {
    double x = 0;
    double y = 0;
    uint button;
    KeyAction action;
}

struct WindowEvents {
    void delegate(KeyEvent key) onKey;
    void delegate(ButtonEvent button) onButton;
    void delegate(double dx, double dy) onMotion;
    void delegate(double x, double y) onPointer;
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
        Maybe!string symbol = keyNameOf(send!ushort(event, "keyCode"));
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
                events.onKey(KeyEvent("Shift_L", action));
            }
        } else if (type == NS_EVENT_LEFT_MOUSE_DOWN) {
            passButton(event, Button1, KeyAction.pressed, events);
        } else if (type == NS_EVENT_LEFT_MOUSE_UP) {
            passButton(event, Button1, KeyAction.released, events);
        } else if (type == NS_EVENT_RIGHT_MOUSE_DOWN) {
            passButton(event, Button3, KeyAction.pressed, events);
        } else if (type == NS_EVENT_RIGHT_MOUSE_UP) {
            passButton(event, Button3, KeyAction.released, events);
        } else if (type == NS_EVENT_SCROLL_WHEEL) {
            passScroll(event, events);
        } else if (type == NS_EVENT_MOUSE_MOVED || type == NS_EVENT_LEFT_MOUSE_DRAGGED || type == NS_EVENT_RIGHT_MOUSE_DRAGGED || type == NS_EVENT_OTHER_MOUSE_DRAGGED) {
            events.onMotion(send!double(event, "deltaX"), send!double(event, "deltaY"));
            CGPoint at = pixelsOf(event);
            events.onPointer(at.x, at.y);
        }
    }

    void passScroll(id event, WindowEvents events) {
        double delta = send!double(event, "deltaY");
        if (delta > 0) {
            passButton(event, Button4, KeyAction.pressed, events);
        } else if (delta < 0) {
            passButton(event, Button5, KeyAction.pressed, events);
        }
    }

    CGPoint pixelsOf(id event) {
        CGPoint inView = send!CGPoint(view, "convertPoint:fromView:", send!CGPoint(event, "locationInWindow"), cast(id) null);
        CGRect bounds = send!CGRect(view, "bounds");
        double density = send!double(window, "backingScaleFactor");
        return CGPoint(inView.x * density, (bounds.size.height - inView.y) * density);
    }

    void passButton(id event, uint button, KeyAction action, WindowEvents events) {
        bool inContent = isInContent(event);
        if (inContent || action == KeyAction.released) {
            CGPoint at = pixelsOf(event);
            events.onButton(ButtonEvent(at.x, at.y, button, action));
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
