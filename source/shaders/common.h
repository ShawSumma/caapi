#ifndef COMMON_H
#define COMMON_H

const float INFINITY = 1.0 / 0.0;

layout(set = 0, binding = 0) uniform Common {
    mat4 view_projection;
    mat4 inverse_projection;
    mat4 camera_inverse;
    vec4 frustum_planes[5];
    vec4 fog_color;
    float fog_density;
    float fog_exponent;
    float view_parity;
    float cull_sinh_radius;
};

#endif
