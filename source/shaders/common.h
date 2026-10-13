#ifndef COMMON_H
#define COMMON_H

const float INFINITY = 1.0 / 0.0;

layout(set = 0, binding = 0) uniform Common {
    mat4 projection;
    mat4 camera_inverse;
    vec4 frustum_planes[5];
    vec4 fog_color;
    vec2 half_tangents;
    float depth_scale;
    float fog_reach;
    float fog_sharpness;
    float view_parity;
    float cull_sinh_radius;
};

#endif
