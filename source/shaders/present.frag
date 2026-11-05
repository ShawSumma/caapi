#version 450

#include "target.h"

const float SRGB_LINEAR_LIMIT = 0.0031308;
const float SRGB_LINEAR_SLOPE = 12.92;
const float SRGB_OFFSET = 0.055;
const float SRGB_GAMMA = 2.4;

STAGE_LINK(0) in vec2 screen;

layout(location = 0) out vec4 color;

uniform sampler2D image;

vec3 encoded(vec3 linear) {
    vec3 low = linear * SRGB_LINEAR_SLOPE;
    vec3 high = (1.0 + SRGB_OFFSET) * pow(linear, vec3(1.0 / SRGB_GAMMA)) - SRGB_OFFSET;
    return mix(high, low, vec3(lessThanEqual(linear, vec3(SRGB_LINEAR_LIMIT))));
}

void main() {
    color = vec4(encoded(texelFetch(image, ivec2(gl_FragCoord.xy), 0).rgb), 1.0);
}
