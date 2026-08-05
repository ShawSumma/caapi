module client.graphics.core;

import core.stdc.stdio : printf;
import bindings.vk;

struct VulkanCore {
    // Caps for the fixed buffers below. Enumerations that exceed them are
    // truncated rather than allocated for.
    enum uint MAX_PHYSICAL_DEVICES = 16;
    enum uint MAX_QUEUE_FAMILIES = 32;
    enum uint MAX_INSTANCE_EXTENSIONS = 16;

    VkInstance instance;
    VkPhysicalDevice physicalDevice;
    VkDevice device;
    VkQueue graphicsQueue;
    uint graphicsQueueFamily;
    VkSurfaceKHR surface;
    bool multiDrawIndirect;

    bool init(void* window) {
        uint extCount;
        const(char*)* extNames = SDL_Vulkan_GetInstanceExtensions(&extCount);
        if (extNames is null) {
            printf("Failed to get Vulkan instance extensions from SDL\n");
            return false;
        }

        VkApplicationInfo appInfo;
        appInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_APPLICATION_INFO;
        appInfo.pApplicationName = "mined";
        appInfo.applicationVersion = 1;
        appInfo.pEngineName = "mined";
        appInfo.engineVersion = 1;
        appInfo.apiVersion = (1 << 22) | (1 << 12);

        VkInstanceCreateInfo createInfo;
        createInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
        createInfo.pApplicationInfo = &appInfo;
        createInfo.enabledExtensionCount = extCount;
        createInfo.ppEnabledExtensionNames = extNames;

        // Declared out here because the create info keeps a pointer into it
        // until vkCreateInstance has run.
        const(char)*[MAX_INSTANCE_EXTENSIONS] instanceExts;
        version (OSX) {
            // The loader hides MoltenVK unless portability enumeration is on.
            uint copied = extCount;
            if (copied > MAX_INSTANCE_EXTENSIONS - 1) {
                copied = MAX_INSTANCE_EXTENSIONS - 1;
            }
            foreach (i; 0 .. copied) {
                instanceExts[i] = extNames[i];
            }
            instanceExts[copied] = "VK_KHR_portability_enumeration".ptr;
            createInfo.enabledExtensionCount = copied + 1;
            createInfo.ppEnabledExtensionNames = instanceExts.ptr;
            createInfo.flags = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
        }

        VkResult res = vkCreateInstance(&createInfo, null, &instance);
        if (res != VkResult.VK_SUCCESS) {
            printf("vkCreateInstance failed: %d\n", cast(int) res);
            return false;
        }

        if (!SDL_Vulkan_CreateSurface(window, instance, null, &surface)) {
            printf("SDL_Vulkan_CreateSurface failed\n");
            return false;
        }

        uint deviceCount;
        vkEnumeratePhysicalDevices(instance, &deviceCount, null);
        if (deviceCount == 0) {
            printf("No Vulkan devices found\n");
            return false;
        }
        if (deviceCount > MAX_PHYSICAL_DEVICES) {
            deviceCount = MAX_PHYSICAL_DEVICES;
        }
        VkPhysicalDevice[MAX_PHYSICAL_DEVICES] devices;
        vkEnumeratePhysicalDevices(instance, &deviceCount, devices.ptr);
        physicalDevice = devices[0];

        uint queueFamilyCount;
        vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, null);
        if (queueFamilyCount > MAX_QUEUE_FAMILIES) {
            queueFamilyCount = MAX_QUEUE_FAMILIES;
        }
        VkQueueFamilyProperties[MAX_QUEUE_FAMILIES] queueFamilies;
        vkGetPhysicalDeviceQueueFamilyProperties(
            physicalDevice,
            &queueFamilyCount,
            queueFamilies.ptr,
        );

        graphicsQueueFamily = uint.max;
        for (uint i = 0; i < queueFamilyCount; i = i + 1) {
            bool doesGraphics = (queueFamilies[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0;
            if (doesGraphics) {
                VkBool32 presentSupport;
                vkGetPhysicalDeviceSurfaceSupportKHR(
                    physicalDevice,
                    i,
                    surface,
                    &presentSupport,
                );
                if (presentSupport != 0) {
                    graphicsQueueFamily = i;
                    break;
                }
            }
        }
        if (graphicsQueueFamily == uint.max) {
            printf("No suitable queue family found\n");
            return false;
        }

        float queuePriority = 1.0f;
        VkDeviceQueueCreateInfo queueCreateInfo;
        queueCreateInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        queueCreateInfo.queueFamilyIndex = graphicsQueueFamily;
        queueCreateInfo.queueCount = 1;
        queueCreateInfo.pQueuePriorities = &queuePriority;

        const(char)*[2] deviceExtensions;
        uint deviceExtCount = 0;
        deviceExtensions[deviceExtCount] = "VK_KHR_swapchain".ptr;
        deviceExtCount = deviceExtCount + 1;
        version (OSX) {
            deviceExtensions[deviceExtCount] = "VK_KHR_portability_subset".ptr;
            deviceExtCount = deviceExtCount + 1;
        }

        // vkCmdDrawIndirect with a draw count above one requires this feature.
        VkPhysicalDeviceFeatures supported;
        vkGetPhysicalDeviceFeatures(physicalDevice, &supported);
        multiDrawIndirect = supported.flags[FEATURE_MULTI_DRAW_INDIRECT] != 0;
        VkPhysicalDeviceFeatures enabled;
        enabled.flags[] = 0;
        if (multiDrawIndirect) {
            enabled.flags[FEATURE_MULTI_DRAW_INDIRECT] = 1;
        }

        VkDeviceCreateInfo deviceCreateInfo;
        deviceCreateInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        deviceCreateInfo.queueCreateInfoCount = 1;
        deviceCreateInfo.pQueueCreateInfos = &queueCreateInfo;
        deviceCreateInfo.enabledExtensionCount = deviceExtCount;
        deviceCreateInfo.ppEnabledExtensionNames = deviceExtensions.ptr;
        deviceCreateInfo.pEnabledFeatures = &enabled;

        res = vkCreateDevice(physicalDevice, &deviceCreateInfo, null, &device);
        if (res != VkResult.VK_SUCCESS) {
            printf("vkCreateDevice failed: %d\n", cast(int) res);
            return false;
        }

        vkGetDeviceQueue(device, graphicsQueueFamily, 0, &graphicsQueue);
        // Worth surfacing: without it the renderer falls back to one
        // vkCmdDrawIndirect per chunk, which dominates command recording.
        printf(
            "Vulkan core initialized (multiDrawIndirect=%d)\n",
            cast(int) multiDrawIndirect,
        );
        return true;
    }

    void cleanup() {
        if (device !is null) {
            vkDeviceWaitIdle(device);
            vkDestroyDevice(device, null);
        }
        if (surface != VK_NULL_HANDLE) {
            vkDestroySurfaceKHR(instance, surface, null);
        }
        if (instance !is null) {
            vkDestroyInstance(instance, null);
        }
    }
}
