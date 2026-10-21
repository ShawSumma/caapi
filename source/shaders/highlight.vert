#version 450

#include "common.h"

const vec3 CORNERS[8] = vec3[](
    vec3(0, 0, 0), vec3(1, 0, 0), vec3(0, 1, 0), vec3(1, 1, 0),
    vec3(0, 0, 1), vec3(1, 0, 1), vec3(0, 1, 1), vec3(1, 1, 1)
);

const int EDGES[24] = int[](
    0, 1, 1, 3, 3, 2, 2, 0,
    4, 5, 5, 7, 7, 6, 6, 4,
    0, 4, 1, 5, 3, 7, 2, 6
);

const vec3 VOXEL_CENTER = vec3(0.5);
const float OUTLINE_SCALE = 1.01;

layout(push_constant) uniform PushConstants {
    mat4 model;
    vec4 low;
    vec4 high;
};

void main() {
    vec3 c = VOXEL_CENTER + (CORNERS[EDGES[gl_VertexIndex]] - VOXEL_CENTER) * OUTLINE_SCALE;
    gl_Position = projection * camera_inverse * model * vec4(mix(low.xyz, high.xyz, c), 1.0);
}
