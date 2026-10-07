module client.graphics.voxels.surface;

import core.stdc.stdlib : free, malloc;
import bindings.platform : VK_ACCESS_SHADER_READ_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, VK_COMMAND_BUFFER_LEVEL_PRIMARY, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, VK_FILTER_LINEAR, VK_FORMAT_R8G8B8A8_SRGB, VK_IMAGE_ASPECT_COLOR_BIT, VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_TILING_OPTIMAL, VK_IMAGE_TYPE_2D, VK_IMAGE_USAGE_SAMPLED_BIT, VK_IMAGE_USAGE_TRANSFER_DST_BIT, VK_IMAGE_VIEW_TYPE_2D_ARRAY, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, VK_SAMPLER_ADDRESS_MODE_REPEAT, VK_SAMPLER_MIPMAP_MODE_NEAREST, VK_SAMPLE_COUNT_1_BIT, VK_SHADER_STAGE_FRAGMENT_BIT, VK_SHADER_STAGE_VERTEX_BIT, VK_SHARING_MODE_EXCLUSIVE, VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO, VK_STRUCTURE_TYPE_SUBMIT_INFO, VkBuffer, VkBufferImageCopy, VkCommandBuffer, VkCommandBufferAllocateInfo, VkCommandBufferBeginInfo, VkCommandPool, VkDescriptorBufferInfo, VkDescriptorImageInfo, VkDescriptorPool, VkDescriptorPoolCreateInfo, VkDescriptorPoolSize, VkDescriptorSet, VkDescriptorSetAllocateInfo, VkDescriptorSetLayout, VkDescriptorSetLayoutBinding, VkDevice, VkDeviceMemory, VkExtent3D, VkImage, VkImageCreateInfo, VkImageMemoryBarrier, VkImageSubresourceLayers, VkImageSubresourceRange, VkImageView, VkImageViewCreateInfo, VkPhysicalDevice, VkPipeline, VkPipelineLayout, VkPushConstantRange, VkQueue, VkRenderPass, VkSampler, VkSamplerCreateInfo, VkShaderModule, VkSubmitInfo, VkWriteDescriptorSet, vkAllocateCommandBuffers, vkAllocateDescriptorSets, vkBeginCommandBuffer, vkCmdCopyBufferToImage, vkCmdPipelineBarrier, vkCreateDescriptorPool, vkCreateImage, vkCreateImageView, vkCreateSampler, vkDestroyDescriptorPool, vkDestroyDescriptorSetLayout, vkDestroyImage, vkDestroyImageView, vkDestroyPipeline, vkDestroyPipelineLayout, vkDestroySampler, vkDestroyShaderModule, vkEndCommandBuffer, vkFreeCommandBuffers, vkFreeMemory, vkQueueSubmit, vkQueueWaitIdle, vkUpdateDescriptorSets;
import client.graphics.frustum : FRUSTUM_PLANE_COUNT;
import client.graphics.matrices : MATRIX_FLOATS;
import client.graphics.pipeline : Blend, GpuBuffer, PipelineSettings, QUEUE_FAMILY_IGNORED, WHOLE_SIZE, bindDeviceLocalImage, bufferWrite, createGraphicsPipeline, createPipelineLayout, createSetLayout, createShader, expectSuccess, imageWrite, layoutBinding;
import common.material : Material;

enum string VOXELS_VERT_SPV = import("voxels.vert.spv");
enum string VOXELS_FRAG_SPV = import("voxels.frag.spv");
enum uint TEXTURE_SIZE = 16;
enum ubyte TEXTURE_OPAQUE = 255;
enum uint TEXTURE_LAYERS = Material.max;
enum uint TEXEL_BYTES = 4;
enum uint COLOR_CHANNELS = 3;

immutable ubyte[COLOR_CHANNELS][TEXTURE_LAYERS] MATERIAL_SRGB = [
    [120, 85, 58],
    [219, 203, 150],
    [160, 140, 110],
    [170, 110, 80],
    [90, 70, 50],
    [150, 120, 80],
    [130, 105, 75],
    [135, 90, 65],
    [190, 100, 60],
    [200, 195, 175],
    [95, 95, 100],
    [210, 205, 190],
    [205, 175, 125],
    [170, 80, 55],
    [235, 235, 230],
    [75, 80, 90],
    [165, 150, 145],
    [200, 200, 195],
    [130, 130, 130],
    [60, 60, 60],
    [50, 50, 55],
    [110, 130, 60],
    [50, 90, 170],
    [220, 80, 20],
    [105, 75, 45],
    [60, 120, 40],
    [180, 140, 90],
    [130, 130, 135],
    [220, 220, 215],
    [180, 215, 240],
    [200, 220, 230],
    [135, 130, 125],
    [245, 248, 250],
    [110, 130, 60],
    [170, 160, 90],
    [70, 150, 50],
    [90, 110, 50],
    [90, 140, 50],
    [70, 100, 80],
    [215, 210, 195],
    [125, 175, 70],
    [80, 58, 38],
    [45, 85, 55],
    [165, 205, 225],
    [160, 160, 155],
    [115, 120, 130],
];
enum uint FACES_BINDING = 0;
enum uint TEXTURE_BINDING = 1;
enum uint TRANSFORMS_BINDING = 2;
enum uint COMMON_UBO_BINDING = 0;
enum uint DEPTH_INPUT_BINDING = 1;

struct LayoutPush {
    uint dimension;
    float cellRatio;
}

struct CommonUniforms {
    float[MATRIX_FLOATS] projection;
    float[MATRIX_FLOATS] inverseProjection;
    float[MATRIX_FLOATS] cameraInverse;
    float[4][FRUSTUM_PLANE_COUNT] frustumPlanes;
    float[4] fogColor;
    float fogDensity;
    float fogExponent;
    float viewParity;
    float cullSinhRadius;
}

struct SurfacePipeline {
    GpuBuffer commonUbo;
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

    void setup(VkPhysicalDevice physicalDevice, VkDevice device, VkRenderPass renderPass, VkQueue queue, VkCommandPool commandPool, VkImageView depthView) {
        VkDescriptorSetLayoutBinding[2] commonBindings = [
            layoutBinding(COMMON_UBO_BINDING, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT),
            layoutBinding(DEPTH_INPUT_BINDING, VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT, VK_SHADER_STAGE_FRAGMENT_BIT),
        ];
        commonLayout = createSetLayout(device, commonBindings[]);
        VkDescriptorSetLayoutBinding[3] staticBindings = [
            layoutBinding(FACES_BINDING, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_VERTEX_BIT),
            layoutBinding(TEXTURE_BINDING, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, VK_SHADER_STAGE_FRAGMENT_BIT),
            layoutBinding(TRANSFORMS_BINDING, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_VERTEX_BIT),
        ];
        staticLayout = createSetLayout(device, staticBindings[]);
        allocateSets(device);
        commonUbo = GpuBuffer.makeMapped(physicalDevice, device, CommonUniforms.sizeof, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
        createTextureArray(physicalDevice, device, queue, commandPool);
        writeDescriptors(device, depthView);
        createPipeline(device, renderPass);
    }

    void allocateSets(VkDevice device) {
        VkDescriptorPoolSize[4] sizes = [
            VkDescriptorPoolSize(VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1),
            VkDescriptorPoolSize(VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 2),
            VkDescriptorPoolSize(VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1),
            VkDescriptorPoolSize(VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT, 1),
        ];
        VkDescriptorPoolCreateInfo poolInfo;
        poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        poolInfo.maxSets = 2;
        poolInfo.poolSizeCount = sizes.length;
        poolInfo.pPoolSizes = sizes.ptr;
        expectSuccess(vkCreateDescriptorPool(device, &poolInfo, null, &descriptorPool));
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
        expectSuccess(vkAllocateDescriptorSets(device, &allocateInfo, allocated.ptr));
        commonSet = allocated[0];
        staticSet = allocated[1];
    }

    void writeDescriptors(VkDevice device, VkImageView depthView) {
        VkDescriptorBufferInfo commonInfo = VkDescriptorBufferInfo(commonUbo.buffer, 0, WHOLE_SIZE);
        VkDescriptorImageInfo textureInfo = VkDescriptorImageInfo(textureSampler, textureView, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
        VkDescriptorImageInfo depthInfo = VkDescriptorImageInfo(null, depthView, VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL);
        VkWriteDescriptorSet[3] writes = [
            bufferWrite(commonSet, COMMON_UBO_BINDING, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, &commonInfo),
            imageWrite(commonSet, DEPTH_INPUT_BINDING, VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT, &depthInfo),
            imageWrite(staticSet, TEXTURE_BINDING, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, &textureInfo),
        ];
        vkUpdateDescriptorSets(device, writes.length, writes.ptr, 0, null);
    }

    void bindStorage(VkDevice device, uint binding, VkBuffer buffer) {
        VkDescriptorBufferInfo info = VkDescriptorBufferInfo(buffer, 0, WHOLE_SIZE);
        VkWriteDescriptorSet write = bufferWrite(staticSet, binding, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, &info);
        vkUpdateDescriptorSets(device, 1, &write, 0, null);
    }

    void createPipeline(VkDevice device, VkRenderPass renderPass) {
        VkShaderModule vertexShader = createShader(device, VOXELS_VERT_SPV);
        VkShaderModule fragmentShader = createShader(device, VOXELS_FRAG_SPV);
        VkDescriptorSetLayout[2] setLayouts = [
            commonLayout,
            staticLayout,
        ];
        VkPushConstantRange[1] pushConstants = [
            VkPushConstantRange(VK_SHADER_STAGE_VERTEX_BIT, 0, LayoutPush.sizeof),
        ];
        pipelineLayout = createPipelineLayout(device, setLayouts[], pushConstants[]);
        PipelineSettings settings = PipelineSettings(
            pipelineLayout,
            renderPass,
            vertexShader,
            fragmentShader,
            VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            0,
            Blend.opaque,
            true,
            true,
            true,
        );
        pipeline = createGraphicsPipeline(device, settings);
        vkDestroyShaderModule(device, vertexShader, null);
        vkDestroyShaderModule(device, fragmentShader, null);
    }

    void createTextureArray(VkPhysicalDevice physicalDevice, VkDevice device, VkQueue queue, VkCommandPool commandPool) {
        size_t layerTexels = TEXTURE_SIZE * TEXTURE_SIZE;
        size_t totalBytes = layerTexels * TEXEL_BYTES * TEXTURE_LAYERS;
        ubyte* pixels = cast(ubyte*) malloc(totalBytes);
        foreach (texel; 0 .. layerTexels * TEXTURE_LAYERS) {
            pixels[texel * TEXEL_BYTES .. texel * TEXEL_BYTES + COLOR_CHANNELS] = MATERIAL_SRGB[texel / layerTexels][];
            pixels[texel * TEXEL_BYTES + COLOR_CHANNELS] = TEXTURE_OPAQUE;
        }
        GpuBuffer staging = GpuBuffer.makeFilled(physicalDevice, device, pixels[0 .. totalBytes], VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
        free(pixels);
        VkImageSubresourceRange range = VkImageSubresourceRange(VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, TEXTURE_LAYERS);
        createTextureImage(physicalDevice, device);
        uploadTexture(device, queue, commandPool, staging.buffer, range);
        staging.destroy(device);
        VkImageViewCreateInfo viewInfo;
        viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        viewInfo.image = textureImage;
        viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D_ARRAY;
        viewInfo.format = VK_FORMAT_R8G8B8A8_SRGB;
        viewInfo.subresourceRange = range;
        expectSuccess(vkCreateImageView(device, &viewInfo, null, &textureView));
        VkSamplerCreateInfo samplerInfo;
        samplerInfo.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
        samplerInfo.magFilter = VK_FILTER_LINEAR;
        samplerInfo.minFilter = VK_FILTER_LINEAR;
        samplerInfo.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST;
        samplerInfo.addressModeU = VK_SAMPLER_ADDRESS_MODE_REPEAT;
        samplerInfo.addressModeV = VK_SAMPLER_ADDRESS_MODE_REPEAT;
        samplerInfo.addressModeW = VK_SAMPLER_ADDRESS_MODE_REPEAT;
        expectSuccess(vkCreateSampler(device, &samplerInfo, null, &textureSampler));
    }

    void createTextureImage(VkPhysicalDevice physicalDevice, VkDevice device) {
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
        expectSuccess(vkCreateImage(device, &imageInfo, null, &textureImage));
        textureMemory = bindDeviceLocalImage(physicalDevice, device, textureImage);
    }

    void uploadTexture(VkDevice device, VkQueue queue, VkCommandPool commandPool, VkBuffer staging, VkImageSubresourceRange range) {
        VkCommandBufferAllocateInfo commandInfo;
        commandInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        commandInfo.commandPool = commandPool;
        commandInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        commandInfo.commandBufferCount = 1;
        VkCommandBuffer commands;
        expectSuccess(vkAllocateCommandBuffers(device, &commandInfo, &commands));
        recordTextureUpload(commands, staging, range);
        VkSubmitInfo submitInfo;
        submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submitInfo.commandBufferCount = 1;
        submitInfo.pCommandBuffers = &commands;
        expectSuccess(vkQueueSubmit(queue, 1, &submitInfo, null));
        expectSuccess(vkQueueWaitIdle(queue));
        vkFreeCommandBuffers(device, commandPool, 1, &commands);
    }

    void recordTextureUpload(VkCommandBuffer commands, VkBuffer staging, VkImageSubresourceRange range) {
        VkCommandBufferBeginInfo beginInfo;
        beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        vkBeginCommandBuffer(commands, &beginInfo);
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
        vkCmdCopyBufferToImage(commands, staging, textureImage, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        vkCmdPipelineBarrier(commands, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, null, 0, null, 1, &barrier);
        vkEndCommandBuffer(commands);
    }

    void updateDepthDescriptor(VkDevice device, VkImageView depthView) {
        VkDescriptorImageInfo depthInfo = VkDescriptorImageInfo(null, depthView, VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL);
        VkWriteDescriptorSet write = imageWrite(commonSet, DEPTH_INPUT_BINDING, VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT, &depthInfo);
        vkUpdateDescriptorSets(device, 1, &write, 0, null);
    }

    void updateCommonUbo(CommonUniforms uniforms) {
        *cast(CommonUniforms*) commonUbo.mapped = uniforms;
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
        commonUbo.destroy(device);
    }
}
