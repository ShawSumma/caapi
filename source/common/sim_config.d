module common.sim_config;

import common.dodeca : Vertex, chunkToNode;
import common.math : MVector, Matrix4;

struct SimConfig {
    CharacterConfig character;
    float metersToAbsolute;

    static SimConfig fromRaw(SimConfigRaw raw) {
        float scale = metersToAbsoluteFor(raw.chunkSize, raw.voxelSize);
        return SimConfig(CharacterConfig.fromRaw(raw.character, scale), scale);
    }
}

struct SimConfigRaw {
    CharacterConfigRaw character;
    float voxelSize = 1.0f;
    ubyte chunkSize = 12;
}

struct CharacterConfig {
    float noClipMovementSpeed;
    float flyMovementSpeed;
    float maxGroundSpeed;
    float speedCap;
    float maxGroundSlope;
    float groundAcceleration;
    float airAcceleration;
    float gravityAcceleration;
    float airResistance;
    float jumpSpeed;
    float stepHeight;
    float contactSkin;
    float characterRadius;
    float characterHalfHeight;
    float eyeOffset;

    static CharacterConfig fromRaw(CharacterConfigRaw raw, float metersToAbsolute) {
        CharacterConfig config;
        config.noClipMovementSpeed = raw.noClipMovementSpeed * metersToAbsolute;
        config.flyMovementSpeed = raw.flyMovementSpeed * metersToAbsolute;
        config.maxGroundSpeed = raw.maxGroundSpeed * metersToAbsolute;
        config.speedCap = raw.speedCap * metersToAbsolute;
        config.maxGroundSlope = raw.maxGroundSlope;
        config.groundAcceleration = raw.groundAcceleration * metersToAbsolute;
        config.airAcceleration = raw.airAcceleration * metersToAbsolute;
        config.gravityAcceleration = raw.gravityAcceleration * metersToAbsolute;
        config.airResistance = raw.airResistance;
        config.jumpSpeed = raw.jumpSpeed * metersToAbsolute;
        config.stepHeight = raw.stepHeight * metersToAbsolute;
        config.contactSkin = raw.contactSkin * metersToAbsolute;
        config.characterRadius = raw.characterRadius * metersToAbsolute;
        config.characterHalfHeight = raw.characterHeight / 2.0f * metersToAbsolute;
        config.eyeOffset = (raw.eyeHeight - raw.characterHeight / 2.0f) * metersToAbsolute;
        return config;
    }
}

struct CharacterConfigRaw {
    float noClipMovementSpeed = 12.0f;
    float flyMovementSpeed = 8.0f;
    float maxGroundSpeed = 4.0f;
    float speedCap = 30.0f;
    float maxGroundSlope = 1.73f;
    float groundAcceleration = 50.0f;
    float airAcceleration = 20.0f;
    float gravityAcceleration = 32.0f;
    float airResistance = 0.2f;
    float jumpSpeed = 9.0f;
    float stepHeight = 1.1f;
    float contactSkin = 0.01f;
    float characterRadius = 0.4f;
    float characterHeight = 1.8f;
    float eyeHeight = 1.5f;
}

float metersToAbsoluteFor(ubyte chunkSize, float voxelSize) {
    Matrix4!float chunkMatrix = Vertex.A.chunkToNode;
    MVector!float faceA = chunkMatrix * MVector!float(1.0f, 0.5f, 0.5f, 1.0f);
    MVector!float faceB = chunkMatrix * MVector!float(0.0f, 0.5f, 0.5f, 1.0f);
    float minChunkFaceSeparation = faceA.normalizedPoint().distance(faceB.normalizedPoint());
    return minChunkFaceSeparation / cast(float) chunkSize / voxelSize;
}
