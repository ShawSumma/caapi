#version 450

#include "target.h"

const vec2 CORNERS[3] = vec2[](vec2(0.0, 0.0), vec2(2.0, 0.0), vec2(0.0, 2.0));

STAGE_LINK(0) out vec2 screen;

void main() {
    screen = CORNERS[VERTEX_INDEX];
    gl_Position = vec4(screen * 2.0 - 1.0, 0.0, 1.0);
}
