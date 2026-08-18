#version 450

#include "common.h"

layout(location = 0) in vec2 texcoords;

layout(location = 0) out vec4 fog;

layout(input_attachment_index = 0, set = 0, binding = 1) uniform subpassInput depth;

const float HUD_ORIGIN = 12.0;
const float HUD_PAD = 6.0;
const float HUD_CELL = 13.0;
const float HUD_BAR = 9.0;
const float HUD_ROW = 36.0;
const float HUD_GAP = 4.0;
const vec2 HUD_GRID = vec2(
    5.0 * (HUD_CELL + HUD_GAP) - HUD_GAP,
    3.0 * (HUD_ROW + HUD_GAP) - HUD_GAP
);

// One row per primary, five signed bars each: where red, green and blue
// currently sit in channel space. Alpha is how much scene survives, so zero
// is an opaque mark.
vec4 readout(vec2 p) {
    vec2 g = p - HUD_PAD;
    vec4 backing = vec4(0.0, 0.0, 0.0, 0.3);
    if (any(lessThan(g, vec2(0.0))) || any(greaterThanEqual(g, HUD_GRID))) {
        return backing;
    }

    int row = int(floor(g.y / (HUD_ROW + HUD_GAP)));
    int col = int(floor(g.x / (HUD_CELL + HUD_GAP)));
    float y = g.y - float(row) * (HUD_ROW + HUD_GAP);
    float x = g.x - float(col) * (HUD_CELL + HUD_GAP);
    if (y >= HUD_ROW || x >= HUD_CELL) {
        return backing;
    }

    vec3 tint = vec3(0.0);
    tint[row] = 1.0;

    float mid = HUD_ROW * 0.5;
    float end = mid - walk_channel[col][row] * (mid - 1.0);
    bool onBar = abs(x - HUD_CELL * 0.5) < HUD_BAR * 0.5;
    if (onBar && y >= min(mid, end) && y < max(mid, end)) {
        return vec4(tint, 0.0);
    }
    if (abs(y - mid) < 1.0) {
        return vec4(tint * 0.5, 0.1);
    }
    return vec4(tint * 0.12, 0.25);
}

void main() {
    vec4 clip_pos = vec4(texcoords * 2.0 - 1.0, subpassLoad(depth).x, 1.0);
    vec4 scaled_view_pos = inverse_projection * clip_pos;
    // Cancel out perspective, obtaining klein ball position.
    vec3 view_pos = scaled_view_pos.xyz / scaled_view_pos.w;
    float view_length = length(view_pos);

    // Convert to true hyperbolic distance, respecting atanh's domain.
    float dist = INFINITY;
    if (view_length < 1.0) {
        dist = atanh(view_length);
    }

    // Exponential fog raised to a power.
    fog = vec4(0.5, 0.65, 0.9, exp(-pow(dist * fog_density, 5.0)));

    // Crosshair overlay, drawn in aspect-corrected NDC so the arms are square.
    float aspect = abs(inverse_projection[0][0] / inverse_projection[1][1]);
    vec2 p = texcoords * 2.0 - 1.0;
    p.x = p.x * aspect;
    float arm = 0.025;
    float thick = 0.004;
    bool horizontal = abs(p.x) <= arm && abs(p.y) <= thick;
    bool vertical = abs(p.x) <= thick && abs(p.y) <= arm;
    if (horizontal || vertical) {
        fog = vec4(1.0, 1.0, 1.0, 0.25);
    }

    if (walking()) {
        vec2 panel = texcoords * viewport.xy - HUD_ORIGIN;
        if (all(greaterThanEqual(panel, vec2(0.0)))
            && all(lessThan(panel, HUD_GRID + 2.0 * HUD_PAD))) {
            fog = readout(panel);
        }
    }
}
