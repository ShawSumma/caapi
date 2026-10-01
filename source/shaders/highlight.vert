#version 450

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    vec4 voxel;
};

const vec3 corners[8] = vec3[](
    vec3(0, 0, 0), vec3(1, 0, 0), vec3(0, 1, 0), vec3(1, 1, 0),
    vec3(0, 0, 1), vec3(1, 0, 1), vec3(0, 1, 1), vec3(1, 1, 1)
);

const int edges[24] = int[](
    0, 1, 1, 3, 3, 2, 2, 0,
    4, 5, 5, 7, 7, 6, 6, 4,
    0, 4, 1, 5, 3, 7, 2, 6
);

const vec3 VOXEL_CENTER = vec3(0.5);
const float OUTLINE_SCALE = 1.01;

void main() {
    vec3 c = corners[edges[gl_VertexIndex]];
    vec3 p = voxel.xyz + VOXEL_CENTER + (c - VOXEL_CENTER) * OUTLINE_SCALE;
    gl_Position = mvp * vec4(p / voxel.w, 1.0);
}
