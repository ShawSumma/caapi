const SHADER_HEADER = `#version 300 es
precision highp float;
precision highp int;
precision highp usampler2D;
precision highp sampler2DArray;
`;

const COMMON_BLOCK = `
layout(std140) uniform Common {
    mat4 projection;
    mat4 camera_inverse;
    vec4 frustum_planes[5];
    vec4 fog_color;
    vec4 sun;
    vec4 eye;
    vec2 half_tangents;
    float depth_scale;
    float fog_reach;
    float fog_sharpness;
    float view_parity;
    float cull_sinh_radius;
};
`;

const PLACE_CLIP = `
out vec2 depth_ratio;

void place_clip(vec4 clip) {
    depth_ratio = clip.zw;
    gl_Position = vec4(clip.x, -clip.y, 2.0 * clip.z - clip.w, clip.w);
}
`;

const WRITE_DEPTH = `
in vec2 depth_ratio;

void write_depth() {
    gl_FragDepth = depth_ratio.x / depth_ratio.y;
}
`;

const FULLSCREEN_VERT = SHADER_HEADER + `
const vec2 CORNERS[3] = vec2[3](vec2(0.0, 0.0), vec2(2.0, 0.0), vec2(0.0, 2.0));

out vec2 screen;

void main() {
    screen = CORNERS[gl_VertexID];
    gl_Position = vec4(screen * 2.0 - 1.0, 0.0, 1.0);
}
`;

const VOXELS_VERT = SHADER_HEADER + COMMON_BLOCK + PLACE_CLIP + `
const uint COORD_BITS = 8u;
const uint COORD_MASK = 255u;
const uint AXIS_SHIFT = 24u;
const uint AXIS_MASK = 3u;
const uint REVERSED_BIT = 4u;
const uint FLIPPED_BIT = 8u;
const uint MATERIAL_MASK = 65535u;
const uint WINDOW_SHIFT = 16u;
const uint WINDOW_MASK = 255u;
const uint OCCLUSION_SHIFT = 24u;
const uint OCCLUSION_BITS = 2u;
const uint OCCLUSION_MASK = 3u;
const float OCCLUSION_LEVELS = 3.0;
const float OCCLUSION_DARKEST = 0.05;
const int VERTICES_PER_FACE = 6;
const uint FIRST_SOLID_MATERIAL = 1u;
const uint BITS_PER_WORD = 32u;
const uint WINDOWS_PER_SIDE = 16u;
const float SHADE_FACING_SUN = 1.0;
const float SHADE_AWAY = 0.5;
const int FACE_ROW_SHIFT = 12;
const int FACE_COLUMN_MASK = 4095;

uniform usampler2D faces;
uniform mat4 draw_transform;
uniform float draw_reversed;
uniform uint dimension;
uniform float cell_ratio;
uniform uint glowing_materials[3];
uniform uint framed_material;

out vec3 texcoords;
out float brightness;
flat out float glowing;

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
    int face_index = gl_VertexID / VERTICES_PER_FACE;
    uvec2 face = texelFetch(faces, ivec2(face_index & FACE_COLUMN_MASK, face_index >> FACE_ROW_SHIFT), 0).rg;
    uint code = face.x >> AXIS_SHIFT;
    int axis = int(code & AXIS_MASK);
    bool is_reversed = ((code & REVERSED_BIT) != 0u) != (draw_reversed != 0.0);
    uvec2 corner = face_corner(uint(gl_VertexID % VERTICES_PER_FACE), is_reversed, (code & FLIPPED_BIT) != 0u);
    uint material = face.y & MATERIAL_MASK;
    vec2 on_layer = vec2(corner);
    if (material != framed_material) {
        uint window = (face.y >> WINDOW_SHIFT) & WINDOW_MASK;
        on_layer = (on_layer + vec2(float(window % WINDOWS_PER_SIDE), float(window / WINDOWS_PER_SIDE))) / float(WINDOWS_PER_SIDE);
    }
    texcoords = vec3(on_layer, float(material - FIRST_SOLID_MATERIAL));
    uvec3 grid = uvec3(face.x & COORD_MASK, (face.x >> COORD_BITS) & COORD_MASK, (face.x >> (2u * COORD_BITS)) & COORD_MASK);
    grid[(axis + 1) % 3] += corner.x;
    grid[(axis + 2) % 3] += corner.y;
    vec3 cube = vec3(grid) / float(dimension);
    if (cell_ratio != 1.0) {
        cube = (1.0 - pow(vec3(cell_ratio), vec3(grid))) / (1.0 - pow(cell_ratio, float(dimension)));
    }
    vec4 point = draw_transform * vec4(cube, 1.0);
    float shade = mix(SHADE_AWAY, SHADE_FACING_SUN, 0.5 + 0.5 * facing_sun(point, draw_transform[(axis + 1) % 3], draw_transform[(axis + 2) % 3]));
    uint occlusion_index = corner.x | (corner.y << 1u);
    uint level = (face.y >> (OCCLUSION_SHIFT + OCCLUSION_BITS * occlusion_index)) & OCCLUSION_MASK;
    brightness = mix(OCCLUSION_DARKEST, 1.0, float(level) / OCCLUSION_LEVELS) * shade;
    glowing = float((glowing_materials[material / BITS_PER_WORD] >> (material % BITS_PER_WORD)) & 1u);
    place_clip(projection * camera_inverse * point);
}
`;

const VOXELS_FRAG = SHADER_HEADER + WRITE_DEPTH + `
const float CLEAR_ALPHA = 0.5;

in vec3 texcoords;
in float brightness;
flat in float glowing;

layout(location = 0) out vec4 color;
layout(location = 1) out vec4 glow;

uniform sampler2DArray textures;

void main() {
    vec4 texel = texture(textures, texcoords);
    if (texel.a < CLEAR_ALPHA) {
        discard;
    }
    color = vec4(texel.rgb * mix(brightness, 1.0, glowing), 1.0);
    glow = vec4(glowing);
    write_depth();
}
`;

const HIGHLIGHT_VERT = SHADER_HEADER + COMMON_BLOCK + PLACE_CLIP + `
const vec3 CORNERS[8] = vec3[8](
    vec3(0, 0, 0), vec3(1, 0, 0), vec3(0, 1, 0), vec3(1, 1, 0),
    vec3(0, 0, 1), vec3(1, 0, 1), vec3(0, 1, 1), vec3(1, 1, 1)
);

const int EDGES[24] = int[24](
    0, 1, 1, 3, 3, 2, 2, 0,
    4, 5, 5, 7, 7, 6, 6, 4,
    0, 4, 1, 5, 3, 7, 2, 6
);

const vec3 VOXEL_CENTER = vec3(0.5);
const float OUTLINE_SCALE = 1.01;

uniform mat4 model;
uniform vec3 low;
uniform vec3 high;

void main() {
    vec3 c = VOXEL_CENTER + (CORNERS[EDGES[gl_VertexID]] - VOXEL_CENTER) * OUTLINE_SCALE;
    place_clip(projection * camera_inverse * model * vec4(mix(low, high, c), 1.0));
}
`;

const HIGHLIGHT_FRAG = SHADER_HEADER + WRITE_DEPTH + `
const float EDGE_SRGB = 0.05;
const float SRGB_OFFSET = 0.055;
const float SRGB_GAMMA = 2.4;

layout(location = 0) out vec4 color;
layout(location = 1) out vec4 glow;

void main() {
    float edge = pow((EDGE_SRGB + SRGB_OFFSET) / (1.0 + SRGB_OFFSET), SRGB_GAMMA);
    color = vec4(edge, edge, edge, 1.0);
    glow = vec4(0.0);
    write_depth();
}
`;

const MARKER_VERT = SHADER_HEADER + COMMON_BLOCK + PLACE_CLIP + `
const float SRGB_POWER = 2.2;
const float CHANNEL_MOST = 255.0;

const vec3 CORNERS[8] = vec3[8](
    vec3(-1, -1, -1), vec3(1, -1, -1), vec3(-1, 1, -1), vec3(1, 1, -1),
    vec3(-1, -1, 1), vec3(1, -1, 1), vec3(-1, 1, 1), vec3(1, 1, 1)
);

const int TRIANGLES[36] = int[36](
    0, 1, 3, 3, 2, 0,
    4, 6, 7, 7, 5, 4,
    0, 4, 5, 5, 1, 0,
    2, 3, 7, 7, 6, 2,
    0, 2, 6, 6, 4, 0,
    1, 5, 7, 7, 3, 1
);

uniform mat4 model;
uniform float half_side;
uniform uint marker_color;

out vec3 shade;

void main() {
    vec3 written = vec3(float(marker_color & 255u), float((marker_color >> 8u) & 255u), float((marker_color >> 16u) & 255u)) / CHANNEL_MOST;
    shade = pow(written, vec3(SRGB_POWER));
    place_clip(projection * camera_inverse * model * vec4(CORNERS[TRIANGLES[gl_VertexID]] * half_side, 1.0));
}
`;

const MARKER_FRAG = SHADER_HEADER + WRITE_DEPTH + `
in vec3 shade;

layout(location = 0) out vec4 color;
layout(location = 1) out vec4 glow;

void main() {
    color = vec4(shade, 1.0);
    glow = vec4(1.0);
    write_depth();
}
`;

const FOG_FRAG = SHADER_HEADER + COMMON_BLOCK + `
in vec2 screen;

out vec4 fog;

uniform sampler2D depth_input;
uniform sampler2D glow_input;

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec2 slope = (screen * 2.0 - 1.0) * half_tangents;
    float klein_depth = depth_scale / (texelFetch(depth_input, pixel, 0).r + depth_scale);
    float radius = klein_depth * sqrt(1.0 + dot(slope, slope));
    float kept = 0.0;
    if (radius < 1.0) {
        kept = exp(-pow(atanh(radius) / fog_reach, fog_sharpness));
    }
    fog = vec4(fog_color.rgb, mix(kept, 1.0, texelFetch(glow_input, pixel, 0).r));
}
`;

const CROSSHAIR_VERT = SHADER_HEADER + `
const float ARM_HALF_LENGTH = 0.025;
const float ARM_HALF_THICKNESS = 0.004;
const int VERTICES_PER_ARM = 6;

const vec4 ARMS[3] = vec4[3](
    vec4(-ARM_HALF_LENGTH, -ARM_HALF_THICKNESS, ARM_HALF_LENGTH, ARM_HALF_THICKNESS),
    vec4(-ARM_HALF_THICKNESS, ARM_HALF_THICKNESS, ARM_HALF_THICKNESS, ARM_HALF_LENGTH),
    vec4(-ARM_HALF_THICKNESS, -ARM_HALF_LENGTH, ARM_HALF_THICKNESS, -ARM_HALF_THICKNESS)
);

const vec2 CORNERS[6] = vec2[6](
    vec2(0, 0),
    vec2(1, 0),
    vec2(1, 1),
    vec2(1, 1),
    vec2(0, 1),
    vec2(0, 0)
);

uniform float width_over_height;

void main() {
    vec4 arm = ARMS[gl_VertexID / VERTICES_PER_ARM];
    vec2 position = mix(arm.xy, arm.zw, CORNERS[gl_VertexID % VERTICES_PER_ARM]);
    gl_Position = vec4(position.x / width_over_height, -position.y, 0.0, 1.0);
}
`;

const CROSSHAIR_FRAG = SHADER_HEADER + `
const float CROSSHAIR_OPACITY = 0.75;

out vec4 color;

void main() {
    color = vec4(1.0, 1.0, 1.0, CROSSHAIR_OPACITY);
}
`;

const HUD_VERT = SHADER_HEADER + `
const float SRGB_POWER = 2.2;

layout(location = 0) in vec2 at;
layout(location = 1) in vec4 written;

out vec4 shade;

void main() {
    shade = vec4(pow(written.rgb, vec3(SRGB_POWER)), written.a);
    gl_Position = vec4(at.x, -at.y, 0.0, 1.0);
}
`;

const HUD_FRAG = SHADER_HEADER + `
in vec4 shade;

out vec4 color;

void main() {
    color = shade;
}
`;

const PRESENT_FRAG = SHADER_HEADER + `
const float SRGB_LINEAR_LIMIT = 0.0031308;
const float SRGB_LINEAR_SLOPE = 12.92;
const float SRGB_OFFSET = 0.055;
const float SRGB_GAMMA = 2.4;

in vec2 screen;

out vec4 color;

uniform sampler2D image;

vec3 encoded(vec3 linear) {
    vec3 low = linear * SRGB_LINEAR_SLOPE;
    vec3 high = (1.0 + SRGB_OFFSET) * pow(linear, vec3(1.0 / SRGB_GAMMA)) - SRGB_OFFSET;
    return mix(high, low, vec3(lessThanEqual(linear, vec3(SRGB_LINEAR_LIMIT))));
}

void main() {
    color = vec4(encoded(texelFetch(image, ivec2(gl_FragCoord.xy), 0).rgb), 1.0);
}
`;
