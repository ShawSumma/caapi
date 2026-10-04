#version 460

#include "common.h"
#include "draw.h"
#include "surface-extraction/surface.h"

layout(location = 0) out vec3 texcoords_out;
layout(location = 1) out float occlusion;

layout(set = 1, binding = 0) readonly restrict buffer Surfaces {
    Surface surfaces[];
};

layout(set = 1, binding = 2) readonly restrict buffer Transforms {
    DrawTransform draws[];
};

layout(push_constant) uniform PushConstants {
    uint dimension;
};

const uvec3 vertices[12][6] = {
    {{0, 0, 0}, {0, 0, 1}, {0, 1, 1}, {0, 1, 1}, {0, 1, 0}, {0, 0, 0}},
    {{0, 0, 0}, {1, 0, 0}, {1, 0, 1}, {1, 0, 1}, {0, 0, 1}, {0, 0, 0}},
    {{0, 0, 0}, {0, 1, 0}, {1, 1, 0}, {1, 1, 0}, {1, 0, 0}, {0, 0, 0}},

    {{0, 0, 0}, {0, 1, 0}, {0, 1, 1}, {0, 1, 1}, {0, 0, 1}, {0, 0, 0}},
    {{0, 0, 0}, {0, 0, 1}, {1, 0, 1}, {1, 0, 1}, {1, 0, 0}, {0, 0, 0}},
    {{0, 0, 0}, {1, 0, 0}, {1, 1, 0}, {1, 1, 0}, {0, 1, 0}, {0, 0, 0}},

    {{0, 0, 1}, {0, 1, 1}, {0, 1, 0}, {0, 1, 0}, {0, 0, 0}, {0, 0, 1}},
    {{1, 0, 0}, {1, 0, 1}, {0, 0, 1}, {0, 0, 1}, {0, 0, 0}, {1, 0, 0}},
    {{0, 1, 0}, {1, 1, 0}, {1, 0, 0}, {1, 0, 0}, {0, 0, 0}, {0, 1, 0}},

    {{0, 0, 1}, {0, 0, 0}, {0, 1, 0}, {0, 1, 0}, {0, 1, 1}, {0, 0, 1}},
    {{1, 0, 0}, {0, 0, 0}, {0, 0, 1}, {0, 0, 1}, {1, 0, 1}, {1, 0, 0}},
    {{0, 1, 0}, {0, 0, 0}, {1, 0, 0}, {1, 0, 0}, {1, 1, 0}, {0, 1, 0}}
};

const uvec2 texcoords[4][6] = {
    {{0, 0}, {0, 1}, {1, 1}, {1, 1}, {1, 0}, {0, 0}},
    {{0, 0}, {1, 0}, {1, 1}, {1, 1}, {0, 1}, {0, 0}},
    {{0, 1}, {1, 1}, {1, 0}, {1, 0}, {0, 0}, {0, 1}},
    {{0, 1}, {0, 0}, {1, 0}, {1, 0}, {1, 1}, {0, 1}},
};

const uint VERTICES_PER_FACE = 6;
const uint FIRST_SOLID_MATERIAL = 1;

void main() {
    uint index = gl_VertexIndex / VERTICES_PER_FACE;
    uint vertex = gl_VertexIndex % VERTICES_PER_FACE;
    Surface s = surfaces[index];
    uvec3 pos = get_pos(s);
    uint axis = get_axis(s);
    DrawTransform draw = draws[gl_InstanceIndex];
    if (draw.reversed.x != 0.0) {
        if (axis % FLIPPED_DIAGONAL_OFFSET < REVERSED_AXIS_OFFSET) {
            axis += REVERSED_AXIS_OFFSET;
        } else {
            axis -= REVERSED_AXIS_OFFSET;
        }
    }
    uvec2 uv = texcoords[axis / AXES][vertex];
    texcoords_out = vec3(uv, get_mat(s) - FIRST_SOLID_MATERIAL);
    occlusion = get_occlusion(s, uv);
    vec3 relative_coords = vertices[axis][vertex] + pos;
    gl_Position = view_projection * draw.transform * vec4(relative_coords / dimension, 1);
}
