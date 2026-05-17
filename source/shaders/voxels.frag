#version 450

layout(location = 0) in vec3 texcoords;
layout(location = 1) in float occlusion;
layout(location = 0) out vec4 color;

// Procedural palette by material index (texcoords.z stores material-1).
// We'll add a real sampler2DArray once PNG materials are loaded.
vec3 mat_color(int m) {
    // Bright stable color per material. Force a minimum brightness so dark hashes
    // don't make the world look black.
    vec3 c = vec3(
        fract(sin(float(m) * 12.9898) * 43758.5453),
        fract(sin(float(m) * 78.233)  * 43758.5453),
        fract(sin(float(m) * 37.719)  * 43758.5453)
    );
    // Lift into a bright pastel range.
    c = c * 0.5 + 0.5;
    return c;
}

void main() {
    int m = int(texcoords.z);
    color = vec4(mat_color(m) * occlusion, 1.0);
}
