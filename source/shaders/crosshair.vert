#version 450

const float ARM_HALF_LENGTH = 0.025;
const float ARM_HALF_THICKNESS = 0.004;
const uint VERTICES_PER_ARM = 6;

layout(push_constant) uniform PushConstants {
    float width_over_height;
};

const vec4 ARMS[3] = vec4[](
    vec4(-ARM_HALF_LENGTH, -ARM_HALF_THICKNESS, ARM_HALF_LENGTH, ARM_HALF_THICKNESS),
    vec4(-ARM_HALF_THICKNESS, ARM_HALF_THICKNESS, ARM_HALF_THICKNESS, ARM_HALF_LENGTH),
    vec4(-ARM_HALF_THICKNESS, -ARM_HALF_LENGTH, ARM_HALF_THICKNESS, -ARM_HALF_THICKNESS)
);

const vec2 CORNERS[6] = vec2[](
    vec2(0, 0),
    vec2(1, 0),
    vec2(1, 1),
    vec2(1, 1),
    vec2(0, 1),
    vec2(0, 0)
);

void main() {
    vec4 arm = ARMS[gl_VertexIndex / VERTICES_PER_ARM];
    vec2 position = mix(arm.xy, arm.zw, CORNERS[gl_VertexIndex % VERTICES_PER_ARM]);
    gl_Position = vec4(position.x / width_over_height, position.y, 0.0, 1.0);
}
