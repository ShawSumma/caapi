module common.settings;

import common.dodeca : Vertex, chunkToNode;
import common.math : MVector, Matrix4;

struct SimConfig {
    CharacterConfig character;
    float metersToAbsolute;

    static SimConfig fromMeters(SimMeters meters) {
        float scale = metersToAbsoluteFor(meters.chunkSize, meters.voxelSize);
        return SimConfig(CharacterConfig.fromMeters(meters.character, scale), scale);
    }
}

struct SimMeters {
    CharacterMeters character;
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

    static CharacterConfig fromMeters(CharacterMeters meters, float metersToAbsolute) {
        return CharacterConfig(
            meters.noClipMovementSpeed * metersToAbsolute,
            meters.flyMovementSpeed * metersToAbsolute,
            meters.maxGroundSpeed * metersToAbsolute,
            meters.speedCap * metersToAbsolute,
            meters.maxGroundSlope,
            meters.groundAcceleration * metersToAbsolute,
            meters.airAcceleration * metersToAbsolute,
            meters.gravityAcceleration * metersToAbsolute,
            meters.airResistance,
            meters.jumpSpeed * metersToAbsolute,
            meters.stepHeight * metersToAbsolute,
            meters.contactSkin * metersToAbsolute,
            meters.characterRadius * metersToAbsolute,
            meters.characterHeight / 2.0f * metersToAbsolute,
            (meters.eyeHeight - meters.characterHeight / 2.0f) * metersToAbsolute,
        );
    }
}

struct CharacterMeters {
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
    Matrix4!float chunkMatrix = Vertex.a.chunkToNode;
    MVector!float faceA = chunkMatrix * MVector!float([1.0f, 0.5f, 0.5f, 1.0f]);
    MVector!float faceB = chunkMatrix * MVector!float([0.0f, 0.5f, 0.5f, 1.0f]);
    float minChunkFaceSeparation = faceA.normalizedPoint().distance(faceB.normalizedPoint());
    return minChunkFaceSeparation / cast(float) chunkSize / voxelSize;
}
