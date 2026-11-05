#version 450

#include "target.h"

const float SRGB_POWER = 2.2;

STAGE_LINK(0) out vec4 shade;

#if defined(GL_ES)
    layout(location = 0) in vec2 vertex_at;
    layout(location = 1) in vec4 vertex_written;

    vec2 position_of_vertex() {
        return vertex_at;
    }

    vec4 written_of_vertex() {
        return vertex_written;
    }
#else
    struct Vertex {
        vec2 at;
        uint color;
        uint unused;
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
#endif

void main() {
    vec2 at = position_of_vertex();
    vec4 written = written_of_vertex();
    shade = vec4(pow(written.rgb, vec3(SRGB_POWER)), written.a);
    gl_Position = vec4(at.x, SCREEN_Y(at.y), 0.0, 1.0);
}
