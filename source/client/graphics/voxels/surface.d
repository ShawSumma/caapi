module client.graphics.voxels.surface;

import core.stdc.stdlib : free, malloc;
import core.stdc.string : memcpy, memset;
import bindings.platform : VK_ACCESS_SHADER_READ_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, VK_COMMAND_BUFFER_LEVEL_PRIMARY, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, VK_FILTER_LINEAR, VK_FORMAT_R32G32B32A32_SFLOAT, VK_FORMAT_R8G8B8A8_SRGB, VK_IMAGE_ASPECT_COLOR_BIT, VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_TILING_OPTIMAL, VK_IMAGE_TYPE_2D, VK_IMAGE_USAGE_SAMPLED_BIT, VK_IMAGE_USAGE_TRANSFER_DST_BIT, VK_IMAGE_VIEW_TYPE_2D_ARRAY, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, VK_SAMPLER_ADDRESS_MODE_REPEAT, VK_SAMPLER_MIPMAP_MODE_NEAREST, VK_SAMPLE_COUNT_1_BIT, VK_SHADER_STAGE_FRAGMENT_BIT, VK_SHADER_STAGE_VERTEX_BIT, VK_SHARING_MODE_EXCLUSIVE, VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO, VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO, VK_STRUCTURE_TYPE_SUBMIT_INFO, VK_SUCCESS, VK_VERTEX_INPUT_RATE_INSTANCE, VkBuffer, VkBufferImageCopy, VkCommandBuffer, VkCommandBufferAllocateInfo, VkCommandBufferBeginInfo, VkCommandPool, VkDescriptorBufferInfo, VkDescriptorImageInfo, VkDescriptorPool, VkDescriptorPoolCreateInfo, VkDescriptorPoolSize, VkDescriptorSet, VkDescriptorSetAllocateInfo, VkDescriptorSetLayout, VkDescriptorSetLayoutBinding, VkDevice, VkDeviceMemory, VkDeviceSize, VkExtent3D, VkImage, VkImageCreateInfo, VkImageMemoryBarrier, VkImageSubresourceLayers, VkImageSubresourceRange, VkImageView, VkImageViewCreateInfo, VkMemoryAllocateInfo, VkMemoryRequirements, VkPhysicalDevice, VkPipeline, VkPipelineLayout, VkPipelineVertexInputStateCreateInfo, VkPushConstantRange, VkQueue, VkRenderPass, VkSampler, VkSamplerCreateInfo, VkShaderModule, VkSubmitInfo, VkVertexInputAttributeDescription, VkVertexInputBindingDescription, VkWriteDescriptorSet, vkAllocateCommandBuffers, vkAllocateDescriptorSets, vkAllocateMemory, vkBeginCommandBuffer, vkBindImageMemory, vkCmdCopyBufferToImage, vkCmdPipelineBarrier, vkCreateDescriptorPool, vkCreateImage, vkCreateImageView, vkCreateSampler, vkDestroyDescriptorPool, vkDestroyDescriptorSetLayout, vkDestroyImage, vkDestroyImageView, vkDestroyPipeline, vkDestroyPipelineLayout, vkDestroySampler, vkDestroyShaderModule, vkEndCommandBuffer, vkFreeCommandBuffers, vkFreeMemory, vkGetImageMemoryRequirements, vkMapMemory, vkQueueSubmit, vkQueueWaitIdle, vkUnmapMemory, vkUpdateDescriptorSets;
import client.graphics.pipeline : GpuBuffer, PipelineSettings, QUEUE_FAMILY_IGNORED, WHOLE_SIZE, bufferWrite, createFilledBuffer, createGraphicsPipeline, createPipelineLayout, createSetLayout, createShader, createZeroedBuffer, destroyBuffer, findMemoryType, imageWrite, layoutBinding;
import common.world : Material;

enum string VOXELS_VERT_SPV = import("voxels.vert.spv");
enum string VOXELS_FRAG_SPV = import("voxels.frag.spv");
enum uint TEXTURE_SIZE = 16;
enum ubyte TEXTURE_GRAY = 178;
enum ubyte TEXTURE_OPAQUE = 255;
enum uint TEXTURE_LAYERS = Material.max;
enum uint TEXEL_BYTES = 4;
enum uint COMMON_UBO_BYTES = 160;
enum uint COMMON_VIEW_PROJECTION_OFFSET = 0;
enum uint COMMON_INVERSE_PROJECTION_OFFSET = 64;
enum uint COMMON_FOG_DENSITY_OFFSET = 128;
enum uint COMMON_TIME_OFFSET = 132;
enum uint COMMON_LIGHT_OFFSET = 144;
enum uint MATRIX_BYTES = 64;
enum uint TRANSFORM_STRIDE = 64;
enum uint TRANSFORM_COLUMNS = 4;
enum uint TRANSFORM_COLUMN_BYTES = 16;
enum uint DIMENSION_PUSH_BYTES = 4;

struct SurfacePipeline {
    GpuBuffer commonUbo;
    GpuBuffer transformsVbo;
    VkDescriptorSetLayout commonLayout;
    VkDescriptorSetLayout staticLayout;
    VkDescriptorPool descriptorPool;
    VkDescriptorSet commonSet;
    VkDescriptorSet staticSet;
    VkPipelineLayout pipelineLayout;
    VkPipeline pipeline;
    VkImage textureImage;
    VkDeviceMemory textureMemory;
    VkImageView textureView;
    VkSampler textureSampler;

    bool setup(VkPhysicalDevice physicalDevice, VkDevice device, VkRenderPass renderPass, VkQueue queue, VkCommandPool commandPool, VkBuffer facesBuffer, VkImageView depthView, uint transformCount) {
        VkDescriptorSetLayoutBinding[2] commonBindings = [
            layoutBinding(0, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT),
            layoutBinding(1, VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT, VK_SHADER_STAGE_FRAGMENT_BIT),
        ];
        commonLayout = createSetLayout(device, commonBindings[]);
        VkDescriptorSetLayoutBinding[2] staticBindings = [
            layoutBinding(0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_VERTEX_BIT),
            layoutBinding(1, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, VK_SHADER_STAGE_FRAGMENT_BIT),
        ];
        staticLayout = createSetLayout(device, staticBindings[]);
        allocateSets(device);
        commonUbo = createZeroedBuffer(physicalDevice, device, COMMON_UBO_BYTES, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
        transformsVbo = createZeroedBuffer(physicalDevice, device, cast(VkDeviceSize) transformCount * TRANSFORM_STRIDE, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
        bool ok = createTextureArray(physicalDevice, device, queue, commandPool);
        if (ok) {
            writeDescriptors(device, facesBuffer, depthView);
            ok = createPipeline(device, renderPass);
        }
        return ok;
    }

    void allocateSets(VkDevice device) {
        VkDescriptorPoolSize[4] sizes = [
            VkDescriptorPoolSize(VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1),
            VkDescriptorPoolSize(VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1),
            VkDescriptorPoolSize(VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1),
            VkDescriptorPoolSize(VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT, 1),
        ];
        VkDescriptorPoolCreateInfo poolInfo;
        poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        poolInfo.maxSets = 2;
        poolInfo.poolSizeCount = sizes.length;
        poolInfo.pPoolSizes = sizes.ptr;
        vkCreateDescriptorPool(device, &poolInfo, null, &descriptorPool);
        VkDescriptorSetLayout[2] setLayouts = [
            commonLayout,
            staticLayout,
        ];
        VkDescriptorSetAllocateInfo allocateInfo;
        allocateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        allocateInfo.descriptorPool = descriptorPool;
        allocateInfo.descriptorSetCount = setLayouts.length;
        allocateInfo.pSetLayouts = setLayouts.ptr;
        VkDescriptorSet[2] allocated;
        vkAllocateDescriptorSets(device, &allocateInfo, allocated.ptr);
        commonSet = allocated[0];
        staticSet = allocated[1];
    }

    void writeDescriptors(VkDevice device, VkBuffer facesBuffer, VkImageView depthView) {
        VkDescriptorBufferInfo commonInfo = VkDescriptorBufferInfo(commonUbo.buffer, 0, WHOLE_SIZE);
        VkDescriptorBufferInfo facesInfo = VkDescriptorBufferInfo(facesBuffer, 0, WHOLE_SIZE);
        VkDescriptorImageInfo textureInfo = VkDescriptorImageInfo(textureSampler, textureView, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
        VkDescriptorImageInfo depthInfo = VkDescriptorImageInfo(null, depthView, VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL);
        VkWriteDescriptorSet[4] writes = [
            bufferWrite(commonSet, 0, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, &commonInfo),
            imageWrite(commonSet, 1, VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT, &depthInfo),
            bufferWrite(staticSet, 0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, &facesInfo),
            imageWrite(staticSet, 1, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, &textureInfo),
        ];
        vkUpdateDescriptorSets(device, writes.length, writes.ptr, 0, null);
    }

    bool createPipeline(VkDevice device, VkRenderPass renderPass) {
        VkShaderModule vertexShader = createShader(device, VOXELS_VERT_SPV);
        VkShaderModule fragmentShader = createShader(device, VOXELS_FRAG_SPV);
        VkDescriptorSetLayout[2] setLayouts = [
            commonLayout,
            staticLayout,
        ];
        VkPushConstantRange[1] pushConstants = [
            VkPushConstantRange(VK_SHADER_STAGE_VERTEX_BIT, 0, DIMENSION_PUSH_BYTES),
        ];
        pipelineLayout = createPipelineLayout(device, setLayouts[], pushConstants[]);
        VkVertexInputBindingDescription binding = VkVertexInputBindingDescription(0, TRANSFORM_STRIDE, VK_VERTEX_INPUT_RATE_INSTANCE);
        VkVertexInputAttributeDescription[TRANSFORM_COLUMNS] attributes;
        foreach (i; 0 .. TRANSFORM_COLUMNS) {
            attributes[i] = VkVertexInputAttributeDescription(i, 0, VK_FORMAT_R32G32B32A32_SFLOAT, i * TRANSFORM_COLUMN_BYTES);
        }
        VkPipelineVertexInputStateCreateInfo vertexInput;
        vertexInput.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
        vertexInput.vertexBindingDescriptionCount = 1;
        vertexInput.pVertexBindingDescriptions = &binding;
        vertexInput.vertexAttributeDescriptionCount = TRANSFORM_COLUMNS;
        vertexInput.pVertexAttributeDescriptions = attributes.ptr;
        PipelineSettings settings;
        settings.vertexInput = &vertexInput;
        settings.layout = pipelineLayout;
        settings.renderPass = renderPass;
        settings.vertexShader = vertexShader;
        settings.fragmentShader = fragmentShader;
        settings.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
        settings.depthTest = true;
        settings.depthWrite = true;
        if (vertexShader !is null && fragmentShader !is null && pipelineLayout !is null) {
            pipeline = createGraphicsPipeline(device, settings);
        }
        vkDestroyShaderModule(device, vertexShader, null);
        vkDestroyShaderModule(device, fragmentShader, null);
        return pipeline !is null;
    }

    bool createTextureArray(VkPhysicalDevice physicalDevice, VkDevice device, VkQueue queue, VkCommandPool commandPool) {
        size_t layerBytes = TEXTURE_SIZE * TEXTURE_SIZE * TEXEL_BYTES;
        size_t totalBytes = layerBytes * TEXTURE_LAYERS;
        ubyte* pixels = cast(ubyte*) malloc(totalBytes);
        memset(pixels, TEXTURE_GRAY, totalBytes);
        foreach (texel; 0 .. totalBytes / TEXEL_BYTES) {
            pixels[texel * TEXEL_BYTES + 3] = TEXTURE_OPAQUE;
        }
        GpuBuffer staging = createFilledBuffer(physicalDevice, device, pixels[0 .. totalBytes], VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
        free(pixels);

        VkImageCreateInfo imageInfo;
        imageInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
        imageInfo.imageType = VK_IMAGE_TYPE_2D;
        imageInfo.format = VK_FORMAT_R8G8B8A8_SRGB;
        imageInfo.extent = VkExtent3D(TEXTURE_SIZE, TEXTURE_SIZE, 1);
        imageInfo.mipLevels = 1;
        imageInfo.arrayLayers = TEXTURE_LAYERS;
        imageInfo.samples = VK_SAMPLE_COUNT_1_BIT;
        imageInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
        imageInfo.usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
        imageInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
        imageInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        vkCreateImage(device, &imageInfo, null, &textureImage);
        VkMemoryRequirements requirements;
        vkGetImageMemoryRequirements(device, textureImage, &requirements);
        VkMemoryAllocateInfo allocateInfo;
        allocateInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        allocateInfo.allocationSize = requirements.size;
        allocateInfo.memoryTypeIndex = findMemoryType(physicalDevice, requirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
        vkAllocateMemory(device, &allocateInfo, null, &textureMemory);
        vkBindImageMemory(device, textureImage, textureMemory, 0);

        VkCommandBufferAllocateInfo commandInfo;
        commandInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        commandInfo.commandPool = commandPool;
        commandInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        commandInfo.commandBufferCount = 1;
        VkCommandBuffer commands;
        vkAllocateCommandBuffers(device, &commandInfo, &commands);
        VkCommandBufferBeginInfo beginInfo;
        beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        vkBeginCommandBuffer(commands, &beginInfo);
        VkImageSubresourceRange range = VkImageSubresourceRange(VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, TEXTURE_LAYERS);
        VkImageMemoryBarrier barrier;
        barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.srcQueueFamilyIndex = QUEUE_FAMILY_IGNORED;
        barrier.dstQueueFamilyIndex = QUEUE_FAMILY_IGNORED;
        barrier.image = textureImage;
        barrier.subresourceRange = range;
        vkCmdPipelineBarrier(commands, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, 0, null, 1, &barrier);
        VkBufferImageCopy region;
        region.imageSubresource = VkImageSubresourceLayers(VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, TEXTURE_LAYERS);
        region.imageExtent = VkExtent3D(TEXTURE_SIZE, TEXTURE_SIZE, 1);
        vkCmdCopyBufferToImage(commands, staging.buffer, textureImage, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        vkCmdPipelineBarrier(commands, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, null, 0, null, 1, &barrier);
        vkEndCommandBuffer(commands);
        VkSubmitInfo submitInfo;
        submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submitInfo.commandBufferCount = 1;
        submitInfo.pCommandBuffers = &commands;
        vkQueueSubmit(queue, 1, &submitInfo, null);
        vkQueueWaitIdle(queue);
        vkFreeCommandBuffers(device, commandPool, 1, &commands);
        destroyBuffer(device, &staging);

        VkImageViewCreateInfo viewInfo;
        viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        viewInfo.image = textureImage;
        viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D_ARRAY;
        viewInfo.format = VK_FORMAT_R8G8B8A8_SRGB;
        viewInfo.subresourceRange = range;
        bool ok = vkCreateImageView(device, &viewInfo, null, &textureView) == VK_SUCCESS;
        if (ok) {
            VkSamplerCreateInfo samplerInfo;
            samplerInfo.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
            samplerInfo.magFilter = VK_FILTER_LINEAR;
            samplerInfo.minFilter = VK_FILTER_LINEAR;
            samplerInfo.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST;
            samplerInfo.addressModeU = VK_SAMPLER_ADDRESS_MODE_REPEAT;
            samplerInfo.addressModeV = VK_SAMPLER_ADDRESS_MODE_REPEAT;
            samplerInfo.addressModeW = VK_SAMPLER_ADDRESS_MODE_REPEAT;
            ok = vkCreateSampler(device, &samplerInfo, null, &textureSampler) == VK_SUCCESS;
        }
        return ok;
    }

    void updateDepthDescriptor(VkDevice device, VkImageView depthView) {
        VkDescriptorImageInfo depthInfo = VkDescriptorImageInfo(null, depthView, VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL);
        VkWriteDescriptorSet write = imageWrite(commonSet, 1, VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT, &depthInfo);
        vkUpdateDescriptorSets(device, 1, &write, 0, null);
    }

    void updateCommonUbo(VkDevice device, float[16] viewProjection, float[16] inverseProjection, float fogDensity, float time, float[4] lightDirection) {
        ubyte[COMMON_UBO_BYTES] data = 0;
        memcpy(data.ptr + COMMON_VIEW_PROJECTION_OFFSET, viewProjection.ptr, MATRIX_BYTES);
        memcpy(data.ptr + COMMON_INVERSE_PROJECTION_OFFSET, inverseProjection.ptr, MATRIX_BYTES);
        memcpy(data.ptr + COMMON_FOG_DENSITY_OFFSET, &fogDensity, float.sizeof);
        memcpy(data.ptr + COMMON_TIME_OFFSET, &time, float.sizeof);
        memcpy(data.ptr + COMMON_LIGHT_OFFSET, lightDirection.ptr, lightDirection.sizeof);
        void* mapped;
        vkMapMemory(device, commonUbo.memory, 0, COMMON_UBO_BYTES, 0, &mapped);
        memcpy(mapped, data.ptr, COMMON_UBO_BYTES);
        vkUnmapMemory(device, commonUbo.memory);
    }

    void cleanup(VkDevice device) {
        vkDestroyPipeline(device, pipeline, null);
        vkDestroyPipelineLayout(device, pipelineLayout, null);
        vkDestroyDescriptorPool(device, descriptorPool, null);
        vkDestroyDescriptorSetLayout(device, commonLayout, null);
        vkDestroyDescriptorSetLayout(device, staticLayout, null);
        vkDestroySampler(device, textureSampler, null);
        vkDestroyImageView(device, textureView, null);
        vkDestroyImage(device, textureImage, null);
        vkFreeMemory(device, textureMemory, null);
        destroyBuffer(device, &commonUbo);
        destroyBuffer(device, &transformsVbo);
    }
}
