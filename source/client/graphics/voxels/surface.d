module client.graphics.voxels.surface;

import std.stdio;
import bindings.vk;
import client.graphics.pipeline : GpuBuffer;

// Matches surface-extraction/surface.h
struct Surface {
    uint pos_axis;
    uint occlusion_mat;

    static uint pack(uint x, uint y, uint z, uint axis, bool reverse, bool flip, uint mat,
                     uint[4] occlusion, out uint posAxis, out uint occMat) {
        uint a = axis + 3u * (reverse ? 1u : 0u) + 6u * (flip ? 1u : 0u);
        posAxis = (x & 0xFF) | ((y & 0xFF) << 8) | ((z & 0xFF) << 16) | (a << 24);
        occMat = (mat & 0xFFFF) | (occlusion[0] << 24) | (occlusion[1] << 26)
               | (occlusion[2] << 28) | (occlusion[3] << 30);
        return posAxis;
    }
}

/// Port of hypermine's Surface (rendering pipeline + descriptor set wiring).
struct SurfacePipeline {
    VkShaderModule vertShader;
    VkShaderModule fragShader;
    VkDescriptorSetLayout commonLayout;
    VkDescriptorSetLayout staticLayout;
    VkDescriptorPool descPool;
    VkDescriptorSet commonSet;
    VkDescriptorSet staticSet;
    VkPipelineLayout pipelineLayout;
    VkPipeline pipeline;

    GpuBuffer commonUbo;     // set=0 binding=0
    GpuBuffer surfacesSsbo;  // set=1 binding=0
    GpuBuffer transformsVbo; // per-instance mat4
    uint surfaceCount;
    uint chunkCount;

    bool init(VkPhysicalDevice phys, VkDevice device, VkRenderPass renderPass,
              Surface[] surfaces, float[16][] transforms, ulong externalSurfacesBuf = 0) {
        static immutable ubyte[] vertSpv = cast(ubyte[]) import("voxels.vert.spv");
        static immutable ubyte[] fragSpv = cast(ubyte[]) import("voxels.frag.spv");

        if (!createShader(device, vertSpv, vertShader)) {
            return false;
        }
        if (!createShader(device, fragSpv, fragShader)) {
            return false;
        }

        // --- Descriptor set layouts ---
        // set 0 binding 0 = Common UBO (vert)
        VkDescriptorSetLayoutBinding commonBind;
        commonBind.binding = 0;
        commonBind.descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        commonBind.descriptorCount = 1;
        commonBind.stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_VERTEX_BIT |
                                VkShaderStageFlagBits.VK_SHADER_STAGE_FRAGMENT_BIT;
        VkDescriptorSetLayoutCreateInfo commonCi;
        commonCi.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
        commonCi.bindingCount = 1;
        commonCi.pBindings = &commonBind;
        vkCreateDescriptorSetLayout(device, &commonCi, null, &commonLayout);

        // set 1 binding 0 = Surfaces SSBO (vert)
        VkDescriptorSetLayoutBinding staticBind;
        staticBind.binding = 0;
        staticBind.descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        staticBind.descriptorCount = 1;
        staticBind.stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_VERTEX_BIT;
        VkDescriptorSetLayoutCreateInfo staticCi;
        staticCi.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
        staticCi.bindingCount = 1;
        staticCi.pBindings = &staticBind;
        vkCreateDescriptorSetLayout(device, &staticCi, null, &staticLayout);

        // --- Descriptor pool + sets ---
        VkDescriptorPoolSize[2] sizes;
        sizes[0].type = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        sizes[0].descriptorCount = 1;
        sizes[1].type = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        sizes[1].descriptorCount = 1;
        VkDescriptorPoolCreateInfo poolCi;
        poolCi.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        poolCi.maxSets = 2;
        poolCi.poolSizeCount = 2;
        poolCi.pPoolSizes = sizes.ptr;
        vkCreateDescriptorPool(device, &poolCi, null, &descPool);

        VkDescriptorSetLayout[2] setLayouts = [commonLayout, staticLayout];
        VkDescriptorSetAllocateInfo dsai;
        dsai.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        dsai.descriptorPool = descPool;
        dsai.descriptorSetCount = 2;
        dsai.pSetLayouts = setLayouts.ptr;
        VkDescriptorSet[2] allocated;
        vkAllocateDescriptorSets(device, &dsai, allocated.ptr);
        commonSet = allocated[0];
        staticSet = allocated[1];

        // --- Buffers ---
        // Common UBO: mat4 vp, mat4 invp, float fog, float time, vec2 pad → 144 bytes
        ubyte[144] commonInit = 0;
        commonUbo = GpuBuffer.create(phys, device, commonInit[],
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);

        if (externalSurfacesBuf != 0) {
            surfacesSsbo.buffer = externalSurfacesBuf;
            // We don't own this buffer; cleanup() will skip it.
            surfacesSsbo.memory = 0;
            surfaceCount = 0; // unknown (will use draw indirect)
        } else {
            surfacesSsbo = GpuBuffer.create(phys, device, cast(void[]) surfaces,
                VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
            surfaceCount = cast(uint) surfaces.length;
        }

        transformsVbo = GpuBuffer.create(phys, device, cast(void[]) transforms,
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
        chunkCount = cast(uint) transforms.length;

        // --- Write descriptors ---
        VkDescriptorBufferInfo commonInfo;
        commonInfo.buffer = commonUbo.buffer;
        commonInfo.offset = 0;
        commonInfo.range = VK_WHOLE_SIZE;
        VkDescriptorBufferInfo ssboInfo;
        ssboInfo.buffer = surfacesSsbo.buffer;
        ssboInfo.offset = 0;
        ssboInfo.range = VK_WHOLE_SIZE;
        VkWriteDescriptorSet[2] writes;
        writes[0].sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        writes[0].dstSet = commonSet;
        writes[0].dstBinding = 0;
        writes[0].descriptorCount = 1;
        writes[0].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        writes[0].pBufferInfo = &commonInfo;
        writes[1].sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        writes[1].dstSet = staticSet;
        writes[1].dstBinding = 0;
        writes[1].descriptorCount = 1;
        writes[1].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        writes[1].pBufferInfo = &ssboInfo;
        vkUpdateDescriptorSets(device, 2, writes.ptr, 0, null);

        // --- Pipeline layout ---
        VkPushConstantRange pcr;
        pcr.stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_VERTEX_BIT;
        pcr.offset = 0;
        pcr.size = 4;
        VkPipelineLayoutCreateInfo plci;
        plci.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
        plci.setLayoutCount = 2;
        plci.pSetLayouts = setLayouts.ptr;
        plci.pushConstantRangeCount = 1;
        plci.pPushConstantRanges = &pcr;
        auto res = vkCreatePipelineLayout(device, &plci, null, &pipelineLayout);
        if (res != VkResult.VK_SUCCESS) { writeln("voxels pipeline layout failed"); return false; }

        // --- Pipeline ---
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
        binding.stride = 64; // mat4
        binding.inputRate = cast(VkVertexInputRate) VkVertexInputRateExt.VK_VERTEX_INPUT_RATE_INSTANCE;

        VkVertexInputAttributeDescription[4] attrs;
        foreach (i; 0 .. 4) {
            attrs[i].location = cast(uint) i;
            attrs[i].binding = 0;
            attrs[i].format = 109; // VK_FORMAT_R32G32B32A32_SFLOAT
            attrs[i].offset = cast(uint)(i * 16);
        }

        VkPipelineVertexInputStateCreateInfo vi;
        vi.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
        vi.vertexBindingDescriptionCount = 1;
        vi.pVertexBindingDescriptions = &binding;
        vi.vertexAttributeDescriptionCount = 4;
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

        VkPipelineDepthStencilStateCreateInfo dssci;
        dssci.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
        dssci.depthTestEnable = 1;
        dssci.depthWriteEnable = 1;
        dssci.depthCompareOp = VkCompareOp.VK_COMPARE_OP_LESS;

        VkPipelineColorBlendAttachmentState cba;
        cba.colorWriteMask = 0xf;
        VkPipelineColorBlendStateCreateInfo cb;
        cb.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
        cb.attachmentCount = 1;
        cb.pAttachments = &cba;

        VkDynamicState[2] dyn = [VkDynamicState.VK_DYNAMIC_STATE_VIEWPORT, VkDynamicState.VK_DYNAMIC_STATE_SCISSOR];
        VkPipelineDynamicStateCreateInfo ds;
        ds.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
        ds.dynamicStateCount = 2;
        ds.pDynamicStates = dyn.ptr;

        VkGraphicsPipelineCreateInfo gpci;
        gpci.sType = VkStructureType.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
        gpci.stageCount = 2;
        gpci.pStages = stages.ptr;
        gpci.pVertexInputState = &vi;
        gpci.pInputAssemblyState = &ia;
        gpci.pViewportState = &vp;
        gpci.pRasterizationState = &rs;
        gpci.pMultisampleState = &ms;
        gpci.pDepthStencilState = &dssci;
        gpci.pColorBlendState = &cb;
        gpci.pDynamicState = &ds;
        gpci.layout = pipelineLayout;
        gpci.renderPass = renderPass;

        res = vkCreateGraphicsPipelines(device, 0, 1, &gpci, null, &pipeline);
        if (res != VkResult.VK_SUCCESS) { writefln("voxels pipeline create failed: %s", res); return false; }
        writefln("Voxels pipeline created (%d surfaces, %d chunks)", surfaceCount, chunkCount);
        return true;
    }

    void updateCommonUbo(VkDevice device, float[16] vp, float[16] invp, float fogDensity, float time) {
        // common UBO layout: mat4 vp (64), mat4 invp (64), float fog (4), float time (4), pad (8)
        ubyte[144] data = 0;
        import core.stdc.string : memcpy;
        memcpy(data.ptr + 0,   vp.ptr,   64);
        memcpy(data.ptr + 64,  invp.ptr, 64);
        memcpy(data.ptr + 128, &fogDensity, 4);
        memcpy(data.ptr + 132, &time, 4);
        void* mapped;
        vkMapMemory(device, commonUbo.memory, 0, 144, 0, &mapped);
        memcpy(mapped, data.ptr, 144);
        vkUnmapMemory(device, commonUbo.memory);
    }

    void cleanup(VkDevice device) {
        if (pipeline) {
            vkDestroyPipeline(device, pipeline, null);
        }
        if (pipelineLayout) {
            vkDestroyPipelineLayout(device, pipelineLayout, null);
        }
        if (descPool) {
            vkDestroyDescriptorPool(device, descPool, null);
        }
        if (commonLayout) {
            vkDestroyDescriptorSetLayout(device, commonLayout, null);
        }
        if (staticLayout) {
            vkDestroyDescriptorSetLayout(device, staticLayout, null);
        }
        if (vertShader) {
            vkDestroyShaderModule(device, vertShader, null);
        }
        if (fragShader) {
            vkDestroyShaderModule(device, fragShader, null);
        }
        commonUbo.cleanup(device);
        // surfacesSsbo may be external — only free if we own it
        if (surfacesSsbo.memory != 0) {
            surfacesSsbo.cleanup(device);
        }
        transformsVbo.cleanup(device);
    }
}

private bool createShader(VkDevice device, const(ubyte)[] spv, ref VkShaderModule mod) {
    VkShaderModuleCreateInfo ci;
    ci.sType = VkStructureType.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    ci.codeSize = spv.length;
    ci.pCode = cast(const(uint)*) spv.ptr;
    return vkCreateShaderModule(device, &ci, null, &mod) == VkResult.VK_SUCCESS;
}
