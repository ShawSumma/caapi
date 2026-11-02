#version 450

layout(location = 0) in vec3 shade;
layout(location = 0) out vec4 color;
layout(location = 1) out float glow;

void main() {
    color = vec4(shade, 1.0);
    glow = 1.0;
}
