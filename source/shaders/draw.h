#ifndef DRAW_H
#define DRAW_H

struct ChunkVertex {
    mat4 chunk_to_node;
    vec4 sphere_center;
};

struct Drawable {
    uint node;
    uint vertex;
    uint face_offset;
    uint face_count;
};

struct DrawTransform {
    mat4 transform;
    vec4 reversed;
};

struct DrawCommand {
    uint vertex_count;
    uint instance_count;
    uint first_vertex;
    uint first_instance;
};

#endif
