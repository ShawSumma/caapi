module client.graphics.pipeline;

import core.stdc.stdlib : free, malloc;
import core.stdc.string : memcpy, memset;
import bindings.platform : VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA, VK_BLEND_FACTOR_SRC_ALPHA, VK_BLEND_OP_ADD, VK_COMPARE_OP_GREATER, VK_CULL_MODE_NONE, VK_DYNAMIC_STATE_SCISSOR, VK_DYNAMIC_STATE_VIEWPORT, VK_FRONT_FACE_COUNTER_CLOCKWISE, VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT, VK_POLYGON_MODE_FILL, VK_SAMPLE_COUNT_1_BIT, VK_SHADER_STAGE_COMPUTE_BIT, VK_SHADER_STAGE_FRAGMENT_BIT, VK_SHADER_STAGE_VERTEX_BIT, VK_SHARING_MODE_EXCLUSIVE, VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER, VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO, VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO, VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO, VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO, VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO, VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO, VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO, VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO, VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO, VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO, VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, VK_SUCCESS, VkAccessFlags, VkBuffer, VkBufferCreateInfo, VkBufferMemoryBarrier, VkBufferUsageFlags, VkComputePipelineCreateInfo, VkDescriptorBufferInfo, VkDescriptorImageInfo, VkDescriptorSet, VkDescriptorSetLayout, VkDescriptorSetLayoutBinding, VkDescriptorSetLayoutCreateInfo, VkDescriptorType, VkDevice, VkDeviceMemory, VkDeviceSize, VkDynamicState, VkGraphicsPipelineCreateInfo, VkMemoryAllocateInfo, VkMemoryPropertyFlags, VkMemoryRequirements, VkPhysicalDevice, VkPhysicalDeviceMemoryProperties, VkPipeline, VkPipelineColorBlendAttachmentState, VkPipelineColorBlendStateCreateInfo, VkPipelineDepthStencilStateCreateInfo, VkPipelineDynamicStateCreateInfo, VkPipelineInputAssemblyStateCreateInfo, VkPipelineLayout, VkPipelineLayoutCreateInfo, VkPipelineMultisampleStateCreateInfo, VkPipelineRasterizationStateCreateInfo, VkPipelineShaderStageCreateInfo, VkPipelineVertexInputStateCreateInfo, VkPipelineViewportStateCreateInfo, VkPrimitiveTopology, VkPushConstantRange, VkRenderPass, VkShaderModule, VkShaderModuleCreateInfo, VkShaderStageFlagBits, VkShaderStageFlags, VkWriteDescriptorSet, vkAllocateMemory, vkBindBufferMemory, vkCreateBuffer, vkCreateComputePipelines, vkCreateDescriptorSetLayout, vkCreateGraphicsPipelines, vkCreatePipelineLayout, vkCreateShaderModule, vkDestroyBuffer, vkFreeMemory, vkGetBufferMemoryRequirements, vkGetPhysicalDeviceMemoryProperties, vkMapMemory, vkUnmapMemory;

enum uint NO_MEMORY_TYPE = uint.max;
enum uint COLOR_WRITE_RGB = 0x7;
enum uint COLOR_WRITE_RGBA = 0xf;
enum ulong WHOLE_SIZE = ulong.max;
enum uint QUEUE_FAMILY_IGNORED = uint.max;
enum uint SUBPASS_EXTERNAL = uint.max;
enum uint VULKAN_TRUE = 1;

struct GpuBuffer {
    VkBuffer buffer;
    VkDeviceMemory memory;
    VkDeviceSize size;
}

struct PipelineSettings {
    VkPipelineVertexInputStateCreateInfo* vertexInput;
    VkPipelineLayout layout;
    VkRenderPass renderPass;
    VkShaderModule vertexShader;
    VkShaderModule fragmentShader;
    VkPrimitiveTopology topology;
    uint subpass;
    bool depthTest;
    bool depthWrite;
    bool fogBlend;
}

uint findMemoryType(VkPhysicalDevice physicalDevice, uint typeBits, VkMemoryPropertyFlags wanted) {
    VkPhysicalDeviceMemoryProperties properties;
    vkGetPhysicalDeviceMemoryProperties(physicalDevice, &properties);
    uint result = NO_MEMORY_TYPE;
    foreach (i; 0 .. properties.memoryTypeCount) {
        if (result == NO_MEMORY_TYPE && (typeBits & (1u << i)) != 0 && (properties.memoryTypes[i].propertyFlags & wanted) == wanted) {
            result = i;
        }
    }
    return result;
}

GpuBuffer createHostVisibleBuffer(VkPhysicalDevice physicalDevice, VkDevice device, VkDeviceSize size, VkBufferUsageFlags usage) {
    GpuBuffer result;
    result.size = size;
    VkBufferCreateInfo bufferInfo;
    bufferInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bufferInfo.size = size;
    bufferInfo.usage = usage;
    bufferInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    vkCreateBuffer(device, &bufferInfo, null, &result.buffer);
    VkMemoryRequirements requirements;
    vkGetBufferMemoryRequirements(device, result.buffer, &requirements);
    VkMemoryAllocateInfo allocateInfo;
    allocateInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocateInfo.allocationSize = requirements.size;
    allocateInfo.memoryTypeIndex = findMemoryType(physicalDevice, requirements.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    vkAllocateMemory(device, &allocateInfo, null, &result.memory);
    vkBindBufferMemory(device, result.buffer, result.memory, 0);
    return result;
}

GpuBuffer createFilledBuffer(VkPhysicalDevice physicalDevice, VkDevice device, const(void)[] data, VkBufferUsageFlags usage) {
    GpuBuffer result = createHostVisibleBuffer(physicalDevice, device, data.length, usage);
    void* mapped;
    vkMapMemory(device, result.memory, 0, data.length, 0, &mapped);
    memcpy(mapped, data.ptr, data.length);
    vkUnmapMemory(device, result.memory);
    return result;
}

GpuBuffer createZeroedBuffer(VkPhysicalDevice physicalDevice, VkDevice device, VkDeviceSize size, VkBufferUsageFlags usage) {
    GpuBuffer result = createHostVisibleBuffer(physicalDevice, device, size, usage);
    void* mapped;
    vkMapMemory(device, result.memory, 0, size, 0, &mapped);
    memset(mapped, 0, size);
    vkUnmapMemory(device, result.memory);
    return result;
}

void destroyBuffer(VkDevice device, GpuBuffer* buffer) {
    if (buffer.buffer !is null) {
        vkDestroyBuffer(device, buffer.buffer, null);
    }
    if (buffer.memory !is null) {
        vkFreeMemory(device, buffer.memory, null);
    }
    *buffer = GpuBuffer.init;
}

VkShaderModule createShader(VkDevice device, const(char)[] spirv) {
    uint* code = cast(uint*) malloc(spirv.length);
    memcpy(code, spirv.ptr, spirv.length);
    VkShaderModuleCreateInfo info;
    info.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    info.codeSize = spirv.length;
    info.pCode = code;
    VkShaderModule result = null;
    if (vkCreateShaderModule(device, &info, null, &result) != VK_SUCCESS) {
        result = null;
    }
    free(code);
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
    VkPipelineVertexInputStateCreateInfo emptyVertexInput;
    emptyVertexInput.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
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
    rasterization.cullMode = VK_CULL_MODE_NONE;
    rasterization.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE;
    rasterization.lineWidth = 1.0f;
    VkPipelineMultisampleStateCreateInfo multisample;
    multisample.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    multisample.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
    VkPipelineDepthStencilStateCreateInfo depthStencil;
    depthStencil.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
    depthStencil.depthTestEnable = settings.depthTest;
    depthStencil.depthWriteEnable = settings.depthWrite;
    depthStencil.depthCompareOp = VK_COMPARE_OP_GREATER;
    VkPipelineColorBlendAttachmentState blendAttachment;
    blendAttachment.colorWriteMask = COLOR_WRITE_RGBA;
    if (settings.fogBlend) {
        blendAttachment.blendEnable = VULKAN_TRUE;
        blendAttachment.srcColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
        blendAttachment.dstColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA;
        blendAttachment.colorBlendOp = VK_BLEND_OP_ADD;
        blendAttachment.alphaBlendOp = VK_BLEND_OP_ADD;
        blendAttachment.colorWriteMask = COLOR_WRITE_RGB;
    }
    VkPipelineColorBlendStateCreateInfo colorBlend;
    colorBlend.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    colorBlend.attachmentCount = 1;
    colorBlend.pAttachments = &blendAttachment;
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
    info.pVertexInputState = &emptyVertexInput;
    if (settings.vertexInput !is null) {
        info.pVertexInputState = settings.vertexInput;
    }
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
    VkPipeline result = null;
    if (vkCreateGraphicsPipelines(device, null, 1, &info, null, &result) != VK_SUCCESS) {
        result = null;
    }
    return result;
}

VkPipeline createComputePipeline(VkDevice device, VkShaderModule shader, VkPipelineLayout layout) {
    VkComputePipelineCreateInfo info;
    info.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
    info.stage = shaderStage(VK_SHADER_STAGE_COMPUTE_BIT, shader);
    info.layout = layout;
    VkPipeline result = null;
    if (vkCreateComputePipelines(device, null, 1, &info, null, &result) != VK_SUCCESS) {
        result = null;
    }
    return result;
}

VkBufferMemoryBarrier bufferBarrier(VkBuffer buffer, VkAccessFlags sourceAccess, VkAccessFlags destinationAccess) {
    VkBufferMemoryBarrier barrier;
    barrier.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
    barrier.srcAccessMask = sourceAccess;
    barrier.dstAccessMask = destinationAccess;
    barrier.srcQueueFamilyIndex = QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = QUEUE_FAMILY_IGNORED;
    barrier.buffer = buffer;
    barrier.size = WHOLE_SIZE;
    return barrier;
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
    VkDescriptorSetLayout result = null;
    vkCreateDescriptorSetLayout(device, &info, null, &result);
    return result;
}

VkPipelineLayout createPipelineLayout(VkDevice device, VkDescriptorSetLayout[] setLayouts, VkPushConstantRange[] pushConstants) {
    VkPipelineLayoutCreateInfo info;
    info.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    info.setLayoutCount = cast(uint) setLayouts.length;
    info.pSetLayouts = setLayouts.ptr;
    info.pushConstantRangeCount = cast(uint) pushConstants.length;
    info.pPushConstantRanges = pushConstants.ptr;
    VkPipelineLayout result = null;
    if (vkCreatePipelineLayout(device, &info, null, &result) != VK_SUCCESS) {
        result = null;
    }
    return result;
}
