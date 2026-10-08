#version 450

layout(location = 0) in vec3 texcoords;
layout(location = 1) in float occlusion;
layout(location = 0) out vec4 color;

layout(set = 1, binding = 1) uniform sampler2DArray textures;

const float CLEAR_ALPHA = 0.5;

void main() {
    vec4 texel = texture(textures, texcoords);
    if (texel.a < CLEAR_ALPHA) {
        discard;
    }
    color = vec4(texel.rgb * occlusion, 1.0);
}
