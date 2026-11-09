module client.graphics.uniforms;

import core.stdc.math : expf, powf, sinhf, tanf;
import base.maybe : Maybe, MaybeIndex;
import base.numbers : RADIANS_PER_DEGREE, lowerOf;
import base.units : Angle, Time;
import base.vector3 : Vec3, scaled;
import client.camera : CAMERA_FORWARD;
import client.graphics.frustum : FRUSTUM_PLANE_COUNT, Frustum, kleinDepthScale;
import client.graphics.matrices : MATRIX_FLOATS, determinant, flatten, matrixMultiply;
import client.world : FOG_SHARPNESS, LocalWorld, fogReach;
import common.color : ColorTurn, Seen, seenOf, spectrumOf, turned;
import common.look : Color;
import common.material : BITS_PER_WORD, ByteColor, MATERIAL_WORDS, MaterialSet, hidden, materialColors, materialCount, without;
import common.node : ChunkLayout;
import common.perception : BAND_COUNT;
import common.raycast.graph : GraphCastHit;
import geometry.cube : Cell;
import geometry.honeycomb : CUBE_RADIUS, cubeToNode;
import geometry.lorentz : Motion, Normal, Point, Vec4;

enum Angle HALF_VERTICAL_FOV = Angle(cast(float)(45 * RADIANS_PER_DEGREE));
enum float NEAR_PLANE = 1.0e-4f;
enum uint TINT_SLOTS = MATERIAL_WORDS * BITS_PER_WORD;
enum float MOST_TINT = 16;
enum float CHANNEL_MOST = 255;

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
    LinearColor[TINT_SLOTS] materialTints;
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
    float warpStrength;
    float warpSeconds;
}

struct PostSettings {
    float[BAND_COUNT] bandGains;
    float afterimage = 0;
}

struct HighlightTarget {
    float[MATRIX_FLOATS] model;
    Vec3!float low;
    Vec3!float high;
}

CommonUniforms commonUniforms(ref const LocalWorld world, LinearColor fogLinear, float widthOverHeight) {
    Frustum frustum = Frustum.fromVerticalTangent(tanf(HALF_VERTICAL_FOV.value) * world.view.fieldTangentScale.value, widthOverHeight);
    Motion!float camera = world.cameraInNearbyFrame() * Motion!float.shift(CAMERA_FORWARD.scaled(-world.view.eyeBack.value));
    float[MATRIX_FLOATS] cameraInverse = flatten(camera.inverse().m);
    float[MATRIX_FLOATS] projection = frustum.projection(NEAR_PLANE);
    Vec3!float sunward = world.sunward;
    return CommonUniforms(
        materialTints(world.view.colorTurn),
        projection,
        cameraInverse,
        frustum.planes(),
        fogLinear,
        camera * Vec4!float([sunward.x, sunward.y, sunward.z, 1]),
        camera * Point!float.origin(),
        frustum,
        kleinDepthScale(NEAR_PLANE),
        fogReach(world.viewRadius()) * world.view.fogShare.value,
        FOG_SHARPNESS,
        parityOf(determinant(matrixMultiply(projection, cameraInverse))),
        sinhf(CUBE_RADIUS),
        world.view.warpStrength.value,
        world.view.warpSeconds.value,
    );
}

PostSettings postSettings(ref const LocalWorld world, Time frame) {
    PostSettings settings;
    foreach (band; 0 .. BAND_COUNT) {
        settings.bandGains[band] = world.view.bandGains[band].value;
    }
    if (world.view.afterimageTime.value > 0) {
        settings.afterimage = expf(-frame.value / world.view.afterimageTime.value);
    }
    return settings;
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

MaterialSet unseenMaterials(ref const LocalWorld world) {
    return hidden.without(world.view.visible);
}

LinearColor perceivedFog(ref const LocalWorld world) {
    LinearColor plain = linearOf(world.fogColor);
    Seen seen = seenOf(turned(spectrumOf([plain.red, plain.green, plain.blue]), world.view.colorTurn));
    return LinearColor(seen[0], seen[1], seen[2], 1);
}

LinearColor[TINT_SLOTS] materialTints(ColorTurn turn) {
    LinearColor[TINT_SLOTS] tints = LinearColor(1, 1, 1, 1);
    foreach (index; 1 .. materialCount()) {
        ByteColor written = materialColors.ptr[index];
        Seen plain = [srgbToLinear(written.red / CHANNEL_MOST), srgbToLinear(written.green / CHANNEL_MOST), srgbToLinear(written.blue / CHANNEL_MOST)];
        Seen seen = seenOf(turned(spectrumOf(plain), turn));
        tints[index] = LinearColor(tintOf(seen[0], plain[0]), tintOf(seen[1], plain[1]), tintOf(seen[2], plain[2]), 1);
    }
    return tints;
}

float tintOf(float seen, float plain) {
    if (plain > 0) {
        return lowerOf(seen / plain, MOST_TINT);
    } else {
        return 1;
    }
}

float srgbToLinear(float encoded) {
    if (encoded > SRGB_LINEAR_LIMIT) {
        return powf((encoded + SRGB_OFFSET) / (1.0f + SRGB_OFFSET), SRGB_GAMMA);
    } else {
        return encoded / SRGB_LINEAR_SLOPE;
    }
}
