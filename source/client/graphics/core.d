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

    bool init(void* window) {
        // Get required extensions from SDL
        uint extCount;
        auto extNames = SDL_Vulkan_GetInstanceExtensions(&extCount);
        if (extNames is null) {
            writeln("Failed to get Vulkan instance extensions from SDL");
            return false;
        }

        // Create instance
        VkApplicationInfo appInfo;
        appInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_APPLICATION_INFO;
        appInfo.pApplicationName = "mined";
        appInfo.applicationVersion = 1;
        appInfo.pEngineName = "mined";
        appInfo.engineVersion = 1;
        appInfo.apiVersion = (1 << 22) | (0 << 12); // VK_API_VERSION_1_0

        VkInstanceCreateInfo createInfo;
        createInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
        createInfo.pApplicationInfo = &appInfo;
        createInfo.enabledExtensionCount = extCount;
        createInfo.ppEnabledExtensionNames = extNames;

        auto res = vkCreateInstance(&createInfo, null, &instance);
        if (res != VkResult.VK_SUCCESS) {
            writefln("vkCreateInstance failed: %s", res);
            return false;
        }

        // Create surface via SDL
        if (!SDL_Vulkan_CreateSurface(window, instance, null, &surface)) {
            writeln("SDL_Vulkan_CreateSurface failed");
            return false;
        }

        // Pick physical device
        uint deviceCount;
        vkEnumeratePhysicalDevices(instance, &deviceCount, null);
        if (deviceCount == 0) {
            writeln("No Vulkan devices found");
            return false;
        }
        auto devices = new VkPhysicalDevice[](deviceCount);
        vkEnumeratePhysicalDevices(instance, &deviceCount, devices.ptr);
        physicalDevice = devices[0];

        // Find graphics queue family with present support
        uint queueFamilyCount;
        vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, null);
        auto queueFamilies = new VkQueueFamilyProperties[](queueFamilyCount);
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

        // Create logical device
        float queuePriority = 1.0f;
        VkDeviceQueueCreateInfo queueCreateInfo;
        queueCreateInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        queueCreateInfo.queueFamilyIndex = graphicsQueueFamily;
        queueCreateInfo.queueCount = 1;
        queueCreateInfo.pQueuePriorities = &queuePriority;

        const(char)*[1] deviceExtensions = ["VK_KHR_swapchain".ptr];

        VkDeviceCreateInfo deviceCreateInfo;
        deviceCreateInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        deviceCreateInfo.queueCreateInfoCount = 1;
        deviceCreateInfo.pQueueCreateInfos = &queueCreateInfo;
        deviceCreateInfo.enabledExtensionCount = 1;
        deviceCreateInfo.ppEnabledExtensionNames = deviceExtensions.ptr;

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
