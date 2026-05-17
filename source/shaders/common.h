#ifndef COMMON_H
#define COMMON_H

const float PI = 3.14159265;
const float INFINITY = 1.0 / 0.0;

layout(set = 0, binding = 0) uniform Common {
    mat4 view_projection;
    mat4 inverse_projection;
    float fog_density;
    float time;
    vec4 light_dir; // xyz = light direction in node-local frame, w unused
};

#endif
