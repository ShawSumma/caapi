#version 450

const float EDGE_SRGB = 0.05;
const float SRGB_OFFSET = 0.055;
const float SRGB_GAMMA = 2.4;

layout(location = 0) out vec4 color;

void main() {
    float edge = pow((EDGE_SRGB + SRGB_OFFSET) / (1.0 + SRGB_OFFSET), SRGB_GAMMA);
    color = vec4(edge, edge, edge, 1.0);
}
