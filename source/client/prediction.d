module client.prediction;

import common.graph : Graph;
import common.proto : CharacterInput, Position;
import common.sim_config : SimConfig;

struct PredictedMotion {
    CharacterInput[] log;
    ushort generation;
    Position predictedPosition;
    float[3] predictedVelocity = [0, 0, 0];
    bool predictedOnGround;

    static PredictedMotion create(Position initialPosition) {
        PredictedMotion p;
        p.predictedPosition = initialPosition;
        p.predictedVelocity = [0, 0, 0];
        p.predictedOnGround = false;
        return p;
    }

    ushort push(ref const SimConfig cfg, ref Graph graph, const ref CharacterInput input) {
        runCharacterStep(cfg, graph, predictedPosition, predictedVelocity, predictedOnGround, input);
        log ~= input;
        generation = cast(ushort)(generation + 1);
        return generation;
    }

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
            return;
        }
        log = log[obsolete .. $];
        predictedPosition = position;
        predictedVelocity = velocity;
        predictedOnGround = onGround;

        foreach (ref input; log) {
            runCharacterStep(cfg, graph, predictedPosition, predictedVelocity, predictedOnGround, input);
        }
    }

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

void runCharacterStep(
    ref const SimConfig cfg,
    ref Graph graph,
    ref Position position,
    ref float[3] velocity,
    ref bool onGround,
    const ref CharacterInput input,
) {
    float dt = cfg.stepInterval.total!"msecs" / 1000.0f;
    if (input.noClip) {
        velocity = [
            input.movement[0] * 4.0f,
            input.movement[1] * 4.0f,
            input.movement[2] * 4.0f,
        ];
    }
}
