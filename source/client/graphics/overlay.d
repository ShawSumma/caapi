module client.graphics.overlay;

import core.stdc.string : memcpy;
import bindings.platform : VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_PIPELINE_BIND_POINT_GRAPHICS, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, VK_SHADER_STAGE_FRAGMENT_BIT, VK_SHADER_STAGE_VERTEX_BIT, VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, VkCommandBuffer, VkDescriptorBufferInfo, VkDescriptorPool, VkDescriptorPoolCreateInfo, VkDescriptorPoolSize, VkDescriptorSet, VkDescriptorSetAllocateInfo, VkDescriptorSetLayout, VkDescriptorSetLayoutBinding, VkDevice, VkPhysicalDevice, VkPipeline, VkPipelineLayout, VkPushConstantRange, VkRenderPass, VkShaderModule, VkWriteDescriptorSet, vkAllocateDescriptorSets, vkCmdBindDescriptorSets, vkCmdBindPipeline, vkCmdDraw, vkCmdPushConstants, vkCreateDescriptorPool, vkDestroyDescriptorPool, vkDestroyDescriptorSetLayout, vkDestroyPipeline, vkDestroyPipelineLayout, vkDestroyShaderModule, vkUpdateDescriptorSets;
import client.graphics.matrices : MATRIX_FLOATS, flatten;
import client.graphics.pipeline : Blend, Culling, Depth, GpuBuffer, PipelineSettings, WHOLE_SIZE, bufferWrite, createGraphicsPipeline, createPipelineLayout, createSetLayout, createShader, expectSuccess, layoutBinding;
import client.hud : HudVertex, MOST_VERTICES, Marker;

enum string HUD_VERT_SPV = import("hud.vert.spv");
enum string HUD_FRAG_SPV = import("hud.frag.spv");
enum string MARKER_VERT_SPV = import("marker.vert.spv");
enum string MARKER_FRAG_SPV = import("marker.frag.spv");
enum uint HUD_SUBPASS = 1;
enum uint MARKER_SUBPASS = 0;
enum uint CUBE_VERTICES = 36;

struct HudPipeline {
    GpuBuffer vertexBuffer;
    VkDescriptorSetLayout setLayout;
    VkDescriptorPool pool;
    VkDescriptorSet set;
    VkPipelineLayout pipelineLayout;
    VkPipeline pipeline;
    uint vertexCount;

    void setup(VkPhysicalDevice physicalDevice, VkDevice device, VkRenderPass renderPass) {
        vertexBuffer = GpuBuffer.makeMapped(physicalDevice, device, MOST_VERTICES * HudVertex.sizeof, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
        VkDescriptorSetLayoutBinding[1] bindings = [
            layoutBinding(0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_VERTEX_BIT),
        ];
        setLayout = createSetLayout(device, bindings[]);
        VkDescriptorPoolSize size = VkDescriptorPoolSize(VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1);
        VkDescriptorPoolCreateInfo poolInfo;
        poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        poolInfo.maxSets = 1;
        poolInfo.poolSizeCount = 1;
        poolInfo.pPoolSizes = &size;
        expectSuccess(vkCreateDescriptorPool(device, &poolInfo, null, &pool));
        VkDescriptorSetAllocateInfo allocateInfo;
        allocateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        allocateInfo.descriptorPool = pool;
        allocateInfo.descriptorSetCount = 1;
        allocateInfo.pSetLayouts = &setLayout;
        expectSuccess(vkAllocateDescriptorSets(device, &allocateInfo, &set));
        VkDescriptorBufferInfo info = VkDescriptorBufferInfo(vertexBuffer.buffer, 0, WHOLE_SIZE);
        VkWriteDescriptorSet write = bufferWrite(set, 0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, &info);
        vkUpdateDescriptorSets(device, 1, &write, 0, null);
        VkShaderModule vertexShader = createShader(device, HUD_VERT_SPV);
        VkShaderModule fragmentShader = createShader(device, HUD_FRAG_SPV);
        VkDescriptorSetLayout[1] setLayouts = [
            setLayout,
        ];
        pipelineLayout = createPipelineLayout(device, setLayouts[], null);
        PipelineSettings settings = PipelineSettings(
            pipelineLayout,
            renderPass,
            vertexShader,
            fragmentShader,
            VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            HUD_SUBPASS,
            Blend.alpha,
            Depth.ignored,
            Culling.none,
        );
        pipeline = createGraphicsPipeline(device, settings);
        vkDestroyShaderModule(device, vertexShader, null);
        vkDestroyShaderModule(device, fragmentShader, null);
    }

    void upload(const(HudVertex)[] vertices) {
        vertexCount = cast(uint) vertices.length;
        memcpy(vertexBuffer.mapped, vertices.ptr, vertices.length * HudVertex.sizeof);
    }

    void draw(VkCommandBuffer commands) {
        if (vertexCount > 0) {
            vkCmdBindPipeline(commands, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
            vkCmdBindDescriptorSets(commands, VK_PIPELINE_BIND_POINT_GRAPHICS, pipelineLayout, 0, 1, &set, 0, null);
            vkCmdDraw(commands, vertexCount, 1, 0, 0);
        }
    }

    void cleanup(VkDevice device) {
        vkDestroyPipeline(device, pipeline, null);
        vkDestroyPipelineLayout(device, pipelineLayout, null);
        vkDestroyDescriptorPool(device, pool, null);
        vkDestroyDescriptorSetLayout(device, setLayout, null);
        vertexBuffer.destroy(device);
    }
}

struct MarkerPush {
    float[MATRIX_FLOATS] model;
    float half;
    uint color;
}

struct MarkerPipeline {
    VkPipelineLayout pipelineLayout;
    VkPipeline pipeline;

    void setup(VkDevice device, VkRenderPass renderPass, VkDescriptorSetLayout commonLayout) {
        VkShaderModule vertexShader = createShader(device, MARKER_VERT_SPV);
        VkShaderModule fragmentShader = createShader(device, MARKER_FRAG_SPV);
        VkDescriptorSetLayout[1] setLayouts = [
            commonLayout,
        ];
        VkPushConstantRange[1] pushConstants = [
            VkPushConstantRange(VK_SHADER_STAGE_VERTEX_BIT, 0, MarkerPush.sizeof),
        ];
        pipelineLayout = createPipelineLayout(device, setLayouts[], pushConstants[]);
        PipelineSettings settings = PipelineSettings(
            pipelineLayout,
            renderPass,
            vertexShader,
            fragmentShader,
            VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            MARKER_SUBPASS,
            Blend.opaque,
            Depth.written,
            Culling.none,
        );
        pipeline = createGraphicsPipeline(device, settings);
        vkDestroyShaderModule(device, vertexShader, null);
        vkDestroyShaderModule(device, fragmentShader, null);
    }

    void draw(VkCommandBuffer commands, VkDescriptorSet commonSet, const(Marker)[] markers) {
        if (markers.length > 0) {
            vkCmdBindPipeline(commands, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
            vkCmdBindDescriptorSets(commands, VK_PIPELINE_BIND_POINT_GRAPHICS, pipelineLayout, 0, 1, &commonSet, 0, null);
            foreach (ref marker; markers) {
                MarkerPush push = MarkerPush(flatten(marker.frame.m), marker.half, marker.color);
                vkCmdPushConstants(commands, pipelineLayout, VK_SHADER_STAGE_VERTEX_BIT, 0, MarkerPush.sizeof, &push);
                vkCmdDraw(commands, CUBE_VERTICES, 1, 0, 0);
            }
        }
    }

    void cleanup(VkDevice device) {
        vkDestroyPipeline(device, pipeline, null);
        vkDestroyPipelineLayout(device, pipelineLayout, null);
    }
}
