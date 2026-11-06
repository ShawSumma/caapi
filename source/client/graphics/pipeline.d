module client.graphics.pipeline;

import core.stdc.stdlib : free, malloc;
import core.stdc.string : memcpy, memset;
import bindings.platform : VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA, VK_BLEND_FACTOR_SRC_ALPHA, VK_BLEND_OP_ADD, VK_COMPARE_OP_GREATER, VK_CULL_MODE_BACK_BIT, VK_CULL_MODE_NONE, VK_DYNAMIC_STATE_SCISSOR, VK_DYNAMIC_STATE_VIEWPORT, VK_FRONT_FACE_CLOCKWISE, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, VK_MEMORY_PROPERTY_HOST_CACHED_BIT, VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT, VK_POLYGON_MODE_FILL, VK_SAMPLE_COUNT_1_BIT, VK_SHADER_STAGE_COMPUTE_BIT, VK_SHADER_STAGE_FRAGMENT_BIT, VK_SHADER_STAGE_VERTEX_BIT, VK_SHARING_MODE_EXCLUSIVE, VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO, VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO, VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO, VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO, VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO, VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO, VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO, VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO, VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO, VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO, VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, VK_SUCCESS, VkBlendFactor, VkBuffer, VkBufferCreateInfo, VkBufferUsageFlags, VkComputePipelineCreateInfo, VkCullModeFlags, VkDescriptorBufferInfo, VkDescriptorImageInfo, VkDescriptorSet, VkDescriptorSetLayout, VkDescriptorSetLayoutBinding, VkDescriptorSetLayoutCreateInfo, VkDescriptorType, VkDevice, VkDeviceMemory, VkDeviceSize, VkDynamicState, VkGraphicsPipelineCreateInfo, VkImage, VkMemoryAllocateInfo, VkMemoryPropertyFlags, VkMemoryRequirements, VkPhysicalDevice, VkPhysicalDeviceMemoryProperties, VkPipeline, VkPipelineColorBlendAttachmentState, VkPipelineColorBlendStateCreateInfo, VkPipelineDepthStencilStateCreateInfo, VkPipelineDynamicStateCreateInfo, VkPipelineInputAssemblyStateCreateInfo, VkPipelineLayout, VkPipelineLayoutCreateInfo, VkPipelineMultisampleStateCreateInfo, VkPipelineRasterizationStateCreateInfo, VkPipelineShaderStageCreateInfo, VkPipelineVertexInputStateCreateInfo, VkPipelineViewportStateCreateInfo, VkPrimitiveTopology, VkPushConstantRange, VkRenderPass, VkResult, VkShaderModule, VkShaderModuleCreateInfo, VkShaderStageFlagBits, VkShaderStageFlags, VkWriteDescriptorSet, vkAllocateMemory, vkBindBufferMemory, vkBindImageMemory, vkCreateBuffer, vkCreateComputePipelines, vkCreateDescriptorSetLayout, vkCreateGraphicsPipelines, vkCreatePipelineLayout, vkCreateShaderModule, vkDestroyBuffer, vkFreeMemory, vkGetBufferMemoryRequirements, vkGetImageMemoryRequirements, vkGetPhysicalDeviceMemoryProperties, vkMapMemory;

enum uint COLOR_WRITE_RED = 0x1;
enum uint COLOR_WRITE_RGB = 0x7;
enum uint COLOR_WRITE_RGBA = 0xf;
enum uint MOST_COLOR_ATTACHMENTS = 2;
enum ulong WHOLE_SIZE = ulong.max;
enum uint QUEUE_FAMILY_IGNORED = uint.max;
enum uint SUBPASS_EXTERNAL = uint.max;
enum uint VULKAN_TRUE = 1;

void expectSuccess(VkResult result) {
    if (result != VK_SUCCESS) {
        assert(false);
    }
}

struct GpuBuffer {
    VkBuffer buffer;
    VkDeviceMemory memory;
    VkDeviceSize size;
    void* mapped;

    static GpuBuffer make(VkPhysicalDevice physicalDevice, VkDevice device, VkDeviceSize size, VkBufferUsageFlags usage, VkMemoryPropertyFlags properties) {
        GpuBuffer result;
        result.size = size;
        VkBufferCreateInfo bufferInfo;
        bufferInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
        bufferInfo.size = size;
        bufferInfo.usage = usage;
        bufferInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
        expectSuccess(vkCreateBuffer(device, &bufferInfo, null, &result.buffer));
        VkMemoryRequirements requirements;
        vkGetBufferMemoryRequirements(device, result.buffer, &requirements);
        result.memory = allocateMemory(physicalDevice, device, requirements, properties);
        expectSuccess(vkBindBufferMemory(device, result.buffer, result.memory, 0));
        return result;
    }

    static GpuBuffer makeDeviceLocal(VkPhysicalDevice physicalDevice, VkDevice device, VkDeviceSize size, VkBufferUsageFlags usage) {
        return make(physicalDevice, device, size, usage, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    }

    static GpuBuffer makeMapped(VkPhysicalDevice physicalDevice, VkDevice device, VkDeviceSize size, VkBufferUsageFlags usage) {
        GpuBuffer result = make(physicalDevice, device, size, usage, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
        expectSuccess(vkMapMemory(device, result.memory, 0, size, 0, &result.mapped));
        memset(result.mapped, 0, size);
        return result;
    }

    static GpuBuffer makeReadable(VkPhysicalDevice physicalDevice, VkDevice device, VkDeviceSize size, VkBufferUsageFlags usage) {
        GpuBuffer result = make(physicalDevice, device, size, usage, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT | VK_MEMORY_PROPERTY_HOST_CACHED_BIT);
        expectSuccess(vkMapMemory(device, result.memory, 0, size, 0, &result.mapped));
        return result;
    }

    static GpuBuffer makeFilled(VkPhysicalDevice physicalDevice, VkDevice device, const(void)[] data, VkBufferUsageFlags usage) {
        GpuBuffer result = makeMapped(physicalDevice, device, data.length, usage);
        memcpy(result.mapped, data.ptr, data.length);
        return result;
    }

    void destroy(VkDevice device) {
        vkDestroyBuffer(device, buffer, null);
        vkFreeMemory(device, memory, null);
        this = GpuBuffer.init;
    }
}

bool isMemoryTypeUsable(ref const VkPhysicalDeviceMemoryProperties properties, uint index, uint typeBits, VkMemoryPropertyFlags wanted) {
    return (typeBits & (1u << index)) != 0 && (properties.memoryTypes[index].propertyFlags & wanted) == wanted;
}

uint memoryTypeIndex(VkPhysicalDevice physicalDevice, uint typeBits, VkMemoryPropertyFlags wanted) {
    VkPhysicalDeviceMemoryProperties properties;
    vkGetPhysicalDeviceMemoryProperties(physicalDevice, &properties);
    uint index = 0;
    while (index < properties.memoryTypeCount && !isMemoryTypeUsable(properties, index, typeBits, wanted)) {
        index += 1;
    }
    assert(index < properties.memoryTypeCount);
    return index;
}

VkDeviceMemory allocateMemory(VkPhysicalDevice physicalDevice, VkDevice device, VkMemoryRequirements requirements, VkMemoryPropertyFlags properties) {
    VkMemoryAllocateInfo allocateInfo;
    allocateInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocateInfo.allocationSize = requirements.size;
    allocateInfo.memoryTypeIndex = memoryTypeIndex(physicalDevice, requirements.memoryTypeBits, properties);
    VkDeviceMemory memory;
    expectSuccess(vkAllocateMemory(device, &allocateInfo, null, &memory));
    return memory;
}

VkDeviceMemory bindDeviceLocalImage(VkPhysicalDevice physicalDevice, VkDevice device, VkImage image) {
    VkMemoryRequirements requirements;
    vkGetImageMemoryRequirements(device, image, &requirements);
    VkDeviceMemory memory = allocateMemory(physicalDevice, device, requirements, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    expectSuccess(vkBindImageMemory(device, image, memory, 0));
    return memory;
}

enum Blend : ubyte {
    opaque,
    transmittance,
    alpha,
}

enum Depth : ubyte {
    ignored,
    tested,
    written,
}

enum Culling : ubyte {
    none,
    backFaces,
}

enum Outputs : ubyte {
    color,
    colorAndGlow,
    colorAndHistory,
}

struct PipelineSettings {
    VkPipelineLayout layout;
    VkRenderPass renderPass;
    VkShaderModule vertexShader;
    VkShaderModule fragmentShader;
    VkPrimitiveTopology topology;
    uint subpass;
    Blend blend;
    Depth depth;
    Culling culling;
    Outputs outputs;

    VkCullModeFlags cullMode() const {
        if (culling == Culling.backFaces) {
            return VK_CULL_MODE_BACK_BIT;
        } else {
            return VK_CULL_MODE_NONE;
        }
    }

    VkPipelineColorBlendAttachmentState blendAttachment() const {
        if (blend == Blend.opaque) {
            return opaqueAttachment();
        } else if (blend == Blend.transmittance) {
            return blendedAttachment(VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA, VK_BLEND_FACTOR_SRC_ALPHA);
        } else {
            return blendedAttachment(VK_BLEND_FACTOR_SRC_ALPHA, VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA);
        }
    }

    uint colorAttachmentCount() const {
        if (outputs == Outputs.color) {
            return 1;
        } else {
            return MOST_COLOR_ATTACHMENTS;
        }
    }

    VkPipelineColorBlendAttachmentState secondAttachment() const {
        if (outputs == Outputs.colorAndHistory) {
            return opaqueAttachment();
        } else {
            return glowAttachment();
        }
    }
}

VkPipelineColorBlendAttachmentState opaqueAttachment() {
    VkPipelineColorBlendAttachmentState attachment;
    attachment.colorWriteMask = COLOR_WRITE_RGBA;
    return attachment;
}

VkPipelineColorBlendAttachmentState glowAttachment() {
    VkPipelineColorBlendAttachmentState attachment;
    attachment.colorWriteMask = COLOR_WRITE_RED;
    return attachment;
}

VkPipelineColorBlendAttachmentState blendedAttachment(VkBlendFactor sourceFactor, VkBlendFactor destinationFactor) {
    VkPipelineColorBlendAttachmentState attachment;
    attachment.blendEnable = VULKAN_TRUE;
    attachment.srcColorBlendFactor = sourceFactor;
    attachment.dstColorBlendFactor = destinationFactor;
    attachment.colorBlendOp = VK_BLEND_OP_ADD;
    attachment.alphaBlendOp = VK_BLEND_OP_ADD;
    attachment.colorWriteMask = COLOR_WRITE_RGB;
    return attachment;
}

VkShaderModule createShader(VkDevice device, const(char)[] spirv) {
    uint* code = cast(uint*) malloc(spirv.length);
    memcpy(code, spirv.ptr, spirv.length);
    VkShaderModuleCreateInfo info;
    info.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    info.codeSize = spirv.length;
    info.pCode = code;
    VkShaderModule result;
    VkResult created = vkCreateShaderModule(device, &info, null, &result);
    free(code);
    expectSuccess(created);
    return result;
}

VkPipelineShaderStageCreateInfo shaderStage(VkShaderStageFlagBits stage, VkShaderModule shaderModule) {
    return VkPipelineShaderStageCreateInfo(VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, null, 0, stage, shaderModule, "main", null);
}

VkPipeline createGraphicsPipeline(VkDevice device, PipelineSettings settings) {
    VkPipelineShaderStageCreateInfo[2] stages = [
        shaderStage(VK_SHADER_STAGE_VERTEX_BIT, settings.vertexShader),
        shaderStage(VK_SHADER_STAGE_FRAGMENT_BIT, settings.fragmentShader),
    ];
    VkPipelineVertexInputStateCreateInfo vertexInput;
    vertexInput.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
    VkPipelineInputAssemblyStateCreateInfo inputAssembly;
    inputAssembly.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    inputAssembly.topology = settings.topology;
    VkPipelineViewportStateCreateInfo viewport;
    viewport.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    viewport.viewportCount = 1;
    viewport.scissorCount = 1;
    VkPipelineRasterizationStateCreateInfo rasterization;
    rasterization.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    rasterization.polygonMode = VK_POLYGON_MODE_FILL;
    rasterization.cullMode = settings.cullMode();
    rasterization.frontFace = VK_FRONT_FACE_CLOCKWISE;
    rasterization.lineWidth = 1.0f;
    VkPipelineMultisampleStateCreateInfo multisample;
    multisample.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    multisample.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
    VkPipelineDepthStencilStateCreateInfo depthStencil;
    depthStencil.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
    if (settings.depth != Depth.ignored) {
        depthStencil.depthTestEnable = VULKAN_TRUE;
    }
    if (settings.depth == Depth.written) {
        depthStencil.depthWriteEnable = VULKAN_TRUE;
    }
    depthStencil.depthCompareOp = VK_COMPARE_OP_GREATER;
    VkPipelineColorBlendAttachmentState[MOST_COLOR_ATTACHMENTS] blendAttachments = [
        settings.blendAttachment(),
        settings.secondAttachment(),
    ];
    VkPipelineColorBlendStateCreateInfo colorBlend;
    colorBlend.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    colorBlend.attachmentCount = settings.colorAttachmentCount();
    colorBlend.pAttachments = blendAttachments.ptr;
    VkDynamicState[2] dynamicStates = [
        VK_DYNAMIC_STATE_VIEWPORT,
        VK_DYNAMIC_STATE_SCISSOR,
    ];
    VkPipelineDynamicStateCreateInfo dynamicState;
    dynamicState.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
    dynamicState.dynamicStateCount = 2;
    dynamicState.pDynamicStates = dynamicStates.ptr;
    VkGraphicsPipelineCreateInfo info;
    info.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    info.stageCount = 2;
    info.pStages = stages.ptr;
    info.pVertexInputState = &vertexInput;
    info.pInputAssemblyState = &inputAssembly;
    info.pViewportState = &viewport;
    info.pRasterizationState = &rasterization;
    info.pMultisampleState = &multisample;
    info.pDepthStencilState = &depthStencil;
    info.pColorBlendState = &colorBlend;
    info.pDynamicState = &dynamicState;
    info.layout = settings.layout;
    info.renderPass = settings.renderPass;
    info.subpass = settings.subpass;
    VkPipeline result;
    expectSuccess(vkCreateGraphicsPipelines(device, null, 1, &info, null, &result));
    return result;
}

VkPipeline createComputePipeline(VkDevice device, VkShaderModule shader, VkPipelineLayout layout) {
    VkComputePipelineCreateInfo info;
    info.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
    info.stage = shaderStage(VK_SHADER_STAGE_COMPUTE_BIT, shader);
    info.layout = layout;
    VkPipeline result;
    expectSuccess(vkCreateComputePipelines(device, null, 1, &info, null, &result));
    return result;
}

VkWriteDescriptorSet bufferWrite(VkDescriptorSet set, uint binding, VkDescriptorType type, VkDescriptorBufferInfo* info) {
    VkWriteDescriptorSet write;
    write.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    write.dstSet = set;
    write.dstBinding = binding;
    write.descriptorCount = 1;
    write.descriptorType = type;
    write.pBufferInfo = info;
    return write;
}

VkWriteDescriptorSet imageWrite(VkDescriptorSet set, uint binding, VkDescriptorType type, VkDescriptorImageInfo* info) {
    VkWriteDescriptorSet write;
    write.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    write.dstSet = set;
    write.dstBinding = binding;
    write.descriptorCount = 1;
    write.descriptorType = type;
    write.pImageInfo = info;
    return write;
}

VkDescriptorSetLayoutBinding layoutBinding(uint binding, VkDescriptorType type, VkShaderStageFlags stages) {
    VkDescriptorSetLayoutBinding result;
    result.binding = binding;
    result.descriptorType = type;
    result.descriptorCount = 1;
    result.stageFlags = stages;
    return result;
}

VkDescriptorSetLayout createSetLayout(VkDevice device, VkDescriptorSetLayoutBinding[] bindings) {
    VkDescriptorSetLayoutCreateInfo info;
    info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    info.bindingCount = cast(uint) bindings.length;
    info.pBindings = bindings.ptr;
    VkDescriptorSetLayout result;
    expectSuccess(vkCreateDescriptorSetLayout(device, &info, null, &result));
    return result;
}

VkPipelineLayout createPipelineLayout(VkDevice device, VkDescriptorSetLayout[] setLayouts, VkPushConstantRange[] pushConstants) {
    VkPipelineLayoutCreateInfo info;
    info.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    info.setLayoutCount = cast(uint) setLayouts.length;
    info.pSetLayouts = setLayouts.ptr;
    info.pushConstantRangeCount = cast(uint) pushConstants.length;
    info.pPushConstantRanges = pushConstants.ptr;
    VkPipelineLayout result;
    expectSuccess(vkCreatePipelineLayout(device, &info, null, &result));
    return result;
}
