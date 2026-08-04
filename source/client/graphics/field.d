module client.graphics.field;

import std.stdio;
import bindings.vk;

enum uint PRODUCER_NONE = 0;
enum uint PRODUCER_DIFFUSION = 1;
enum uint PRODUCER_CYCLIC = 2;

// The field that drives perception.
//
// The interface is deliberately narrow: this owns a texture, and the voxel
// shader samples it. Anything able to fill an image is a valid producer, so
// replacing Gray-Scott means writing a different compute shader and changing
// nothing downstream.
struct PerceptionField {
    // Simulation resolution, independent of the window. The lattice wraps, so
    // the field is toroidal and tiles seamlessly over any viewport.
    enum uint SIZE = 512;
    enum uint WORKGROUP = 16;

    VkImage[2] images;
    VkDeviceMemory[2] memory;
    VkImageView[2] views;
    VkSampler sampler;

    VkShaderModule diffusionShader;
    VkShaderModule cyclicShader;
    VkDescriptorSetLayout setLayout;
    VkPipelineLayout pipelineLayout;
    VkPipeline diffusionPipeline;
    VkPipeline cyclicPipeline;
    VkDescriptorPool descPool;
    VkDescriptorSet[2] sets;

    bool ready;
    bool transitioned;
    bool seeded;

    // Gray-Scott. Feed and kill sit in a narrow window. Most pairs either die
    // out to a flat field or saturate; this one keeps growing and rearranging.
    float feed = 0.055f;
    float kill = 0.062f;
    float dt = 1.0f;

    // Steps per second, not per frame, so the pattern moves at the same speed
    // whatever the framerate. Diffusion is a slow partial differential
    // equation and needs a lot of them. The cyclic automaton advances a whole
    // cell per step, so a wavefront crosses the field in SIZE over rate
    // seconds, and the rate wants to be low.
    float diffusionRate = 1200.0f;
    float cyclicRate = 8.0f;
    float stepAccum = 0;

    // Threshold is the sensitive one. At one the waves sweep and organise into
    // spirals; higher values leave it stuck in a metastable speckle that never
    // resolves.
    float cyclicThreshold = 1.0f;
    float cyclicStates = 16.0f;

    static struct Push {
        float feed;
        float kill;
        float dt;
        uint seeding;
    }

    bool init(VkPhysicalDevice phys, VkDevice device) {
        VkPhysicalDeviceMemoryProperties memProps;
        vkGetPhysicalDeviceMemoryProperties(phys, &memProps);

        foreach (i; 0 .. 2) {
            VkImageCreateInfo ici;
            ici.sType = VkStructureType.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
            ici.imageType = VkImageType.VK_IMAGE_TYPE_2D;
            ici.format = VkFormat.VK_FORMAT_R32G32B32A32_SFLOAT;
            ici.extent = VkExtent3D(SIZE, SIZE, 1);
            ici.mipLevels = 1;
            ici.arrayLayers = 1;
            ici.samples = 1;
            ici.tiling = VkImageTiling.VK_IMAGE_TILING_OPTIMAL;
            uint storageBit = VkImageUsageFlagBits.VK_IMAGE_USAGE_STORAGE_BIT;
            uint sampledBit = VkImageUsageFlagBits.VK_IMAGE_USAGE_SAMPLED_BIT;
            ici.usage = storageBit | sampledBit;
            ici.sharingMode = VkSharingMode.VK_SHARING_MODE_EXCLUSIVE;
            ici.initialLayout = VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED;
            if (vkCreateImage(device, &ici, null, &images[i]) != VkResult.VK_SUCCESS) {
                return false;
            }

            VkMemoryRequirements req;
            vkGetImageMemoryRequirements(device, images[i], &req);
            uint memIdx = uint.max;
            for (uint j = 0; j < memProps.memoryTypeCount; j = j + 1) {
                bool typeAllowed = (req.memoryTypeBits & (1u << j)) != 0;
                uint deviceLocal = VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
                bool isDeviceLocal = (memProps.memoryTypes[j].propertyFlags & deviceLocal) != 0;
                if (typeAllowed && isDeviceLocal) {
                    memIdx = j;
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
            vkAllocateMemory(device, &mai, null, &memory[i]);
            vkBindImageMemory(device, images[i], memory[i], 0);

            VkImageViewCreateInfo ivci;
            ivci.sType = VkStructureType.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
            ivci.image = images[i];
            ivci.viewType = VkImageViewType.VK_IMAGE_VIEW_TYPE_2D;
            ivci.format = VkFormat.VK_FORMAT_R32G32B32A32_SFLOAT;
            ivci.subresourceRange = colorRange();
            if (vkCreateImageView(device, &ivci, null, &views[i]) != VkResult.VK_SUCCESS) {
                return false;
            }
        }

        VkSamplerCreateInfo sci;
        sci.sType = VkStructureType.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
        sci.magFilter = VK_FILTER_LINEAR;
        sci.minFilter = VK_FILTER_LINEAR;
        sci.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST;
        sci.addressModeU = VK_SAMPLER_ADDRESS_MODE_REPEAT;
        sci.addressModeV = VK_SAMPLER_ADDRESS_MODE_REPEAT;
        sci.addressModeW = VK_SAMPLER_ADDRESS_MODE_REPEAT;
        if (vkCreateSampler(device, &sci, null, &sampler) != VkResult.VK_SUCCESS) {
            return false;
        }

        static immutable ubyte[] rdSpv = cast(immutable(ubyte)[]) import("reaction.comp.spv");
        VkShaderModuleCreateInfo smci;
        smci.sType = VkStructureType.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
        smci.codeSize = rdSpv.length;
        smci.pCode = cast(const(uint)*) rdSpv.ptr;
        if (vkCreateShaderModule(device, &smci, null, &diffusionShader) != VkResult.VK_SUCCESS) {
            return false;
        }

        static immutable ubyte[] cycSpv = cast(immutable(ubyte)[]) import("cyclic.comp.spv");
        VkShaderModuleCreateInfo csmci;
        csmci.sType = VkStructureType.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
        csmci.codeSize = cycSpv.length;
        csmci.pCode = cast(const(uint)*) cycSpv.ptr;
        if (vkCreateShaderModule(device, &csmci, null, &cyclicShader) != VkResult.VK_SUCCESS) {
            return false;
        }

        VkDescriptorSetLayoutBinding[2] binds;
        foreach (i; 0 .. 2) {
            binds[i].binding = cast(uint) i;
            binds[i].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
            binds[i].descriptorCount = 1;
            binds[i].stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT;
        }
        VkDescriptorSetLayoutCreateInfo dlci;
        dlci.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
        dlci.bindingCount = 2;
        dlci.pBindings = binds.ptr;
        vkCreateDescriptorSetLayout(device, &dlci, null, &setLayout);

        VkDescriptorPoolSize size;
        size.type = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
        size.descriptorCount = 4;
        VkDescriptorPoolCreateInfo dpci;
        dpci.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        dpci.maxSets = 2;
        dpci.poolSizeCount = 1;
        dpci.pPoolSizes = &size;
        vkCreateDescriptorPool(device, &dpci, null, &descPool);

        VkDescriptorSetLayout[2] layouts = [setLayout, setLayout];
        VkDescriptorSetAllocateInfo dsai;
        dsai.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        dsai.descriptorPool = descPool;
        dsai.descriptorSetCount = 2;
        dsai.pSetLayouts = layouts.ptr;
        if (vkAllocateDescriptorSets(device, &dsai, sets.ptr) != VkResult.VK_SUCCESS) {
            return false;
        }

        // The first set reads image zero and writes image one; the second set
        // does the reverse.
        VkDescriptorImageInfo[4] infos;
        uint[4] viewIndex = [0, 1, 1, 0];
        foreach (i; 0 .. 4) {
            infos[i].sampler = 0;
            infos[i].imageView = views[viewIndex[i]];
            infos[i].imageLayout = VkImageLayout.VK_IMAGE_LAYOUT_GENERAL;
        }
        VkWriteDescriptorSet[4] writes;
        foreach (i; 0 .. 4) {
            writes[i].sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
            writes[i].dstSet = sets[i / 2];
            writes[i].dstBinding = cast(uint) (i % 2);
            writes[i].descriptorCount = 1;
            writes[i].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
            writes[i].pImageInfo = cast(const(void)*) &infos[i];
        }
        vkUpdateDescriptorSets(device, 4, writes.ptr, 0, null);

        VkPushConstantRange pcr;
        pcr.stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT;
        pcr.offset = 0;
        pcr.size = Push.sizeof;
        VkPipelineLayoutCreateInfo plci;
        plci.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
        plci.setLayoutCount = 1;
        plci.pSetLayouts = &setLayout;
        plci.pushConstantRangeCount = 1;
        plci.pPushConstantRanges = &pcr;
        if (vkCreatePipelineLayout(device, &plci, null, &pipelineLayout) != VkResult.VK_SUCCESS) {
            return false;
        }

        VkComputePipelineCreateInfo cpci;
        cpci.sType = VkStructureType.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
        cpci.stage.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        cpci.stage.stage = VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT;
        cpci.stage.mod = diffusionShader;
        cpci.stage.pName = "main";
        cpci.layout = pipelineLayout;
        VkResult res = vkCreateComputePipelines(device, 0, 1, &cpci, null, &diffusionPipeline);
        if (res != VkResult.VK_SUCCESS) {
            return false;
        }

        cpci.stage.mod = cyclicShader;
        res = vkCreateComputePipelines(device, 0, 1, &cpci, null, &cyclicPipeline);
        if (res != VkResult.VK_SUCCESS) {
            return false;
        }

        ready = true;
        writefln("Perception field initialized (%dx%d)", SIZE, SIZE);
        return true;
    }

    // Steps are always emitted in pairs so the result lands back in the first
    // image, which is the one the voxel shader samples. Its descriptor is
    // written once at init and never touched again.
    uint dueSteps(float frameDt, bool cyclic) {
        if (!seeded) {
            // Both producers start from noise and need a lot of steps to
            // organise, but should crawl once they have. Pay that cost once up
            // front instead of making the player watch static resolve.
            if (cyclic) {
                return 400;
            }
            return 2;
        }

        float rate = diffusionRate;
        if (cyclic) {
            rate = cyclicRate;
        }
        stepAccum = stepAccum + frameDt * rate;

        uint pairs = cast(uint) (stepAccum * 0.5f);
        if (pairs > 32) {
            // After a long stall, catch up a little rather than all at once.
            pairs = 32;
            stepAccum = 0;
        } else {
            stepAccum = stepAccum - pairs * 2.0f;
        }
        return pairs * 2;
    }

    // Advances the field. Recorded before the render pass, since the voxel
    // shader samples the result in the same frame. With no producer nothing
    // samples the image, and it is only transitioned so its descriptor stays
    // valid.
    void recordSteps(VkCommandBuffer cmd, uint producer, float frameDt) {
        if (!ready) {
            return;
        }

        if (!transitioned) {
            VkImageMemoryBarrier[2] toGeneral;
            foreach (i; 0 .. 2) {
                toGeneral[i] = barrier(
                    images[i],
                    0,
                    VkAccessFlagBits.VK_ACCESS_SHADER_WRITE_BIT,
                    VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED,
                    VkImageLayout.VK_IMAGE_LAYOUT_GENERAL
                );
            }
            uint computeStage = VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
            vkCmdPipelineBarrier(
                cmd,
                computeStage,
                computeStage,
                0,
                0,
                null,
                0,
                null,
                2,
                toGeneral.ptr
            );
            transitioned = true;
        }

        if (producer == PRODUCER_NONE) {
            return;
        }

        bool cyclic = producer == PRODUCER_CYCLIC;
        VkPipeline pipeline = diffusionPipeline;
        if (cyclic) {
            pipeline = cyclicPipeline;
        }

        uint steps = dueSteps(frameDt, cyclic);
        uint computeStage = VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
        if (steps > 0) {
            vkCmdBindPipeline(cmd, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
            uint groups = (SIZE + WORKGROUP - 1) / WORKGROUP;

            foreach (step; 0 .. steps) {
                Push push;
                push.feed = feed;
                push.kill = kill;
                if (cyclic) {
                    push.feed = cyclicThreshold;
                    push.kill = cyclicStates;
                }
                push.dt = dt;
                push.seeding = 0;
                if (!seeded && step == 0) {
                    push.seeding = 1;
                }

                vkCmdBindDescriptorSets(
                    cmd,
                    VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_COMPUTE,
                    pipelineLayout,
                    0,
                    1,
                    &sets[step % 2],
                    0,
                    null
                );
                vkCmdPushConstants(
                    cmd,
                    pipelineLayout,
                    VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT,
                    0,
                    Push.sizeof,
                    &push
                );
                vkCmdDispatch(cmd, groups, groups, 1);

                VkImageMemoryBarrier[2] between;
                foreach (i; 0 .. 2) {
                    between[i] = barrier(
                        images[i],
                        VkAccessFlagBits.VK_ACCESS_SHADER_WRITE_BIT,
                        VkAccessFlagBits.VK_ACCESS_SHADER_READ_BIT,
                        VkImageLayout.VK_IMAGE_LAYOUT_GENERAL,
                        VkImageLayout.VK_IMAGE_LAYOUT_GENERAL
                    );
                }
                vkCmdPipelineBarrier(
                    cmd,
                    computeStage,
                    computeStage,
                    0,
                    0,
                    null,
                    0,
                    null,
                    2,
                    between.ptr
                );
            }
            seeded = true;
        }

        VkImageMemoryBarrier toSample = barrier(
            images[0],
            VkAccessFlagBits.VK_ACCESS_SHADER_WRITE_BIT,
            VkAccessFlagBits.VK_ACCESS_SHADER_READ_BIT,
            VkImageLayout.VK_IMAGE_LAYOUT_GENERAL,
            VkImageLayout.VK_IMAGE_LAYOUT_GENERAL
        );
        vkCmdPipelineBarrier(
            cmd,
            computeStage,
            VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
            0,
            0,
            null,
            0,
            null,
            1,
            &toSample
        );
    }

    void cleanup(VkDevice device) {
        if (diffusionPipeline != VK_NULL_HANDLE) {
            vkDestroyPipeline(device, diffusionPipeline, null);
        }
        if (cyclicPipeline != VK_NULL_HANDLE) {
            vkDestroyPipeline(device, cyclicPipeline, null);
        }
        if (pipelineLayout != VK_NULL_HANDLE) {
            vkDestroyPipelineLayout(device, pipelineLayout, null);
        }
        if (descPool != VK_NULL_HANDLE) {
            vkDestroyDescriptorPool(device, descPool, null);
        }
        if (setLayout != VK_NULL_HANDLE) {
            vkDestroyDescriptorSetLayout(device, setLayout, null);
        }
        if (diffusionShader != VK_NULL_HANDLE) {
            vkDestroyShaderModule(device, diffusionShader, null);
        }
        if (cyclicShader != VK_NULL_HANDLE) {
            vkDestroyShaderModule(device, cyclicShader, null);
        }
        if (sampler != VK_NULL_HANDLE) {
            vkDestroySampler(device, sampler, null);
        }
        foreach (i; 0 .. 2) {
            if (views[i] != VK_NULL_HANDLE) {
                vkDestroyImageView(device, views[i], null);
            }
            if (images[i] != VK_NULL_HANDLE) {
                vkDestroyImage(device, images[i], null);
            }
            if (memory[i] != VK_NULL_HANDLE) {
                vkFreeMemory(device, memory[i], null);
            }
        }
    }
}

VkImageSubresourceRange colorRange() {
    return VkImageSubresourceRange(
        VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT,
        0,
        1,
        0,
        1
    );
}

VkImageMemoryBarrier barrier(
    VkImage image,
    uint srcAccess,
    uint dstAccess,
    VkImageLayout oldLayout,
    VkImageLayout newLayout,
) {
    VkImageMemoryBarrier b;
    b.sType = VkStructureType.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    b.srcAccessMask = srcAccess;
    b.dstAccessMask = dstAccess;
    b.oldLayout = oldLayout;
    b.newLayout = newLayout;
    b.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    b.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    b.image = image;
    b.subresourceRange = colorRange();
    return b;
}
