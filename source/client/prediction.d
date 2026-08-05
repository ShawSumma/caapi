module client.prediction;

import common.array : Array;
import common.graph : Graph;
import common.proto : CharacterInput, Position;
import common.sim_config : SimConfig;

struct PredictedMotion {
    Array!CharacterInput log;
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

    void release() {
        log.release();
    }

    ushort push(
        ref const SimConfig cfg,
        ref Graph graph,
        const ref CharacterInput input,
    ) {
        CharacterStep stepped = runCharacterStep(
            cfg,
            graph,
            predictedPosition,
            predictedVelocity,
            predictedOnGround,
            input,
        );
        predictedPosition = stepped.position;
        predictedVelocity = stepped.velocity;
        predictedOnGround = stepped.onGround;
        log.push(input);
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
        ushort firstGen = cast(ushort)(generation - cast(ushort) log.length());
        size_t obsolete = cast(size_t) cast(ushort)(serverGeneration - firstGen);
        if (obsolete > log.length() || obsolete == 0) {
            return;
        }
        log.dropFront(obsolete);
        predictedPosition = position;
        predictedVelocity = velocity;
        predictedOnGround = onGround;

        foreach (i; 0 .. log.length()) {
            CharacterStep stepped = runCharacterStep(
                cfg,
                graph,
                predictedPosition,
                predictedVelocity,
                predictedOnGround,
                log[i],
            );
            predictedPosition = stepped.position;
            predictedVelocity = stepped.velocity;
            predictedOnGround = stepped.onGround;
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

struct CharacterStep {
    Position position;
    float[3] velocity;
    bool onGround;
}

// Only the noClip branch is implemented. Collision-backed prediction still
// goes through common.character_controller; this stub exists so the client
// can replay its input log without pulling that in.
CharacterStep runCharacterStep(
    ref const SimConfig cfg,
    ref Graph graph,
    Position position,
    float[3] velocity,
    bool onGround,
    const ref CharacterInput input,
) {
    CharacterStep result;
    result.position = position;
    result.velocity = velocity;
    result.onGround = onGround;
    if (input.noClip) {
        result.velocity = [
            input.movement[0] * 4.0f,
            input.movement[1] * 4.0f,
            input.movement[2] * 4.0f,
        ];
    }
    return result;
}
