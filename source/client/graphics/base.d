module client.graphics.base;

import std.stdio;
import bindings.vk;

struct SwapchainState {
    VkSwapchainKHR swapchain;
    VkFormat format;
    VkExtent2D extent;
    VkImage[] images;
    VkImageView[] imageViews;
    VkImage depthImage;
    VkDeviceMemory depthMemory;
    VkImageView depthView;
    VkRenderPass renderPass;
    VkFramebuffer[] framebuffers;
    VkCommandPool commandPool;
    VkCommandBuffer commandBuffer;
    VkSemaphore imageAvailableSemaphore;
    VkSemaphore renderFinishedSemaphore;
    VkFence inFlightFence;

    bool init(VkPhysicalDevice physDevice, VkDevice device, VkSurfaceKHR surface, uint queueFamily) {
        // Get surface capabilities
        VkSurfaceCapabilitiesKHR caps;
        vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physDevice, surface, &caps);

        // Get surface format
        uint formatCount;
        vkGetPhysicalDeviceSurfaceFormatsKHR(physDevice, surface, &formatCount, null);
        auto formats = new VkSurfaceFormatKHR[](formatCount);
        vkGetPhysicalDeviceSurfaceFormatsKHR(physDevice, surface, &formatCount, formats.ptr);
        format = formats[0].format;
        auto colorSpace = formats[0].colorSpace;

        extent = caps.currentExtent;
        writefln("Swapchain extent: %dx%d", extent.width, extent.height);
        uint imageCount = caps.minImageCount + 1;
        if (caps.maxImageCount > 0 && imageCount > caps.maxImageCount) {
            imageCount = caps.maxImageCount;
        }

        // Create swapchain
        VkSwapchainCreateInfoKHR sci;
        sci.sType = VkStructureType.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
        sci.surface = surface;
        sci.minImageCount = imageCount;
        sci.imageFormat = format;
        sci.imageColorSpace = colorSpace;
        sci.imageExtent = extent;
        sci.imageArrayLayers = 1;
        sci.imageUsage = VkImageUsageFlagBits.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
        sci.imageSharingMode = VkSharingMode.VK_SHARING_MODE_EXCLUSIVE;
        sci.preTransform = caps.currentTransform;
        sci.compositeAlpha = VkCompositeAlphaFlagBitsKHR.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
        sci.presentMode = VkPresentModeKHR.VK_PRESENT_MODE_FIFO_KHR;
        sci.clipped = 1;

        auto res = vkCreateSwapchainKHR(device, &sci, null, &swapchain);
        if (res != VkResult.VK_SUCCESS) {
            writefln("vkCreateSwapchainKHR failed: %s", res);
            return false;
        }

        // Get swapchain images
        uint imgCount;
        vkGetSwapchainImagesKHR(device, swapchain, &imgCount, null);
        images = new VkImage[](imgCount);
        vkGetSwapchainImagesKHR(device, swapchain, &imgCount, images.ptr);

        // Create image views
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

        // Depth image
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
        dci.usage = VkImageUsageFlagBits.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
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
                dmti = i; break;
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

        // Create render pass
        VkAttachmentDescription[2] attachments;
        attachments[0].format = format;
        attachments[0].samples = 1;
        attachments[0].loadOp = VkAttachmentLoadOp.VK_ATTACHMENT_LOAD_OP_CLEAR;
        attachments[0].storeOp = VkAttachmentStoreOp.VK_ATTACHMENT_STORE_OP_STORE;
        attachments[0].stencilLoadOp = VkAttachmentLoadOp.VK_ATTACHMENT_LOAD_OP_CLEAR;
        attachments[0].stencilStoreOp = VkAttachmentStoreOp.VK_ATTACHMENT_STORE_OP_STORE;
        attachments[0].initialLayout = VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED;
        attachments[0].finalLayout = VkImageLayout.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

        attachments[1].format = VkFormat.VK_FORMAT_D32_SFLOAT;
        attachments[1].samples = 1;
        attachments[1].loadOp = VkAttachmentLoadOp.VK_ATTACHMENT_LOAD_OP_CLEAR;
        attachments[1].storeOp = VkAttachmentStoreOp.VK_ATTACHMENT_STORE_OP_STORE;
        attachments[1].stencilLoadOp = VkAttachmentLoadOp.VK_ATTACHMENT_LOAD_OP_CLEAR;
        attachments[1].stencilStoreOp = VkAttachmentStoreOp.VK_ATTACHMENT_STORE_OP_STORE;
        attachments[1].initialLayout = VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED;
        attachments[1].finalLayout = VkImageLayout.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

        VkAttachmentReference colorRef;
        colorRef.attachment = 0;
        colorRef.layout = VkImageLayout.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
        VkAttachmentReference depthRef;
        depthRef.attachment = 1;
        depthRef.layout = VkImageLayout.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

        VkSubpassDescription subpass;
        subpass.pipelineBindPoint = VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS;
        subpass.colorAttachmentCount = 1;
        subpass.pColorAttachments = &colorRef;
        subpass.pDepthStencilAttachment = &depthRef;

        VkSubpassDependency dep;
        dep.srcSubpass = VK_SUBPASS_EXTERNAL;
        dep.dstSubpass = 0;
        dep.srcStageMask = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        dep.dstStageMask = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        dep.srcAccessMask = 0;
        dep.dstAccessMask = 0x00000100; // VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT

        VkRenderPassCreateInfo rpci;
        rpci.sType = VkStructureType.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
        rpci.attachmentCount = 2;
        rpci.pAttachments = attachments.ptr;
        rpci.subpassCount = 1;
        rpci.pSubpasses = &subpass;
        rpci.dependencyCount = 1;
        rpci.pDependencies = &dep;

        vkCreateRenderPass(device, &rpci, null, &renderPass);

        // Create framebuffers
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

        // Command pool and buffer
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

        // Sync objects
        VkSemaphoreCreateInfo semCI;
        semCI.sType = VkStructureType.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
        vkCreateSemaphore(device, &semCI, null, &imageAvailableSemaphore);
        vkCreateSemaphore(device, &semCI, null, &renderFinishedSemaphore);

        VkFenceCreateInfo fenceCI;
        fenceCI.sType = VkStructureType.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
        fenceCI.flags = VkFenceCreateFlagBits.VK_FENCE_CREATE_SIGNALED_BIT;
        vkCreateFence(device, &fenceCI, null, &inFlightFence);

        writeln("Swapchain and render pass created");
        return true;
    }

    void cleanup(VkDevice device) {
        vkDestroyFence(device, inFlightFence, null);
        vkDestroySemaphore(device, renderFinishedSemaphore, null);
        vkDestroySemaphore(device, imageAvailableSemaphore, null);
        vkDestroyCommandPool(device, commandPool, null);
        foreach (fb; framebuffers) {
            vkDestroyFramebuffer(device, fb, null);
        }
        vkDestroyRenderPass(device, renderPass, null);
        if (depthView) {
            vkDestroyImageView(device, depthView, null);
        }
        if (depthImage) {
            vkDestroyImage(device, depthImage, null);
        }
        if (depthMemory) {
            vkFreeMemory(device, depthMemory, null);
        }
        foreach (iv; imageViews) {
            vkDestroyImageView(device, iv, null);
        }
        vkDestroySwapchainKHR(device, swapchain, null);
    }
}
