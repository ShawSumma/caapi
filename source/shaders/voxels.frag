#version 450

layout(location = 0) in flat vec3 voxel_color;
layout(location = 1) in float occlusion;
layout(location = 0) out vec4 color;

void main() {
    color = vec4(voxel_color * occlusion, 1.0);
}
