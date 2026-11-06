module client.graphics.fog;

import bindings.platform : VK_PIPELINE_BIND_POINT_GRAPHICS, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, VkCommandBuffer, VkDescriptorSet, VkDescriptorSetLayout, VkDevice, VkPipeline, VkPipelineLayout, VkRenderPass, VkShaderModule, vkCmdBindDescriptorSets, vkCmdBindPipeline, vkCmdDraw, vkDestroyPipeline, vkDestroyPipelineLayout, vkDestroyShaderModule;
import client.graphics.pipeline : Blend, Culling, Depth, Outputs, PipelineSettings, createGraphicsPipeline, createPipelineLayout, createShader;

enum string FULLSCREEN_VERT_SPV = import("fullscreen.vert.spv");
enum string FOG_FRAG_SPV = import("fog.frag.spv");
enum uint FULLSCREEN_TRIANGLE_VERTICES = 3;
enum uint FOG_SUBPASS = 1;

struct FogPipeline {
    VkPipelineLayout pipelineLayout;
    VkPipeline pipeline;

    void setup(VkDevice device, VkRenderPass renderPass, VkDescriptorSetLayout commonLayout) {
        VkShaderModule vertexShader = createShader(device, FULLSCREEN_VERT_SPV);
        VkShaderModule fragmentShader = createShader(device, FOG_FRAG_SPV);
        VkDescriptorSetLayout[1] setLayouts = [
            commonLayout,
        ];
        pipelineLayout = createPipelineLayout(device, setLayouts[], null);
        PipelineSettings settings = PipelineSettings(
            pipelineLayout,
            renderPass,
            vertexShader,
            fragmentShader,
            VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            FOG_SUBPASS,
            Blend.transmittance,
            Depth.ignored,
            Culling.none,
            Outputs.color,
        );
        pipeline = createGraphicsPipeline(device, settings);
        vkDestroyShaderModule(device, vertexShader, null);
        vkDestroyShaderModule(device, fragmentShader, null);
    }

    void draw(VkCommandBuffer commands, VkDescriptorSet commonSet) {
        vkCmdBindPipeline(commands, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
        vkCmdBindDescriptorSets(commands, VK_PIPELINE_BIND_POINT_GRAPHICS, pipelineLayout, 0, 1, &commonSet, 0, null);
        vkCmdDraw(commands, FULLSCREEN_TRIANGLE_VERTICES, 1, 0, 0);
    }

    void cleanup(VkDevice device) {
        vkDestroyPipeline(device, pipeline, null);
        vkDestroyPipelineLayout(device, pipelineLayout, null);
    }
}
