module common.sim_config;

import core.time : Duration, dur;
import common.math : MVector, MPoint;
import common.dodeca : vertexChunkToNode, Vertex;

/// Complete simulation config parameters
struct SimConfig {
    Duration stepInterval;
    float viewDistance;
    float chunkGenerationDistance;
    float fogDistance;
    Duration inputQueueSize;
    bool gameplayEnabled;
    ubyte chunkSize;
    CharacterConfig character;
    float metersToAbsolute;

    static SimConfig fromRaw(SimConfigRaw raw = SimConfigRaw.init) {
        ubyte chunkSize = raw.chunkSize != 0 ? raw.chunkSize : 12;
        float voxelSize = raw.voxelSize != 0 ? raw.voxelSize : 1.0f;
        float m2a = metersToAbsoluteCalc(chunkSize, voxelSize);
        ushort rate = raw.rate != 0 ? raw.rate : 30;

        SimConfig cfg;
        cfg.stepInterval = dur!"msecs"(1000 / rate);
        cfg.viewDistance = (raw.viewDistance != 0 ? raw.viewDistance : 75.0f) * m2a;
        cfg.chunkGenerationDistance = (raw.chunkGenerationDistance != 0 ? raw.chunkGenerationDistance : 60.0f) * m2a;
        cfg.fogDistance = (raw.fogDistance != 0 ? raw.fogDistance : 90.0f) * m2a;
        cfg.inputQueueSize = dur!"msecs"(raw.inputQueueSizeMs != 0 ? raw.inputQueueSizeMs : 50);
        cfg.gameplayEnabled = raw.gameplayEnabled;
        cfg.chunkSize = chunkSize;
        cfg.character = CharacterConfig.fromRaw(raw.character, m2a);
        cfg.metersToAbsolute = m2a;
        return cfg;
    }
}

/// Manually specified simulation config parameters
struct SimConfigRaw {
    ushort rate;
    float viewDistance;
    float chunkGenerationDistance;
    float fogDistance;
    ushort inputQueueSizeMs;
    bool gameplayEnabled;
    ubyte chunkSize;
    float voxelSize;
    CharacterConfigRaw character;
}

/// Static configuration for character physics
struct CharacterConfig {
    float noClipMovementSpeed;
    float maxGroundSpeed;
    float speedCap;
    float maxGroundSlope;
    float groundAcceleration;
    float airAcceleration;
    float gravityAcceleration;
    float airResistance;
    float jumpSpeed;
    float groundDistanceTolerance;
    float characterRadius;
    float blockReach;

    static CharacterConfig fromRaw(CharacterConfigRaw x, float m2a) {
        CharacterConfig c;
        c.noClipMovementSpeed = (x.noClipMovementSpeed != 0 ? x.noClipMovementSpeed : 12.0f) * m2a;
        c.maxGroundSpeed = (x.maxGroundSpeed != 0 ? x.maxGroundSpeed : 4.0f) * m2a;
        c.speedCap = (x.speedCap != 0 ? x.speedCap : 30.0f) * m2a;
        c.maxGroundSlope = x.maxGroundSlope != 0 ? x.maxGroundSlope : 1.73f;
        c.groundAcceleration = (x.groundAcceleration != 0 ? x.groundAcceleration : 20.0f) * m2a;
        c.airAcceleration = (x.airAcceleration != 0 ? x.airAcceleration : 2.0f) * m2a;
        c.gravityAcceleration = (x.gravityAcceleration != 0 ? x.gravityAcceleration : 20.0f) * m2a;
        c.airResistance = x.airResistance != 0 ? x.airResistance : 0.2f;
        c.jumpSpeed = (x.jumpSpeed != 0 ? x.jumpSpeed : 8.0f) * m2a;
        c.groundDistanceTolerance = (x.groundDistanceTolerance != 0 ? x.groundDistanceTolerance : 0.2f) * m2a;
        c.characterRadius = (x.characterRadius != 0 ? x.characterRadius : 0.4f) * m2a;
        c.blockReach = (x.blockReach != 0 ? x.blockReach : 10.0f) * m2a;
        return c;
    }
}

struct CharacterConfigRaw {
    float noClipMovementSpeed;
    float maxGroundSpeed;
    float speedCap;
    float maxGroundSlope;
    float groundAcceleration;
    float airAcceleration;
    float gravityAcceleration;
    float airResistance;
    float jumpSpeed;
    float groundDistanceTolerance;
    float characterRadius;
    float blockReach;
}

private float metersToAbsoluteCalc(ubyte chunkSize, float voxelSize) {

    auto m = vertexChunkToNode(Vertex.A);
    // Compute distance between two points in the chunk
    auto va = MVector!float(1.0f, 0.5f, 0.5f, 1.0f);
    auto vb = MVector!float(0.0f, 0.5f, 0.5f, 1.0f);

    MVector!float transformedA = m * va;
    MVector!float transformedB = m * vb;

    auto a = transformedA.normalizedPoint();
    auto b = transformedB.normalizedPoint();
    float minChunkFaceSeparation = a.distance(b);
    float absoluteVoxelSize = minChunkFaceSeparation / cast(float) chunkSize;
    return absoluteVoxelSize / voxelSize;
}
