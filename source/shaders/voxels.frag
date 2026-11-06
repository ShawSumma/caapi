#version 450

#include "target.h"
#include "depth.h"

const float CLEAR_ALPHA = 0.5;

STAGE_LINK(0) in vec3 texcoords;
STAGE_LINK(1) in float brightness;
STAGE_LINK(2) flat in float glowing;
STAGE_LINK(3) flat in vec3 tint;
layout(location = 0) out vec4 color;
layout(location = 1) out float glow;

BOUND(1, 1) uniform sampler2DArray textures;

void main() {
    vec4 texel = texture(textures, texcoords);
    if (texel.a < CLEAR_ALPHA) {
        discard;
    }
    color = vec4(texel.rgb * tint * mix(brightness, 1.0, glowing), 1.0);
    glow = glowing;
    write_depth();
}
