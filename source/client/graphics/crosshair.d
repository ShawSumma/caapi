module client.graphics.crosshair;

import bindings.platform : VK_PIPELINE_BIND_POINT_GRAPHICS, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, VK_SHADER_STAGE_VERTEX_BIT, VkCommandBuffer, VkDevice, VkPipeline, VkPipelineLayout, VkPushConstantRange, VkRenderPass, VkShaderModule, vkCmdBindPipeline, vkCmdDraw, vkCmdPushConstants, vkDestroyPipeline, vkDestroyPipelineLayout, vkDestroyShaderModule;
import client.graphics.pipeline : Blend, PipelineSettings, createGraphicsPipeline, createPipelineLayout, createShader;

enum string CROSSHAIR_VERT_SPV = import("crosshair.vert.spv");
enum string CROSSHAIR_FRAG_SPV = import("crosshair.frag.spv");
enum uint CROSSHAIR_VERTICES = 18;
enum uint CROSSHAIR_SUBPASS = 1;

struct CrosshairPipeline {
    VkPipelineLayout pipelineLayout;
    VkPipeline pipeline;

    void setup(VkDevice device, VkRenderPass renderPass) {
        VkShaderModule vertexShader = createShader(device, CROSSHAIR_VERT_SPV);
        VkShaderModule fragmentShader = createShader(device, CROSSHAIR_FRAG_SPV);
        VkPushConstantRange[1] pushConstants = [
            VkPushConstantRange(VK_SHADER_STAGE_VERTEX_BIT, 0, float.sizeof),
        ];
        pipelineLayout = createPipelineLayout(device, null, pushConstants[]);
        PipelineSettings settings;
        settings.layout = pipelineLayout;
        settings.renderPass = renderPass;
        settings.vertexShader = vertexShader;
        settings.fragmentShader = fragmentShader;
        settings.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
        settings.subpass = CROSSHAIR_SUBPASS;
        settings.blend = Blend.alpha;
        pipeline = createGraphicsPipeline(device, settings);
        vkDestroyShaderModule(device, vertexShader, null);
        vkDestroyShaderModule(device, fragmentShader, null);
    }

    void draw(VkCommandBuffer commands, float widthOverHeight) {
        vkCmdBindPipeline(commands, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
        vkCmdPushConstants(commands, pipelineLayout, VK_SHADER_STAGE_VERTEX_BIT, 0, float.sizeof, &widthOverHeight);
        vkCmdDraw(commands, CROSSHAIR_VERTICES, 1, 0, 0);
    }

    void cleanup(VkDevice device) {
        vkDestroyPipeline(device, pipeline, null);
        vkDestroyPipelineLayout(device, pipelineLayout, null);
    }
}
