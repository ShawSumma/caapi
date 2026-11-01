#version 450

#include "common.h"

layout(location = 0) in vec2 screen;

layout(location = 0) out vec4 fog;

layout(input_attachment_index = 0, set = 0, binding = 1) uniform subpassInput depth_input;
layout(input_attachment_index = 1, set = 0, binding = 2) uniform subpassInput glow_input;

void main() {
    vec2 slope = (screen * 2.0 - 1.0) * half_tangents;
    float klein_depth = depth_scale / (subpassLoad(depth_input).x + depth_scale);
    float radius = klein_depth * sqrt(1.0 + dot(slope, slope));
    float away = INFINITY;
    if (radius < 1.0) {
        away = atanh(radius);
    }
    fog = vec4(fog_color.rgb, mix(exp(-pow(away / fog_reach, fog_sharpness)), 1.0, subpassLoad(glow_input).x));
}
