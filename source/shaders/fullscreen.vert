#version 450

layout(location = 0) out vec2 screen;

const vec2 CORNERS[3] = vec2[](vec2(0.0, 0.0), vec2(2.0, 0.0), vec2(0.0, 2.0));

void main() {
    screen = CORNERS[gl_VertexIndex];
    gl_Position = vec4(screen * 2.0 - 1.0, 0.0, 1.0);
}
