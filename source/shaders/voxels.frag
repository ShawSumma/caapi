#version 450

#include "common.h"

layout(location = 0) in flat uint voxel_value;
layout(location = 1) in float occlusion;
layout(location = 2) in flat float shade;
layout(location = 3) in vec3 node_pos;
layout(location = 4) in flat vec3 chunk_normal;
layout(location = 5) in flat uint node_seed;
layout(location = 6) in flat vec3 node_turn;
layout(location = 0) out vec4 color;

layout(set = 1, binding = 1) uniform sampler2D perception_field;

// trip.w picks how the colour space is driven.
// Reaction-diffusion in screen space.
const uint FIELD_SCREEN = 0u;
// Reaction-diffusion wrapped onto surfaces.
const uint FIELD_TRIPLANAR = 1u;
// Octaved noise the terrain is carved from.
const uint FIELD_VOLUME = 2u;
// Pure surface orientation.
const uint FIELD_NORMAL = 3u;
// Debug: the field texture itself, unfiltered.
const uint FIELD_RAW = 4u;

const int OCTAVES = 6;

const uint PRODUCER_CYCLIC = 2u;

// Reads the field as a scalar in [0,1], whichever producer wrote it.
//
// Diffusion's activator sits on thin curves and needs a wide blur to spread
// into usable domains. The cyclic automaton already has broad structure and
// only needs enough to take the edge off its quantised states. Blurring that
// wide would destroy the spirals, which are the whole point.
float blurred(vec2 uv) {
    bool cyclic = uint(field_info.x) == PRODUCER_CYCLIC;
    float r = 22.0 / 512.0;
    if (cyclic) {
        r = 1.5 / 512.0;
    }

    vec4 s = texture(perception_field, uv);
    s = s + texture(perception_field, uv + vec2(r, 0.0));
    s = s + texture(perception_field, uv + vec2(-r, 0.0));
    s = s + texture(perception_field, uv + vec2(0.0, r));
    s = s + texture(perception_field, uv + vec2(0.0, -r));
    s = s * 0.2;

    if (cyclic) {
        // The state is stored as a unit vector, so averaging the samples is a
        // circular mean and the wrap costs nothing.
        return fract(atan(s.g, s.r) / (2.0 * PI) + 1.0);
    }
    return s.g * trip.y;
}

// Different nodes read different parts of the field, so the pattern is not the
// same in every node. Continuity still holds within a node, which is where 20
// chunks worth of surface lives.
vec3 node_offset() {
    uint h = node_seed * 747796405u + 2891336453u;
    h = ((h >> ((h >> 28) + 4u)) ^ h) * 277803737u;
    h = h ^ (h >> 22);
    vec3 bytes = vec3(
        float(h & 0xFFu),
        float((h >> 8) & 0xFFu),
        float((h >> 16) & 0xFFu)
    );
    return bytes * (1.0 / 255.0);
}

float hash13(vec3 p) {
    vec3 q = fract(p * 0.3183099 + 0.1);
    q = q * 17.0;
    return fract(q.x * q.y * q.z * (q.x + q.y + q.z));
}

float vnoise3(vec3 p) {
    vec3 cell = floor(p);
    vec3 f = fract(p);
    // Quintic rather than cubic: continuous in the second derivative, so the
    // octaves stack without creasing along cell boundaries.
    f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    float c000 = hash13(cell + vec3(0.0, 0.0, 0.0));
    float c100 = hash13(cell + vec3(1.0, 0.0, 0.0));
    float c010 = hash13(cell + vec3(0.0, 1.0, 0.0));
    float c110 = hash13(cell + vec3(1.0, 1.0, 0.0));
    float c001 = hash13(cell + vec3(0.0, 0.0, 1.0));
    float c101 = hash13(cell + vec3(1.0, 0.0, 1.0));
    float c011 = hash13(cell + vec3(0.0, 1.0, 1.0));
    float c111 = hash13(cell + vec3(1.0, 1.0, 1.0));

    float x00 = mix(c000, c100, f.x);
    float x10 = mix(c010, c110, f.x);
    float x01 = mix(c001, c101, f.x);
    float x11 = mix(c011, c111, f.x);

    float y0 = mix(x00, x10, f.y);
    float y1 = mix(x01, x11, f.y);

    return mix(y0, y1, f.z);
}

float fbm3(vec3 p) {
    float total = 0.0;
    float amplitude = 0.5;
    float norm = 0.0;
    vec3 at = p;
    for (int i = 0; i < OCTAVES; i = i + 1) {
        total = total + amplitude * vnoise3(at);
        norm = norm + amplitude;
        at = at * 2.02 + vec3(19.1, 7.3, 31.7);
        amplitude = amplitude * 0.5;
    }
    return total / norm;
}

vec3 drivers() {
    uint mode = uint(trip.w);
    float scale = trip.z;

    if (mode == FIELD_WALK) {
        return vec3(0.0);
    }

    if (mode == FIELD_TRIPLANAR) {
        // Blend three planar projections by the normal so the pattern wraps
        // the terrain. The weights are a partition summing to one, so this is
        // a single sample in the same range as the field. They are not three
        // independent fields and must not be used as three drivers. The three
        // rotations differ by their gains instead.
        //
        // The factor of four makes one chunk span roughly one tile of the
        // field, so its structure shows instead of a magnified few cells.
        vec3 weights = abs(chunk_normal);
        weights = weights / max(weights.x + weights.y + weights.z, 1e-4);
        vec3 p = node_pos * scale * 4.0 + node_offset();
        float blend = weights.x * blurred(p.yz);
        blend = blend + weights.y * blurred(p.zx);
        blend = blend + weights.z * blurred(p.xy);
        return vec3(blend);
    }

    if (mode == FIELD_VOLUME) {
        // Octaved noise in node-local space. fBm already lands near [0,1] and
        // must not go through the reaction-diffusion gain, which would clamp
        // every driver to 1 and flatten the rotation.
        vec3 p = node_pos * scale * 20.0 + node_offset() * 32.0;
        vec3 f = vec3(
            fbm3(p),
            fbm3(p + vec3(11.3, 4.7, 2.1)),
            fbm3(p + vec3(2.9, 17.1, 8.4))
        );
        // fBm clusters hard around the mean; stretch it to use the whole turn.
        return (f - 0.5) * 2.5 + 0.5;
    }

    if (mode == FIELD_NORMAL) {
        // Orientation alone: every face direction is its own colour space, so
        // the form of the terrain is what you read. Already normalised.
        return chunk_normal * 0.5 + 0.5;
    }

    vec2 centred = gl_FragCoord.xy - 0.5 * viewport.xy;
    vec2 uv = centred / max(viewport.y, 1.0) * scale + 0.5;
    return vec3(blurred(uv));
}

void main() {
    if (uint(trip.w) == FIELD_RAW) {
        // Straight to screen, no rotation and no blur, so the producer can be
        // judged on its own rather than through the terrain and colour space.
        vec2 uv = gl_FragCoord.xy / max(viewport.xy, vec2(1.0));
        vec4 t = texture(perception_field, uv);
        float v = t.g * trip.y;
        if (uint(field_info.x) == PRODUCER_CYCLIC) {
            v = fract(atan(t.g, t.r) / (2.0 * PI) + 1.0);
        }
        color = vec4(vec3(v), 1.0);
        return;
    }

    float levels[5] = unpack_channels(voxel_value);

    vec3 drive = vec3(0.0);
    if (trip.x > 0.5) {
        drive = clamp(drivers(), 0.0, 1.0);
    }

    color = vec4(display(levels, drive, node_turn) * occlusion * shade, 1.0);
}
