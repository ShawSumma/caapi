module client.graphics.highlight;

import bindings.platform : VK_PIPELINE_BIND_POINT_GRAPHICS, VK_PRIMITIVE_TOPOLOGY_LINE_LIST, VK_SHADER_STAGE_VERTEX_BIT, VkCommandBuffer, VkDescriptorSet, VkDescriptorSetLayout, VkDevice, VkPipeline, VkPipelineLayout, VkPushConstantRange, VkRenderPass, VkShaderModule, vkCmdBindDescriptorSets, vkCmdBindPipeline, vkCmdDraw, vkCmdPushConstants, vkDestroyPipeline, vkDestroyPipelineLayout, vkDestroyShaderModule;
import client.graphics.pipeline : Blend, Culling, Depth, PipelineSettings, createGraphicsPipeline, createPipelineLayout, createShader;

enum string HIGHLIGHT_VERT_SPV = import("highlight.vert.spv");
enum string HIGHLIGHT_FRAG_SPV = import("highlight.frag.spv");
enum uint MODEL_FLOATS = 16;
enum uint CORNER_FLOATS = 4;
enum uint HIGHLIGHT_PUSH_FLOATS = MODEL_FLOATS + 2 * CORNER_FLOATS;
enum uint HIGHLIGHT_PUSH_BYTES = HIGHLIGHT_PUSH_FLOATS * float.sizeof;
enum uint CUBE_EDGE_VERTICES = 24;

struct HighlightPipeline {
    VkPipelineLayout pipelineLayout;
    VkPipeline pipeline;

    void setup(VkDevice device, VkRenderPass renderPass, VkDescriptorSetLayout commonLayout) {
        VkShaderModule vertexShader = createShader(device, HIGHLIGHT_VERT_SPV);
        VkShaderModule fragmentShader = createShader(device, HIGHLIGHT_FRAG_SPV);
        VkDescriptorSetLayout[1] setLayouts = [
            commonLayout,
        ];
        VkPushConstantRange[1] pushConstants = [
            VkPushConstantRange(VK_SHADER_STAGE_VERTEX_BIT, 0, HIGHLIGHT_PUSH_BYTES),
        ];
        pipelineLayout = createPipelineLayout(device, setLayouts[], pushConstants[]);
        PipelineSettings settings = PipelineSettings(
            pipelineLayout,
            renderPass,
            vertexShader,
            fragmentShader,
            VK_PRIMITIVE_TOPOLOGY_LINE_LIST,
            0,
            Blend.opaque,
            Depth.tested,
            Culling.none,
        );
        pipeline = createGraphicsPipeline(device, settings);
        vkDestroyShaderModule(device, vertexShader, null);
        vkDestroyShaderModule(device, fragmentShader, null);
    }

    void draw(VkCommandBuffer commands, VkDescriptorSet commonSet, float[16] model, float[3] low, float[3] high) {
        float[HIGHLIGHT_PUSH_FLOATS] constants = 0;
        constants[0 .. MODEL_FLOATS] = model[];
        constants[MODEL_FLOATS .. MODEL_FLOATS + 3] = low[];
        constants[MODEL_FLOATS + CORNER_FLOATS .. MODEL_FLOATS + CORNER_FLOATS + 3] = high[];
        vkCmdBindPipeline(commands, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
        vkCmdBindDescriptorSets(commands, VK_PIPELINE_BIND_POINT_GRAPHICS, pipelineLayout, 0, 1, &commonSet, 0, null);
        vkCmdPushConstants(commands, pipelineLayout, VK_SHADER_STAGE_VERTEX_BIT, 0, HIGHLIGHT_PUSH_BYTES, constants.ptr);
        vkCmdDraw(commands, CUBE_EDGE_VERTICES, 1, 0, 0);
    }

    void cleanup(VkDevice device) {
        vkDestroyPipeline(device, pipeline, null);
        vkDestroyPipelineLayout(device, pipelineLayout, null);
    }
}
