#version 460

#include "common.h"
#include "surface-extraction/surface.h"

layout(location = 0) in mat4 transform;

layout(location = 0) out vec3 texcoords_out;
layout(location = 1) out float occlusion;
layout(location = 2) out vec3 normal_out;

layout(set = 1, binding = 0) readonly restrict buffer Surfaces {
    Surface surfaces[];
};

layout(push_constant) uniform PushConstants {
    uint dimension;
};

const uvec3 vertices[12][6] = {
    {{0, 0, 0}, {0, 0, 1}, {0, 1, 1}, {0, 1, 1}, {0, 1, 0}, {0, 0, 0}}, // -X
    {{0, 0, 0}, {1, 0, 0}, {1, 0, 1}, {1, 0, 1}, {0, 0, 1}, {0, 0, 0}}, // -Y
    {{0, 0, 0}, {0, 1, 0}, {1, 1, 0}, {1, 1, 0}, {1, 0, 0}, {0, 0, 0}}, // -Z

    {{0, 0, 0}, {0, 1, 0}, {0, 1, 1}, {0, 1, 1}, {0, 0, 1}, {0, 0, 0}}, // +X
    {{0, 0, 0}, {0, 0, 1}, {1, 0, 1}, {1, 0, 1}, {1, 0, 0}, {0, 0, 0}}, // +Y
    {{0, 0, 0}, {1, 0, 0}, {1, 1, 0}, {1, 1, 0}, {0, 1, 0}, {0, 0, 0}}, // +Z

    {{0, 0, 1}, {0, 1, 1}, {0, 1, 0}, {0, 1, 0}, {0, 0, 0}, {0, 0, 1}}, // -X
    {{1, 0, 0}, {1, 0, 1}, {0, 0, 1}, {0, 0, 1}, {0, 0, 0}, {1, 0, 0}}, // -Y
    {{0, 1, 0}, {1, 1, 0}, {1, 0, 0}, {1, 0, 0}, {0, 0, 0}, {0, 1, 0}}, // -Z

    {{0, 0, 1}, {0, 0, 0}, {0, 1, 0}, {0, 1, 0}, {0, 1, 1}, {0, 0, 1}}, // +X
    {{1, 0, 0}, {0, 0, 0}, {0, 0, 1}, {0, 0, 1}, {1, 0, 1}, {1, 0, 0}}, // +Y
    {{0, 1, 0}, {0, 0, 0}, {1, 0, 0}, {1, 0, 0}, {1, 1, 0}, {0, 1, 0}}  // +Z
};

const uvec2 texcoords[4][6] = {
    {{0, 0}, {0, 1}, {1, 1}, {1, 1}, {1, 0}, {0, 0}},
    {{0, 0}, {1, 0}, {1, 1}, {1, 1}, {0, 1}, {0, 0}},
    {{0, 1}, {1, 1}, {1, 0}, {1, 0}, {0, 0}, {0, 1}},
    {{0, 1}, {0, 0}, {1, 0}, {1, 0}, {1, 1}, {0, 1}},
};

// Outward-facing normal in chunk-local frame, indexed by axis (0..2 = -X/-Y/-Z, 3..5 = +X/+Y/+Z;
// 6..11 are flipped-diagonal versions of the same six normals).
const vec3 face_normals[12] = {
    vec3(-1, 0, 0), vec3(0, -1, 0), vec3(0, 0, -1),
    vec3( 1, 0, 0), vec3(0,  1, 0), vec3(0, 0,  1),
    vec3(-1, 0, 0), vec3(0, -1, 0), vec3(0, 0, -1),
    vec3( 1, 0, 0), vec3(0,  1, 0), vec3(0, 0,  1),
};

void main() {
    uint index = gl_VertexIndex / 6;
    uint vertex = gl_VertexIndex % 6;
    Surface s = surfaces[index];
    uvec3 pos = get_pos(s);
    uint axis = get_axis(s);
    // ~Half of the chunk transforms have det<0 (vertexChunkToNode includes a
    // reflection for odd-parity vertices). Hypermine handles this by flipping
    // the surface's `inward` flag at extraction time via `reverse_winding`.
    // Since we share one SSBO across all chunks, we do it here instead: flip
    // the axis by ±3, which reverses vertex positions, UV mapping, AND AO
    // corner lookups all at once — matching what hypermine's extract.comp does.
    // Full 4x4 determinant — the 3x3 sub-block determinant is NOT ±1 for
    // Lorentz boosts (only for pure rotations), so we must use the 4x4 det
    // which IS ±1 for any Lorentz isometry.
    float det4 = determinant(transform);
    if (det4 < 0.0) {
        if (axis < 3) { axis += 3; }
        else if (axis < 6) { axis -= 3; }
        else if (axis < 9) { axis += 3; }
        else { axis -= 3; }
    }
    uvec2 uv = texcoords[axis / 3][vertex];
    texcoords_out = vec3(uv, get_mat(s) - 1);
    occlusion = get_occlusion(s, uv);
    vec3 relative_coords = vertices[axis][vertex] + pos;
    gl_Position = view_projection * transform * vec4(relative_coords / dimension, 1);
    normal_out = face_normals[axis];
}
