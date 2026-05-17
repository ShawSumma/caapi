module client.prediction;

import common.graph : Graph;
import common.proto : CharacterInput, Position;
import common.sim_config : SimConfig;

/// Predicts the result of motion inputs in-flight to the server
///
/// When sending input to the server, call `push` to record the input in a local queue of in-flight
/// inputs, and to obtain a generation tag to send alongside the input. The server echos the
/// highest tag it's received alongside every state update, which we then use in `reconcile` to
/// determine which inputs have been integrated into the server's state and no longer need to be
/// predicted.
struct PredictedMotion {
    private CharacterInput[] log;
    private ushort generation;
    private Position predictedPosition;
    private float[3] predictedVelocity = [0, 0, 0];
    private bool predictedOnGround;

    static PredictedMotion create(Position initialPosition) {
        PredictedMotion p;
        p.predictedPosition = initialPosition;
        p.predictedVelocity = [0, 0, 0];
        p.predictedOnGround = false;
        return p;
    }

    /// Update for input about to be sent to the server, returning the generation it should be
    /// tagged with
    ushort push(ref const SimConfig cfg, ref Graph graph, const ref CharacterInput input) {
        // Run character step prediction
        runCharacterStep(cfg, graph, predictedPosition, predictedVelocity, predictedOnGround, input);
        log ~= input;
        generation = cast(ushort)(generation + 1);
        return generation;
    }

    /// Update with the latest state received from the server and the generation it was based on
    void reconcile(
        ref const SimConfig cfg,
        ref Graph graph,
        ushort serverGeneration,
        Position position,
        float[3] velocity,
        bool onGround,
    ) {
        ushort firstGen = cast(ushort)(generation - cast(ushort)log.length);
        size_t obsolete = cast(size_t)cast(ushort)(serverGeneration - firstGen);
        if (obsolete > log.length || obsolete == 0) {
            // We've already processed a state incorporating equal or more recent input
            return;
        }
        log = log[obsolete .. $];
        predictedPosition = position;
        predictedVelocity = velocity;
        predictedOnGround = onGround;

        // Replay remaining inputs
        foreach (ref input; log) {
            runCharacterStep(cfg, graph, predictedPosition, predictedVelocity, predictedOnGround, input);
        }
    }

    /// Latest estimate of the server's state after receiving all `push`ed inputs.
    ref const(Position) getPredictedPosition() const return {
        return predictedPosition;
    }

    ref const(float[3]) getPredictedVelocity() const return {
        return predictedVelocity;
    }

    bool getPredictedOnGround() const {
        return predictedOnGround;
    }
}

/// Placeholder for character_controller.run_character_step from common
/// This should call into common.character_controller once that module is ported.
private void runCharacterStep(
    ref const SimConfig cfg,
    ref Graph graph,
    ref Position position,
    ref float[3] velocity,
    ref bool onGround,
    const ref CharacterInput input,
) {
    // TODO: Call common.character_controller.runCharacterStep when available
    // For now this is a stub that applies simple no-clip movement
    float dt = cfg.stepInterval.total!"msecs" / 1000.0f;
    if (input.noClip) {
        // Simple translation in movement direction
        velocity = [
            input.movement[0] * 4.0f,
            input.movement[1] * 4.0f,
            input.movement[2] * 4.0f,
        ];
    }
}
