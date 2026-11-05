#ifndef TARGET_H
#define TARGET_H

#ifdef GL_ES
precision highp float;
precision highp int;
precision highp sampler2D;
precision highp sampler2DArray;
precision highp usampler2D;
layout(std140) uniform;
#define BOUND(set_index, binding_index)
#define STAGE_LINK(index)
#define PUSH_BEGIN
#define PUSHED uniform
#define PUSH_END
#define VERTEX_INDEX gl_VertexID
#define SCREEN_Y(y) (-(y))
#else
#define BOUND(set_index, binding_index) layout(set = set_index, binding = binding_index)
#define STAGE_LINK(index) layout(location = index)
#define PUSH_BEGIN layout(push_constant) uniform PushConstants {
#define PUSHED
#define PUSH_END };
#define VERTEX_INDEX gl_VertexIndex
#define SCREEN_Y(y) (y)
#endif

#endif
