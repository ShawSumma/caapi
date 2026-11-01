#version 450

#include "common.h"

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

layout(location = 0) out vec3 shade;

layout(push_constant) uniform PushConstants {
    mat4 model;
    float half_side;
    uint marker_color;
};

void main() {
    shade = pow(unpackUnorm4x8(marker_color).rgb, vec3(SRGB_POWER));
    gl_Position = projection * camera_inverse * model * vec4(CORNERS[TRIANGLES[gl_VertexIndex]] * half_side, 1.0);
}
