#version 450

#include "target.h"

STAGE_LINK(0) in vec4 shade;
STAGE_LINK(1) in vec2 texel;
layout(location = 0) out vec4 color;

BOUND(0, 1) uniform sampler2D glyph_atlas;

void main() {
    float coverage = texelFetch(glyph_atlas, ivec2(floor(texel)), 0).r;
    color = vec4(shade.rgb, shade.a * coverage);
}
