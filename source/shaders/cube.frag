#version 330 core

in vec3 vColor;
in float vFog;

out vec4 frag;

void main() {
    float f = clamp(1.0 - (vFog - 1.0) * 0.06, 0.15, 1.0);
    vec3 bg = vec3(0.06, 0.07, 0.10);
    frag = vec4(mix(bg, vColor, f), 1.0);
}
