module bindings.cocoa;

struct MinedEvent {
    int type;
    uint keycode;
    float dx;
    float dy;
    int button;
}

enum : int {
    MINED_EVENT_KEY_DOWN = 1,
    MINED_EVENT_KEY_UP = 2,
    MINED_EVENT_MOUSE_MOTION = 3,
    MINED_EVENT_MOUSE_BUTTON_DOWN = 4,
}

enum : int {
    MINED_BUTTON_LEFT = 1,
    MINED_BUTTON_RIGHT = 2,
}

// macOS virtual keycodes
enum : uint {
    KEY_A = 0,
    KEY_S = 1,
    KEY_D = 2,
    KEY_Q = 12,
    KEY_W = 13,
    KEY_E = 14,
    KEY_SPACE = 49,
    KEY_ESCAPE = 53,
    KEY_SHIFT = 56,
    KEY_F12 = 111,
    KEY_LEFT = 123,
    KEY_RIGHT = 124,
    KEY_DOWN = 125,
    KEY_UP = 126,
}

extern(C) nothrow @nogc {
    void* minedCreateWindow(int width, int height, const(char)* title);
    void* minedGetMetalLayer(void* handle);
    long minedWindowNumber(void* handle);
    int minedShouldClose(void* handle);
    void minedSetCapture(void* handle, int on);
    int minedPollEvent(void* handle, MinedEvent* event);
    void minedDestroyWindow(void* handle);
}
