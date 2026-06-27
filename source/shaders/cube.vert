#version 330 core

layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aColor;

uniform mat4 model;
uniform mat4 proj;

out vec3 vColor;
out float vFog;

void main() {
    vec4 p = model * vec4(aPos, 1.0);
    float m = p.x * p.x + p.y * p.y + p.z * p.z - p.w * p.w;
    float s = (m < 0.0) ? inversesqrt(-m) : 1.0;
    p *= s;
    if (p.w < 0.0) {
        p = -p;
    }

    vec3 q = p.xyz / (p.w + 1.0);

    vFog = p.w;
    gl_Position = proj * vec4(q, 1.0);
    vColor = aColor;
}
