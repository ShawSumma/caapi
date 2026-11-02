#version 450

const float SRGB_POWER = 2.2;

struct Vertex {
    vec2 at;
    uint color;
    uint unused;
};

layout(location = 0) out vec4 color;

layout(set = 0, binding = 0) readonly restrict buffer Vertices {
    Vertex vertices[];
};

void main() {
    Vertex vertex = vertices[gl_VertexIndex];
    vec4 written = unpackUnorm4x8(vertex.color);
    color = vec4(pow(written.rgb, vec3(SRGB_POWER)), written.a);
    gl_Position = vec4(vertex.at, 0.0, 1.0);
}
