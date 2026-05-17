#ifndef SURFACE_EXTRACTION_SURFACE_H_
#define SURFACE_EXTRACTION_SURFACE_H_

struct Surface {
    uint pos_axis;
    uint occlusion_mat;
};

uvec3 get_pos(Surface s) {
    return uvec3(s.pos_axis & 0xFF, (s.pos_axis >> 8) & 0xFF, (s.pos_axis >> 16) & 0xFF);
}

uint get_axis(Surface s) {
    return s.pos_axis >> 24;
}

uint get_mat(Surface s) {
    return s.occlusion_mat & 0xFFFF;
}

float get_occlusion(Surface s, uvec2 texcoords) {
    return float((s.occlusion_mat >> (24 + 2 * (texcoords.x | texcoords.y << 1))) & 0x03) / 3.0 * 0.95 + 0.05;
}

Surface surface(uvec3 pos, uint axis, bool reverse, uint mat, uvec4 occlusion) {
    Surface result;
    axis += 3 * uint(reverse) + 6 * uint(occlusion.y + occlusion.z > occlusion.x + occlusion.w);
    result.pos_axis = pos.x | pos.y << 8 | pos.z << 16 | axis << 24;
    result.occlusion_mat = mat | occlusion.x << 24 | occlusion.y << 26 | occlusion.z << 28 | occlusion.w << 30;
    return result;
}

#endif
