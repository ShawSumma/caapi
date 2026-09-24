module client.graphics.base;

import bindings.platform : VK_ACCESS_COLOR_ATTACHMENT_READ_BIT, VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT, VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT, VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT, VK_ACCESS_INPUT_ATTACHMENT_READ_BIT, VK_ATTACHMENT_LOAD_OP_CLEAR, VK_ATTACHMENT_STORE_OP_DONT_CARE, VK_ATTACHMENT_STORE_OP_STORE, VK_COMMAND_BUFFER_LEVEL_PRIMARY, VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT, VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR, VK_DEPENDENCY_BY_REGION_BIT, VK_FENCE_CREATE_SIGNALED_BIT, VK_FORMAT_D32_SFLOAT, VK_IMAGE_ASPECT_COLOR_BIT, VK_IMAGE_ASPECT_DEPTH_BIT, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL, VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_TILING_OPTIMAL, VK_IMAGE_TYPE_2D, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT, VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT, VK_IMAGE_VIEW_TYPE_2D, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, VK_PIPELINE_BIND_POINT_GRAPHICS, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT, VK_PRESENT_MODE_FIFO_KHR, VK_PRESENT_MODE_MAILBOX_KHR, VK_SAMPLE_COUNT_1_BIT, VK_SHARING_MODE_EXCLUSIVE, VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO, VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO, VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO, VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR, VK_SUCCESS, VkAttachmentDescription, VkAttachmentReference, VkCommandBuffer, VkCommandBufferAllocateInfo, VkCommandPool, VkCommandPoolCreateInfo, VkDevice, VkDeviceMemory, VkExtent2D, VkExtent3D, VkFence, VkFenceCreateInfo, VkFormat, VkFramebuffer, VkFramebufferCreateInfo, VkImage, VkImageAspectFlags, VkImageCreateInfo, VkImageView, VkImageViewCreateInfo, VkMemoryAllocateInfo, VkMemoryRequirements, VkPhysicalDevice, VkPresentModeKHR, VkRenderPass, VkRenderPassCreateInfo, VkSemaphore, VkSemaphoreCreateInfo, VkSubpassDependency, VkSubpassDescription, VkSurfaceCapabilitiesKHR, VkSurfaceFormatKHR, VkSurfaceKHR, VkSwapchainCreateInfoKHR, VkSwapchainKHR, vkAllocateCommandBuffers, vkAllocateMemory, vkBindImageMemory, vkCreateCommandPool, vkCreateFence, vkCreateFramebuffer, vkCreateImage, vkCreateImageView, vkCreateRenderPass, vkCreateSemaphore, vkCreateSwapchainKHR, vkDestroyCommandPool, vkDestroyFence, vkDestroyFramebuffer, vkDestroyImage, vkDestroyImageView, vkDestroyRenderPass, vkDestroySemaphore, vkDestroySwapchainKHR, vkDeviceWaitIdle, vkFreeMemory, vkGetImageMemoryRequirements, vkGetPhysicalDeviceSurfaceCapabilitiesKHR, vkGetPhysicalDeviceSurfaceFormatsKHR, vkGetPhysicalDeviceSurfacePresentModesKHR, vkGetSwapchainImagesKHR;
import client.graphics.pipeline : SUBPASS_EXTERNAL, VULKAN_TRUE, findMemoryType;

enum uint MAX_SWAPCHAIN_IMAGES = 8;
enum uint MAX_SURFACE_FORMATS = 64;
enum uint MAX_PRESENT_MODES = 16;
enum uint UNDEFINED_EXTENT = uint.max;

struct SwapchainState {
    VkImage[MAX_SWAPCHAIN_IMAGES] images;
    VkImageView[MAX_SWAPCHAIN_IMAGES] imageViews;
    VkFramebuffer[MAX_SWAPCHAIN_IMAGES] framebuffers;
    VkPhysicalDevice physicalDevice;
    VkSurfaceKHR surface;
    VkSwapchainKHR swapchain;
    VkImage depthImage;
    VkDeviceMemory depthMemory;
    VkImageView depthView;
    VkRenderPass renderPass;
    VkCommandPool commandPool;
    VkCommandBuffer commandBuffer;
    VkSemaphore imageAvailableSemaphore;
    VkSemaphore renderFinishedSemaphore;
    VkFence inFlightFence;
    VkExtent2D extent;
    VkFormat format;
    uint imageCount;

    bool setup(VkPhysicalDevice physical, VkDevice device, VkSurfaceKHR targetSurface, uint queueFamily) {
        physicalDevice = physical;
        surface = targetSurface;
        bool ok = createSwapchainResources(device);
        if (ok) {
            VkCommandPoolCreateInfo poolInfo;
            poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
            poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
            poolInfo.queueFamilyIndex = queueFamily;
            vkCreateCommandPool(device, &poolInfo, null, &commandPool);
            VkCommandBufferAllocateInfo allocateInfo;
            allocateInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
            allocateInfo.commandPool = commandPool;
            allocateInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
            allocateInfo.commandBufferCount = 1;
            vkAllocateCommandBuffers(device, &allocateInfo, &commandBuffer);
            createSemaphores(device);
            VkFenceCreateInfo fenceInfo;
            fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
            fenceInfo.flags = VK_FENCE_CREATE_SIGNALED_BIT;
            vkCreateFence(device, &fenceInfo, null, &inFlightFence);
        }
        return ok;
    }

    void createSemaphores(VkDevice device) {
        VkSemaphoreCreateInfo semaphoreInfo;
        semaphoreInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
        vkCreateSemaphore(device, &semaphoreInfo, null, &imageAvailableSemaphore);
        vkCreateSemaphore(device, &semaphoreInfo, null, &renderFinishedSemaphore);
    }

    bool recreate(VkDevice device) {
        vkDeviceWaitIdle(device);
        destroySwapchainResources(device);
        vkDestroySemaphore(device, imageAvailableSemaphore, null);
        vkDestroySemaphore(device, renderFinishedSemaphore, null);
        createSemaphores(device);
        return createSwapchainResources(device);
    }

    bool createSwapchainResources(VkDevice device) {
        VkSurfaceCapabilitiesKHR capabilities;
        vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice, surface, &capabilities);
        VkExtent2D previous = extent;
        extent = capabilities.currentExtent;
        if (extent.width == UNDEFINED_EXTENT) {
            extent.width = clampUint(previous.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width);
            extent.height = clampUint(previous.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height);
        }
        bool ok = extent.width != 0 && extent.height != 0;
        if (ok) {
            ok = createSwapchain(device, capabilities);
        }
        if (ok) {
            createDepthResources(device);
            if (renderPass is null) {
                ok = createRenderPass(device);
            }
        }
        if (ok) {
            foreach (i; 0 .. imageCount) {
                VkImageView[2] attachments = [
                    imageViews[i],
                    depthView,
                ];
                VkFramebufferCreateInfo framebufferInfo;
                framebufferInfo.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
                framebufferInfo.renderPass = renderPass;
                framebufferInfo.attachmentCount = 2;
                framebufferInfo.pAttachments = attachments.ptr;
                framebufferInfo.width = extent.width;
                framebufferInfo.height = extent.height;
                framebufferInfo.layers = 1;
                vkCreateFramebuffer(device, &framebufferInfo, null, &framebuffers[i]);
            }
        }
        return ok;
    }

    bool createSwapchain(VkDevice device, VkSurfaceCapabilitiesKHR capabilities) {
        VkSurfaceFormatKHR[MAX_SURFACE_FORMATS] formats;
        uint formatCount = MAX_SURFACE_FORMATS;
        vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface, &formatCount, formats.ptr);
        format = formats[0].format;
        uint wantedImages = capabilities.minImageCount + 1;
        if (capabilities.maxImageCount > 0 && wantedImages > capabilities.maxImageCount) {
            wantedImages = capabilities.maxImageCount;
        }
        VkSwapchainCreateInfoKHR info;
        info.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
        info.surface = surface;
        info.minImageCount = wantedImages;
        info.imageFormat = format;
        info.imageColorSpace = formats[0].colorSpace;
        info.imageExtent = extent;
        info.imageArrayLayers = 1;
        info.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
        info.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
        info.preTransform = capabilities.currentTransform;
        info.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
        info.presentMode = selectPresentMode(physicalDevice, surface);
        info.clipped = VULKAN_TRUE;
        bool ok = vkCreateSwapchainKHR(device, &info, null, &swapchain) == VK_SUCCESS;
        if (ok) {
            imageCount = MAX_SWAPCHAIN_IMAGES;
            vkGetSwapchainImagesKHR(device, swapchain, &imageCount, images.ptr);
            foreach (i; 0 .. imageCount) {
                imageViews[i] = createImageView(device, images[i], format, VK_IMAGE_ASPECT_COLOR_BIT);
            }
        }
        return ok;
    }

    void createDepthResources(VkDevice device) {
        VkImageCreateInfo imageInfo;
        imageInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
        imageInfo.imageType = VK_IMAGE_TYPE_2D;
        imageInfo.format = VK_FORMAT_D32_SFLOAT;
        imageInfo.extent = VkExtent3D(extent.width, extent.height, 1);
        imageInfo.mipLevels = 1;
        imageInfo.arrayLayers = 1;
        imageInfo.samples = VK_SAMPLE_COUNT_1_BIT;
        imageInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
        imageInfo.usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT;
        imageInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
        imageInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        vkCreateImage(device, &imageInfo, null, &depthImage);
        VkMemoryRequirements requirements;
        vkGetImageMemoryRequirements(device, depthImage, &requirements);
        VkMemoryAllocateInfo allocateInfo;
        allocateInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        allocateInfo.allocationSize = requirements.size;
        allocateInfo.memoryTypeIndex = findMemoryType(physicalDevice, requirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
        vkAllocateMemory(device, &allocateInfo, null, &depthMemory);
        vkBindImageMemory(device, depthImage, depthMemory, 0);
        depthView = createImageView(device, depthImage, VK_FORMAT_D32_SFLOAT, VK_IMAGE_ASPECT_DEPTH_BIT);
    }

    bool createRenderPass(VkDevice device) {
        VkAttachmentDescription[2] attachments;
        attachments[0].format = format;
        attachments[0].samples = VK_SAMPLE_COUNT_1_BIT;
        attachments[0].loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
        attachments[0].storeOp = VK_ATTACHMENT_STORE_OP_STORE;
        attachments[0].initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        attachments[0].finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        attachments[1].format = VK_FORMAT_D32_SFLOAT;
        attachments[1].samples = VK_SAMPLE_COUNT_1_BIT;
        attachments[1].loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
        attachments[1].storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
        attachments[1].initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        attachments[1].finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
        VkAttachmentReference colorReference = VkAttachmentReference(0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);
        VkAttachmentReference depthReference = VkAttachmentReference(1, VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL);
        VkAttachmentReference depthInputReference = VkAttachmentReference(1, VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL);
        VkSubpassDescription[2] subpasses;
        subpasses[0].pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
        subpasses[0].colorAttachmentCount = 1;
        subpasses[0].pColorAttachments = &colorReference;
        subpasses[0].pDepthStencilAttachment = &depthReference;
        subpasses[1].pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
        subpasses[1].colorAttachmentCount = 1;
        subpasses[1].pColorAttachments = &colorReference;
        subpasses[1].inputAttachmentCount = 1;
        subpasses[1].pInputAttachments = &depthInputReference;
        VkSubpassDependency[2] dependencies;
        dependencies[0].srcSubpass = SUBPASS_EXTERNAL;
        dependencies[0].dstSubpass = 0;
        dependencies[0].srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT;
        dependencies[0].dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
        dependencies[0].dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
        dependencies[1].srcSubpass = 0;
        dependencies[1].dstSubpass = 1;
        dependencies[1].srcStageMask = VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT | VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT;
        dependencies[1].dstStageMask = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
        dependencies[1].srcAccessMask = VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
        dependencies[1].dstAccessMask = VK_ACCESS_INPUT_ATTACHMENT_READ_BIT;
        dependencies[1].dependencyFlags = VK_DEPENDENCY_BY_REGION_BIT;
        VkRenderPassCreateInfo info;
        info.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
        info.attachmentCount = 2;
        info.pAttachments = attachments.ptr;
        info.subpassCount = 2;
        info.pSubpasses = subpasses.ptr;
        info.dependencyCount = 2;
        info.pDependencies = dependencies.ptr;
        return vkCreateRenderPass(device, &info, null, &renderPass) == VK_SUCCESS;
    }

    void destroySwapchainResources(VkDevice device) {
        foreach (i; 0 .. imageCount) {
            vkDestroyFramebuffer(device, framebuffers[i], null);
            vkDestroyImageView(device, imageViews[i], null);
            framebuffers[i] = null;
            imageViews[i] = null;
        }
        imageCount = 0;
        if (depthView !is null) {
            vkDestroyImageView(device, depthView, null);
            depthView = null;
        }
        if (depthImage !is null) {
            vkDestroyImage(device, depthImage, null);
            depthImage = null;
        }
        if (depthMemory !is null) {
            vkFreeMemory(device, depthMemory, null);
            depthMemory = null;
        }
        if (swapchain !is null) {
            vkDestroySwapchainKHR(device, swapchain, null);
            swapchain = null;
        }
    }

    void cleanup(VkDevice device) {
        vkDestroyFence(device, inFlightFence, null);
        vkDestroySemaphore(device, renderFinishedSemaphore, null);
        vkDestroySemaphore(device, imageAvailableSemaphore, null);
        vkDestroyCommandPool(device, commandPool, null);
        destroySwapchainResources(device);
        vkDestroyRenderPass(device, renderPass, null);
    }
}

VkImageView createImageView(VkDevice device, VkImage image, VkFormat format, VkImageAspectFlags aspect) {
    VkImageViewCreateInfo info;
    info.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    info.image = image;
    info.viewType = VK_IMAGE_VIEW_TYPE_2D;
    info.format = format;
    info.subresourceRange.aspectMask = aspect;
    info.subresourceRange.levelCount = 1;
    info.subresourceRange.layerCount = 1;
    VkImageView result = null;
    vkCreateImageView(device, &info, null, &result);
    return result;
}

uint clampUint(uint value, uint low, uint high) {
    uint result = value;
    if (value < low) {
        result = low;
    } else if (value > high) {
        result = high;
    }
    return result;
}

VkPresentModeKHR selectPresentMode(VkPhysicalDevice physicalDevice, VkSurfaceKHR surface) {
    VkPresentModeKHR[MAX_PRESENT_MODES] modes;
    uint count = MAX_PRESENT_MODES;
    vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, surface, &count, modes.ptr);
    VkPresentModeKHR result = VK_PRESENT_MODE_FIFO_KHR;
    foreach (i; 0 .. count) {
        if (modes[i] == VK_PRESENT_MODE_MAILBOX_KHR) {
            result = VK_PRESENT_MODE_MAILBOX_KHR;
        }
    }
    return result;
}
