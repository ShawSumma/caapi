#version 450

#include "common.h"
#include "draw.h"
#include "face.h"

const uint VERTICES_PER_FACE = 6;
const uint FIRST_SOLID_MATERIAL = 1;
const uint BITS_PER_WORD = 32;
const float SHADE_FACING_SUN = 1.0;
const float SHADE_AWAY = 0.5;

layout(location = 0) out vec3 texcoords;
layout(location = 1) out float brightness;
layout(location = 2) flat out float glowing;

layout(set = 1, binding = 0) readonly restrict buffer Faces {
    Face faces[];
};

layout(set = 1, binding = 2) readonly restrict buffer Transforms {
    DrawTransform draws[];
};

layout(push_constant) uniform PushConstants {
    uint dimension;
    float cell_ratio;
    uint glowing_materials[3];
};

uvec2 face_corner(uint vertex, bool is_reversed, bool is_flipped) {
    uint step = vertex;
    if (vertex >= 3) {
        step = (vertex - 1) % 4;
    }
    uvec2 corner = uvec2(step >> 1, ((step + 1) >> 1) & 1);
    if (is_reversed != is_flipped) {
        corner = corner.yx;
    }
    if (is_flipped) {
        corner.y = 1 - corner.y;
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

// The covector of the plane through the point and two directions in the cube's projective coordinates gives the face's
// normal without knowing its side: back faces are culled, so the eye is always on the outward side. Far from the frame
// origin float rounding can leave the norms without a sign; those faces take the middle shade and are deep in fog.
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
    Face face = faces[gl_VertexIndex / VERTICES_PER_FACE];
    DrawTransform draw = draws[gl_InstanceIndex];
    uint code = face_code(face);
    uint axis = code & AXIS_MASK;
    bool is_reversed = ((code & REVERSED_BIT) != 0) != (draw.reversed.x != 0.0);
    uvec2 corner = face_corner(gl_VertexIndex % VERTICES_PER_FACE, is_reversed, (code & FLIPPED_BIT) != 0);
    uint material = face_material(face);
    texcoords = vec3(corner, material - FIRST_SOLID_MATERIAL);
    uvec3 grid = face_position(face);
    grid[(axis + 1) % 3] += corner.x;
    grid[(axis + 2) % 3] += corner.y;
    vec3 cube = vec3(grid) / float(dimension);
    if (cell_ratio != 1.0) {
        cube = (1.0 - pow(vec3(cell_ratio), vec3(grid))) / (1.0 - pow(cell_ratio, float(dimension)));
    }
    vec4 point = draw.transform * vec4(cube, 1);
    float shade = mix(SHADE_AWAY, SHADE_FACING_SUN, 0.5 + 0.5 * facing_sun(point, draw.transform[(axis + 1) % 3], draw.transform[(axis + 2) % 3]));
    brightness = face_occlusion(face, corner) * shade;
    glowing = float((glowing_materials[material / BITS_PER_WORD] >> (material % BITS_PER_WORD)) & 1u);
    gl_Position = projection * camera_inverse * point;
}
