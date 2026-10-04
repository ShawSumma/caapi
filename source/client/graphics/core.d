module client.graphics.core;

import bindings.platform : Display, VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU, VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU, VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU, VK_QUEUE_GRAPHICS_BIT, VK_STRUCTURE_TYPE_APPLICATION_INFO, VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR, VK_SUCCESS, VkApplicationInfo, VkBool32, VkDevice, VkDeviceCreateInfo, VkDeviceQueueCreateInfo, VkInstance, VkInstanceCreateInfo, VkPhysicalDevice, VkPhysicalDeviceFeatures, VkPhysicalDeviceProperties, VkQueue, VkQueueFamilyProperties, VkResult, VkSurfaceKHR, VkXlibSurfaceCreateInfoKHR, Window, vkCreateDevice, vkCreateInstance, vkCreateXlibSurfaceKHR, vkDestroyDevice, vkDestroyInstance, vkDestroySurfaceKHR, vkDeviceWaitIdle, vkEnumeratePhysicalDevices, vkGetDeviceQueue, vkGetPhysicalDeviceFeatures, vkGetPhysicalDeviceProperties, vkGetPhysicalDeviceQueueFamilyProperties, vkGetPhysicalDeviceSurfaceSupportKHR;
import client.graphics.pipeline : VULKAN_TRUE, expectSuccess;

enum uint VULKAN_API_VERSION_1_1 = (1 << 22) | (1 << 12);
enum uint MAX_PHYSICAL_DEVICES = 16;
enum uint MAX_QUEUE_FAMILIES = 32;
enum uint NO_QUEUE_FAMILY = uint.max;
enum uint APPLICATION_VERSION = 1;
enum uint RANK_UNUSABLE = 0;
enum uint RANK_OTHER = 1;
enum uint RANK_VIRTUAL = 2;
enum uint RANK_INTEGRATED = 3;
enum uint RANK_DISCRETE = 4;

uint deviceTypeRank(VkPhysicalDevice device) {
    VkPhysicalDeviceProperties properties;
    vkGetPhysicalDeviceProperties(device, &properties);
    if (properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
        return RANK_DISCRETE;
    } else if (properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU) {
        return RANK_INTEGRATED;
    } else if (properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU) {
        return RANK_VIRTUAL;
    } else {
        return RANK_OTHER;
    }
}

bool isIndirectDrawingSupported(VkPhysicalDevice device) {
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
    bool isPresenting;

    void setup(Display* display, Window window) {
        isPresenting = true;
        createInstance();
        VkXlibSurfaceCreateInfoKHR info;
        info.sType = VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR;
        info.dpy = display;
        info.window = window;
        expectSuccess(vkCreateXlibSurfaceKHR(instance, &info, null, &surface));
        pickPhysicalDevice();
        createDevice();
    }

    void setupOffscreen() {
        isPresenting = false;
        createInstance();
        pickPhysicalDevice();
        createDevice();
    }

    void createInstance() {
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
        if (isPresenting) {
            info.enabledExtensionCount = extensions.length;
            info.ppEnabledExtensionNames = extensions.ptr;
        }
        expectSuccess(vkCreateInstance(&info, null, &instance));
    }

    uint usableRank(VkPhysicalDevice candidate) {
        if (usableGraphicsFamily(candidate) != NO_QUEUE_FAMILY && isIndirectDrawingSupported(candidate)) {
            return deviceTypeRank(candidate);
        } else {
            return RANK_UNUSABLE;
        }
    }

    void pickPhysicalDevice() {
        VkPhysicalDevice[MAX_PHYSICAL_DEVICES] devices;
        uint deviceCount = MAX_PHYSICAL_DEVICES;
        expectSuccess(vkEnumeratePhysicalDevices(instance, &deviceCount, devices.ptr));
        uint bestRank = RANK_UNUSABLE;
        foreach (candidate; devices[0 .. deviceCount]) {
            uint rank = usableRank(candidate);
            if (rank > bestRank) {
                physicalDevice = candidate;
                bestRank = rank;
            }
        }
        if (bestRank == RANK_UNUSABLE) {
            assert(false);
        }
        graphicsQueueFamily = usableGraphicsFamily(physicalDevice);
        VkPhysicalDeviceProperties properties;
        vkGetPhysicalDeviceProperties(physicalDevice, &properties);
        maxDrawIndirectCount = properties.limits.maxDrawIndirectCount;
    }

    bool isPresentable(VkPhysicalDevice candidate, uint family) {
        if (isPresenting) {
            VkBool32 presentSupport = 0;
            immutable VkResult queried = vkGetPhysicalDeviceSurfaceSupportKHR(candidate, family, surface, &presentSupport);
            return queried == VK_SUCCESS && presentSupport != 0;
        } else {
            return true;
        }
    }

    uint usableGraphicsFamily(VkPhysicalDevice candidate) {
        VkQueueFamilyProperties[MAX_QUEUE_FAMILIES] families;
        uint familyCount = MAX_QUEUE_FAMILIES;
        vkGetPhysicalDeviceQueueFamilyProperties(candidate, &familyCount, families.ptr);
        foreach (i; 0 .. familyCount) {
            immutable bool isFamilyPresentable = isPresentable(candidate, i);
            if ((families[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0 && isFamilyPresentable) {
                return i;
            }
        }
        return NO_QUEUE_FAMILY;
    }

    void createDevice() {
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
        if (isPresenting) {
            info.enabledExtensionCount = extensions.length;
            info.ppEnabledExtensionNames = extensions.ptr;
        }
        expectSuccess(vkCreateDevice(physicalDevice, &info, null, &device));
        vkGetDeviceQueue(device, graphicsQueueFamily, 0, &graphicsQueue);
    }

    void cleanup() {
        vkDeviceWaitIdle(device);
        vkDestroyDevice(device, null);
        if (isPresenting) {
            vkDestroySurfaceKHR(instance, surface, null);
        }
        vkDestroyInstance(instance, null);
    }
}
