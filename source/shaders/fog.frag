#version 450

#include "common.h"

layout(location = 0) in vec2 screen;

layout(location = 0) out vec4 fog;

layout(input_attachment_index = 0, set = 0, binding = 1) uniform subpassInput depth_input;

// The depth of a pixel is depth_scale / klein_depth - depth_scale, where its Klein depth is the distance along the view
// axis in Klein coordinates. Its direction across the screen scales that up to its Klein radius, which is the tanh of
// its distance. A pixel nothing was drawn to has depth 0, at the ideal boundary.
void main() {
    vec2 slope = (screen * 2.0 - 1.0) * half_tangents;
    float klein_depth = depth_scale / (subpassLoad(depth_input).x + depth_scale);
    float radius = klein_depth * sqrt(1.0 + dot(slope, slope));
    float away = radius < 1.0 ? atanh(radius) : INFINITY;
    fog = vec4(fog_color.rgb, exp(-pow(away / fog_reach, fog_sharpness)));
}
