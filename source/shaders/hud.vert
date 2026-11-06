#version 450

#include "target.h"

const float SRGB_POWER = 2.2;
const uint TEXEL_MASK = 0xFFFFu;
const uint TEXEL_Y_SHIFT = 16u;

STAGE_LINK(0) out vec4 shade;
STAGE_LINK(1) out vec2 texel;

#if defined(GL_ES)
    layout(location = 0) in vec2 vertex_at;
    layout(location = 1) in vec4 vertex_written;
    layout(location = 2) in vec2 vertex_texel;

    vec2 position_of_vertex() {
        return vertex_at;
    }

    vec4 written_of_vertex() {
        return vertex_written;
    }

    vec2 texel_of_vertex() {
        return vertex_texel;
    }
#else
    struct Vertex {
        vec2 at;
        uint color;
        uint texel;
    };

    BOUND(0, 0) readonly restrict buffer Vertices {
        Vertex vertices[];
    };

    vec2 position_of_vertex() {
        return vertices[VERTEX_INDEX].at;
    }

    vec4 written_of_vertex() {
        return unpackUnorm4x8(vertices[VERTEX_INDEX].color);
    }

    vec2 texel_of_vertex() {
        uint packed = vertices[VERTEX_INDEX].texel;
        return vec2(float(packed & TEXEL_MASK), float(packed >> TEXEL_Y_SHIFT));
    }
#endif

void main() {
    vec2 at = position_of_vertex();
    vec4 written = written_of_vertex();
    shade = vec4(pow(written.rgb, vec3(SRGB_POWER)), written.a);
    texel = texel_of_vertex();
    gl_Position = vec4(at.x, SCREEN_Y(at.y), 0.0, 1.0);
}
