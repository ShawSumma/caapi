module client.graphics.post;

import bindings.platform : VK_ACCESS_COLOR_ATTACHMENT_READ_BIT, VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT, VK_ACCESS_SHADER_READ_BIT, VK_ACCESS_TRANSFER_READ_BIT, VK_ATTACHMENT_LOAD_OP_DONT_CARE, VK_ATTACHMENT_STORE_OP_STORE, VK_DEPENDENCY_BY_REGION_BIT, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, VK_FILTER_LINEAR, VK_IMAGE_ASPECT_COLOR_BIT, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT, VK_IMAGE_USAGE_SAMPLED_BIT, VK_PIPELINE_BIND_POINT_GRAPHICS, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE, VK_SAMPLER_MIPMAP_MODE_NEAREST, VK_SAMPLE_COUNT_1_BIT, VK_SHADER_STAGE_FRAGMENT_BIT, VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO, VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO, VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO, VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO, VK_SUBPASS_CONTENTS_INLINE, VkAttachmentDescription, VkAttachmentReference, VkCommandBuffer, VkDescriptorImageInfo, VkDescriptorPool, VkDescriptorPoolCreateInfo, VkDescriptorPoolSize, VkDescriptorSet, VkDescriptorSetAllocateInfo, VkDescriptorSetLayout, VkDescriptorSetLayoutBinding, VkDevice, VkDeviceMemory, VkExtent2D, VkFramebuffer, VkFramebufferCreateInfo, VkImage, VkImageView, VkPhysicalDevice, VkPipeline, VkPipelineLayout, VkPushConstantRange, VkRect2D, VkRenderPass, VkRenderPassBeginInfo, VkRenderPassCreateInfo, VkSampler, VkSamplerCreateInfo, VkShaderModule, VkSubpassDependency, VkSubpassDescription, VkViewport, VkWriteDescriptorSet, vkAllocateDescriptorSets, vkCmdBeginRenderPass, vkCmdBindDescriptorSets, vkCmdBindPipeline, vkCmdDraw, vkCmdEndRenderPass, vkCmdPushConstants, vkCmdSetScissor, vkCmdSetViewport, vkCreateDescriptorPool, vkCreateFramebuffer, vkCreateRenderPass, vkCreateSampler, vkDestroyDescriptorPool, vkDestroyDescriptorSetLayout, vkDestroyFramebuffer, vkDestroyImage, vkDestroyImageView, vkDestroyPipeline, vkDestroyPipelineLayout, vkDestroyRenderPass, vkDestroySampler, vkDestroyShaderModule, vkFreeMemory, vkUpdateDescriptorSets;
import base.numbers : higherOf;
import client.graphics.base : MAX_SWAPCHAIN_IMAGES, SCENE_FORMAT, SwapchainState, createImage, createImageView;
import client.graphics.fog : FULLSCREEN_TRIANGLE_VERTICES, FULLSCREEN_VERT_SPV;
import client.graphics.pipeline : Blend, Culling, Depth, Outputs, PipelineSettings, SUBPASS_EXTERNAL, bindDeviceLocalImage, createGraphicsPipeline, createPipelineLayout, createSetLayout, createShader, expectSuccess, imageWrite, layoutBinding;
import client.graphics.renderer : imageBarrier;
import client.graphics.uniforms : PostSettings;
import common.perception : BAND_COUNT;

enum string REDUCE_FRAG_SPV = import("reduce.frag.spv");
enum string POST_FRAG_SPV = import("post.frag.spv");
enum uint PYRAMID_LEVELS = BAND_COUNT;
enum uint HISTORY_COUNT = 2;
enum uint FINER_BINDING = 0;
enum uint SCENE_BINDING = 0;
enum uint PREVIOUS_BINDING = 1;
enum uint FIRST_LEVEL_BINDING = 2;
enum uint POST_SAMPLERS = FIRST_LEVEL_BINDING + PYRAMID_LEVELS;
enum uint SAMPLER_DESCRIPTORS = PYRAMID_LEVELS + HISTORY_COUNT * POST_SAMPLERS;
enum uint POST_SETS = PYRAMID_LEVELS + HISTORY_COUNT;
enum uint REDUCE_DEPENDENCIES = 2;
enum uint PRESENTING_COMPOSITE_DEPENDENCIES = 3;
enum uint OFFSCREEN_COMPOSITE_DEPENDENCIES = 4;

enum History : ubyte {
    fresh,
    kept,
}

struct Target {
    VkImage image;
    VkDeviceMemory memory;
    VkImageView view;
    VkExtent2D extent;

    static Target make(VkPhysicalDevice physicalDevice, VkDevice device, VkExtent2D extent) {
        Target made;
        made.extent = extent;
        made.image = createImage(device, SCENE_FORMAT, extent, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT);
        made.memory = bindDeviceLocalImage(physicalDevice, device, made.image);
        made.view = createImageView(device, made.image, SCENE_FORMAT, VK_IMAGE_ASPECT_COLOR_BIT);
        return made;
    }

    void destroy(VkDevice device) {
        vkDestroyImageView(device, view, null);
        vkDestroyImage(device, image, null);
        vkFreeMemory(device, memory, null);
        this = Target.init;
    }
}

struct PostChain {
    Target[PYRAMID_LEVELS] levels;
    Target[HISTORY_COUNT] histories;
    VkFramebuffer[PYRAMID_LEVELS] levelFramebuffers;
    VkFramebuffer[MAX_SWAPCHAIN_IMAGES * HISTORY_COUNT] compositeFramebuffers;
    VkDescriptorSet[PYRAMID_LEVELS] reduceSets;
    VkDescriptorSet[HISTORY_COUNT] postSets;
    VkRenderPass reducePass;
    VkRenderPass compositePass;
    VkDescriptorSetLayout reduceLayout;
    VkDescriptorSetLayout postLayout;
    VkDescriptorPool pool;
    VkPipelineLayout reducePipelineLayout;
    VkPipelineLayout postPipelineLayout;
    VkPipeline reducePipeline;
    VkPipeline postPipeline;
    VkSampler sampler;
    uint current;
    History history;

    void setup(VkPhysicalDevice physicalDevice, VkDevice device, ref SwapchainState swapchain) {
        createSampler(device);
        VkDescriptorSetLayoutBinding[1] reduceBindings = [
            layoutBinding(FINER_BINDING, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, VK_SHADER_STAGE_FRAGMENT_BIT),
        ];
        reduceLayout = createSetLayout(device, reduceBindings[]);
        VkDescriptorSetLayoutBinding[POST_SAMPLERS] postBindings;
        foreach (binding; 0 .. POST_SAMPLERS) {
            postBindings[binding] = layoutBinding(binding, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, VK_SHADER_STAGE_FRAGMENT_BIT);
        }
        postLayout = createSetLayout(device, postBindings[]);
        allocateSets(device);
        reducePass = createReducePass(device);
        compositePass = createCompositePass(device, swapchain);
        VkDescriptorSetLayout[1] reduceLayouts = [
            reduceLayout,
        ];
        reducePipelineLayout = createPipelineLayout(device, reduceLayouts[], null);
        VkDescriptorSetLayout[1] postLayouts = [
            postLayout,
        ];
        VkPushConstantRange[1] pushConstants = [
            VkPushConstantRange(VK_SHADER_STAGE_FRAGMENT_BIT, 0, PostSettings.sizeof),
        ];
        postPipelineLayout = createPipelineLayout(device, postLayouts[], pushConstants[]);
        reducePipeline = fullscreenPipeline(device, reducePipelineLayout, reducePass, REDUCE_FRAG_SPV, Outputs.color);
        postPipeline = fullscreenPipeline(device, postPipelineLayout, compositePass, POST_FRAG_SPV, Outputs.colorAndHistory);
        rebuild(physicalDevice, device, swapchain);
    }

    void createSampler(VkDevice device) {
        VkSamplerCreateInfo info;
        info.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
        info.magFilter = VK_FILTER_LINEAR;
        info.minFilter = VK_FILTER_LINEAR;
        info.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST;
        info.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
        info.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
        info.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
        expectSuccess(vkCreateSampler(device, &info, null, &sampler));
    }

    void allocateSets(VkDevice device) {
        VkDescriptorPoolSize[1] sizes = [
            VkDescriptorPoolSize(VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, SAMPLER_DESCRIPTORS),
        ];
        VkDescriptorPoolCreateInfo poolInfo;
        poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        poolInfo.maxSets = POST_SETS;
        poolInfo.poolSizeCount = sizes.length;
        poolInfo.pPoolSizes = sizes.ptr;
        expectSuccess(vkCreateDescriptorPool(device, &poolInfo, null, &pool));
        VkDescriptorSetLayout[POST_SETS] setLayouts;
        foreach (level; 0 .. PYRAMID_LEVELS) {
            setLayouts[level] = reduceLayout;
        }
        foreach (index; 0 .. HISTORY_COUNT) {
            setLayouts[PYRAMID_LEVELS + index] = postLayout;
        }
        VkDescriptorSetAllocateInfo allocateInfo;
        allocateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        allocateInfo.descriptorPool = pool;
        allocateInfo.descriptorSetCount = setLayouts.length;
        allocateInfo.pSetLayouts = setLayouts.ptr;
        VkDescriptorSet[POST_SETS] allocated;
        expectSuccess(vkAllocateDescriptorSets(device, &allocateInfo, allocated.ptr));
        reduceSets = allocated[0 .. PYRAMID_LEVELS];
        postSets = allocated[PYRAMID_LEVELS .. POST_SETS];
    }

    void rebuild(VkPhysicalDevice physicalDevice, VkDevice device, ref SwapchainState swapchain) {
        destroySized(device);
        if (!swapchain.isMinimized()) {
            createSized(physicalDevice, device, swapchain);
        }
    }

    void createSized(VkPhysicalDevice physicalDevice, VkDevice device, ref SwapchainState swapchain) {
        VkExtent2D extent = swapchain.extent;
        foreach (level; 0 .. PYRAMID_LEVELS) {
            extent = VkExtent2D(higherOf(extent.width / 2, 1u), higherOf(extent.height / 2, 1u));
            levels[level] = Target.make(physicalDevice, device, extent);
            VkImageView[1] attachments = [
                levels[level].view,
            ];
            levelFramebuffers[level] = framebufferOf(device, reducePass, attachments[], extent);
        }
        foreach (index; 0 .. HISTORY_COUNT) {
            histories[index] = Target.make(physicalDevice, device, swapchain.extent);
        }
        foreach (image; 0 .. swapchain.imageCount) {
            foreach (index; 0 .. HISTORY_COUNT) {
                VkImageView[2] attachments = [
                    swapchain.imageViews[image],
                    histories[index].view,
                ];
                compositeFramebuffers[image * HISTORY_COUNT + index] = framebufferOf(device, compositePass, attachments[], swapchain.extent);
            }
        }
        writeSets(device, swapchain.sceneView);
        current = 0;
        history = History.fresh;
    }

    VkDescriptorImageInfo sampled(VkImageView view) {
        return VkDescriptorImageInfo(sampler, view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
    }

    void writeSets(VkDevice device, VkImageView sceneView) {
        VkDescriptorImageInfo[SAMPLER_DESCRIPTORS] infos;
        VkWriteDescriptorSet[SAMPLER_DESCRIPTORS] writes;
        uint count = 0;
        foreach (level; 0 .. PYRAMID_LEVELS) {
            infos[count] = sampled(sceneView);
            if (level > 0) {
                infos[count] = sampled(levels[level - 1].view);
            }
            writes[count] = imageWrite(reduceSets[level], FINER_BINDING, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, &infos[count]);
            count += 1;
        }
        foreach (index; 0 .. HISTORY_COUNT) {
            foreach (binding; 0 .. POST_SAMPLERS) {
                infos[count] = sampled(postInput(binding, index, sceneView));
                writes[count] = imageWrite(postSets[index], binding, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, &infos[count]);
                count += 1;
            }
        }
        vkUpdateDescriptorSets(device, count, writes.ptr, 0, null);
    }

    VkImageView postInput(uint binding, uint index, VkImageView sceneView) {
        if (binding == SCENE_BINDING) {
            return sceneView;
        } else if (binding == PREVIOUS_BINDING) {
            return histories[(index + 1) % HISTORY_COUNT].view;
        } else {
            return levels[binding - FIRST_LEVEL_BINDING].view;
        }
    }

    void recordReduce(VkCommandBuffer commands) {
        foreach (level; 0 .. PYRAMID_LEVELS) {
            beginPass(commands, reducePass, levelFramebuffers[level], levels[level].extent);
            vkCmdBindPipeline(commands, VK_PIPELINE_BIND_POINT_GRAPHICS, reducePipeline);
            vkCmdBindDescriptorSets(commands, VK_PIPELINE_BIND_POINT_GRAPHICS, reducePipelineLayout, 0, 1, &reduceSets[level], 0, null);
            vkCmdDraw(commands, FULLSCREEN_TRIANGLE_VERTICES, 1, 0, 0);
            vkCmdEndRenderPass(commands);
        }
    }

    void beginComposite(VkCommandBuffer commands, uint imageIndex, VkExtent2D extent, PostSettings settings) {
        PostSettings pushed = settings;
        if (history == History.fresh) {
            imageBarrier(commands, histories[(current + 1) % HISTORY_COUNT].image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, 0, VK_ACCESS_SHADER_READ_BIT, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);
            pushed.afterimage = 0;
        }
        beginPass(commands, compositePass, compositeFramebuffers[imageIndex * HISTORY_COUNT + current], extent);
        vkCmdBindPipeline(commands, VK_PIPELINE_BIND_POINT_GRAPHICS, postPipeline);
        vkCmdBindDescriptorSets(commands, VK_PIPELINE_BIND_POINT_GRAPHICS, postPipelineLayout, 0, 1, &postSets[current], 0, null);
        vkCmdPushConstants(commands, postPipelineLayout, VK_SHADER_STAGE_FRAGMENT_BIT, 0, PostSettings.sizeof, &pushed);
        vkCmdDraw(commands, FULLSCREEN_TRIANGLE_VERTICES, 1, 0, 0);
    }

    void advance() {
        current = (current + 1) % HISTORY_COUNT;
        history = History.kept;
    }

    void destroySized(VkDevice device) {
        foreach (ref framebuffer; levelFramebuffers) {
            vkDestroyFramebuffer(device, framebuffer, null);
            framebuffer = null;
        }
        foreach (ref framebuffer; compositeFramebuffers) {
            vkDestroyFramebuffer(device, framebuffer, null);
            framebuffer = null;
        }
        foreach (ref level; levels) {
            level.destroy(device);
        }
        foreach (ref kept; histories) {
            kept.destroy(device);
        }
    }

    void cleanup(VkDevice device) {
        destroySized(device);
        vkDestroyPipeline(device, postPipeline, null);
        vkDestroyPipeline(device, reducePipeline, null);
        vkDestroyPipelineLayout(device, postPipelineLayout, null);
        vkDestroyPipelineLayout(device, reducePipelineLayout, null);
        vkDestroyDescriptorPool(device, pool, null);
        vkDestroyDescriptorSetLayout(device, postLayout, null);
        vkDestroyDescriptorSetLayout(device, reduceLayout, null);
        vkDestroyRenderPass(device, compositePass, null);
        vkDestroyRenderPass(device, reducePass, null);
        vkDestroySampler(device, sampler, null);
    }
}

void beginPass(VkCommandBuffer commands, VkRenderPass pass, VkFramebuffer framebuffer, VkExtent2D extent) {
    VkRenderPassBeginInfo info;
    info.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    info.renderPass = pass;
    info.framebuffer = framebuffer;
    info.renderArea.extent = extent;
    vkCmdBeginRenderPass(commands, &info, VK_SUBPASS_CONTENTS_INLINE);
    VkViewport viewport = VkViewport(0, 0, cast(float) extent.width, cast(float) extent.height, 0, 1);
    vkCmdSetViewport(commands, 0, 1, &viewport);
    VkRect2D scissor;
    scissor.extent = extent;
    vkCmdSetScissor(commands, 0, 1, &scissor);
}

VkFramebuffer framebufferOf(VkDevice device, VkRenderPass pass, VkImageView[] attachments, VkExtent2D extent) {
    VkFramebufferCreateInfo info;
    info.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
    info.renderPass = pass;
    info.attachmentCount = cast(uint) attachments.length;
    info.pAttachments = attachments.ptr;
    info.width = extent.width;
    info.height = extent.height;
    info.layers = 1;
    VkFramebuffer made;
    expectSuccess(vkCreateFramebuffer(device, &info, null, &made));
    return made;
}

VkPipeline fullscreenPipeline(VkDevice device, VkPipelineLayout layout, VkRenderPass pass, const(char)[] fragment, Outputs outputs) {
    VkShaderModule vertexShader = createShader(device, FULLSCREEN_VERT_SPV);
    VkShaderModule fragmentShader = createShader(device, fragment);
    PipelineSettings settings = PipelineSettings(
        layout,
        pass,
        vertexShader,
        fragmentShader,
        VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        0,
        Blend.opaque,
        Depth.ignored,
        Culling.none,
        outputs,
    );
    VkPipeline made = createGraphicsPipeline(device, settings);
    vkDestroyShaderModule(device, vertexShader, null);
    vkDestroyShaderModule(device, fragmentShader, null);
    return made;
}

VkAttachmentDescription sampledTarget(VkAttachmentDescription described) {
    VkAttachmentDescription made = described;
    made.samples = VK_SAMPLE_COUNT_1_BIT;
    made.loadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    made.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    made.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    return made;
}

VkSubpassDependency writtenForSampling(uint subpass) {
    VkSubpassDependency dependency;
    dependency.srcSubpass = subpass;
    dependency.dstSubpass = SUBPASS_EXTERNAL;
    dependency.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dependency.dstStageMask = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    dependency.srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    dependency.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
    return dependency;
}

VkSubpassDependency afterSampling() {
    VkSubpassDependency dependency;
    dependency.srcSubpass = SUBPASS_EXTERNAL;
    dependency.dstSubpass = 0;
    dependency.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    dependency.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dependency.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    return dependency;
}

VkRenderPass createReducePass(VkDevice device) {
    VkAttachmentDescription described;
    described.format = SCENE_FORMAT;
    described.finalLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    VkAttachmentDescription[1] attachments = [
        sampledTarget(described),
    ];
    VkAttachmentReference color = VkAttachmentReference(0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);
    VkSubpassDescription subpass;
    subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = 1;
    subpass.pColorAttachments = &color;
    VkSubpassDependency[REDUCE_DEPENDENCIES] dependencies = [
        afterSampling(),
        writtenForSampling(0),
    ];
    VkRenderPassCreateInfo info;
    info.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    info.attachmentCount = attachments.length;
    info.pAttachments = attachments.ptr;
    info.subpassCount = 1;
    info.pSubpasses = &subpass;
    info.dependencyCount = dependencies.length;
    info.pDependencies = dependencies.ptr;
    VkRenderPass made;
    expectSuccess(vkCreateRenderPass(device, &info, null, &made));
    return made;
}

uint compositeDependencyCount(ref const SwapchainState swapchain) {
    if (swapchain.isOffscreen) {
        return OFFSCREEN_COMPOSITE_DEPENDENCIES;
    } else {
        return PRESENTING_COMPOSITE_DEPENDENCIES;
    }
}

VkRenderPass createCompositePass(VkDevice device, ref const SwapchainState swapchain) {
    VkAttachmentDescription display;
    display.format = swapchain.format;
    display.finalLayout = swapchain.colorFinalLayout();
    VkAttachmentDescription kept;
    kept.format = SCENE_FORMAT;
    kept.finalLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    VkAttachmentDescription[2] attachments = [
        sampledTarget(display),
        sampledTarget(kept),
    ];
    VkAttachmentReference[2] postColors = [
        VkAttachmentReference(0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL),
        VkAttachmentReference(1, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL),
    ];
    VkSubpassDescription[2] subpasses;
    subpasses[0].pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpasses[0].colorAttachmentCount = postColors.length;
    subpasses[0].pColorAttachments = postColors.ptr;
    subpasses[1].pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpasses[1].colorAttachmentCount = 1;
    subpasses[1].pColorAttachments = postColors.ptr;
    VkSubpassDependency overlay;
    overlay.srcSubpass = 0;
    overlay.dstSubpass = 1;
    overlay.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    overlay.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    overlay.srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    overlay.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    overlay.dependencyFlags = VK_DEPENDENCY_BY_REGION_BIT;
    VkSubpassDependency readback;
    readback.srcSubpass = 1;
    readback.dstSubpass = SUBPASS_EXTERNAL;
    readback.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    readback.dstStageMask = VK_PIPELINE_STAGE_TRANSFER_BIT;
    readback.srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    readback.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    VkSubpassDependency[OFFSCREEN_COMPOSITE_DEPENDENCIES] dependencies = [
        afterSampling(),
        overlay,
        writtenForSampling(0),
        readback,
    ];
    VkRenderPassCreateInfo info;
    info.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    info.attachmentCount = attachments.length;
    info.pAttachments = attachments.ptr;
    info.subpassCount = subpasses.length;
    info.pSubpasses = subpasses.ptr;
    info.dependencyCount = compositeDependencyCount(swapchain);
    info.pDependencies = dependencies.ptr;
    VkRenderPass made;
    expectSuccess(vkCreateRenderPass(device, &info, null, &made));
    return made;
}
