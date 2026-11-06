#version 450

#include "target.h"

layout(location = 0) out vec4 color;

BOUND(0, 0) uniform sampler2D finer;

void main() {
    vec2 texel = 1.0 / vec2(textureSize(finer, 0));
    vec2 center = gl_FragCoord.xy * 2.0 * texel;
    vec3 sum = texture(finer, center + vec2(-texel.x, -texel.y)).rgb;
    sum += texture(finer, center + vec2(texel.x, -texel.y)).rgb;
    sum += texture(finer, center + vec2(-texel.x, texel.y)).rgb;
    sum += texture(finer, center + vec2(texel.x, texel.y)).rgb;
    color = vec4(sum * 0.25, 1.0);
}
