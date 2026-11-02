#version 450

const float CROSSHAIR_OPACITY = 0.75;

layout(location = 0) out vec4 color;

void main() {
    color = vec4(1.0, 1.0, 1.0, CROSSHAIR_OPACITY);
}
