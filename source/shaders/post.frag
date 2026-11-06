#version 450

#include "target.h"

layout(location = 0) out vec4 color;
layout(location = 1) out vec4 kept;

BOUND(0, 0) uniform sampler2D scene;
BOUND(0, 1) uniform sampler2D previous;
BOUND(0, 2) uniform sampler2D level1;
BOUND(0, 3) uniform sampler2D level2;
BOUND(0, 4) uniform sampler2D level3;
BOUND(0, 5) uniform sampler2D level4;

PUSH_BEGIN
    PUSHED vec4 band_gains;
    PUSHED float afterimage;
PUSH_END

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec2 place = gl_FragCoord.xy / vec2(textureSize(scene, 0));
    vec3 finest = texelFetch(scene, pixel, 0).rgb;
    vec3 first = texture(level1, place).rgb;
    vec3 second = texture(level2, place).rgb;
    vec3 third = texture(level3, place).rgb;
    vec3 fourth = texture(level4, place).rgb;
    vec3 banded = fourth + band_gains.x * (finest - first) + band_gains.y * (first - second) + band_gains.z * (second - third) + band_gains.w * (third - fourth);
    vec3 seen = mix(max(banded, vec3(0.0)), texelFetch(previous, pixel, 0).rgb, afterimage);
    color = vec4(seen, 1.0);
    kept = color;
}
