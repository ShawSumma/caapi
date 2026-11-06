#version 450

#include "target.h"
#include "common.h"
#include "clip.h"
#include "warp.h"

const float SRGB_POWER = 2.2;

const vec3 CORNERS[8] = vec3[](
    vec3(-1, -1, -1), vec3(1, -1, -1), vec3(-1, 1, -1), vec3(1, 1, -1),
    vec3(-1, -1, 1), vec3(1, -1, 1), vec3(-1, 1, 1), vec3(1, 1, 1)
);

const int TRIANGLES[36] = int[](
    0, 1, 3, 3, 2, 0,
    4, 6, 7, 7, 5, 4,
    0, 4, 5, 5, 1, 0,
    2, 3, 7, 7, 6, 2,
    0, 2, 6, 6, 4, 0,
    1, 5, 7, 7, 3, 1
);

STAGE_LINK(0) out vec3 shade;

PUSH_BEGIN
    PUSHED mat4 model;
    PUSHED float half_side;
    PUSHED uint marker_color;
PUSH_END

#if defined(GL_ES)
    const float CHANNEL_MOST = 255.0;

    vec3 written_color() {
        return vec3(float(marker_color & 255u), float((marker_color >> 8u) & 255u), float((marker_color >> 16u) & 255u)) / CHANNEL_MOST;
    }
#else
    vec3 written_color() {
        return unpackUnorm4x8(marker_color).rgb;
    }
#endif

void main() {
    shade = pow(written_color(), vec3(SRGB_POWER));
    place_clip(projection * warped(camera_inverse * model * vec4(CORNERS[TRIANGLES[VERTEX_INDEX]] * half_side, 1.0)));
}
