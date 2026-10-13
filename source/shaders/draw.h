#ifndef DRAW_H
#define DRAW_H

struct CubeFrame {
    mat4 cube_to_node;
    vec4 center;
};

struct Drawable {
    uint node;
    uint corner;
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
