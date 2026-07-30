module client.graphics.base;

import std.stdio;
import bindings.vk;

struct SwapchainState {
    VkPhysicalDevice physDevice;
    VkSurfaceKHR surface;
    VkSwapchainKHR swapchain;
    // Render into an owned image instead of a swapchain; no surface, no present.
    bool offscreen;
    VkFormat format;
    VkExtent2D extent;
    VkImage[] images;
    VkImageView[] imageViews;
    VkDeviceMemory colorMemory;
    VkImage depthImage;
    VkDeviceMemory depthMemory;
    VkImageView depthView;
    VkRenderPass renderPass;
    VkFramebuffer[] framebuffers;
    VkCommandPool commandPool;
    VkCommandBuffer commandBuffer;
    VkSemaphore imageAvailableSemaphore;
    // Per image: present can still hold an image's semaphore after the next acquire.
    VkSemaphore[] renderFinishedSemaphores;
    VkFence inFlightFence;

    bool init(VkPhysicalDevice physDevice, VkDevice device, VkSurfaceKHR surface, uint queueFamily) {
        this.physDevice = physDevice;
        this.surface = surface;

        if (!createSwapchainResources(device)) {
            return false;
        }

        VkCommandPoolCreateInfo cpci;
        cpci.sType = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
        cpci.flags = VkCommandPoolCreateFlagBits.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
        cpci.queueFamilyIndex = queueFamily;
        vkCreateCommandPool(device, &cpci, null, &commandPool);

        VkCommandBufferAllocateInfo cbai;
        cbai.sType = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        cbai.commandPool = commandPool;
        cbai.level = VkCommandBufferLevel.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        cbai.commandBufferCount = 1;
        vkAllocateCommandBuffers(device, &cbai, &commandBuffer);

        VkSemaphoreCreateInfo semCI;
        semCI.sType = VkStructureType.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
        vkCreateSemaphore(device, &semCI, null, &imageAvailableSemaphore);
        createRenderFinishedSemaphores(device);

        VkFenceCreateInfo fenceCI;
        fenceCI.sType = VkStructureType.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
        fenceCI.flags = VkFenceCreateFlagBits.VK_FENCE_CREATE_SIGNALED_BIT;
        vkCreateFence(device, &fenceCI, null, &inFlightFence);

        writeln("Swapchain and render pass created");
        return true;
    }

    /// Tear down and rebuild everything that depends on the surface size.
    /// Returns false if the surface currently has zero area (e.g. minimized);
    /// callers should skip rendering and retry later.
    bool recreate(VkDevice device) {
        vkDeviceWaitIdle(device);
        destroySwapchainResources(device);

        // The acquire semaphore may be left signaled by an acquire whose image
        // was never presented; recreate all semaphores to get a clean state.
        vkDestroySemaphore(device, imageAvailableSemaphore, null);
        destroyRenderFinishedSemaphores(device);
        VkSemaphoreCreateInfo semCI;
        semCI.sType = VkStructureType.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
        vkCreateSemaphore(device, &semCI, null, &imageAvailableSemaphore);

        if (!createSwapchainResources(device)) {
            return false;
        }
        createRenderFinishedSemaphores(device);
        return true;
    }

    void createRenderFinishedSemaphores(VkDevice device) {
        VkSemaphoreCreateInfo semCI;
        semCI.sType = VkStructureType.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
        renderFinishedSemaphores = new VkSemaphore[](images.length);
        foreach (ref s; renderFinishedSemaphores) {
            vkCreateSemaphore(device, &semCI, null, &s);
        }
    }

    void destroyRenderFinishedSemaphores(VkDevice device) {
        foreach (s; renderFinishedSemaphores) {
            vkDestroySemaphore(device, s, null);
        }
        renderFinishedSemaphores = null;
    }

    bool createOffscreenTarget(VkDevice device) {
        extent = VkExtent2D(1280, 720);
        format = VkFormat.VK_FORMAT_B8G8R8A8_UNORM;

        VkImageCreateInfo ici;
        ici.sType = VkStructureType.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
        ici.imageType = VkImageType.VK_IMAGE_TYPE_2D;
        ici.format = format;
        ici.extent = VkExtent3D(extent.width, extent.height, 1);
        ici.mipLevels = 1;
        ici.arrayLayers = 1;
        ici.samples = 1;
        ici.tiling = VkImageTiling.VK_IMAGE_TILING_OPTIMAL;
        ici.usage = VkImageUsageFlagBits.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT
                  | VkImageUsageFlagBits.VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
        ici.sharingMode = VkSharingMode.VK_SHARING_MODE_EXCLUSIVE;
        ici.initialLayout = VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED;
        VkImage colorImage;
        vkCreateImage(device, &ici, null, &colorImage);

        VkMemoryRequirements req;
        vkGetImageMemoryRequirements(device, colorImage, &req);
        VkPhysicalDeviceMemoryProperties mp;
        vkGetPhysicalDeviceMemoryProperties(physDevice, &mp);
        uint mti = uint.max;
        for (uint i = 0; i < mp.memoryTypeCount; i++) {
            if ((req.memoryTypeBits & (1u << i)) &&
                (mp.memoryTypes[i].propertyFlags & VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)) {
                mti = i;
                break;
            }
        }
        VkMemoryAllocateInfo mai;
        mai.sType = VkStructureType.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        mai.allocationSize = req.size;
        mai.memoryTypeIndex = mti;
        vkAllocateMemory(device, &mai, null, &colorMemory);
        vkBindImageMemory(device, colorImage, colorMemory, 0);

        images = [colorImage];
        imageViews = new VkImageView[](1);
        VkImageViewCreateInfo ivci;
        ivci.sType = VkStructureType.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        ivci.image = colorImage;
        ivci.viewType = VkImageViewType.VK_IMAGE_VIEW_TYPE_2D;
        ivci.format = format;
        ivci.subresourceRange.aspectMask = VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT;
        ivci.subresourceRange.levelCount = 1;
        ivci.subresourceRange.layerCount = 1;
        vkCreateImageView(device, &ivci, null, &imageViews[0]);
        return true;
    }

    bool createSwapchainResources(VkDevice device) {
        if (offscreen) {
            if (images.length == 0 && !createOffscreenTarget(device)) {
                return false;
            }
            return createDepthAndFramebuffers(device);
        }
        VkSurfaceCapabilitiesKHR caps;
        vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physDevice, surface, &caps);

        VkExtent2D previous = extent;
        extent = caps.currentExtent;
        if (extent.width == uint.max) {
            // Surface lets us pick; clamp the previous extent into the valid range.
            extent.width = clamp(previous.width, caps.minImageExtent.width, caps.maxImageExtent.width);
            extent.height = clamp(previous.height, caps.minImageExtent.height, caps.maxImageExtent.height);
        }
        if (extent.width == 0 || extent.height == 0) {
            return false;
        }

        uint formatCount;
        vkGetPhysicalDeviceSurfaceFormatsKHR(physDevice, surface, &formatCount, null);
        VkSurfaceFormatKHR[] formats = new VkSurfaceFormatKHR[](formatCount);
        vkGetPhysicalDeviceSurfaceFormatsKHR(physDevice, surface, &formatCount, formats.ptr);
        format = formats[0].format;
        VkColorSpaceKHR colorSpace = formats[0].colorSpace;

        uint imageCount = caps.minImageCount + 1;
        if (caps.maxImageCount > 0 && imageCount > caps.maxImageCount) {
            imageCount = caps.maxImageCount;
        }

        VkSwapchainCreateInfoKHR sci;
        sci.sType = VkStructureType.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
        sci.surface = surface;
        sci.minImageCount = imageCount;
        sci.imageFormat = format;
        sci.imageColorSpace = colorSpace;
        sci.imageExtent = extent;
        sci.imageArrayLayers = 1;
        sci.imageUsage = VkImageUsageFlagBits.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT
                       | VkImageUsageFlagBits.VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
        sci.imageSharingMode = VkSharingMode.VK_SHARING_MODE_EXCLUSIVE;
        sci.preTransform = caps.currentTransform;
        sci.compositeAlpha = VkCompositeAlphaFlagBitsKHR.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
        sci.presentMode = selectPresentMode(physDevice, surface);
        sci.clipped = 1;

        VkResult res = vkCreateSwapchainKHR(device, &sci, null, &swapchain);
        if (res != VkResult.VK_SUCCESS) {
            writefln("vkCreateSwapchainKHR failed: %s", res);
            return false;
        }

        uint imgCount;
        vkGetSwapchainImagesKHR(device, swapchain, &imgCount, null);
        images = new VkImage[](imgCount);
        vkGetSwapchainImagesKHR(device, swapchain, &imgCount, images.ptr);

        imageViews = new VkImageView[](imgCount);
        for (uint i = 0; i < imgCount; i++) {
            VkImageViewCreateInfo ivci;
            ivci.sType = VkStructureType.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
            ivci.image = images[i];
            ivci.viewType = VkImageViewType.VK_IMAGE_VIEW_TYPE_2D;
            ivci.format = format;
            ivci.components.r = VkComponentSwizzle.VK_COMPONENT_SWIZZLE_IDENTITY;
            ivci.components.g = VkComponentSwizzle.VK_COMPONENT_SWIZZLE_IDENTITY;
            ivci.components.b = VkComponentSwizzle.VK_COMPONENT_SWIZZLE_IDENTITY;
            ivci.components.a = VkComponentSwizzle.VK_COMPONENT_SWIZZLE_IDENTITY;
            ivci.subresourceRange.aspectMask = VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT;
            ivci.subresourceRange.baseMipLevel = 0;
            ivci.subresourceRange.levelCount = 1;
            ivci.subresourceRange.baseArrayLayer = 0;
            ivci.subresourceRange.layerCount = 1;
            vkCreateImageView(device, &ivci, null, &imageViews[i]);
        }

        return createDepthAndFramebuffers(device);
    }

    bool createDepthAndFramebuffers(VkDevice device) {
        VkImageCreateInfo dci;
        dci.sType = VkStructureType.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
        dci.imageType = VkImageType.VK_IMAGE_TYPE_2D;
        dci.format = VkFormat.VK_FORMAT_D32_SFLOAT;
        dci.extent.width = extent.width;
        dci.extent.height = extent.height;
        dci.extent.depth = 1;
        dci.mipLevels = 1;
        dci.arrayLayers = 1;
        dci.samples = 1;
        dci.tiling = VkImageTiling.VK_IMAGE_TILING_OPTIMAL;
        dci.usage = VkImageUsageFlagBits.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT
                  | VkImageUsageFlagBits.VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT;
        dci.sharingMode = VkSharingMode.VK_SHARING_MODE_EXCLUSIVE;
        dci.initialLayout = VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED;
        vkCreateImage(device, &dci, null, &depthImage);

        VkMemoryRequirements dreq;
        vkGetImageMemoryRequirements(device, depthImage, &dreq);
        VkPhysicalDeviceMemoryProperties dmp;
        vkGetPhysicalDeviceMemoryProperties(physDevice, &dmp);
        uint dmti = uint.max;
        for (uint i = 0; i < dmp.memoryTypeCount; i++) {
            if ((dreq.memoryTypeBits & (1u << i)) &&
                (dmp.memoryTypes[i].propertyFlags & VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)) {
                dmti = i;
                break;
            }
        }
        VkMemoryAllocateInfo dmai;
        dmai.sType = VkStructureType.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        dmai.allocationSize = dreq.size;
        dmai.memoryTypeIndex = dmti;
        vkAllocateMemory(device, &dmai, null, &depthMemory);
        vkBindImageMemory(device, depthImage, depthMemory, 0);

        VkImageViewCreateInfo dvci;
        dvci.sType = VkStructureType.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        dvci.image = depthImage;
        dvci.viewType = VkImageViewType.VK_IMAGE_VIEW_TYPE_2D;
        dvci.format = VkFormat.VK_FORMAT_D32_SFLOAT;
        dvci.subresourceRange.aspectMask = VkImageAspectFlagBits.VK_IMAGE_ASPECT_DEPTH_BIT;
        dvci.subresourceRange.levelCount = 1;
        dvci.subresourceRange.layerCount = 1;
        vkCreateImageView(device, &dvci, null, &depthView);

        // The render pass only depends on the image formats, which are stable;
        // pipelines reference it, so create it once and keep it across resizes.
        if (!renderPass) {
            if (!createRenderPass(device)) {
                return false;
            }
        }

        uint imgCount = cast(uint) images.length;
        framebuffers = new VkFramebuffer[](imgCount);
        for (uint i = 0; i < imgCount; i++) {
            VkImageView[2] fbAttach = [imageViews[i], depthView];
            VkFramebufferCreateInfo fbci;
            fbci.sType = VkStructureType.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
            fbci.renderPass = renderPass;
            fbci.attachmentCount = 2;
            fbci.pAttachments = fbAttach.ptr;
            fbci.width = extent.width;
            fbci.height = extent.height;
            fbci.layers = 1;
            vkCreateFramebuffer(device, &fbci, null, &framebuffers[i]);
        }

        return true;
    }

    bool createRenderPass(VkDevice device) {
        VkAttachmentDescription[2] attachments;
        attachments[0].format = format;
        attachments[0].samples = 1;
        attachments[0].loadOp = VkAttachmentLoadOp.VK_ATTACHMENT_LOAD_OP_CLEAR;
        attachments[0].storeOp = VkAttachmentStoreOp.VK_ATTACHMENT_STORE_OP_STORE;
        attachments[0].initialLayout = VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED;
        attachments[0].finalLayout = offscreen
            ? VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL
            : VkImageLayout.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

        attachments[1].format = VkFormat.VK_FORMAT_D32_SFLOAT;
        attachments[1].samples = 1;
        attachments[1].loadOp = VkAttachmentLoadOp.VK_ATTACHMENT_LOAD_OP_CLEAR;
        attachments[1].storeOp = VkAttachmentStoreOp.VK_ATTACHMENT_STORE_OP_DONT_CARE;
        attachments[1].initialLayout = VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED;
        attachments[1].finalLayout = VkImageLayout.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

        VkAttachmentReference colorRef;
        colorRef.attachment = 0;
        colorRef.layout = VkImageLayout.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
        VkAttachmentReference depthRef;
        depthRef.attachment = 1;
        depthRef.layout = VkImageLayout.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

        VkAttachmentReference depthInputRef;
        depthInputRef.attachment = 1;
        depthInputRef.layout = VkImageLayout.VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL;

        VkSubpassDescription[2] subpasses;
        subpasses[0].pipelineBindPoint = VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS;
        subpasses[0].colorAttachmentCount = 1;
        subpasses[0].pColorAttachments = &colorRef;
        subpasses[0].pDepthStencilAttachment = &depthRef;

        subpasses[1].pipelineBindPoint = VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS;
        subpasses[1].colorAttachmentCount = 1;
        subpasses[1].pColorAttachments = &colorRef;
        subpasses[1].inputAttachmentCount = 1;
        subpasses[1].pInputAttachments = &depthInputRef;

        VkSubpassDependency[2] deps;
        deps[0].srcSubpass = VK_SUBPASS_EXTERNAL;
        deps[0].dstSubpass = 0;
        deps[0].srcStageMask = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT
                              | VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT;
        deps[0].dstStageMask = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT
                              | VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
        deps[0].srcAccessMask = 0;
        deps[0].dstAccessMask = VkAccessFlagBits.VK_ACCESS_COLOR_ATTACHMENT_READ_BIT
                              | VkAccessFlagBits.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
                              | VkAccessFlagBits.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT
                              | VkAccessFlagBits.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;

        deps[1].srcSubpass = 0;
        deps[1].dstSubpass = 1;
        deps[1].srcStageMask = VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT
                              | VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT;
        deps[1].dstStageMask = VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
        deps[1].srcAccessMask = VkAccessFlagBits.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
        deps[1].dstAccessMask = VkAccessFlagBits.VK_ACCESS_INPUT_ATTACHMENT_READ_BIT;
        deps[1].dependencyFlags = VK_DEPENDENCY_BY_REGION_BIT;

        VkRenderPassCreateInfo rpci;
        rpci.sType = VkStructureType.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
        rpci.attachmentCount = 2;
        rpci.pAttachments = attachments.ptr;
        rpci.subpassCount = 2;
        rpci.pSubpasses = subpasses.ptr;
        rpci.dependencyCount = 2;
        rpci.pDependencies = deps.ptr;

        VkResult res = vkCreateRenderPass(device, &rpci, null, &renderPass);
        if (res != VkResult.VK_SUCCESS) {
            writefln("vkCreateRenderPass failed: %s", res);
            return false;
        }
        return true;
    }

    void destroySwapchainResources(VkDevice device) {
        foreach (fb; framebuffers) {
            vkDestroyFramebuffer(device, fb, null);
        }
        framebuffers = null;
        if (depthView) {
            vkDestroyImageView(device, depthView, null);
            depthView = 0;
        }
        if (depthImage) {
            vkDestroyImage(device, depthImage, null);
            depthImage = 0;
        }
        if (depthMemory) {
            vkFreeMemory(device, depthMemory, null);
            depthMemory = 0;
        }
        foreach (iv; imageViews) {
            vkDestroyImageView(device, iv, null);
        }
        imageViews = null;
        images = null;
        if (swapchain) {
            vkDestroySwapchainKHR(device, swapchain, null);
            swapchain = 0;
        }
    }

    void cleanup(VkDevice device) {
        vkDestroyFence(device, inFlightFence, null);
        destroyRenderFinishedSemaphores(device);
        vkDestroySemaphore(device, imageAvailableSemaphore, null);
        vkDestroyCommandPool(device, commandPool, null);
        destroySwapchainResources(device);
        vkDestroyRenderPass(device, renderPass, null);
    }
}

uint clamp(uint v, uint lo, uint hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

VkPresentModeKHR selectPresentMode(VkPhysicalDevice phys, VkSurfaceKHR surface) {
    uint count;
    vkGetPhysicalDeviceSurfacePresentModesKHR(phys, surface, &count, null);
    VkPresentModeKHR[] modes = new VkPresentModeKHR[](count);
    vkGetPhysicalDeviceSurfacePresentModesKHR(phys, surface, &count, modes.ptr);
    foreach (m; modes) {
        if (m == VkPresentModeKHR.VK_PRESENT_MODE_MAILBOX_KHR) {
            return m;
        }
    }
    // FIFO is always available and vsynced; prefer it over IMMEDIATE so we
    // don't tear and spin the GPU on hardware without mailbox support.
    return VkPresentModeKHR.VK_PRESENT_MODE_FIFO_KHR;
}
