module client.graphics.core;

import bindings.platform : Display, VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU, VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU, VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU, VK_QUEUE_GRAPHICS_BIT, VK_STRUCTURE_TYPE_APPLICATION_INFO, VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR, VK_SUCCESS, VkApplicationInfo, VkBool32, VkDevice, VkDeviceCreateInfo, VkDeviceQueueCreateInfo, VkInstance, VkInstanceCreateInfo, VkPhysicalDevice, VkPhysicalDeviceFeatures, VkPhysicalDeviceProperties, VkQueue, VkQueueFamilyProperties, VkSurfaceKHR, VkXlibSurfaceCreateInfoKHR, Window, vkCreateDevice, vkCreateInstance, vkCreateXlibSurfaceKHR, vkDestroyDevice, vkDestroyInstance, vkDestroySurfaceKHR, vkDeviceWaitIdle, vkEnumeratePhysicalDevices, vkGetDeviceQueue, vkGetPhysicalDeviceFeatures, vkGetPhysicalDeviceProperties, vkGetPhysicalDeviceQueueFamilyProperties, vkGetPhysicalDeviceSurfaceSupportKHR;
import client.graphics.pipeline : VULKAN_TRUE;

enum uint VULKAN_API_VERSION_1_1 = (1 << 22) | (1 << 12);
enum uint MAX_PHYSICAL_DEVICES = 16;
enum uint MAX_QUEUE_FAMILIES = 32;
enum uint NO_QUEUE_FAMILY = uint.max;
enum uint APPLICATION_VERSION = 1;
enum uint RANK_OTHER = 0;
enum uint RANK_VIRTUAL = 1;
enum uint RANK_INTEGRATED = 2;
enum uint RANK_DISCRETE = 3;

uint deviceTypeRank(VkPhysicalDevice device) {
    VkPhysicalDeviceProperties properties;
    vkGetPhysicalDeviceProperties(device, &properties);
    uint result = RANK_OTHER;
    if (properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
        result = RANK_DISCRETE;
    } else if (properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU) {
        result = RANK_INTEGRATED;
    } else if (properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU) {
        result = RANK_VIRTUAL;
    }
    return result;
}

bool supportsIndirectDrawing(VkPhysicalDevice device) {
    VkPhysicalDeviceFeatures features;
    vkGetPhysicalDeviceFeatures(device, &features);
    return features.multiDrawIndirect != 0 && features.drawIndirectFirstInstance != 0;
}

struct VulkanCore {
    VkInstance instance;
    VkPhysicalDevice physicalDevice;
    VkDevice device;
    VkQueue graphicsQueue;
    VkSurfaceKHR surface;
    uint graphicsQueueFamily = NO_QUEUE_FAMILY;
    uint maxDrawIndirectCount;
    bool presenting;

    bool setup(Display* display, Window window) {
        presenting = true;
        bool ok = createInstance();
        if (ok) {
            ok = createSurface(display, window);
        }
        if (ok) {
            ok = pickPhysicalDevice();
        }
        if (ok) {
            ok = createDevice();
        }
        return ok;
    }

    bool setupOffscreen() {
        presenting = false;
        bool ok = createInstance();
        if (ok) {
            ok = pickPhysicalDevice();
        }
        if (ok) {
            ok = createDevice();
        }
        return ok;
    }

    bool createInstance() {
        const(char)*[2] extensions = [
            "VK_KHR_surface",
            "VK_KHR_xlib_surface",
        ];
        VkApplicationInfo applicationInfo;
        applicationInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
        applicationInfo.pApplicationName = "mined";
        applicationInfo.applicationVersion = APPLICATION_VERSION;
        applicationInfo.pEngineName = "mined";
        applicationInfo.engineVersion = APPLICATION_VERSION;
        applicationInfo.apiVersion = VULKAN_API_VERSION_1_1;
        VkInstanceCreateInfo info;
        info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
        info.pApplicationInfo = &applicationInfo;
        if (presenting) {
            info.enabledExtensionCount = extensions.length;
            info.ppEnabledExtensionNames = extensions.ptr;
        }
        return vkCreateInstance(&info, null, &instance) == VK_SUCCESS;
    }

    bool createSurface(Display* display, Window window) {
        VkXlibSurfaceCreateInfoKHR info;
        info.sType = VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR;
        info.dpy = display;
        info.window = window;
        return vkCreateXlibSurfaceKHR(instance, &info, null, &surface) == VK_SUCCESS;
    }

    bool pickPhysicalDevice() {
        VkPhysicalDevice[MAX_PHYSICAL_DEVICES] devices;
        uint deviceCount = MAX_PHYSICAL_DEVICES;
        vkEnumeratePhysicalDevices(instance, &deviceCount, devices.ptr);
        uint bestRank = 0;
        foreach (candidate; devices[0 .. deviceCount]) {
            uint family = usableGraphicsFamily(candidate);
            uint rank = deviceTypeRank(candidate);
            if (family != NO_QUEUE_FAMILY && supportsIndirectDrawing(candidate) && (graphicsQueueFamily == NO_QUEUE_FAMILY || rank > bestRank)) {
                physicalDevice = candidate;
                graphicsQueueFamily = family;
                bestRank = rank;
            }
        }
        if (graphicsQueueFamily != NO_QUEUE_FAMILY) {
            VkPhysicalDeviceProperties properties;
            vkGetPhysicalDeviceProperties(physicalDevice, &properties);
            maxDrawIndirectCount = properties.limits.maxDrawIndirectCount;
        }
        return graphicsQueueFamily != NO_QUEUE_FAMILY;
    }

    uint usableGraphicsFamily(VkPhysicalDevice candidate) {
        VkQueueFamilyProperties[MAX_QUEUE_FAMILIES] families;
        uint familyCount = MAX_QUEUE_FAMILIES;
        vkGetPhysicalDeviceQueueFamilyProperties(candidate, &familyCount, families.ptr);
        uint result = NO_QUEUE_FAMILY;
        foreach (i; 0 .. familyCount) {
            VkBool32 presentSupport = VULKAN_TRUE;
            bool queried = true;
            if (presenting) {
                queried = vkGetPhysicalDeviceSurfaceSupportKHR(candidate, i, surface, &presentSupport) == VK_SUCCESS;
            }
            if (result == NO_QUEUE_FAMILY && queried && (families[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0 && presentSupport != 0) {
                result = i;
            }
        }
        return result;
    }

    bool createDevice() {
        float queuePriority = 1.0f;
        VkDeviceQueueCreateInfo queueInfo;
        queueInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        queueInfo.queueFamilyIndex = graphicsQueueFamily;
        queueInfo.queueCount = 1;
        queueInfo.pQueuePriorities = &queuePriority;
        const(char)*[1] extensions = [
            "VK_KHR_swapchain",
        ];
        VkPhysicalDeviceFeatures features;
        features.multiDrawIndirect = VULKAN_TRUE;
        features.drawIndirectFirstInstance = VULKAN_TRUE;
        VkDeviceCreateInfo info;
        info.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        info.queueCreateInfoCount = 1;
        info.pQueueCreateInfos = &queueInfo;
        info.pEnabledFeatures = &features;
        if (presenting) {
            info.enabledExtensionCount = extensions.length;
            info.ppEnabledExtensionNames = extensions.ptr;
        }
        bool ok = vkCreateDevice(physicalDevice, &info, null, &device) == VK_SUCCESS;
        if (ok) {
            vkGetDeviceQueue(device, graphicsQueueFamily, 0, &graphicsQueue);
        }
        return ok;
    }

    void cleanup() {
        if (device !is null) {
            vkDeviceWaitIdle(device);
            vkDestroyDevice(device, null);
        }
        if (surface !is null) {
            vkDestroySurfaceKHR(instance, surface, null);
        }
        if (instance !is null) {
            vkDestroyInstance(instance, null);
        }
    }
}
