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
    VkImage textureImage;
    VkDeviceMemory textureMemory;
    VkImageView textureView;
    VkSampler textureSampler;
    uint surfaceCount;
    uint chunkCount;

    bool init(VkPhysicalDevice phys, VkDevice device, VkRenderPass renderPass,
              Surface[] surfaces, float[16][] transforms,
              VkQueue queue = null, VkCommandPool cmdPool = 0,
              ulong externalSurfacesBuf = 0) {
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

        // set 1: binding 0 = Surfaces SSBO (vert), binding 1 = texture array (frag)
        VkDescriptorSetLayoutBinding[2] staticBinds;
        staticBinds[0].binding = 0;
        staticBinds[0].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        staticBinds[0].descriptorCount = 1;
        staticBinds[0].stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_VERTEX_BIT;
        staticBinds[1].binding = 1;
        staticBinds[1].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        staticBinds[1].descriptorCount = 1;
        staticBinds[1].stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_FRAGMENT_BIT;
        VkDescriptorSetLayoutCreateInfo staticCi;
        staticCi.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
        staticCi.bindingCount = 2;
        staticCi.pBindings = staticBinds.ptr;
        vkCreateDescriptorSetLayout(device, &staticCi, null, &staticLayout);

        // --- Descriptor pool + sets ---
        VkDescriptorPoolSize[3] sizes;
        sizes[0].type = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        sizes[0].descriptorCount = 1;
        sizes[1].type = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        sizes[1].descriptorCount = 1;
        sizes[2].type = VkDescriptorType.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        sizes[2].descriptorCount = 1;
        VkDescriptorPoolCreateInfo poolCi;
        poolCi.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        poolCi.maxSets = 2;
        poolCi.poolSizeCount = 3;
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
        ubyte[160] commonInit = 0;
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

        // --- Create texture array ---
        if (!createTextureArray(phys, device, queue, cmdPool)) {
            writeln("Failed to create texture array");
            return false;
        }

        // --- Write descriptors ---
        VkDescriptorBufferInfo commonInfo;
        commonInfo.buffer = commonUbo.buffer;
        commonInfo.offset = 0;
        commonInfo.range = VK_WHOLE_SIZE;
        VkDescriptorBufferInfo ssboInfo;
        ssboInfo.buffer = surfacesSsbo.buffer;
        ssboInfo.offset = 0;
        ssboInfo.range = VK_WHOLE_SIZE;
        VkDescriptorImageInfo imgInfo;
        imgInfo.sampler = textureSampler;
        imgInfo.imageView = textureView;
        imgInfo.imageLayout = VkImageLayout.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        VkWriteDescriptorSet[3] writes;
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
        writes[2].sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        writes[2].dstSet = staticSet;
        writes[2].dstBinding = 1;
        writes[2].descriptorCount = 1;
        writes[2].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        writes[2].pImageInfo = &imgInfo;
        vkUpdateDescriptorSets(device, 3, writes.ptr, 0, null);

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
        // Cull back faces. Parity-flipped chunks have their winding corrected
        // in voxels.vert by swapping a pair of triangle vertices.
        rs.cullMode = VkCullModeFlagBits.VK_CULL_MODE_NONE;
        rs.frontFace = VkFrontFace.VK_FRONT_FACE_COUNTER_CLOCKWISE;
        rs.lineWidth = 1.0f;

        VkPipelineMultisampleStateCreateInfo ms;
        ms.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
        ms.rasterizationSamples = 1;

        VkPipelineDepthStencilStateCreateInfo dssci;
        dssci.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
        dssci.depthTestEnable = 1;
        dssci.depthWriteEnable = 1;
        // Beltrami-Klein projection from frustum.d is reverse-Z (near=1.0, far=0.0),
        // so we keep larger depth values (closer geometry).
        dssci.depthCompareOp = VkCompareOp.VK_COMPARE_OP_GREATER;

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

    private bool createTextureArray(VkPhysicalDevice phys, VkDevice device,
                                     VkQueue queue, VkCommandPool cmdPool) {
        import common.world : MATERIAL_COUNT;
        import core.stdc.string : memcpy, memset;

        enum TEX_SIZE = 16;
        enum LAYER_COUNT = MATERIAL_COUNT - 1; // exclude Void
        enum PIXEL_BYTES = TEX_SIZE * TEX_SIZE * 4;
        enum TOTAL_BYTES = PIXEL_BYTES * LAYER_COUNT;

        // Fill all layers with gray (178, 178, 178, 255)
        ubyte[TOTAL_BYTES] pixels;
        for (size_t i = 0; i < TOTAL_BYTES; i += 4) {
            pixels[i]   = 178;
            pixels[i+1] = 178;
            pixels[i+2] = 178;
            pixels[i+3] = 255;
        }

        // Create image
        VkImageCreateInfo ici;
        ici.sType = VkStructureType.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
        ici.imageType = VkImageType.VK_IMAGE_TYPE_2D;
        ici.format = VkFormat.VK_FORMAT_R8G8B8A8_UNORM;
        ici.extent = VkExtent3D(TEX_SIZE, TEX_SIZE, 1);
        ici.mipLevels = 1;
        ici.arrayLayers = LAYER_COUNT;
        ici.samples = 1;
        ici.tiling = VkImageTiling.VK_IMAGE_TILING_OPTIMAL;
        ici.usage = VkImageUsageFlagBits.VK_IMAGE_USAGE_TRANSFER_DST_BIT
                  | VkImageUsageFlagBits.VK_IMAGE_USAGE_SAMPLED_BIT;
        ici.sharingMode = VkSharingMode.VK_SHARING_MODE_EXCLUSIVE;
        ici.initialLayout = VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED;
        auto res = vkCreateImage(device, &ici, null, &textureImage);
        if (res != VkResult.VK_SUCCESS) {
            return false;
        }

        // Allocate device-local memory
        VkMemoryRequirements req;
        vkGetImageMemoryRequirements(device, textureImage, &req);
        VkPhysicalDeviceMemoryProperties memProps;
        vkGetPhysicalDeviceMemoryProperties(phys, &memProps);
        uint memIdx = uint.max;
        for (uint i = 0; i < memProps.memoryTypeCount; i++) {
            if ((req.memoryTypeBits & (1u << i)) &&
                (memProps.memoryTypes[i].propertyFlags & VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)) {
                memIdx = i;
                break;
            }
        }
        if (memIdx == uint.max) {
            return false;
        }
        VkMemoryAllocateInfo mai;
        mai.sType = VkStructureType.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        mai.allocationSize = req.size;
        mai.memoryTypeIndex = memIdx;
        vkAllocateMemory(device, &mai, null, &textureMemory);
        vkBindImageMemory(device, textureImage, textureMemory, 0);

        // Create staging buffer
        auto staging = GpuBuffer.create(phys, device, pixels[],
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_TRANSFER_SRC_BIT);

        // Upload via command buffer
        VkCommandBufferAllocateInfo cbai;
        cbai.sType = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        cbai.commandPool = cmdPool;
        cbai.level = VkCommandBufferLevel.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        cbai.commandBufferCount = 1;
        VkCommandBuffer cmd;
        vkAllocateCommandBuffers(device, &cbai, &cmd);

        VkCommandBufferBeginInfo beginInfo;
        beginInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        vkBeginCommandBuffer(cmd, &beginInfo);

        // Transition to TRANSFER_DST
        VkImageMemoryBarrier barrier;
        barrier.sType = VkStructureType.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.oldLayout = VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED;
        barrier.newLayout = VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.image = textureImage;
        barrier.subresourceRange = VkImageSubresourceRange(
            VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, LAYER_COUNT);
        vkCmdPipelineBarrier(cmd,
            VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_TRANSFER_BIT,
            VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_TRANSFER_BIT,
            0, 0, null, 0, null, 1, &barrier);

        // Copy buffer to image
        VkBufferImageCopy region;
        region.bufferOffset = 0;
        region.bufferRowLength = 0;
        region.bufferImageHeight = 0;
        region.imageSubresource = VkImageSubresourceLayers(
            VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, LAYER_COUNT);
        region.imageOffset = VkOffset3D(0, 0, 0);
        region.imageExtent = VkExtent3D(TEX_SIZE, TEX_SIZE, 1);
        vkCmdCopyBufferToImage(cmd, staging.buffer, textureImage,
            VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

        // Transition to SHADER_READ_ONLY
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = VkAccessFlagBits.VK_ACCESS_SHADER_READ_BIT;
        barrier.oldLayout = VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.newLayout = VkImageLayout.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        vkCmdPipelineBarrier(cmd,
            VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_TRANSFER_BIT,
            VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
            0, 0, null, 0, null, 1, &barrier);

        vkEndCommandBuffer(cmd);

        VkSubmitInfo si;
        si.sType = VkStructureType.VK_STRUCTURE_TYPE_SUBMIT_INFO;
        si.commandBufferCount = 1;
        si.pCommandBuffers = &cmd;
        vkQueueSubmit(queue, 1, &si, VK_NULL_HANDLE);
        vkQueueWaitIdle(queue);

        staging.cleanup(device);

        // Create image view
        VkImageViewCreateInfo ivci;
        ivci.sType = VkStructureType.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        ivci.image = textureImage;
        ivci.viewType = VkImageViewType.VK_IMAGE_VIEW_TYPE_2D_ARRAY;
        ivci.format = VkFormat.VK_FORMAT_R8G8B8A8_UNORM;
        ivci.subresourceRange = VkImageSubresourceRange(
            VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, LAYER_COUNT);
        res = vkCreateImageView(device, &ivci, null, &textureView);
        if (res != VkResult.VK_SUCCESS) {
            return false;
        }

        // Create sampler
        VkSamplerCreateInfo sci;
        sci.sType = VkStructureType.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
        sci.magFilter = VK_FILTER_NEAREST;
        sci.minFilter = VK_FILTER_NEAREST;
        sci.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST;
        sci.addressModeU = VK_SAMPLER_ADDRESS_MODE_REPEAT;
        sci.addressModeV = VK_SAMPLER_ADDRESS_MODE_REPEAT;
        sci.addressModeW = VK_SAMPLER_ADDRESS_MODE_REPEAT;
        sci.maxLod = 0;
        res = vkCreateSampler(device, &sci, null, &textureSampler);
        if (res != VkResult.VK_SUCCESS) {
            return false;
        }

        return true;
    }

    void updateCommonUbo(VkDevice device, float[16] vp, float[16] invp,
                         float fogDensity, float time, float[4] lightDir) {
        // common UBO layout (std140):
        //   mat4 vp         0..63
        //   mat4 invp      64..127
        //   float fog      128
        //   float time     132
        //   <pad>          136..143
        //   vec4 lightDir  144..159
        ubyte[160] data = 0;
        import core.stdc.string : memcpy;
        memcpy(data.ptr + 0,   vp.ptr,   64);
        memcpy(data.ptr + 64,  invp.ptr, 64);
        memcpy(data.ptr + 128, &fogDensity, 4);
        memcpy(data.ptr + 132, &time, 4);
        memcpy(data.ptr + 144, lightDir.ptr, 16);
        void* mapped;
        vkMapMemory(device, commonUbo.memory, 0, 160, 0, &mapped);
        memcpy(mapped, data.ptr, 160);
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
        if (textureSampler) {
            vkDestroySampler(device, textureSampler, null);
        }
        if (textureView) {
            vkDestroyImageView(device, textureView, null);
        }
        if (textureImage) {
            vkDestroyImage(device, textureImage, null);
        }
        if (textureMemory) {
            vkFreeMemory(device, textureMemory, null);
        }
        commonUbo.cleanup(device);
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
