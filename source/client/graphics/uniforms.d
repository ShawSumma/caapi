module client.graphics.uniforms;

import core.stdc.math : powf, sinhf;
import base.maybe : Maybe, MaybeIndex;
import base.numbers : RADIANS_PER_DEGREE;
import base.units : Angle;
import base.vector3 : Vec3;
import client.graphics.frustum : FRUSTUM_PLANE_COUNT, Frustum, kleinDepthScale;
import client.graphics.matrices : MATRIX_FLOATS, determinant, flatten, matrixMultiply;
import client.world : FOG_SHARPNESS, LocalWorld, fogReach;
import common.material : MATERIAL_COUNT, isGlowing;
import common.node : ChunkLayout;
import common.raycast.graph : GraphCastHit;
import geometry.cube : Cell;
import geometry.honeycomb : CUBE_RADIUS, cubeToNode;
import geometry.lorentz : Motion, Normal, Point, Vec4;
import plugins.api.api : Color, Material;

enum Angle HALF_VERTICAL_FOV = Angle(cast(float)(45 * RADIANS_PER_DEGREE));
enum float NEAR_PLANE = 1.0e-4f;
enum uint BITS_PER_WORD = 32;
enum uint GLOW_WORDS = (MATERIAL_COUNT + BITS_PER_WORD - 1) / BITS_PER_WORD;

enum float SRGB_LINEAR_LIMIT = 0.04045f;
enum float SRGB_LINEAR_SLOPE = 12.92f;
enum float SRGB_OFFSET = 0.055f;
enum float SRGB_GAMMA = 2.4f;

struct LinearColor {
    float red;
    float green;
    float blue;
    float alpha;
}

struct CommonUniforms {
    float[MATRIX_FLOATS] projection;
    float[MATRIX_FLOATS] cameraInverse;
    Normal!float[FRUSTUM_PLANE_COUNT] frustumPlanes;
    LinearColor fogColor;
    Vec4!float sun;
    Point!float eye;
    Frustum frustum;
    float depthScale;
    float fogReach;
    float fogSharpness;
    float viewParity;
    float cullSinhRadius;
}

struct HighlightTarget {
    float[MATRIX_FLOATS] model;
    Vec3!float low;
    Vec3!float high;
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

CommonUniforms commonUniforms(ref const LocalWorld world, LinearColor fogLinear, float widthOverHeight) {
    Frustum frustum = Frustum.fromVerticalHalf(HALF_VERTICAL_FOV, widthOverHeight);
    Motion!float camera = world.cameraInNearbyFrame();
    float[MATRIX_FLOATS] cameraInverse = flatten(camera.inverse().m);
    float[MATRIX_FLOATS] projection = frustum.projection(NEAR_PLANE);
    Vec3!float sunward = world.sunward;
    return CommonUniforms(
        projection,
        cameraInverse,
        frustum.planes(),
        fogLinear,
        camera * Vec4!float([sunward.x, sunward.y, sunward.z, 1]),
        camera * Point!float.origin(),
        frustum,
        kleinDepthScale(NEAR_PLANE),
        fogReach(world.viewRadius()),
        FOG_SHARPNESS,
        parityOf(determinant(matrixMultiply(projection, cameraInverse))),
        sinhf(CUBE_RADIUS),
    );
}

Maybe!HighlightTarget findHighlightTarget(ref const LocalWorld world) {
    Maybe!GraphCastHit hit = world.castCenterRay();
    if (!hit.exists) {
        return Maybe!HighlightTarget.init;
    } else {
        MaybeIndex!uint index = world.nearby[world.published].indexOf(world.graph.slotOf(hit.value.chunk.node).value);
        if (!index.exists) {
            return Maybe!HighlightTarget.init;
        } else {
            ChunkLayout layout = world.graph.layout;
            float[MATRIX_FLOATS] chunkToWorld = matrixMultiply(flatten(world.cachedNodes[index.value].transform.m), flatten(hit.value.chunk.corner.cubeToNode));
            Cell cell = hit.value.voxelCoords;
            Vec3!float low = Vec3!float(layout.gridToCube(cell.x), layout.gridToCube(cell.y), layout.gridToCube(cell.z));
            Vec3!float high = Vec3!float(layout.gridToCube(cell.x + 1), layout.gridToCube(cell.y + 1), layout.gridToCube(cell.z + 1));
            return Maybe!HighlightTarget.of(HighlightTarget(chunkToWorld, low, high));
        }
    }
}

float parityOf(float value) {
    if (value < 0) {
        return -1.0f;
    } else {
        return 1.0f;
    }
}

LinearColor linearOf(Color color) {
    return LinearColor(srgbToLinear(color.red), srgbToLinear(color.green), srgbToLinear(color.blue), 1);
}

float srgbToLinear(float encoded) {
    if (encoded > SRGB_LINEAR_LIMIT) {
        return powf((encoded + SRGB_OFFSET) / (1.0f + SRGB_OFFSET), SRGB_GAMMA);
    } else {
        return encoded / SRGB_LINEAR_SLOPE;
    }
}
