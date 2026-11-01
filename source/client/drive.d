module client.drive;

import core.stdc.stdio : FILE, fflush, fprintf;
import base.array : Array;
import base.clock : MILLISECONDS_PER_SECOND;
import client.frames : FrameRecord, FrameSummary, MouseMotion, RenderTimes, cameraStep;
import client.images : RGBA_BYTES, copyAsRgba, differenceOf;
import client.png : writePng;
import common.graph : Graph;
import common.position : Position;

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
    bool isOn;
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

DriveAction watching(bool isOn) {
    return DriveAction(DriveActionKind.watch, 0, 0, 0, DriveKey.init, 0, null, isOn);
}

DriveAction logging(bool isOn) {
    return DriveAction(DriveActionKind.log, 0, 0, 0, DriveKey.init, 0, null, isOn);
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
    double lastNow = 0;
    uint pendingFrames;
    uint frame;
    uint summaryFrame;
    bool isWatching;
    bool isLogging;
    bool isCaptureAsked;
    bool isSummaryAsked;
    bool isSettling;
    bool hasDrawn;
    bool isDrawnImaged;
    bool isWaitingImage;
    bool hasLast;
    bool isFinished;
    bool isFailed;

    void start(const(char)* name, const(DriveAction)[] chosen, FILE* output, float sensitivity) {
        report = output;
        fprintf(report, "drive: %s, the mouse turns %g radians per count\n", name, cast(double) sensitivity);
        actions = chosen;
    }

    void fail(const(char)* message) {
        fprintf(report, "drive error: %s\n", message);
        isFailed = true;
        isFinished = true;
    }

    DriveInput next(bool isLoaded) {
        events.clear();
        events.appendAll(later.slice());
        later.clear();
        if (isSettling && isLoaded) {
            finishSettling(true);
        }
        while (pendingFrames == 0 && !isFinished) {
            if (nextAction == actions.length) {
                isFinished = true;
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
            if (pendingFrames == 0 && isSettling) {
                finishSettling(false);
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
                    isSettling = true;
                    pendingFrames = action.frames;
                }
                break;
            case DriveActionKind.capture:
                capturePath.clear();
                capturePath.appendAll(action.text);
                isCaptureAsked = true;
                break;
            case DriveActionKind.watch:
                isWatching = action.isOn;
                if (!isWatching) {
                    previous.clear();
                }
                break;
            case DriveActionKind.log:
                isLogging = action.isOn;
                break;
            case DriveActionKind.summary:
                askSummary(action.text);
                break;
        }
    }

    void finishSettling(bool isSettled) {
        pendingFrames = 0;
        isSettling = false;
        fprintf(report, "settle: %s at frame %u\n", settleOutcome(isSettled), frame);
    }

    void record(double now, double dt, double stepMs, DriveInput input, Position camera, ref const Graph graph) {
        if (!isFinished) {
            FrameRecord made;
            made.frame = frame;
            made.dtMs = dt * MILLISECONDS_PER_SECOND;
            made.stepMs = stepMs;
            made.dx = input.dx;
            made.dy = input.dy;
            if (hasLast) {
                made.intervalMs = (now - lastNow) * MILLISECONDS_PER_SECOND;
                made.hasInterval = true;
                made.step = graph.cameraStep(lastCamera, camera);
            }
            lastNow = now;
            lastCamera = camera;
            hasLast = true;
            frame += 1;
            drawnPath.clear();
            if (isCaptureAsked) {
                drawnPath.appendAll(capturePath.slice());
                isCaptureAsked = false;
            }
            drawn = made;
            hasDrawn = true;
            isDrawnImaged = isWatching || drawnPath.length > 0;
        }
    }

    bool wantsImage() const {
        return hasDrawn && isDrawnImaged;
    }

    bool isDone() const {
        return isFinished && !hasDrawn && !isWaitingImage;
    }

    void finishFrame(RenderTimes render, const(ubyte)[] image, uint width, uint height, bool isBgra) {
        if (isWaitingImage) {
            takeImage(image, width, height, isBgra);
            print(waiting);
            isWaitingImage = false;
        }
        if (hasDrawn) {
            drawn.render = render;
            if (isDrawnImaged) {
                waiting = drawn;
                Array!char swapped = waitingPath;
                waitingPath = drawnPath;
                drawnPath = swapped;
                isWaitingImage = true;
            } else {
                print(drawn);
            }
            hasDrawn = false;
        }
    }

    void takeImage(const(ubyte)[] image, uint width, uint height, bool isBgra) {
        if (image is null) {
            if (waitingPath.length > 0) {
                fprintf(report, "frame %u: not captured, the frame was not drawn or cannot be read back\n", waiting.frame);
            }
        } else {
            size_t pixels = cast(size_t) width * height;
            current.resize(pixels * RGBA_BYTES);
            copyAsRgba(current.slice(), image, isBgra);
            if (isWatching && previous.length == current.length) {
                waiting.image = differenceOf(previous.slice(), current.slice(), RGBA_BYTES, pixels);
                waiting.hasImage = true;
            }
            if (waitingPath.length > 0) {
                waitingPath.append('\0');
                bool isWritten = writePng(waitingPath.ptr, width, height, current.slice());
                fprintf(report, "frame %u: %s %s\n", waiting.frame, capturedText(isWritten), waitingPath.ptr);
            }
            Array!ubyte swapped = previous;
            previous = current;
            current = swapped;
        }
    }

    void print(ref const FrameRecord made) {
        if (isSummaryAsked && made.frame >= summaryFrame) {
            printSummary();
        }
        if (isLogging) {
            made.print(report);
        }
        summary.add(made);
    }

    void askSummary(const(char)[] title) {
        if (isSummaryAsked) {
            printSummary();
        }
        summaryTitle.clear();
        summaryTitle.appendAll(title);
        summaryFrame = frame;
        isSummaryAsked = true;
    }

    void printSummary() {
        fprintf(report, "== %.*s\n", cast(int) summaryTitle.length, summaryTitle.ptr);
        summary.print(report);
        summary = FrameSummary.init;
        isSummaryAsked = false;
    }

    void finish() {
        if (isSummaryAsked) {
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

immutable(char)* capturedText(bool isWritten) {
    if (isWritten) {
        return "captured";
    } else {
        return "could not write";
    }
}

immutable(char)* settleOutcome(bool isSettled) {
    if (isSettled) {
        return "settled";
    } else {
        return "not settled";
    }
}
