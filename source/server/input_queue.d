module server.input_queue;

import core.time : Duration, MonoTime;
import common.proto : CharacterInput;

struct InputQueue {
    CharacterInput[] queue;
    size_t front;
    size_t count;
    MonoTime epoch;
    bool hasEpoch;

    static InputQueue create() {
        InputQueue q;
        q.hasEpoch = false;
        return q;
    }

    void push(CharacterInput input, MonoTime now) {
        queue ~= input;
        count++;
        if (!hasEpoch) {
            epoch = now;
            hasEpoch = true;
        }
    }

    CharacterInput* pop(MonoTime now, Duration delay) {
        if (!hasEpoch) {
            return null;
        }
        if (now - epoch < delay) {
            return null;
        }
        if (count == 0) {
            hasEpoch = false;
            return null;
        }
        CharacterInput* result = &queue[front];
        front++;
        count--;
        if (front > 64 && count == 0) {
            queue = queue[front .. $];
            front = 0;
        }
        return result;
    }
}
