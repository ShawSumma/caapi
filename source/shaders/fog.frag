#version 450

#include "target.h"
#include "common.h"

STAGE_LINK(0) in vec2 screen;

layout(location = 0) out vec4 fog;

#if defined(GL_ES)
    uniform sampler2D depth_input;
    uniform sampler2D glow_input;
    #define LOAD_INPUT(name) texelFetch(name, ivec2(gl_FragCoord.xy), 0)
#else
    layout(input_attachment_index = 0, set = 0, binding = 1) uniform subpassInput depth_input;
    layout(input_attachment_index = 1, set = 0, binding = 2) uniform subpassInput glow_input;
    #define LOAD_INPUT(name) subpassLoad(name)
#endif

void main() {
    vec2 slope = (screen * 2.0 - 1.0) * half_tangents;
    float klein_depth = depth_scale / (LOAD_INPUT(depth_input).x + depth_scale);
    float radius = klein_depth * sqrt(1.0 + dot(slope, slope));
    float kept = 0.0;
    if (radius < 1.0) {
        kept = exp(-pow(atanh(radius) / fog_reach, fog_sharpness));
    }
    fog = vec4(fog_color.rgb, mix(kept, 1.0, LOAD_INPUT(glow_input).x));
}
