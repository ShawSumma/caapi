module client.graphics.uniforms;

import core.stdc.math : powf, sinhf;
import base.maybe : Maybe;
import base.numbers : RADIANS_PER_DEGREE;
import base.units : Angle;
import client.graphics.frustum : FRUSTUM_PLANE_COUNT, Frustum, kleinDepthScale;
import client.graphics.matrices : MATRIX_FLOATS, determinant, flatten, matrixMultiply;
import client.world : FOG_SHARPNESS, LocalWorld, fogReach;
import common.material : MATERIAL_COUNT, isGlowing;
import common.node : ChunkLayout;
import common.raycast.graph : GraphCastHit;
import common.traversal : NOT_COLLECTED;
import geometry.honeycomb : CUBE_RADIUS, cubeToNode;
import geometry.lorentz : Motion, Normal, Point, Vec4;
import plugins.api.api : Material;

enum Angle HALF_VERTICAL_FOV = Angle(cast(float)(45 * RADIANS_PER_DEGREE));
enum float NEAR_PLANE = 1.0e-4f;
enum uint COLOR_CHANNELS = 3;
enum uint BITS_PER_WORD = 32;
enum uint GLOW_WORDS = (MATERIAL_COUNT + BITS_PER_WORD - 1) / BITS_PER_WORD;

enum float SRGB_LINEAR_LIMIT = 0.04045f;
enum float SRGB_LINEAR_SLOPE = 12.92f;
enum float SRGB_OFFSET = 0.055f;
enum float SRGB_GAMMA = 2.4f;

struct CommonUniforms {
    float[MATRIX_FLOATS] projection;
    float[MATRIX_FLOATS] cameraInverse;
    float[4][FRUSTUM_PLANE_COUNT] frustumPlanes;
    float[4] fogColor;
    float[4] sun;
    float[4] eye;
    float[2] halfTangents;
    float depthScale;
    float fogReach;
    float fogSharpness;
    float viewParity;
    float cullSinhRadius;
}

struct HighlightTarget {
    float[MATRIX_FLOATS] model;
    float[3] low;
    float[3] high;
}

uint[GLOW_WORDS] glowingMaterials() {
    uint[GLOW_WORDS] words = 0;
    foreach (index; 0 .. MATERIAL_COUNT) {
        if (isGlowing(cast(Material) index)) {
            words[index / BITS_PER_WORD] |= 1u << (index % BITS_PER_WORD);
        }
    }
    return words;
}

CommonUniforms commonUniforms(ref const LocalWorld world, float[4] fogLinear, float widthOverHeight) {
    Frustum frustum = Frustum.fromVerticalHalf(HALF_VERTICAL_FOV, widthOverHeight);
    Motion!float camera = world.cameraInNearbyFrame();
    float[MATRIX_FLOATS] cameraInverse = flatten(camera.inverse().m);
    float[MATRIX_FLOATS] projection = frustum.projection(NEAR_PLANE);
    Normal!float[FRUSTUM_PLANE_COUNT] planes = frustum.planes();
    float[4][FRUSTUM_PLANE_COUNT] frustumPlanes;
    foreach (i; 0 .. FRUSTUM_PLANE_COUNT) {
        frustumPlanes[i] = planes[i].v.c;
    }
    float[3] sunward = world.sunward;
    return CommonUniforms(
        projection,
        cameraInverse,
        frustumPlanes,
        fogLinear,
        (camera * Vec4!float([sunward[0], sunward[1], sunward[2], 1])).c,
        (camera * Point!float.origin()).v.c,
        [frustum.tanHalfWidth, frustum.tanHalfHeight],
        kleinDepthScale(NEAR_PLANE),
        fogReach(world.viewRadius()),
        FOG_SHARPNESS,
        parityOf(determinant(matrixMultiply(projection, cameraInverse))),
        sinhf(CUBE_RADIUS),
    );
}

Maybe!HighlightTarget findHighlightTarget(ref const LocalWorld world) {
    GraphCastHit hit = world.castCenterRay();
    uint index = world.nearby[world.published].indexOf(world.graph.slotOf(hit.chunk.node));
    if (!hit.isHit() || index == NOT_COLLECTED) {
        return Maybe!HighlightTarget.init;
    } else {
        ChunkLayout layout = world.graph.layout;
        float[MATRIX_FLOATS] chunkToWorld = matrixMultiply(flatten(world.cachedNodes[index].transform.m), flatten(hit.chunk.corner.cubeToNode));
        ubyte[3] cell = hit.voxelCoords.c;
        float[3] low = [layout.gridToCube(cell[0]), layout.gridToCube(cell[1]), layout.gridToCube(cell[2])];
        float[3] high = [layout.gridToCube(cell[0] + 1), layout.gridToCube(cell[1] + 1), layout.gridToCube(cell[2] + 1)];
        return Maybe!HighlightTarget.of(HighlightTarget(chunkToWorld, low, high));
    }
}

float parityOf(float value) {
    if (value < 0) {
        return -1.0f;
    } else {
        return 1.0f;
    }
}

float srgbToLinear(float encoded) {
    if (encoded > SRGB_LINEAR_LIMIT) {
        return powf((encoded + SRGB_OFFSET) / (1.0f + SRGB_OFFSET), SRGB_GAMMA);
    } else {
        return encoded / SRGB_LINEAR_SLOPE;
    }
}
