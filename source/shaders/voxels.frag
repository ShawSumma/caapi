#version 450

const float CLEAR_ALPHA = 0.5;

layout(location = 0) in vec3 texcoords;
layout(location = 1) in float brightness;
layout(location = 2) flat in float glowing;
layout(location = 0) out vec4 color;
layout(location = 1) out float glow;

layout(set = 1, binding = 1) uniform sampler2DArray textures;

void main() {
    vec4 texel = texture(textures, texcoords);
    if (texel.a < CLEAR_ALPHA) {
        discard;
    }
    color = vec4(texel.rgb * mix(brightness, 1.0, glowing), 1.0);
    glow = glowing;
}
