#version 460

#include "common.h"
#include "draw.h"
#include "face.h"

layout(location = 0) out vec3 texcoords;
layout(location = 1) out float occlusion;

layout(set = 1, binding = 0) readonly restrict buffer Faces {
    Face faces[];
};

layout(set = 1, binding = 2) readonly restrict buffer Transforms {
    DrawTransform draws[];
};

layout(push_constant) uniform PushConstants {
    uint dimension;
    float cell_ratio;
};

const uint VERTICES_PER_FACE = 6;
const uint FIRST_SOLID_MATERIAL = 1;

// A face's six vertices are two triangles over a cycle of its corners, 0 1 2 and 2 3 0, which run (0, 0), (0, 1),
// (1, 1), (1, 0) along the face's two in-plane axes and meet along the diagonal from (0, 0) to (1, 1). Swapping the
// axes reverses the winding; mirroring the second axis moves the diagonal and reverses the winding again.
uvec2 face_corner(uint vertex, bool is_reversed, bool is_flipped) {
    uint step = vertex < 3 ? vertex : (vertex - 1) % 4;
    uvec2 corner = uvec2(step >> 1, ((step + 1) >> 1) & 1);
    if (is_reversed != is_flipped) {
        corner = corner.yx;
    }
    if (is_flipped) {
        corner.y = 1 - corner.y;
    }
    return corner;
}

void main() {
    Face face = faces[gl_VertexIndex / VERTICES_PER_FACE];
    DrawTransform draw = draws[gl_InstanceIndex];
    uint code = face_code(face);
    uint axis = code & AXIS_MASK;
    bool is_reversed = ((code & REVERSED_BIT) != 0) != (draw.reversed.x != 0.0);
    uvec2 corner = face_corner(gl_VertexIndex % VERTICES_PER_FACE, is_reversed, (code & FLIPPED_BIT) != 0);
    texcoords = vec3(corner, face_material(face) - FIRST_SOLID_MATERIAL);
    occlusion = face_occlusion(face, corner);
    uvec3 grid = face_position(face);
    grid[(axis + 1) % 3] += corner.x;
    grid[(axis + 2) % 3] += corner.y;
    vec3 cube = vec3(grid) / float(dimension);
    if (cell_ratio != 1.0) {
        cube = (1.0 - pow(vec3(cell_ratio), vec3(grid))) / (1.0 - pow(cell_ratio, float(dimension)));
    }
    gl_Position = projection * camera_inverse * draw.transform * vec4(cube, 1);
}
