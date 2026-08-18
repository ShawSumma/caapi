#version 460

#include "common.h"
#include "surface-extraction/surface.h"

layout(location = 0) in mat4 transform;
// Low 5 bits: which of the 20 chunks of the node this is. Upper bits: a hash
// of the node's id, which persists as the graph grows and so never moves.
// y packs the node's accumulated turn of the colour space, ten bits an angle.
layout(location = 4) in uvec2 chunk_info;

layout(set = 1, binding = 2) readonly restrict buffer ChunkToNode {
    mat4 chunk_to_node[];
};

layout(location = 0) out flat uint voxel_value;
layout(location = 1) out float occlusion;
layout(location = 2) out flat float shade;
layout(location = 3) out vec3 node_pos;
layout(location = 4) out flat vec3 chunk_normal;
layout(location = 5) out flat uint node_seed;
layout(location = 6) out flat vec3 node_turn;

layout(set = 1, binding = 0) readonly restrict buffer Surfaces {
    Surface surfaces[];
};

layout(push_constant) uniform PushConstants {
    uint dimension;
};

// Rows 0 to 5 face down then up each axis; rows 6 to 11 repeat that with the
// winding reversed.
const uvec3 vertices[12][6] = {
    {{0, 0, 0}, {0, 0, 1}, {0, 1, 1}, {0, 1, 1}, {0, 1, 0}, {0, 0, 0}},
    {{0, 0, 0}, {1, 0, 0}, {1, 0, 1}, {1, 0, 1}, {0, 0, 1}, {0, 0, 0}},
    {{0, 0, 0}, {0, 1, 0}, {1, 1, 0}, {1, 1, 0}, {1, 0, 0}, {0, 0, 0}},
    {{0, 0, 0}, {0, 1, 0}, {0, 1, 1}, {0, 1, 1}, {0, 0, 1}, {0, 0, 0}},
    {{0, 0, 0}, {0, 0, 1}, {1, 0, 1}, {1, 0, 1}, {1, 0, 0}, {0, 0, 0}},
    {{0, 0, 0}, {1, 0, 0}, {1, 1, 0}, {1, 1, 0}, {0, 1, 0}, {0, 0, 0}},
    {{0, 0, 1}, {0, 1, 1}, {0, 1, 0}, {0, 1, 0}, {0, 0, 0}, {0, 0, 1}},
    {{1, 0, 0}, {1, 0, 1}, {0, 0, 1}, {0, 0, 1}, {0, 0, 0}, {1, 0, 0}},
    {{0, 1, 0}, {1, 1, 0}, {1, 0, 0}, {1, 0, 0}, {0, 0, 0}, {0, 1, 0}},
    {{0, 0, 1}, {0, 0, 0}, {0, 1, 0}, {0, 1, 0}, {0, 1, 1}, {0, 0, 1}},
    {{1, 0, 0}, {0, 0, 0}, {0, 0, 1}, {0, 0, 1}, {1, 0, 1}, {1, 0, 0}},
    {{0, 1, 0}, {0, 0, 0}, {1, 0, 0}, {1, 0, 0}, {1, 1, 0}, {0, 1, 0}},
};

const uvec2 texcoords[4][6] = {
    {{0, 0}, {0, 1}, {1, 1}, {1, 1}, {1, 0}, {0, 0}},
    {{0, 0}, {1, 0}, {1, 1}, {1, 1}, {0, 1}, {0, 0}},
    {{0, 1}, {1, 1}, {1, 0}, {1, 0}, {0, 0}, {0, 1}},
    {{0, 1}, {0, 0}, {1, 0}, {1, 0}, {1, 1}, {0, 1}},
};

float voxel_noise(uvec3 p) {
    uint h = p.x * 374761393u + p.y * 668265263u + p.z * 3266489917u;
    h = (h ^ (h >> 13)) * 1274126177u;
    h = h ^ (h >> 16);
    return float(h & 0xFFFFu) / 65535.0;
}

void main() {
    uint index = gl_VertexIndex / 6u;
    uint vertex = gl_VertexIndex % 6u;
    Surface s = surfaces[index];
    uvec3 pos = get_pos(s);
    uint axis = get_axis(s);

    // The winding flip below depends on a camera-relative determinant, so it
    // moves as the player does. Keep the unflipped axis for anything that has
    // to stay put.
    uint stable_axis = axis;
    float det4 = determinant(view_projection * transform);
    if (det4 < 0.0) {
        if (axis < 3u) {
            axis = axis + 3u;
        } else if (axis < 6u) {
            axis = axis - 3u;
        } else if (axis < 9u) {
            axis = axis + 3u;
        } else {
            axis = axis - 3u;
        }
    }

    uvec2 uv = texcoords[axis / 3u][vertex];

    // Spread the material enum across the 241 non-reserved values so the
    // five-trit tuples actually vary. 97 is coprime with 241, so this is a
    // bijection, and the offset of one keeps black and white out of reach.
    voxel_value = 1u + (get_mat(s) * 97u) % 241u;
    shade = mix(0.85, 1.15, voxel_noise(pos));
    occlusion = get_occlusion(s, uv);

    vec3 relative_coords = vertices[axis][vertex] + pos;
    vec3 chunk_pos = relative_coords / dimension;

    // Node-local: one frame covering all 20 chunks of a node, so a field
    // evaluated here runs continuously across chunk seams instead of tiling
    // per chunk. It is fixed to the node, not to the camera, so unlike
    // anything built from the transform it does not shift when the player
    // crosses into the next node.
    vec4 np = chunk_to_node[chunk_info.x & 31u] * vec4(chunk_pos, 1.0);
    node_pos = np.xyz / max(np.w, 1e-4);
    node_seed = chunk_info.x >> 5u;
    node_turn = vec3(
        float(chunk_info.y & 1023u),
        float((chunk_info.y >> 10u) & 1023u),
        float((chunk_info.y >> 20u) & 1023u)
    ) * (2.0 * PI / 1024.0);

    // Faces 0 to 2 and 6 to 8 point down their axis, 3 to 5 and 9 to 11 point
    // up it. No transform is applied: the linear part of a Lorentz isometry
    // shears, and there is no global parallel frame to carry a normal into.
    uint normal_axis = stable_axis % 3u;
    chunk_normal = vec3(0.0);
    if ((stable_axis / 3u) % 2u == 1u) {
        chunk_normal[normal_axis] = 1.0;
    } else {
        chunk_normal[normal_axis] = -1.0;
    }

    gl_Position = view_projection * transform * vec4(chunk_pos, 1.0);
}
