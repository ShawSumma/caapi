module client.graphics.highlight;

import bindings.platform : VK_PIPELINE_BIND_POINT_GRAPHICS, VK_PRIMITIVE_TOPOLOGY_LINE_LIST, VK_SHADER_STAGE_VERTEX_BIT, VkCommandBuffer, VkDevice, VkPipeline, VkPipelineLayout, VkPushConstantRange, VkRenderPass, VkShaderModule, vkCmdBindPipeline, vkCmdDraw, vkCmdPushConstants, vkDestroyPipeline, vkDestroyPipelineLayout, vkDestroyShaderModule;
import client.graphics.pipeline : PipelineSettings, createGraphicsPipeline, createPipelineLayout, createShader;

enum string HIGHLIGHT_VERT_SPV = import("highlight.vert.spv");
enum string HIGHLIGHT_FRAG_SPV = import("highlight.frag.spv");
enum uint HIGHLIGHT_PUSH_FLOATS = 20;
enum uint HIGHLIGHT_PUSH_BYTES = HIGHLIGHT_PUSH_FLOATS * 4;
enum uint CUBE_EDGE_VERTICES = 24;
enum uint MVP_FLOATS = 16;

struct HighlightPipeline {
    VkPipelineLayout pipelineLayout;
    VkPipeline pipeline;

    void setup(VkDevice device, VkRenderPass renderPass) {
        VkShaderModule vertexShader = createShader(device, HIGHLIGHT_VERT_SPV);
        VkShaderModule fragmentShader = createShader(device, HIGHLIGHT_FRAG_SPV);
        VkPushConstantRange[1] pushConstants = [
            VkPushConstantRange(VK_SHADER_STAGE_VERTEX_BIT, 0, HIGHLIGHT_PUSH_BYTES),
        ];
        pipelineLayout = createPipelineLayout(device, null, pushConstants[]);
        PipelineSettings settings;
        settings.layout = pipelineLayout;
        settings.renderPass = renderPass;
        settings.vertexShader = vertexShader;
        settings.fragmentShader = fragmentShader;
        settings.topology = VK_PRIMITIVE_TOPOLOGY_LINE_LIST;
        settings.isDepthTested = true;
        pipeline = createGraphicsPipeline(device, settings);
        vkDestroyShaderModule(device, vertexShader, null);
        vkDestroyShaderModule(device, fragmentShader, null);
    }

    void draw(VkCommandBuffer commands, float[16] mvp, float[3] voxelCoords, float dimension) {
        float[HIGHLIGHT_PUSH_FLOATS] constants;
        constants[0 .. MVP_FLOATS] = mvp[];
        constants[MVP_FLOATS .. MVP_FLOATS + 3] = voxelCoords[];
        constants[MVP_FLOATS + 3] = dimension;
        vkCmdBindPipeline(commands, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
        vkCmdPushConstants(commands, pipelineLayout, VK_SHADER_STAGE_VERTEX_BIT, 0, HIGHLIGHT_PUSH_BYTES, constants.ptr);
        vkCmdDraw(commands, CUBE_EDGE_VERTICES, 1, 0, 0);
    }

    void cleanup(VkDevice device) {
        vkDestroyPipeline(device, pipeline, null);
        vkDestroyPipelineLayout(device, pipelineLayout, null);
    }
}
