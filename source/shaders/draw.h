#ifndef DRAW_H
#define DRAW_H

// Where one of a node's twenty cubes sits in the node, and the center its culling sphere is around.
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
