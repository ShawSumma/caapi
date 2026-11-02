module client.drive;

import core.stdc.stdio : FILE, fflush, fprintf;
import base.array : Array;
import base.clock : MILLISECONDS_PER_SECOND;
import base.maybe : Maybe;
import base.names : textFor;
import client.frames : FrameRecord, FrameSummary, MouseMotion, RenderTimes, cameraStep;
import client.images : ImageDifference, PixelOrder, RGBA_BYTES, copyAsRgba, differenceOf;
import client.png : writePng;
import common.graph : Graph;
import common.position : Position;
import plugins.api.flags : Flags;

enum uint LEFT_BUTTON = 1;
enum uint RIGHT_BUTTON = 3;

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

enum Toggle : ubyte {
    off,
    on,
}

enum DriveMark : ubyte {
    watching,
    logging,
    captureAsked,
    summaryAsked,
    settling,
    drawn,
    drawnImaged,
    waitingImage,
    finished,
    failed,
}

enum DriveActionKind : ubyte {
    frames,
    move,
    hold,
    release,
    tap,
    click,
    settle,
    capture,
    watch,
    log,
    summary,
}

struct DriveAction {
    DriveActionKind kind;
    uint frames;
    double dx = 0;
    double dy = 0;
    DriveKey key;
    uint button;
    string text;
    Toggle toggle;
}

struct NamedDrive {
    string name;
    immutable(DriveAction)[] actions;
}

DriveAction framesOf(uint count) {
    return DriveAction(DriveActionKind.frames, count);
}

DriveAction moveBy(double dx, double dy, uint count) {
    return DriveAction(DriveActionKind.move, count, dx, dy);
}

DriveAction holdKey(DriveKey key) {
    return DriveAction(DriveActionKind.hold, 0, 0, 0, key);
}

DriveAction releaseKey(DriveKey key) {
    return DriveAction(DriveActionKind.release, 0, 0, 0, key);
}

DriveAction tapKey(DriveKey key) {
    return DriveAction(DriveActionKind.tap, 0, 0, 0, key);
}

DriveAction clickButton(uint button) {
    return DriveAction(DriveActionKind.click, 0, 0, 0, DriveKey.init, button);
}

DriveAction settleWithin(uint limit) {
    return DriveAction(DriveActionKind.settle, limit);
}

DriveAction captureTo(string path) {
    return DriveAction(DriveActionKind.capture, 0, 0, 0, DriveKey.init, 0, path);
}

DriveAction watching(Toggle toggle) {
    return DriveAction(DriveActionKind.watch, 0, 0, 0, DriveKey.init, 0, null, toggle);
}

DriveAction logging(Toggle toggle) {
    return DriveAction(DriveActionKind.log, 0, 0, 0, DriveKey.init, 0, null, toggle);
}

DriveAction summaryOf(string title) {
    return DriveAction(DriveActionKind.summary, 0, 0, 0, DriveKey.init, 0, title);
}

struct DriveHost {
    const(DriveAction)[] actions;
    size_t nextAction;
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
    Maybe!double lastNow;
    uint pendingFrames;
    uint frame;
    uint summaryFrame;
    Flags!DriveMark marks;

    bool isFailed() const {
        return marks.has(DriveMark.failed);
    }

    void start(const(char)* name, const(DriveAction)[] chosen, FILE* output, float sensitivity) {
        report = output;
        fprintf(report, "drive: %s, the mouse turns %g radians per count\n", name, cast(double) sensitivity);
        actions = chosen;
    }

    void fail(const(char)* message) {
        fprintf(report, "drive error: %s\n", message);
        marks.set(DriveMark.failed);
        marks.set(DriveMark.finished);
    }

    DriveInput next(bool isWorldSettled) {
        events.clear();
        events.appendAll(later.slice());
        later.clear();
        if (marks.has(DriveMark.settling) && isWorldSettled) {
            finishSettling("settled");
        }
        while (pendingFrames == 0 && !marks.has(DriveMark.finished)) {
            if (nextAction == actions.length) {
                marks.set(DriveMark.finished);
            } else {
                apply(actions[nextAction]);
                nextAction += 1;
            }
        }
        DriveInput input;
        if (pendingFrames > 0) {
            pendingFrames -= 1;
            if (motion.isActive()) {
                double[2] share = motion.next();
                input.dx = share[0];
                input.dy = share[1];
            }
            if (pendingFrames == 0 && marks.has(DriveMark.settling)) {
                finishSettling("not settled");
            }
        }
        input.events = events.slice();
        return input;
    }

    void apply(ref const DriveAction action) {
        final switch (action.kind) {
            case DriveActionKind.frames:
                pendingFrames = action.frames;
                break;
            case DriveActionKind.move:
                if (action.frames == 0) {
                    fail("mouse motion needs at least one frame");
                } else {
                    motion = MouseMotion([action.dx, action.dy], [0, 0], action.frames, 0);
                    pendingFrames = action.frames;
                }
                break;
            case DriveActionKind.hold:
                events.append(DriveEvent(DriveEventKind.press, action.key, 0));
                break;
            case DriveActionKind.release:
                events.append(DriveEvent(DriveEventKind.release, action.key, 0));
                break;
            case DriveActionKind.tap:
                events.append(DriveEvent(DriveEventKind.press, action.key, 0));
                later.append(DriveEvent(DriveEventKind.release, action.key, 0));
                break;
            case DriveActionKind.click:
                if (action.button != LEFT_BUTTON && action.button != RIGHT_BUTTON) {
                    fail("the button is 1 (left) or 3 (right)");
                } else {
                    events.append(DriveEvent(DriveEventKind.click, DriveKey.init, action.button));
                }
                break;
            case DriveActionKind.settle:
                if (action.frames == 0) {
                    fail("settling needs at least one frame");
                } else {
                    marks.set(DriveMark.settling);
                    pendingFrames = action.frames;
                }
                break;
            case DriveActionKind.capture:
                capturePath.clear();
                capturePath.appendAll(action.text);
                marks.set(DriveMark.captureAsked);
                break;
            case DriveActionKind.watch:
                marks.put(DriveMark.watching, action.toggle == Toggle.on);
                if (action.toggle == Toggle.off) {
                    previous.clear();
                }
                break;
            case DriveActionKind.log:
                marks.put(DriveMark.logging, action.toggle == Toggle.on);
                break;
            case DriveActionKind.summary:
                askSummary(action.text);
                break;
        }
    }

    void finishSettling(immutable(char)* outcome) {
        pendingFrames = 0;
        marks.clear(DriveMark.settling);
        fprintf(report, "settle: %s at frame %u\n", outcome, frame);
    }

    void record(double now, double dt, double stepMs, DriveInput input, Position camera, ref const Graph graph) {
        if (!marks.has(DriveMark.finished)) {
            FrameRecord made;
            made.frame = frame;
            made.dtMs = dt * MILLISECONDS_PER_SECOND;
            made.stepMs = stepMs;
            made.dx = input.dx;
            made.dy = input.dy;
            if (lastNow.exists) {
                made.intervalMs = Maybe!double.of((now - lastNow.value) * MILLISECONDS_PER_SECOND);
                made.step = graph.cameraStep(lastCamera, camera);
            }
            lastNow = Maybe!double.of(now);
            lastCamera = camera;
            frame += 1;
            drawnPath.clear();
            if (marks.has(DriveMark.captureAsked)) {
                drawnPath.appendAll(capturePath.slice());
                marks.clear(DriveMark.captureAsked);
            }
            drawn = made;
            marks.set(DriveMark.drawn);
            marks.put(DriveMark.drawnImaged, marks.has(DriveMark.watching) || drawnPath.length > 0);
        }
    }

    bool wantsImage() const {
        return marks.has(DriveMark.drawn) && marks.has(DriveMark.drawnImaged);
    }

    bool isDone() const {
        return marks.has(DriveMark.finished) && !marks.has(DriveMark.drawn) && !marks.has(DriveMark.waitingImage);
    }

    void finishFrame(RenderTimes render, const(ubyte)[] image, uint width, uint height, PixelOrder order) {
        if (marks.has(DriveMark.waitingImage)) {
            takeImage(image, width, height, order);
            print(waiting);
            marks.clear(DriveMark.waitingImage);
        }
        if (marks.has(DriveMark.drawn)) {
            drawn.render = render;
            if (marks.has(DriveMark.drawnImaged)) {
                waiting = drawn;
                Array!char swapped = waitingPath;
                waitingPath = drawnPath;
                drawnPath = swapped;
                marks.set(DriveMark.waitingImage);
            } else {
                print(drawn);
            }
            marks.clear(DriveMark.drawn);
        }
    }

    void takeImage(const(ubyte)[] image, uint width, uint height, PixelOrder order) {
        if (image is null) {
            if (waitingPath.length > 0) {
                fprintf(report, "frame %u: not captured, the frame was not drawn or cannot be read back\n", waiting.frame);
            }
        } else {
            size_t pixels = cast(size_t) width * height;
            current.resize(pixels * RGBA_BYTES);
            copyAsRgba(current.slice(), image, order);
            if (marks.has(DriveMark.watching) && previous.length == current.length) {
                waiting.image = Maybe!ImageDifference.of(differenceOf(previous.slice(), current.slice(), RGBA_BYTES, pixels));
            }
            if (waitingPath.length > 0) {
                waitingPath.append('\0');
                fprintf(report, "frame %u: %s %s\n", waiting.frame, textFor(writePng(waitingPath.ptr, width, height, current.slice()), "captured", "could not write"), waitingPath.ptr);
            }
            Array!ubyte swapped = previous;
            previous = current;
            current = swapped;
        }
    }

    void print(ref const FrameRecord made) {
        if (marks.has(DriveMark.summaryAsked) && made.frame >= summaryFrame) {
            printSummary();
        }
        if (marks.has(DriveMark.logging)) {
            made.print(report);
        }
        summary.add(made);
    }

    void askSummary(const(char)[] title) {
        if (marks.has(DriveMark.summaryAsked)) {
            printSummary();
        }
        summaryTitle.clear();
        summaryTitle.appendAll(title);
        summaryFrame = frame;
        marks.set(DriveMark.summaryAsked);
    }

    void printSummary() {
        fprintf(report, "== %.*s\n", cast(int) summaryTitle.length, summaryTitle.ptr);
        summary.print(report);
        summary = FrameSummary.init;
        marks.clear(DriveMark.summaryAsked);
    }

    void finish() {
        if (marks.has(DriveMark.summaryAsked)) {
            printSummary();
        }
        fprintf(report, "== after the last summary\n");
        summary.print(report);
        summaryTitle.release();
        fflush(report);
        events.release();
        later.release();
        capturePath.release();
        drawnPath.release();
        waitingPath.release();
        previous.release();
        current.release();
    }
}
