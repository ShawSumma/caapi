#version 450

#include "target.h"

STAGE_LINK(0) in vec4 shade;
layout(location = 0) out vec4 color;

void main() {
    color = shade;
}
