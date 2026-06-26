#version 450

layout(push_constant) uniform PushConstants {
    mat4 mvp;   // view_projection * node transform * chunk-to-node
    vec4 voxel; // xyz = voxel coords within chunk, w = chunk dimension
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

void main() {
    vec3 c = corners[edges[gl_VertexIndex]];
    // Inflate slightly so the lines sit just outside the voxel faces
    // instead of z-fighting with them.
    vec3 p = voxel.xyz + 0.5 + (c - 0.5) * 1.01;
    gl_Position = mvp * vec4(p / voxel.w, 1.0);
}
