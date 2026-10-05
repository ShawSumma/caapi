module common.settings;

import core.stdc.math : cbrtf;
import common.dodeca : NODE_VOLUME, VERTEX_COUNT, Vertex, chunkToNode;
import common.math : MVector, Matrix4;
import common.node : ChunkLayout, GridSpacing;

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
    float sprintSpeed;
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
            meters.sprintSpeed * metersToAbsolute,
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
    float maxGroundSpeed = 4.5f;
    float sprintSpeed = 6.5f;
    float speedCap = 30.0f;
    float maxGroundSlope = 1.73f;
    float groundAcceleration = 50.0f;
    float airAcceleration = 20.0f;
    float gravityAcceleration = 32.0f;
    float airResistance = 0.2f;
    float jumpSpeed = 9.0f;
    float stepHeight = 2.4f;
    float contactSkin = 0.01f;
    float characterRadius = 0.4f;
    float characterHeight = 1.8f;
    float eyeHeight = 1.5f;
}

float metersToAbsoluteFor(ubyte chunkSize, float voxelSize) {
    return cbrtf(NODE_VOLUME / VERTEX_COUNT) / chunkSize / voxelSize;
}

float longestVoxelEdge(ubyte chunkSize, GridSpacing spacing) {
    Matrix4!float chunkMatrix = Vertex.a.chunkToNode;
    ChunkLayout layout = ChunkLayout.make(chunkSize, spacing);
    float longest = 0;
    foreach (x; 0 .. chunkSize) {
        foreach (y; 0 .. chunkSize) {
            foreach (z; 0 .. chunkSize) {
                int[3] cell = [x, y, z];
                float[3] corner = [layout.gridToChunk(x), layout.gridToChunk(y), layout.gridToChunk(z)];
                foreach (axis; 0 .. 3) {
                    float[3] far = corner;
                    far[axis] = layout.gridToChunk(cell[axis] + 1);
                    float edge = (chunkMatrix * MVector!float([corner[0], corner[1], corner[2], 1.0f])).normalizedPoint().distance((chunkMatrix * MVector!float([far[0], far[1], far[2], 1.0f])).normalizedPoint());
                    if (edge > longest) {
                        longest = edge;
                    }
                }
            }
        }
    }
    return longest;
}

unittest {
    SimMeters meters;
    SimConfig config = SimConfig.fromMeters(meters);
    foreach (spacing; 0 .. GridSpacing.max + 1) {
        assert(config.character.stepHeight > longestVoxelEdge(meters.chunkSize, cast(GridSpacing) spacing));
    }
}
