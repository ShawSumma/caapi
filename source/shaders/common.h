#ifndef COMMON_H
#define COMMON_H

const float PI = 3.14159265;
const float INFINITY = 1.0 / 0.0;

const uint CHANNEL_COUNT = 5u;

layout(set = 0, binding = 0) uniform Common {
    mat4 view_projection;
    mat4 inverse_projection;
    float fog_density;
    float time;
    // xyz = light direction in node-local frame, w unused
    vec4 light_dir;
    // xyz = resting angle of each triple rotation
    vec4 rot_base;
    // xyz = how far the field turns each triple
    vec4 rot_gain;
    // x = enabled, y = gain, z = scale, w = field mode
    vec4 trip;
    // xy = size in pixels
    vec4 viewport;
    // x = producer: 0 none, 1 diffusion, 2 cyclic
    vec4 field_info;
};

// A voxel is a base-3 numeral: five channels, three levels each.
float[5] unpack_channels(uint value) {
    float levels[5];
    uint remaining = value;
    for (uint i = 0u; i < CHANNEL_COUNT; i = i + 1u) {
        levels[i] = float(remaining % 3u) * 0.5;
        remaining = remaining / 3u;
    }
    return levels;
}

// Turn three channels about the diagonal they share.
//
// At a third of a turn this is exactly a cyclic relabelling of the three:
// whichever channel was driving red now drives green, and so on. At a sixth it
// stops halfway between, which is where the secondaries live. Every angle in
// between is a valid colour space, which is the point. The space is being made
// live rather than picked from a list.
//
// The diagonal is the rotation axis, so it is fixed. An all-max voxel stays
// white and an all-zero voxel stays black at every angle, which is what keeps
// the two reserved values reserved.
float[5] rotate_triple(float[5] levels, int i, int j, int k, float theta) {
    const vec3 axis = vec3(0.57735026919);
    vec3 v = vec3(levels[i], levels[j], levels[k]);
    float c = cos(theta);
    float s = sin(theta);
    v = v * c + cross(axis, v) * s + axis * (dot(axis, v) * (1.0 - c));
    levels[i] = v.x;
    levels[j] = v.y;
    levels[k] = v.z;
    return levels;
}

// Channels 0, 1 and 2 land on red, green and blue. Channels 3 and 4 are out of
// sight until a rotation brings them in, and bringing one in necessarily
// pushes another out. There is no palette anywhere in here.
//
// The three rotations are driven independently, so a field with three natural
// components, such as triplanar weights or a surface normal, can turn each one
// separately rather than pushing a single scalar through all three.
vec3 display(float[5] levels, vec3 drive) {
    float turned[5] = rotate_triple(levels, 0, 1, 2, rot_base.x + rot_gain.x * drive.x);
    turned = rotate_triple(turned, 0, 1, 3, rot_base.y + rot_gain.y * drive.y);
    turned = rotate_triple(turned, 2, 3, 4, rot_base.z + rot_gain.z * drive.z);
    // Rotation can swing a component negative; there is no negative light.
    return clamp(vec3(turned[0], turned[1], turned[2]), 0.0, 1.0);
}

#endif
