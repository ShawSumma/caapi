module client.graphics.overlay;

import core.stdc.string : memcpy;
import bindings.platform : VK_ACCESS_SHADER_READ_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_FILTER_NEAREST, VK_FORMAT_R8_UNORM, VK_IMAGE_ASPECT_COLOR_BIT, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_TILING_OPTIMAL, VK_IMAGE_TYPE_2D, VK_IMAGE_USAGE_SAMPLED_BIT, VK_IMAGE_USAGE_TRANSFER_DST_BIT, VK_IMAGE_VIEW_TYPE_2D, VK_PIPELINE_BIND_POINT_GRAPHICS, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE, VK_SAMPLER_MIPMAP_MODE_NEAREST, VK_SAMPLE_COUNT_1_BIT, VK_SHADER_STAGE_FRAGMENT_BIT, VK_SHADER_STAGE_VERTEX_BIT, VK_SHARING_MODE_EXCLUSIVE, VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO, VkBufferImageCopy, VkCommandBuffer, VkDescriptorBufferInfo, VkDescriptorImageInfo, VkDescriptorPool, VkDescriptorPoolCreateInfo, VkDescriptorPoolSize, VkDescriptorSet, VkDescriptorSetAllocateInfo, VkDescriptorSetLayout, VkDescriptorSetLayoutBinding, VkDevice, VkDeviceMemory, VkExtent3D, VkImage, VkImageCreateInfo, VkImageMemoryBarrier, VkImageSubresourceLayers, VkImageSubresourceRange, VkImageView, VkImageViewCreateInfo, VkPhysicalDevice, VkPipeline, VkPipelineLayout, VkPushConstantRange, VkRenderPass, VkSampler, VkSamplerCreateInfo, VkShaderModule, VkWriteDescriptorSet, vkAllocateDescriptorSets, vkCmdBindDescriptorSets, vkCmdBindPipeline, vkCmdCopyBufferToImage, vkCmdDraw, vkCmdPipelineBarrier, vkCmdPushConstants, vkCreateDescriptorPool, vkCreateImage, vkCreateImageView, vkCreateSampler, vkDestroyDescriptorPool, vkDestroyDescriptorSetLayout, vkDestroyImage, vkDestroyImageView, vkDestroyPipeline, vkDestroyPipelineLayout, vkDestroySampler, vkDestroyShaderModule, vkFreeMemory, vkUpdateDescriptorSets;
import base.maybe : Maybe;
import client.graphics.matrices : MATRIX_FLOATS, flatten;
import client.graphics.pipeline : Blend, Culling, Depth, GpuBuffer, Outputs, PipelineSettings, QUEUE_FAMILY_IGNORED, WHOLE_SIZE, bindDeviceLocalImage, bufferWrite, createGraphicsPipeline, createPipelineLayout, createSetLayout, createShader, expectSuccess, imageWrite, layoutBinding;
import client.hud : HudVertex, MOST_VERTICES, Marker;
import client.text : ATLAS_HEIGHT, ATLAS_WIDTH, GlyphAtlas;

enum string HUD_VERT_SPV = import("hud.vert.spv");
enum string HUD_FRAG_SPV = import("hud.frag.spv");
enum string MARKER_VERT_SPV = import("marker.vert.spv");
enum string MARKER_FRAG_SPV = import("marker.frag.spv");
enum uint HUD_SUBPASS = 1;
enum uint MARKER_SUBPASS = 0;
enum uint CUBE_VERTICES = 36;
enum uint HUD_VERTICES_BINDING = 0;
enum uint HUD_ATLAS_BINDING = 1;

struct HudPipeline {
    GpuBuffer vertexBuffer;
    GpuBuffer atlasStaging;
    VkDescriptorSetLayout setLayout;
    VkDescriptorPool pool;
    VkDescriptorSet set;
    VkPipelineLayout pipelineLayout;
    VkPipeline pipeline;
    VkImage atlasImage;
    VkDeviceMemory atlasMemory;
    VkImageView atlasView;
    VkSampler atlasSampler;
    Maybe!uint uploadedRevision;
    uint vertexCount;

    void setup(VkPhysicalDevice physicalDevice, VkDevice device, VkRenderPass renderPass) {
        vertexBuffer = GpuBuffer.makeMapped(physicalDevice, device, MOST_VERTICES * HudVertex.sizeof, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
        atlasStaging = GpuBuffer.makeMapped(physicalDevice, device, cast(size_t) ATLAS_WIDTH * ATLAS_HEIGHT, VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
        createAtlas(physicalDevice, device);
        VkDescriptorSetLayoutBinding[2] bindings = [
            layoutBinding(HUD_VERTICES_BINDING, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_VERTEX_BIT),
            layoutBinding(HUD_ATLAS_BINDING, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, VK_SHADER_STAGE_FRAGMENT_BIT),
        ];
        setLayout = createSetLayout(device, bindings[]);
        VkDescriptorPoolSize[2] sizes = [
            VkDescriptorPoolSize(VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1),
            VkDescriptorPoolSize(VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1),
        ];
        VkDescriptorPoolCreateInfo poolInfo;
        poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        poolInfo.maxSets = 1;
        poolInfo.poolSizeCount = sizes.length;
        poolInfo.pPoolSizes = sizes.ptr;
        expectSuccess(vkCreateDescriptorPool(device, &poolInfo, null, &pool));
        VkDescriptorSetAllocateInfo allocateInfo;
        allocateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        allocateInfo.descriptorPool = pool;
        allocateInfo.descriptorSetCount = 1;
        allocateInfo.pSetLayouts = &setLayout;
        expectSuccess(vkAllocateDescriptorSets(device, &allocateInfo, &set));
        VkDescriptorBufferInfo info = VkDescriptorBufferInfo(vertexBuffer.buffer, 0, WHOLE_SIZE);
        VkDescriptorImageInfo atlasInfo = VkDescriptorImageInfo(atlasSampler, atlasView, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
        VkWriteDescriptorSet[2] writes = [
            bufferWrite(set, HUD_VERTICES_BINDING, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, &info),
            imageWrite(set, HUD_ATLAS_BINDING, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, &atlasInfo),
        ];
        vkUpdateDescriptorSets(device, writes.length, writes.ptr, 0, null);
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
            Outputs.color,
        );
        pipeline = createGraphicsPipeline(device, settings);
        vkDestroyShaderModule(device, vertexShader, null);
        vkDestroyShaderModule(device, fragmentShader, null);
    }

    void createAtlas(VkPhysicalDevice physicalDevice, VkDevice device) {
        VkImageCreateInfo imageInfo;
        imageInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
        imageInfo.imageType = VK_IMAGE_TYPE_2D;
        imageInfo.format = VK_FORMAT_R8_UNORM;
        imageInfo.extent = VkExtent3D(ATLAS_WIDTH, ATLAS_HEIGHT, 1);
        imageInfo.mipLevels = 1;
        imageInfo.arrayLayers = 1;
        imageInfo.samples = VK_SAMPLE_COUNT_1_BIT;
        imageInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
        imageInfo.usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
        imageInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
        imageInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        expectSuccess(vkCreateImage(device, &imageInfo, null, &atlasImage));
        atlasMemory = bindDeviceLocalImage(physicalDevice, device, atlasImage);
        VkImageViewCreateInfo viewInfo;
        viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        viewInfo.image = atlasImage;
        viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
        viewInfo.format = VK_FORMAT_R8_UNORM;
        viewInfo.subresourceRange = atlasRange();
        expectSuccess(vkCreateImageView(device, &viewInfo, null, &atlasView));
        VkSamplerCreateInfo samplerInfo;
        samplerInfo.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
        samplerInfo.magFilter = VK_FILTER_NEAREST;
        samplerInfo.minFilter = VK_FILTER_NEAREST;
        samplerInfo.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST;
        samplerInfo.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
        samplerInfo.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
        samplerInfo.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
        expectSuccess(vkCreateSampler(device, &samplerInfo, null, &atlasSampler));
    }

    void upload(const(HudVertex)[] vertices) {
        vertexCount = cast(uint) vertices.length;
        memcpy(vertexBuffer.mapped, vertices.ptr, vertices.length * HudVertex.sizeof);
    }

    void recordAtlasUpload(VkCommandBuffer commands, ref const GlyphAtlas atlas) {
        if (uploadedRevision != Maybe!uint.of(atlas.revision)) {
            memcpy(atlasStaging.mapped, atlas.pixels.ptr, atlas.pixels.length);
            VkImageMemoryBarrier barrier;
            barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
            barrier.srcAccessMask = VK_ACCESS_SHADER_READ_BIT;
            barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
            barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
            barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
            barrier.srcQueueFamilyIndex = QUEUE_FAMILY_IGNORED;
            barrier.dstQueueFamilyIndex = QUEUE_FAMILY_IGNORED;
            barrier.image = atlasImage;
            barrier.subresourceRange = atlasRange();
            vkCmdPipelineBarrier(commands, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, 0, null, 1, &barrier);
            VkBufferImageCopy region;
            region.imageSubresource = VkImageSubresourceLayers(VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1);
            region.imageExtent = VkExtent3D(ATLAS_WIDTH, ATLAS_HEIGHT, 1);
            vkCmdCopyBufferToImage(commands, atlasStaging.buffer, atlasImage, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
            barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
            barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
            barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
            barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
            vkCmdPipelineBarrier(commands, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, null, 0, null, 1, &barrier);
            uploadedRevision = Maybe!uint.of(atlas.revision);
        }
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
        vkDestroySampler(device, atlasSampler, null);
        vkDestroyImageView(device, atlasView, null);
        vkDestroyImage(device, atlasImage, null);
        vkFreeMemory(device, atlasMemory, null);
        atlasStaging.destroy(device);
        vertexBuffer.destroy(device);
    }
}

VkImageSubresourceRange atlasRange() {
    return VkImageSubresourceRange(VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1);
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
            Outputs.colorAndGlow,
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
