#version 450

#include "common.h"

layout(location = 0) in vec2 texcoords;

layout(location = 0) out vec4 fog;

layout(input_attachment_index=0, set=0, binding=1) uniform subpassInput depth;

void main() {
    vec4 clip_pos = vec4(texcoords * 2.0 - 1.0, subpassLoad(depth).x, 1.0);
    vec4 scaled_view_pos = inverse_projection * clip_pos;
    // Cancel out perspective, obtaining klein ball position
    vec3 view_pos = scaled_view_pos.xyz / scaled_view_pos.w;
    float view_length = length(view_pos);
    // Convert to true hyperbolic distance, taking care to respect atanh's domain
    float dist = view_length >= 1.0 ? INFINITY : atanh(view_length);
    // Exponential^k fog
    fog = vec4(0.5, 0.65, 0.9, exp(-pow(dist * fog_density, 5)));

    // Crosshair overlay, drawn in aspect-corrected NDC so the arms are square.
    float aspect = abs(inverse_projection[0][0] / inverse_projection[1][1]);
    vec2 p = texcoords * 2.0 - 1.0;
    p.x *= aspect;
    float arm = 0.025;
    float thick = 0.004;
    if ((abs(p.x) <= arm && abs(p.y) <= thick) || (abs(p.x) <= thick && abs(p.y) <= arm)) {
        fog = vec4(1.0, 1.0, 1.0, 0.25);
    }
}
