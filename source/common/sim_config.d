module common.sim_config;

import core.time : Duration, dur;
import common.math : MIsometry, MVector, MPoint;
import common.dodeca : vertexChunkToNode, Vertex;

struct SimConfig {
    Duration stepInterval;
    Duration inputQueueSize;
    float viewDistance;
    float chunkGenerationDistance;
    float fogDistance;
    float metersToAbsolute;
    ubyte chunkSize;
    bool gameplayEnabled;
    CharacterConfig character;

    static SimConfig fromRaw(SimConfigRaw raw = SimConfigRaw.init) {
        float m2a = metersToAbsoluteCalc(raw.chunkSize, raw.voxelSize);

        SimConfig cfg;
        cfg.stepInterval = dur!"msecs"(1000 / raw.rate);
        cfg.inputQueueSize = dur!"msecs"(raw.inputQueueSizeMs);
        cfg.viewDistance = raw.viewDistance * m2a;
        cfg.chunkGenerationDistance = raw.chunkGenerationDistance * m2a;
        cfg.fogDistance = raw.fogDistance * m2a;
        cfg.metersToAbsolute = m2a;
        cfg.chunkSize = raw.chunkSize;
        cfg.gameplayEnabled = raw.gameplayEnabled;
        cfg.character = CharacterConfig.fromRaw(raw.character, m2a);
        return cfg;
    }
}

struct SimConfigRaw {
    ushort rate = 30;
    ushort inputQueueSizeMs = 50;
    float viewDistance = 75.0f;
    float chunkGenerationDistance = 60.0f;
    float fogDistance = 90.0f;
    float voxelSize = 1.0f;
    ubyte chunkSize = 12;
    bool gameplayEnabled;
    CharacterConfigRaw character;
}

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
        c.noClipMovementSpeed = x.noClipMovementSpeed * m2a;
        c.maxGroundSpeed = x.maxGroundSpeed * m2a;
        c.speedCap = x.speedCap * m2a;
        c.maxGroundSlope = x.maxGroundSlope;
        c.groundAcceleration = x.groundAcceleration * m2a;
        c.airAcceleration = x.airAcceleration * m2a;
        c.gravityAcceleration = x.gravityAcceleration * m2a;
        c.airResistance = x.airResistance;
        c.jumpSpeed = x.jumpSpeed * m2a;
        c.groundDistanceTolerance = x.groundDistanceTolerance * m2a;
        c.characterRadius = x.characterRadius * m2a;
        c.blockReach = x.blockReach * m2a;
        return c;
    }
}

struct CharacterConfigRaw {
    float noClipMovementSpeed = 12.0f;
    float maxGroundSpeed = 4.0f;
    float speedCap = 30.0f;
    float maxGroundSlope = 1.73f;
    float groundAcceleration = 20.0f;
    float airAcceleration = 2.0f;
    float gravityAcceleration = 20.0f;
    float airResistance = 0.2f;
    float jumpSpeed = 8.0f;
    float groundDistanceTolerance = 0.2f;
    float characterRadius = 0.4f;
    float blockReach = 10.0f;
}

float metersToAbsoluteCalc(ubyte chunkSize, float voxelSize) {
    MIsometry!float m = vertexChunkToNode(Vertex.A);
    MVector!float va = MVector!float(1.0f, 0.5f, 0.5f, 1.0f);
    MVector!float vb = MVector!float(0.0f, 0.5f, 0.5f, 1.0f);

    MVector!float transformedA = m * va;
    MVector!float transformedB = m * vb;

    MPoint!float a = transformedA.normalizedPoint();
    MPoint!float b = transformedB.normalizedPoint();
    float minChunkFaceSeparation = a.distance(b);
    float absoluteVoxelSize = minChunkFaceSeparation / cast(float) chunkSize;
    return absoluteVoxelSize / voxelSize;
}
