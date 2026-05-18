module client.graphics.pipeline;

import std.stdio;
import bindings.vk;
import client.worldgen.dummy : Vertex;

struct CubePipeline {
    VkShaderModule vertShader;
    VkShaderModule fragShader;
    VkPipelineLayout layout;
    VkPipeline pipeline;

    bool init(VkDevice device, VkRenderPass renderPass) {
        static immutable ubyte[] vertSpv = cast(immutable(ubyte)[]) import("cube.vert.spv");
        static immutable ubyte[] fragSpv = cast(immutable(ubyte)[]) import("cube.frag.spv");

        if (!createShader(device, vertSpv, vertShader)) {
            return false;
        }
        if (!createShader(device, fragSpv, fragShader)) {
            return false;
        }

        VkPipelineShaderStageCreateInfo[2] stages;
        stages[0].sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        stages[0].stage = VkShaderStageFlagBits.VK_SHADER_STAGE_VERTEX_BIT;
        stages[0].mod = vertShader;
        stages[0].pName = "main";
        stages[1].sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        stages[1].stage = VkShaderStageFlagBits.VK_SHADER_STAGE_FRAGMENT_BIT;
        stages[1].mod = fragShader;
        stages[1].pName = "main";

        VkVertexInputBindingDescription binding;
        binding.binding = 0;
        binding.stride = Vertex.sizeof;
        binding.inputRate = VkVertexInputRate.VK_VERTEX_INPUT_RATE_VERTEX;

        VkVertexInputAttributeDescription[2] attrs;
        attrs[0].location = 0;
        attrs[0].binding = 0;
        attrs[0].format = VkFormatExt.VK_FORMAT_R32G32B32_SFLOAT;
        attrs[0].offset = Vertex.pos.offsetof;
        attrs[1].location = 1;
        attrs[1].binding = 0;
        attrs[1].format = VkFormatExt.VK_FORMAT_R32G32B32_SFLOAT;
        attrs[1].offset = Vertex.color.offsetof;

        VkPipelineVertexInputStateCreateInfo vi;
        vi.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
        vi.vertexBindingDescriptionCount = 1;
        vi.pVertexBindingDescriptions = &binding;
        vi.vertexAttributeDescriptionCount = 2;
        vi.pVertexAttributeDescriptions = attrs.ptr;

        VkPipelineInputAssemblyStateCreateInfo ia;
        ia.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
        ia.topology = VkPrimitiveTopology.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;

        VkPipelineViewportStateCreateInfo vp;
        vp.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
        vp.viewportCount = 1;
        vp.scissorCount = 1;

        VkPipelineRasterizationStateCreateInfo rs;
        rs.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
        rs.polygonMode = VkPolygonMode.VK_POLYGON_MODE_FILL;
        rs.cullMode = VkCullModeFlagBits.VK_CULL_MODE_BACK_BIT;
        rs.frontFace = VkFrontFace.VK_FRONT_FACE_COUNTER_CLOCKWISE;
        rs.lineWidth = 1.0f;

        VkPipelineMultisampleStateCreateInfo ms;
        ms.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
        ms.rasterizationSamples = 1;

        VkPipelineColorBlendAttachmentState cba;
        cba.blendEnable = 0;
        cba.colorWriteMask = 0xf; // RGBA

        VkPipelineColorBlendStateCreateInfo cb;
        cb.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
        cb.attachmentCount = 1;
        cb.pAttachments = &cba;

        VkDynamicState[2] dyn = [VkDynamicState.VK_DYNAMIC_STATE_VIEWPORT, VkDynamicState.VK_DYNAMIC_STATE_SCISSOR];
        VkPipelineDynamicStateCreateInfo ds;
        ds.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
        ds.dynamicStateCount = 2;
        ds.pDynamicStates = dyn.ptr;

        VkPushConstantRange pcr;
        pcr.stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_VERTEX_BIT;
        pcr.offset = 0;
        pcr.size = 64; // mat4

        VkPipelineLayoutCreateInfo plci;
        plci.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
        plci.pushConstantRangeCount = 1;
        plci.pPushConstantRanges = &pcr;

        auto res = vkCreatePipelineLayout(device, &plci, null, &layout);
        if (res != VkResult.VK_SUCCESS) { writeln("pipeline layout failed"); return false; }

        VkGraphicsPipelineCreateInfo gpci;
        gpci.sType = VkStructureType.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
        gpci.stageCount = 2;
        gpci.pStages = stages.ptr;
        gpci.pVertexInputState = &vi;
        gpci.pInputAssemblyState = &ia;
        gpci.pViewportState = &vp;
        gpci.pRasterizationState = &rs;
        gpci.pMultisampleState = &ms;
        gpci.pColorBlendState = &cb;
        gpci.pDynamicState = &ds;

        VkPipelineDepthStencilStateCreateInfo dssci;
        dssci.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
        dssci.depthTestEnable = 1;
        dssci.depthWriteEnable = 1;
        dssci.depthCompareOp = VkCompareOp.VK_COMPARE_OP_LESS;
        gpci.pDepthStencilState = &dssci;
        gpci.layout = layout;
        gpci.renderPass = renderPass;
        gpci.subpass = 0;

        res = vkCreateGraphicsPipelines(device, 0, 1, &gpci, null, &pipeline);
        if (res != VkResult.VK_SUCCESS) { writefln("pipeline create failed: %s", res); return false; }
        writeln("Cube pipeline created");
        return true;
    }

    void cleanup(VkDevice device) {
        if (pipeline) {
            vkDestroyPipeline(device, pipeline, null);
        }
        if (layout) {
            vkDestroyPipelineLayout(device, layout, null);
        }
        if (vertShader) {
            vkDestroyShaderModule(device, vertShader, null);
        }
        if (fragShader) {
            vkDestroyShaderModule(device, fragShader, null);
        }
    }
}

private bool createShader(VkDevice device, const(ubyte)[] spv, ref VkShaderModule mod) {
    VkShaderModuleCreateInfo ci;
    ci.sType = VkStructureType.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    ci.codeSize = spv.length;
    ci.pCode = cast(const(uint)*) spv.ptr;
    auto res = vkCreateShaderModule(device, &ci, null, &mod);
    return res == VkResult.VK_SUCCESS;
}

struct GpuBuffer {
    ulong buffer;
    VkDeviceMemory memory;
    VkDeviceSize size;

    static GpuBuffer create(VkPhysicalDevice phys, VkDevice device, const(void)[] data, uint usage) {
        GpuBuffer b;
        b.size = data.length;

        VkBufferCreateInfo bci;
        bci.sType = VkStructureType.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
        bci.size = data.length;
        bci.usage = usage;
        bci.sharingMode = VkSharingMode.VK_SHARING_MODE_EXCLUSIVE;
        vkCreateBuffer(device, &bci, null, &b.buffer);

        VkMemoryRequirements req;
        vkGetBufferMemoryRequirements(device, b.buffer, &req);

        VkPhysicalDeviceMemoryProperties memProps;
        vkGetPhysicalDeviceMemoryProperties(phys, &memProps);

        uint memTypeIdx = uint.max;
        uint wanted = VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                      VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
        for (uint i = 0; i < memProps.memoryTypeCount; i++) {
            if ((req.memoryTypeBits & (1u << i)) &&
                (memProps.memoryTypes[i].propertyFlags & wanted) == wanted) {
                memTypeIdx = i;
                break;
            }
        }

        VkMemoryAllocateInfo mai;
        mai.sType = VkStructureType.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        mai.allocationSize = req.size;
        mai.memoryTypeIndex = memTypeIdx;
        vkAllocateMemory(device, &mai, null, &b.memory);
        vkBindBufferMemory(device, b.buffer, b.memory, 0);

        void* mapped;
        vkMapMemory(device, b.memory, 0, req.size, 0, &mapped);
        import core.stdc.string : memcpy;
        memcpy(mapped, data.ptr, data.length);
        vkUnmapMemory(device, b.memory);

        return b;
    }

    void cleanup(VkDevice device) {
        if (buffer) {
            vkDestroyBuffer(device, buffer, null);
        }
        if (memory) {
            vkFreeMemory(device, memory, null);
        }
    }
}
