#ifndef SURFACE_EXTRACTION_SURFACE_H_
#define SURFACE_EXTRACTION_SURFACE_H_

const uint COORD_BITS = 8;
const uint COORD_MASK = (1u << COORD_BITS) - 1u;
const uint AXIS_SHIFT = 3 * COORD_BITS;
const uint MATERIAL_MASK = 0xFFFFu;
const uint OCCLUSION_SHIFT = 24;
const uint OCCLUSION_BITS = 2;
const uint OCCLUSION_MASK = (1u << OCCLUSION_BITS) - 1u;
const uint OCCLUSION_LEVELS = OCCLUSION_MASK;
const float OCCLUSION_DARKEST = 0.05;
const uint AXES = 3;
const uint REVERSED_AXIS_OFFSET = AXES;
const uint FLIPPED_DIAGONAL_OFFSET = 2 * AXES;

struct Surface {
    uint pos_axis;
    uint occlusion_mat;
};

uvec3 get_pos(Surface s) {
    return uvec3(s.pos_axis & COORD_MASK, (s.pos_axis >> COORD_BITS) & COORD_MASK, (s.pos_axis >> (2 * COORD_BITS)) & COORD_MASK);
}

uint get_axis(Surface s) {
    return s.pos_axis >> AXIS_SHIFT;
}

uint get_mat(Surface s) {
    return s.occlusion_mat & MATERIAL_MASK;
}

float get_occlusion(Surface s, uvec2 texcoords) {
    uint corner = texcoords.x | texcoords.y << 1;
    uint level = (s.occlusion_mat >> (OCCLUSION_SHIFT + OCCLUSION_BITS * corner)) & OCCLUSION_MASK;
    return mix(OCCLUSION_DARKEST, 1.0, float(level) / float(OCCLUSION_LEVELS));
}

Surface surface(uvec3 pos, uint axis, bool reverse, uint mat, uvec4 occlusion) {
    Surface result;
    axis += REVERSED_AXIS_OFFSET * uint(reverse) + FLIPPED_DIAGONAL_OFFSET * uint(occlusion.y + occlusion.z > occlusion.x + occlusion.w);
    result.pos_axis = pos.x | pos.y << COORD_BITS | pos.z << (2 * COORD_BITS) | axis << AXIS_SHIFT;
    result.occlusion_mat = mat | occlusion.x << OCCLUSION_SHIFT | occlusion.y << (OCCLUSION_SHIFT + OCCLUSION_BITS) | occlusion.z << (OCCLUSION_SHIFT + 2 * OCCLUSION_BITS) | occlusion.w << (OCCLUSION_SHIFT + 3 * OCCLUSION_BITS);
    return result;
}

#endif
