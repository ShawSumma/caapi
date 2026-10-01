#ifndef COMMON_H
#define COMMON_H

const float INFINITY = 1.0 / 0.0;

layout(set = 0, binding = 0) uniform Common {
    mat4 view_projection;
    mat4 inverse_projection;
    vec4 fog_color;
    float fog_density;
    float fog_exponent;
};

#endif
