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
    vec4 light_dir; // xyz = light direction in node-local frame, w unused
    vec4 rot_base;  // xyz = resting angle of each triple rotation
    vec4 rot_gain;  // xyz = how far the field turns each triple
    vec4 trip;      // x = enabled, y = gain, z = scale, w = field mode
    vec4 viewport;  // xy = size in pixels
    vec4 field_info; // x = producer: 0 none, 1 diffusion, 2 cyclic
};

/// A voxel is a base-3 numeral: five channels, three levels each.
void unpack_channels(uint value, out float levels[5]) {
    for (uint i = 0u; i < CHANNEL_COUNT; i++) {
        levels[i] = float(value % 3u) * 0.5;
        value /= 3u;
    }
}

/// Turn three channels about the diagonal they share.
///
/// At a third of a turn this is exactly a cyclic relabelling of the three —
/// whichever channel was driving red now drives green, and so on. At a sixth
/// it stops halfway between, which is where the secondaries live. Every angle
/// in between is a valid colour space, which is the point: the space is being
/// made live rather than picked from a list.
///
/// The diagonal is the rotation axis, so it is fixed. An all-max voxel stays
/// white and an all-zero voxel stays black at every angle, which is what keeps
/// the two reserved values reserved.
void rotate_triple(inout float levels[5], int i, int j, int k, float theta) {
    const vec3 n = vec3(0.57735026919); // (1,1,1)/sqrt(3)
    vec3 v = vec3(levels[i], levels[j], levels[k]);
    float c = cos(theta);
    float s = sin(theta);
    v = v * c + cross(n, v) * s + n * (dot(n, v) * (1.0 - c));
    levels[i] = v.x;
    levels[j] = v.y;
    levels[k] = v.z;
}

/// Channels 0, 1 and 2 land on red, green and blue. Channels 3 and 4 are out
/// of sight until a rotation brings them in, and bringing one in necessarily
/// pushes another out. There is no palette anywhere in here.
///
/// The three rotations are driven independently, so a field that has three
/// natural components — triplanar weights, a surface normal — can turn each
/// one separately rather than pushing a single scalar through all three.
vec3 display(float levels[5], vec3 drive) {
    rotate_triple(levels, 0, 1, 2, rot_base.x + rot_gain.x * drive.x);
    rotate_triple(levels, 0, 1, 3, rot_base.y + rot_gain.y * drive.y);
    rotate_triple(levels, 2, 3, 4, rot_base.z + rot_gain.z * drive.z);
    // Rotation can swing a component negative; there is no negative light.
    return clamp(vec3(levels[0], levels[1], levels[2]), 0.0, 1.0);
}

#endif
