module client.graphics.voxels.surface;

import std.stdio;
import core.stdc.string : memcpy;
import bindings.vk;
import client.graphics.pipeline : GpuBuffer;
import client.graphics.fog : createShader;

struct PackedSurface {
    uint posAxis;
    uint occMat;
}

struct Surface {
    uint pos_axis;
    uint occlusion_mat;

    static PackedSurface pack(
        uint x,
        uint y,
        uint z,
        uint axis,
        bool reverse,
        bool flip,
        uint mat,
        uint[4] occlusion,
    ) {
        uint oriented = axis;
        if (reverse) {
            oriented = oriented + 3u;
        }
        if (flip) {
            oriented = oriented + 6u;
        }

        uint packedPos = x & 0xFF;
        packedPos = packedPos | ((y & 0xFF) << 8);
        packedPos = packedPos | ((z & 0xFF) << 16);
        packedPos = packedPos | (oriented << 24);

        uint packedOcc = mat & 0xFFFF;
        packedOcc = packedOcc | (occlusion[0] << 24);
        packedOcc = packedOcc | (occlusion[1] << 26);
        packedOcc = packedOcc | (occlusion[2] << 28);
        packedOcc = packedOcc | (occlusion[3] << 30);

        PackedSurface result;
        result.posAxis = packedPos;
        result.occMat = packedOcc;
        return result;
    }
}

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

    GpuBuffer commonUbo;
    GpuBuffer surfacesSsbo;
    GpuBuffer transformsVbo;
    // The 20 chunk-to-node isometries, one per dodecahedral vertex. Constant,
    // uploaded once. Lets the vertex stage put a chunk-local position into its
    // node's frame, which is stable and covers all 20 chunks continuously.
    GpuBuffer chunkToNodeBuf;
    uint surfaceCount;
    uint chunkCount;

    bool init(
        VkPhysicalDevice phys,
        VkDevice device,
        VkRenderPass renderPass,
        Surface[] surfaces,
        float[16][] transforms,
        ulong externalSurfacesBuf = 0,
        VkImageView depthView = 0,
        VkImageView fieldView = 0,
        VkSampler fieldSampler = 0,
        float[] chunkToNode = null,
    ) {
        static immutable ubyte[] vertSpv = cast(immutable(ubyte)[]) import("voxels.vert.spv");
        static immutable ubyte[] fragSpv = cast(immutable(ubyte)[]) import("voxels.frag.spv");

        vertShader = createShader(device, vertSpv);
        if (vertShader == VK_NULL_HANDLE) {
            return false;
        }
        fragShader = createShader(device, fragSpv);
        if (fragShader == VK_NULL_HANDLE) {
            return false;
        }

        VkDescriptorSetLayoutBinding[2] commonBinds;
        commonBinds[0].binding = 0;
        commonBinds[0].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        commonBinds[0].descriptorCount = 1;
        uint vertexStage = VkShaderStageFlagBits.VK_SHADER_STAGE_VERTEX_BIT;
        uint fragmentStage = VkShaderStageFlagBits.VK_SHADER_STAGE_FRAGMENT_BIT;
        commonBinds[0].stageFlags = vertexStage | fragmentStage;
        commonBinds[1].binding = 1;
        commonBinds[1].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT;
        commonBinds[1].descriptorCount = 1;
        commonBinds[1].stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_FRAGMENT_BIT;
        VkDescriptorSetLayoutCreateInfo commonCi;
        commonCi.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
        commonCi.bindingCount = 2;
        commonCi.pBindings = commonBinds.ptr;
        vkCreateDescriptorSetLayout(device, &commonCi, null, &commonLayout);

        VkDescriptorSetLayoutBinding[3] staticBinds;
        staticBinds[0].binding = 0;
        staticBinds[0].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        staticBinds[0].descriptorCount = 1;
        staticBinds[0].stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_VERTEX_BIT;
        staticBinds[1].binding = 1;
        staticBinds[1].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        staticBinds[1].descriptorCount = 1;
        staticBinds[1].stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_FRAGMENT_BIT;
        staticBinds[2].binding = 2;
        staticBinds[2].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        staticBinds[2].descriptorCount = 1;
        staticBinds[2].stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_VERTEX_BIT;
        VkDescriptorSetLayoutCreateInfo staticCi;
        staticCi.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
        staticCi.bindingCount = 3;
        staticCi.pBindings = staticBinds.ptr;
        vkCreateDescriptorSetLayout(device, &staticCi, null, &staticLayout);

        VkDescriptorPoolSize[4] sizes;
        sizes[0].type = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        sizes[0].descriptorCount = 1;
        sizes[1].type = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        sizes[1].descriptorCount = 2;
        sizes[2].type = VkDescriptorType.VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT;
        sizes[2].descriptorCount = 1;
        sizes[3].type = VkDescriptorType.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        sizes[3].descriptorCount = 1;
        VkDescriptorPoolCreateInfo poolCi;
        poolCi.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        poolCi.maxSets = 2;
        poolCi.poolSizeCount = 4;
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

        ubyte[240] commonInit = 0;
        commonUbo = GpuBuffer.create(
            phys,
            device,
            commonInit[],
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
        );

        if (externalSurfacesBuf != 0) {
            surfacesSsbo.buffer = externalSurfacesBuf;
            surfacesSsbo.memory = 0;
            surfaceCount = 0;
        } else {
            surfacesSsbo = GpuBuffer.create(
                phys,
                device,
                cast(void[]) surfaces,
                VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
            );
            surfaceCount = cast(uint) surfaces.length;
        }

        uint vertexBufferBit = VkBufferUsageFlagBits.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
        uint storageBufferBit = VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
        transformsVbo = GpuBuffer.create(
            phys,
            device,
            cast(void[]) transforms,
            vertexBufferBit | storageBufferBit,
        );
        chunkCount = cast(uint) transforms.length;

        chunkToNodeBuf = GpuBuffer.create(
            phys,
            device,
            cast(void[]) chunkToNode,
            storageBufferBit,
        );


        VkDescriptorBufferInfo commonInfo;
        commonInfo.buffer = commonUbo.buffer;
        commonInfo.offset = 0;
        commonInfo.range = VK_WHOLE_SIZE;
        VkDescriptorBufferInfo ssboInfo;
        ssboInfo.buffer = surfacesSsbo.buffer;
        ssboInfo.offset = 0;
        ssboInfo.range = VK_WHOLE_SIZE;
        VkDescriptorImageInfo depthInfo;
        depthInfo.sampler = 0;
        depthInfo.imageView = depthView;
        depthInfo.imageLayout = VkImageLayout.VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL;
        VkDescriptorImageInfo fieldInfo;
        fieldInfo.sampler = fieldSampler;
        fieldInfo.imageView = fieldView;
        fieldInfo.imageLayout = VkImageLayout.VK_IMAGE_LAYOUT_GENERAL;
        VkDescriptorBufferInfo c2nInfo;
        c2nInfo.buffer = chunkToNodeBuf.buffer;
        c2nInfo.offset = 0;
        c2nInfo.range = VK_WHOLE_SIZE;
        VkWriteDescriptorSet[5] writes;
        writes[0].sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        writes[0].dstSet = commonSet;
        writes[0].dstBinding = 0;
        writes[0].descriptorCount = 1;
        writes[0].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        writes[0].pBufferInfo = &commonInfo;
        writes[1].sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        writes[1].dstSet = commonSet;
        writes[1].dstBinding = 1;
        writes[1].descriptorCount = 1;
        writes[1].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT;
        writes[1].pImageInfo = cast(const(void)*) &depthInfo;
        writes[2].sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        writes[2].dstSet = staticSet;
        writes[2].dstBinding = 0;
        writes[2].descriptorCount = 1;
        writes[2].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        writes[2].pBufferInfo = &ssboInfo;
        writes[3].sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        writes[3].dstSet = staticSet;
        writes[3].dstBinding = 1;
        writes[3].descriptorCount = 1;
        writes[3].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        writes[3].pImageInfo = cast(const(void)*) &fieldInfo;
        writes[4].sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        writes[4].dstSet = staticSet;
        writes[4].dstBinding = 2;
        writes[4].descriptorCount = 1;
        writes[4].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        writes[4].pBufferInfo = &c2nInfo;
        vkUpdateDescriptorSets(device, 5, writes.ptr, 0, null);

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
        VkResult res = vkCreatePipelineLayout(device, &plci, null, &pipelineLayout);
        if (res != VkResult.VK_SUCCESS) {
            writeln("voxels pipeline layout failed");
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

        VkVertexInputBindingDescription[2] bindings;
        bindings[0].binding = 0;
        bindings[0].stride = 64;
        bindings[0].inputRate = cast(VkVertexInputRate) VkVertexInputRateExt.VK_VERTEX_INPUT_RATE_INSTANCE;
        // Per-chunk identity, on the same instance rate as the transform so it
        // is indexed identically however the draw sets firstInstance.
        bindings[1].binding = 1;
        bindings[1].stride = 4;
        bindings[1].inputRate = cast(VkVertexInputRate) VkVertexInputRateExt.VK_VERTEX_INPUT_RATE_INSTANCE;

        VkVertexInputAttributeDescription[5] attrs;
        foreach (i; 0 .. 4) {
            attrs[i].location = cast(uint) i;
            attrs[i].binding = 0;
            attrs[i].format = VkFormatExt.VK_FORMAT_R32G32B32A32_SFLOAT;
            attrs[i].offset = cast(uint)(i * 16);
        }
        attrs[4].location = 4;
        attrs[4].binding = 1;
        // The other attributes use VkFormatExt; this one only exists in
        // VkFormat, so convert rather than duplicate the value.
        attrs[4].format = cast(typeof(attrs[4].format)) VkFormat.VK_FORMAT_R32_UINT;
        attrs[4].offset = 0;

        VkPipelineVertexInputStateCreateInfo vi;
        vi.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
        vi.vertexBindingDescriptionCount = 2;
        vi.pVertexBindingDescriptions = bindings.ptr;
        vi.vertexAttributeDescriptionCount = 5;
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
        rs.cullMode = VkCullModeFlagBits.VK_CULL_MODE_NONE;
        rs.frontFace = VkFrontFace.VK_FRONT_FACE_COUNTER_CLOCKWISE;
        rs.depthBiasConstantFactor = 0;
        rs.depthBiasClamp = 0;
        rs.depthBiasSlopeFactor = 0;
        rs.lineWidth = 1.0f;

        VkPipelineMultisampleStateCreateInfo ms;
        ms.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
        ms.rasterizationSamples = 1;

        VkPipelineDepthStencilStateCreateInfo dssci;
        dssci.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
        dssci.depthTestEnable = 1;
        dssci.depthWriteEnable = 1;
        dssci.depthCompareOp = VkCompareOp.VK_COMPARE_OP_GREATER;

        VkPipelineColorBlendAttachmentState cba;
        cba.colorWriteMask = 0xf;
        VkPipelineColorBlendStateCreateInfo cb;
        cb.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
        cb.attachmentCount = 1;
        cb.pAttachments = &cba;

        VkDynamicState[2] dyn = [
            VkDynamicState.VK_DYNAMIC_STATE_VIEWPORT,
            VkDynamicState.VK_DYNAMIC_STATE_SCISSOR,
        ];
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
        if (res != VkResult.VK_SUCCESS) {
            writefln("voxels pipeline create failed: %s", res);
            return false;
        }
        writefln("Voxels pipeline created (%d surfaces, %d chunks)", surfaceCount, chunkCount);
        return true;
    }

    /// Re-point the fog subpass's depth input attachment after the swapchain
    /// (and thus the depth image) has been recreated.
    void updateDepthDescriptor(VkDevice device, VkImageView depthView) {
        VkDescriptorImageInfo depthInfo;
        depthInfo.sampler = 0;
        depthInfo.imageView = depthView;
        depthInfo.imageLayout = VkImageLayout.VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL;
        VkWriteDescriptorSet write;
        write.sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        write.dstSet = commonSet;
        write.dstBinding = 1;
        write.descriptorCount = 1;
        write.descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT;
        write.pImageInfo = cast(const(void)*) &depthInfo;
        vkUpdateDescriptorSets(device, 1, &write, 0, null);
    }

    void updateCommonUbo(
        VkDevice device,
        float[16] vp,
        float[16] invp,
        float fogDensity,
        float time,
        float[4] lightDir,
        float[4] rotBase,
        float[4] rotGain,
        float[4] trip,
        float[4] viewport,
        float[4] fieldInfo,
    ) {
        ubyte[240] data = 0;
        memcpy(data.ptr + 0, vp.ptr, 64);
        memcpy(data.ptr + 64, invp.ptr, 64);
        memcpy(data.ptr + 128, &fogDensity, 4);
        memcpy(data.ptr + 132, &time, 4);
        memcpy(data.ptr + 144, lightDir.ptr, 16);
        memcpy(data.ptr + 160, rotBase.ptr, 16);
        memcpy(data.ptr + 176, rotGain.ptr, 16);
        memcpy(data.ptr + 192, trip.ptr, 16);
        memcpy(data.ptr + 208, viewport.ptr, 16);
        memcpy(data.ptr + 224, fieldInfo.ptr, 16);
        void* mapped;
        vkMapMemory(device, commonUbo.memory, 0, 240, 0, &mapped);
        memcpy(mapped, data.ptr, 240);
        vkUnmapMemory(device, commonUbo.memory);
    }

    void cleanup(VkDevice device) {
        if (pipeline != VK_NULL_HANDLE) {
            vkDestroyPipeline(device, pipeline, null);
        }
        if (pipelineLayout != VK_NULL_HANDLE) {
            vkDestroyPipelineLayout(device, pipelineLayout, null);
        }
        if (descPool != VK_NULL_HANDLE) {
            vkDestroyDescriptorPool(device, descPool, null);
        }
        if (commonLayout != VK_NULL_HANDLE) {
            vkDestroyDescriptorSetLayout(device, commonLayout, null);
        }
        if (staticLayout != VK_NULL_HANDLE) {
            vkDestroyDescriptorSetLayout(device, staticLayout, null);
        }
        if (vertShader != VK_NULL_HANDLE) {
            vkDestroyShaderModule(device, vertShader, null);
        }
        if (fragShader != VK_NULL_HANDLE) {
            vkDestroyShaderModule(device, fragShader, null);
        }
        commonUbo.cleanup(device);
        if (surfacesSsbo.memory != 0) {
            surfacesSsbo.cleanup(device);
        }
        transformsVbo.cleanup(device);
        chunkToNodeBuf.cleanup(device);
    }
}
