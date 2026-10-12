#ifndef FACE_H
#define FACE_H

const uint COORD_BITS = 8;
const uint COORD_MASK = (1u << COORD_BITS) - 1u;
const uint AXIS_SHIFT = 3 * COORD_BITS;
const uint AXIS_MASK = 3u;
const uint REVERSED_BIT = 1u << 2;
const uint FLIPPED_BIT = 1u << 3;
const uint MATERIAL_MASK = 0xFFFFu;
const uint OCCLUSION_SHIFT = 24;
const uint OCCLUSION_BITS = 2;
const uint OCCLUSION_MASK = (1u << OCCLUSION_BITS) - 1u;
const uint OCCLUSION_LEVELS = OCCLUSION_MASK;
const float OCCLUSION_DARKEST = 0.05;

// Packed by Quad in meshing.d: the cell, then the axis the face looks along, whether it faces down that axis and
// whether its diagonal is flipped; the material, then two bits of shading for each corner.
struct Face {
    uint pos_axis;
    uint occlusion_material;
};

uvec3 face_position(Face face) {
    return uvec3(face.pos_axis & COORD_MASK, (face.pos_axis >> COORD_BITS) & COORD_MASK, (face.pos_axis >> (2 * COORD_BITS)) & COORD_MASK);
}

uint face_code(Face face) {
    return face.pos_axis >> AXIS_SHIFT;
}

uint face_material(Face face) {
    return face.occlusion_material & MATERIAL_MASK;
}

// Corners are numbered by their steps along the face's two in-plane axes, the first axis in the low bit.
float face_occlusion(Face face, uvec2 corner) {
    uint index = corner.x | corner.y << 1;
    uint level = (face.occlusion_material >> (OCCLUSION_SHIFT + OCCLUSION_BITS * index)) & OCCLUSION_MASK;
    return mix(OCCLUSION_DARKEST, 1.0, float(level) / float(OCCLUSION_LEVELS));
}

#endif
