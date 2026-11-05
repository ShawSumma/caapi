#ifndef FACE_H
#define FACE_H

const uint COORD_BITS = 8u;
const uint COORD_MASK = (1u << COORD_BITS) - 1u;
const uint AXIS_SHIFT = 3u * COORD_BITS;
const uint AXIS_MASK = 3u;
const uint REVERSED_BIT = 1u << 2u;
const uint FLIPPED_BIT = 1u << 3u;
const uint MATERIAL_MASK = 0xFFFFu;
const uint WINDOW_SHIFT = 16u;
const uint WINDOW_MASK = 0xFFu;
const uint OCCLUSION_SHIFT = 24u;
const uint OCCLUSION_BITS = 2u;
const uint OCCLUSION_MASK = (1u << OCCLUSION_BITS) - 1u;
const uint OCCLUSION_LEVELS = OCCLUSION_MASK;
const float OCCLUSION_DARKEST = 0.05;

struct Face {
    uint pos_axis;
    uint occlusion_material;
};

uvec3 face_position(Face face) {
    return uvec3(face.pos_axis & COORD_MASK, (face.pos_axis >> COORD_BITS) & COORD_MASK, (face.pos_axis >> (2u * COORD_BITS)) & COORD_MASK);
}

uint face_code(Face face) {
    return face.pos_axis >> AXIS_SHIFT;
}

uint face_material(Face face) {
    return face.occlusion_material & MATERIAL_MASK;
}

uint face_window(Face face) {
    return (face.occlusion_material >> WINDOW_SHIFT) & WINDOW_MASK;
}

float face_occlusion(Face face, uvec2 corner) {
    uint index = corner.x | corner.y << 1u;
    uint level = (face.occlusion_material >> (OCCLUSION_SHIFT + OCCLUSION_BITS * index)) & OCCLUSION_MASK;
    return mix(OCCLUSION_DARKEST, 1.0, float(level) / float(OCCLUSION_LEVELS));
}

#endif
