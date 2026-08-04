#ifndef SURFACE_EXTRACTION_SURFACE_H
#define SURFACE_EXTRACTION_SURFACE_H

struct Surface {
    uint pos_axis;
    uint occlusion_mat;
};

uvec3 get_pos(Surface s) {
    uint x = s.pos_axis & 0xFFu;
    uint y = (s.pos_axis >> 8) & 0xFFu;
    uint z = (s.pos_axis >> 16) & 0xFFu;
    return uvec3(x, y, z);
}

uint get_axis(Surface s) {
    return s.pos_axis >> 24;
}

uint get_mat(Surface s) {
    return s.occlusion_mat & 0xFFFFu;
}

float get_occlusion(Surface s, uvec2 texcoords) {
    uint corner = texcoords.x | (texcoords.y << 1);
    uint level = (s.occlusion_mat >> (24u + 2u * corner)) & 0x03u;
    return float(level) / 3.0 * 0.95 + 0.05;
}

Surface surface(uvec3 pos, uint axis, bool reverse, uint mat, uvec4 occlusion) {
    // Faces pointing the other way sit three rows further down the vertex
    // table, and a further six when the two diagonals disagree, which is what
    // picks the triangulation that hides the occlusion seam.
    uint oriented = axis;
    if (reverse) {
        oriented = oriented + 3u;
    }
    if (occlusion.y + occlusion.z > occlusion.x + occlusion.w) {
        oriented = oriented + 6u;
    }

    uint packed_occlusion = occlusion.x << 24;
    packed_occlusion = packed_occlusion | (occlusion.y << 26);
    packed_occlusion = packed_occlusion | (occlusion.z << 28);
    packed_occlusion = packed_occlusion | (occlusion.w << 30);

    Surface result;
    result.pos_axis = pos.x | (pos.y << 8) | (pos.z << 16) | (oriented << 24);
    result.occlusion_mat = mat | packed_occlusion;
    return result;
}

#endif
