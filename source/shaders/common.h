#ifndef COMMON_H
#define COMMON_H

const float INFINITY = 1.0 / 0.0;

layout(set = 0, binding = 0) uniform Common {
    mat4 projection;
    mat4 inverse_projection;
    mat4 camera_inverse;
    mat4 view_warp;
    vec4 frustum_planes[5];
    vec4 fog_color;
    float fog_density;
    float fog_exponent;
    float view_parity;
    float cull_sinh_radius;
    float warp_inner;
    float warp_outer;
    float warp_cull_cosh;
};

vec4 warped_clip(vec4 camera_point) {
    vec3 klein = camera_point.xyz / camera_point.w;
    float dist = atanh(min(length(klein), 0.999999));
    float strength = 1.0 - smoothstep(warp_inner, warp_outer, dist);
    vec3 warped = mix(klein, mat3(view_warp) * klein, strength);
    return projection * vec4(warped * camera_point.w, camera_point.w);
}

#endif
