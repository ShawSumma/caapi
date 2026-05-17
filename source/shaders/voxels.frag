#version 450

layout(location = 0) in vec3 texcoords;
layout(location = 1) in float occlusion;
layout(location = 2) in vec3 normal;
layout(location = 0) out vec4 color;

// Hypermine uses: color = texture(textures, texcoords) * occlusion;
// We substitute a procedural color per material until the PNG texture array
// is loaded. texcoords.z = material index - 1.
void main() {
    color = vec4(vec3(0.7) * occlusion, 1.0);
}
