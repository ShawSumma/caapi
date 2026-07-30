module client.graphics.core;

import std.stdio;
import bindings.vk;

struct VulkanCore {
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
            writeln("Failed to get Vulkan instance extensions from SDL");
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

        version (OSX) {
            // The loader hides MoltenVK unless portability enumeration is on.
            const(char)*[] osxExts = extNames[0 .. extCount].dup;
            osxExts ~= "VK_KHR_portability_enumeration".ptr;
            createInfo.enabledExtensionCount = cast(uint) osxExts.length;
            createInfo.ppEnabledExtensionNames = osxExts.ptr;
            createInfo.flags = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
        }

        VkResult res = vkCreateInstance(&createInfo, null, &instance);
        if (res != VkResult.VK_SUCCESS) {
            writefln("vkCreateInstance failed: %s", res);
            return false;
        }

        if (!SDL_Vulkan_CreateSurface(window, instance, null, &surface)) {
            writeln("SDL_Vulkan_CreateSurface failed");
            return false;
        }

        uint deviceCount;
        vkEnumeratePhysicalDevices(instance, &deviceCount, null);
        if (deviceCount == 0) {
            writeln("No Vulkan devices found");
            return false;
        }
        VkPhysicalDevice[] devices = new VkPhysicalDevice[](deviceCount);
        vkEnumeratePhysicalDevices(instance, &deviceCount, devices.ptr);
        physicalDevice = devices[0];

        uint queueFamilyCount;
        vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, null);
        VkQueueFamilyProperties[] queueFamilies = new VkQueueFamilyProperties[](queueFamilyCount);
        vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, queueFamilies.ptr);

        graphicsQueueFamily = uint.max;
        for (uint i = 0; i < queueFamilyCount; i++) {
            if (queueFamilies[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) {
                VkBool32 presentSupport;
                vkGetPhysicalDeviceSurfaceSupportKHR(physicalDevice, i, surface, &presentSupport);
                if (presentSupport) {
                    graphicsQueueFamily = i;
                    break;
                }
            }
        }
        if (graphicsQueueFamily == uint.max) {
            writeln("No suitable queue family found");
            return false;
        }

        float queuePriority = 1.0f;
        VkDeviceQueueCreateInfo queueCreateInfo;
        queueCreateInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        queueCreateInfo.queueFamilyIndex = graphicsQueueFamily;
        queueCreateInfo.queueCount = 1;
        queueCreateInfo.pQueuePriorities = &queuePriority;

        const(char)*[] deviceExtensions = ["VK_KHR_swapchain".ptr];
        version (OSX) {
            deviceExtensions ~= "VK_KHR_portability_subset".ptr;
        }

        // vkCmdDrawIndirect with drawCount > 1 requires this feature.
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
        deviceCreateInfo.enabledExtensionCount = cast(uint) deviceExtensions.length;
        deviceCreateInfo.ppEnabledExtensionNames = deviceExtensions.ptr;
        deviceCreateInfo.pEnabledFeatures = &enabled;

        res = vkCreateDevice(physicalDevice, &deviceCreateInfo, null, &device);
        if (res != VkResult.VK_SUCCESS) {
            writefln("vkCreateDevice failed: %s", res);
            return false;
        }

        vkGetDeviceQueue(device, graphicsQueueFamily, 0, &graphicsQueue);
        writeln("Vulkan core initialized");
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
