#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>

typedef struct {
    int type; // 1 key down, 2 key up, 3 mouse motion, 4 mouse button down
    unsigned int keycode;
    float dx;
    float dy;
    int button; // 1 left, 2 right
} MinedEvent;

@interface MinedWindowContext : NSObject <NSWindowDelegate>
@property(strong) NSWindow *window;
@property(strong) CAMetalLayer *layer;
@property bool shiftDown;
@property bool captured;
@property bool shouldClose;
@end

@implementation MinedWindowContext
- (BOOL)windowShouldClose:(NSWindow *)sender {
    self.shouldClose = true;
    return NO;
}
@end

void *minedCreateWindow(int width, int height, const char *title) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp finishLaunching];

        NSRect frame = NSMakeRect(0, 0, width, height);
        NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable;
        NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                       styleMask:style
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        [window setTitle:[NSString stringWithUTF8String:title]];
        [window center];

        CAMetalLayer *layer = [CAMetalLayer layer];
        layer.contentsScale = 1.0;
        layer.drawableSize = CGSizeMake(width, height);
        NSView *view = window.contentView;
        view.wantsLayer = YES;
        view.layer = layer;

        MinedWindowContext *ctx = [[MinedWindowContext alloc] init];
        ctx.window = window;
        ctx.layer = layer;
        window.delegate = ctx;
        window.acceptsMouseMovedEvents = YES;

        [window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];

        return (__bridge_retained void *)ctx;
    }
}

void *minedGetMetalLayer(void *handle) {
    MinedWindowContext *ctx = (__bridge MinedWindowContext *)handle;
    return (__bridge void *)ctx.layer;
}

long minedWindowNumber(void *handle) {
    MinedWindowContext *ctx = (__bridge MinedWindowContext *)handle;
    return ctx.window.windowNumber;
}

int minedShouldClose(void *handle) {
    MinedWindowContext *ctx = (__bridge MinedWindowContext *)handle;
    return ctx.shouldClose ? 1 : 0;
}

void minedSetCapture(void *handle, int on) {
    MinedWindowContext *ctx = (__bridge MinedWindowContext *)handle;
    if (on && !ctx.captured) {
        CGAssociateMouseAndMouseCursorPosition(false);
        [NSCursor hide];
        ctx.captured = true;
    } else if (!on && ctx.captured) {
        CGAssociateMouseAndMouseCursorPosition(true);
        [NSCursor unhide];
        ctx.captured = false;
    }
}

int minedPollEvent(void *handle, MinedEvent *out) {
    MinedWindowContext *ctx = (__bridge MinedWindowContext *)handle;
    @autoreleasepool {
        for (;;) {
            NSEvent *ev = [NSApp nextEventMatchingMask:NSEventMaskAny
                                             untilDate:[NSDate distantPast]
                                                inMode:NSDefaultRunLoopMode
                                               dequeue:YES];
            if (ev == nil) {
                return 0;
            }
            switch (ev.type) {
            case NSEventTypeKeyDown:
                if (ev.isARepeat) {
                    continue;
                }
                out->type = 1;
                out->keycode = ev.keyCode;
                return 1;
            case NSEventTypeKeyUp:
                out->type = 2;
                out->keycode = ev.keyCode;
                return 1;
            case NSEventTypeFlagsChanged: {
                bool shift = (ev.modifierFlags & NSEventModifierFlagShift) != 0;
                if (shift != ctx.shiftDown) {
                    ctx.shiftDown = shift;
                    out->type = shift ? 1 : 2;
                    out->keycode = 56;
                    return 1;
                }
                continue;
            }
            case NSEventTypeMouseMoved:
            case NSEventTypeLeftMouseDragged:
            case NSEventTypeRightMouseDragged:
                if (ctx.captured) {
                    out->type = 3;
                    out->dx = (float)ev.deltaX;
                    out->dy = (float)ev.deltaY;
                    return 1;
                }
                [NSApp sendEvent:ev];
                continue;
            case NSEventTypeLeftMouseDown:
            case NSEventTypeRightMouseDown: {
                [NSApp sendEvent:ev];
                NSView *view = ctx.window.contentView;
                NSPoint p = [view convertPoint:ev.locationInWindow fromView:nil];
                if ([view mouse:p inRect:view.bounds]) {
                    out->type = 4;
                    out->button = (ev.type == NSEventTypeLeftMouseDown) ? 1 : 2;
                    return 1;
                }
                continue;
            }
            default:
                [NSApp sendEvent:ev];
                continue;
            }
        }
    }
}

void minedDestroyWindow(void *handle) {
    MinedWindowContext *ctx = (__bridge_transfer MinedWindowContext *)handle;
    [ctx.window close];
    ctx.window = nil;
}
