module server.input_queue;

import core.time : Duration, MonoTime;
import common.proto : CharacterInput;

/// A jitter-tolerant queue of inputs received from a client
///
/// Clients send a stream of input roughly at tickrate, but with an undefined time offset causing
/// ticks to line up imperfectly. If they happen to line up very closely, or if tickrate is
/// sufficiently high, then network jitter might cause frequent variation in whether an input is
/// received just before or just after the simulation is stepped. If we applied inputs ASAP, this
/// would make it impossible for the client to accurately predict the effects of its input, leading
/// to severe visual jitter.
///
/// To correct this, we wait a certain amount of time after receiving the first input, and only then
/// begin consuming one input per tick. This ensures that each input can be late by that amount of
/// time without disrupting the client's prediction. If we nonetheless run out of inputs, it's
/// likely that the client fell behind, e.g. due to a temporary hang, clock drift, or a change in
/// the network path, so we wait again to recover the margin for error.
struct InputQueue {
    private CharacterInput[] queue;
    private size_t front;
    private size_t count;
    /// Time at which the first input in the latest uninterrupted sequence was received
    private MonoTime epoch;
    private bool hasEpoch;

    static InputQueue create() {
        InputQueue q;
        q.hasEpoch = false;
        return q;
    }

    /// Enqueue a new input. Called immediately on receipt.
    void push(CharacterInput input, MonoTime now) {
        queue ~= input;
        count++;
        if (!hasEpoch) {
            epoch = now;
            hasEpoch = true;
        }
    }

    /// Obtain the input for the next simulation step.
    ///
    /// Must be called immediately prior to the step. `delay` is the amount of time after the first
    /// input in a given uninterrupted sequence of inputs we must wait before beginning to consume inputs.
    CharacterInput* pop(MonoTime now, Duration delay) {
        if (!hasEpoch) {
            return null;
        }
        if (now - epoch < delay) {
            // The first input hasn't aged long enough; try again later!
            return null;
        }
        if (count == 0) {
            // Queue underrun; the client may have fallen behind, so we need to re-establish our
            // margin for error.
            hasEpoch = false;
            return null;
        }
        // Pop from front
        auto result = &queue[front];
        front++;
        count--;
        // Compact occasionally
        if (front > 64 && count == 0) {
            queue = queue[front .. $];
            front = 0;
        }
        return result;
    }
}
