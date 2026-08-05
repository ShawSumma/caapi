module server.input_queue;

import common.array : Array;
import common.proto : CharacterInput;

struct InputQueue {
    Array!CharacterInput queue;
    size_t front;
    size_t count;
    // Monotonic milliseconds, as produced by common.clock.nowMs.
    double epochMs;
    bool hasEpoch;

    static InputQueue create() {
        InputQueue q;
        q.hasEpoch = false;
        return q;
    }

    void release() {
        queue.release();
        front = 0;
        count = 0;
        hasEpoch = false;
    }

    void push(CharacterInput input, double nowMs) {
        queue.push(input);
        count = count + 1;
        if (!hasEpoch) {
            epochMs = nowMs;
            hasEpoch = true;
        }
    }

    CharacterInput* pop(double nowMs, double delayMs) {
        if (!hasEpoch) {
            return null;
        }
        if (nowMs - epochMs < delayMs) {
            return null;
        }
        if (count == 0) {
            hasEpoch = false;
            return null;
        }
        CharacterInput* result = &queue[front];
        front = front + 1;
        count = count - 1;
        if (front > 64 && count == 0) {
            queue.dropFront(front);
            front = 0;
        }
        return result;
    }
}
