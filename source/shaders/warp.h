#if !defined(WARP_H)
#define WARP_H

#include "common.h"

const float WARP_FREQUENCY = 6.0;
const float WARP_RATE = 1.3;
const float WARP_RATE_ACROSS = 0.9;

vec4 warped(vec4 camera_point) {
    float reach = length(camera_point.xyz);
    if (warp_strength == 0.0 || reach == 0.0) {
        return camera_point;
    }
    vec3 direction = camera_point.xyz / reach;
    float off_axis = length(direction.xy);
    vec2 sway = vec2(sin(WARP_FREQUENCY * direction.y + warp_seconds * WARP_RATE), sin(WARP_FREQUENCY * direction.x - warp_seconds * WARP_RATE_ACROSS));
    vec3 moved = normalize(direction + vec3(sway * (warp_strength * off_axis), 0.0));
    return vec4(moved * reach, camera_point.w);
}

#endif
