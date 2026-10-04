#ifndef FACE_H
#define FACE_H

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

struct Face {
    uint pos_axis;
    uint occlusion_material;
};

uvec3 face_position(Face face) {
    return uvec3(face.pos_axis & COORD_MASK, (face.pos_axis >> COORD_BITS) & COORD_MASK, (face.pos_axis >> (2 * COORD_BITS)) & COORD_MASK);
}

uint face_axis(Face face) {
    return face.pos_axis >> AXIS_SHIFT;
}

uint face_material(Face face) {
    return face.occlusion_material & MATERIAL_MASK;
}

float face_occlusion(Face face, uvec2 texcoords) {
    uint corner = texcoords.x | texcoords.y << 1;
    uint level = (face.occlusion_material >> (OCCLUSION_SHIFT + OCCLUSION_BITS * corner)) & OCCLUSION_MASK;
    return mix(OCCLUSION_DARKEST, 1.0, float(level) / float(OCCLUSION_LEVELS));
}

#endif
