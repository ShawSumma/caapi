#if !defined(COMMON_H)
#define COMMON_H

#include "target.h"

BOUND(0, 0) uniform Common {
    vec4 material_tints[96];
    mat4 projection;
    mat4 camera_inverse;
    vec4 frustum_planes[5];
    vec4 fog_color;
    vec4 sun;
    vec4 eye;
    vec2 half_tangents;
    float depth_scale;
    float fog_reach;
    float fog_sharpness;
    float view_parity;
    float cull_sinh_radius;
    float warp_strength;
    float warp_seconds;
};

#endif
