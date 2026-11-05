#version 450

#include "target.h"
#include "common.h"
#include "draw.h"
#include "face.h"
#include "clip.h"

const uint VERTICES_PER_FACE = 6u;
const uint FIRST_SOLID_MATERIAL = 1u;
const uint BITS_PER_WORD = 32u;
const uint WINDOWS_PER_SIDE = 16u;
const float SHADE_FACING_SUN = 1.0;
const float SHADE_AWAY = 0.5;

STAGE_LINK(0) out vec3 texcoords;
STAGE_LINK(1) out float brightness;
STAGE_LINK(2) flat out float glowing;

#ifdef GL_ES
const uint FACE_ROW_SHIFT = 12u;
const uint FACE_COLUMN_MASK = 4095u;

uniform usampler2D face_texture;
uniform DrawTransform current_draw;

Face load_face(uint index) {
    uvec2 words = texelFetch(face_texture, ivec2(index & FACE_COLUMN_MASK, index >> FACE_ROW_SHIFT), 0).rg;
    return Face(words.x, words.y);
}

DrawTransform load_draw() {
    return current_draw;
}
#else
BOUND(1, 0) readonly restrict buffer Faces {
    Face faces[];
};

BOUND(1, 2) readonly restrict buffer Transforms {
    DrawTransform draws[];
};

Face load_face(uint index) {
    return faces[index];
}

DrawTransform load_draw() {
    return draws[gl_InstanceIndex];
}
#endif

PUSH_BEGIN
    PUSHED uint dimension;
    PUSHED float cell_ratio;
    PUSHED uint glowing_materials[3];
    PUSHED uint framed_material;
PUSH_END

uvec2 face_corner(uint vertex_index, bool is_reversed, bool is_flipped) {
    uint step_index = vertex_index;
    if (vertex_index >= 3u) {
        step_index = (vertex_index - 1u) % 4u;
    }
    uvec2 corner = uvec2(step_index >> 1u, ((step_index + 1u) >> 1u) & 1u);
    if (is_reversed != is_flipped) {
        corner = corner.yx;
    }
    if (is_flipped) {
        corner.y = 1u - corner.y;
    }
    return corner;
}

vec4 cross4(vec4 a, vec4 b, vec4 c) {
    return vec4(
        dot(a.yzw, cross(b.yzw, c.yzw)),
        -dot(a.xzw, cross(b.xzw, c.xzw)),
        dot(a.xyw, cross(b.xyw, c.xyw)),
        -dot(a.xyz, cross(b.xyz, c.xyz))
    );
}

float minkowski(vec4 a, vec4 b) {
    return dot(a.xyz, b.xyz) - a.w * b.w;
}

float facing_sun(vec4 point, vec4 along, vec4 across) {
    vec4 plane = cross4(point, along, across);
    if (dot(plane, eye) < 0.0) {
        plane = -plane;
    }
    float plane_norm = dot(plane.xyz, plane.xyz) - plane.w * plane.w;
    float point_norm = -minkowski(point, point);
    float toward = -minkowski(sun, point);
    if (plane_norm <= 0.0 || point_norm <= 0.0 || toward <= 0.0) {
        return 0.0;
    }
    return clamp(dot(plane, sun) * sqrt(point_norm / plane_norm) / toward, -1.0, 1.0);
}

void main() {
    uint vertex_index = uint(VERTEX_INDEX);
    Face face = load_face(vertex_index / VERTICES_PER_FACE);
    DrawTransform draw = load_draw();
    uint code = face_code(face);
    uint axis = code & AXIS_MASK;
    uvec2 corner = face_corner(vertex_index % VERTICES_PER_FACE, ((code & REVERSED_BIT) != 0u) != (draw.reversed.x != 0.0), (code & FLIPPED_BIT) != 0u);
    uint material = face_material(face);
    vec2 on_layer = vec2(corner);
    if (material != framed_material) {
        uint window = face_window(face);
        on_layer = (on_layer + vec2(window % WINDOWS_PER_SIDE, window / WINDOWS_PER_SIDE)) / float(WINDOWS_PER_SIDE);
    }
    texcoords = vec3(on_layer, float(material - FIRST_SOLID_MATERIAL));
    uvec3 grid = face_position(face);
    grid[(axis + 1u) % 3u] += corner.x;
    grid[(axis + 2u) % 3u] += corner.y;
    vec3 cube = vec3(grid) / float(dimension);
    if (cell_ratio != 1.0) {
        cube = (1.0 - pow(vec3(cell_ratio), vec3(grid))) / (1.0 - pow(cell_ratio, float(dimension)));
    }
    vec4 point = draw.transform * vec4(cube, 1.0);
    float shade = mix(SHADE_AWAY, SHADE_FACING_SUN, 0.5 + 0.5 * facing_sun(point, draw.transform[(axis + 1u) % 3u], draw.transform[(axis + 2u) % 3u]));
    brightness = face_occlusion(face, corner) * shade;
    glowing = float((glowing_materials[material / BITS_PER_WORD] >> (material % BITS_PER_WORD)) & 1u);
    place_clip(projection * camera_inverse * point);
}
