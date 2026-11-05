#version 450

#include "target.h"

const float ARM_HALF_LENGTH = 0.025;
const float ARM_HALF_THICKNESS = 0.004;
const uint VERTICES_PER_ARM = 6u;

const vec4 ARMS[3] = vec4[](
    vec4(-ARM_HALF_LENGTH, -ARM_HALF_THICKNESS, ARM_HALF_LENGTH, ARM_HALF_THICKNESS),
    vec4(-ARM_HALF_THICKNESS, ARM_HALF_THICKNESS, ARM_HALF_THICKNESS, ARM_HALF_LENGTH),
    vec4(-ARM_HALF_THICKNESS, -ARM_HALF_LENGTH, ARM_HALF_THICKNESS, -ARM_HALF_THICKNESS)
);

const vec2 CORNERS[6] = vec2[](
    vec2(0, 0),
    vec2(1, 0),
    vec2(1, 1),
    vec2(1, 1),
    vec2(0, 1),
    vec2(0, 0)
);

PUSH_BEGIN
    PUSHED float width_over_height;
PUSH_END

void main() {
    uint vertex_index = uint(VERTEX_INDEX);
    vec4 arm = ARMS[vertex_index / VERTICES_PER_ARM];
    vec2 position = mix(arm.xy, arm.zw, CORNERS[vertex_index % VERTICES_PER_ARM]);
    gl_Position = vec4(position.x / width_over_height, SCREEN_Y(position.y), 0.0, 1.0);
}
