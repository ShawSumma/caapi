module client.graphics.core;

import bindings.platform : VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU, VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU, VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU, VK_QUEUE_GRAPHICS_BIT, VK_STRUCTURE_TYPE_APPLICATION_INFO, VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, VK_SUCCESS, VkApplicationInfo, VkBool32, VkDevice, VkDeviceCreateInfo, VkDeviceQueueCreateInfo, VkInstance, VkInstanceCreateFlags, VkInstanceCreateInfo, VkPhysicalDevice, VkPhysicalDeviceFeatures, VkPhysicalDeviceProperties, VkQueue, VkQueueFamilyProperties, VkResult, VkSurfaceKHR, vkCreateDevice, vkCreateInstance, vkDestroyDevice, vkDestroyInstance, vkDestroySurfaceKHR, vkDeviceWaitIdle, vkEnumeratePhysicalDevices, vkGetDeviceQueue, vkGetPhysicalDeviceFeatures, vkGetPhysicalDeviceProperties, vkGetPhysicalDeviceQueueFamilyProperties, vkGetPhysicalDeviceSurfaceSupportKHR;
import client.graphics.pipeline : VULKAN_TRUE, expectSuccess;

enum uint VULKAN_API_VERSION_1_1 = (1 << 22) | (1 << 12);
enum uint MAX_PHYSICAL_DEVICES = 16;
enum uint MAX_QUEUE_FAMILIES = 32;
enum uint MAX_EXTENSIONS = 4;
enum uint NO_QUEUE_FAMILY = uint.max;
enum uint APPLICATION_VERSION = 1;
enum uint RANK_UNUSABLE = 0;
enum uint RANK_OTHER = 1;
enum uint RANK_VIRTUAL = 2;
enum uint RANK_INTEGRATED = 3;
enum uint RANK_DISCRETE = 4;
immutable string[1] SWAPCHAIN_EXTENSIONS = ["VK_KHR_swapchain"];

version (OSX) {
    import bindings.platform : CAMetalLayer, VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR, VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT, VkMetalSurfaceCreateInfoEXT, vkCreateMetalSurfaceEXT;

    struct SurfaceSource {
        const(CAMetalLayer)* layer;
    }

    // MoltenVK is a portability driver: the loader lists it only when asked to, and its devices need the subset extension.
    immutable string[1] INSTANCE_EXTENSIONS = ["VK_KHR_portability_enumeration"];
    immutable string[2] SURFACE_EXTENSIONS = ["VK_KHR_surface", "VK_EXT_metal_surface"];
    immutable string[1] DEVICE_EXTENSIONS = ["VK_KHR_portability_subset"];
    enum VkInstanceCreateFlags INSTANCE_FLAGS = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;

    VkSurfaceKHR createSurface(VkInstance instance, SurfaceSource source) {
        VkMetalSurfaceCreateInfoEXT info;
        info.sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
        info.pLayer = source.layer;
        VkSurfaceKHR surface;
        expectSuccess(vkCreateMetalSurfaceEXT(instance, &info, null, &surface));
        return surface;
    }
} else {
    import bindings.platform : Display, VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR, VkXlibSurfaceCreateInfoKHR, Window, vkCreateXlibSurfaceKHR;

    struct SurfaceSource {
        Display* display;
        Window window;
    }

    immutable string[0] INSTANCE_EXTENSIONS = [];
    immutable string[2] SURFACE_EXTENSIONS = ["VK_KHR_surface", "VK_KHR_xlib_surface"];
    immutable string[0] DEVICE_EXTENSIONS = [];
    enum VkInstanceCreateFlags INSTANCE_FLAGS = 0;

    VkSurfaceKHR createSurface(VkInstance instance, SurfaceSource source) {
        VkXlibSurfaceCreateInfoKHR info;
        info.sType = VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR;
        info.dpy = source.display;
        info.window = source.window;
        VkSurfaceKHR surface;
        expectSuccess(vkCreateXlibSurfaceKHR(instance, &info, null, &surface));
        return surface;
    }
}

struct ExtensionList {
    const(char)*[MAX_EXTENSIONS] names;
    uint count;

    void add(const(string)[] added) {
        foreach (name; added) {
            assert(count < MAX_EXTENSIONS);
            names[count] = name.ptr;
            count += 1;
        }
    }
}

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

    void setup(SurfaceSource source) {
        isPresenting = true;
        createInstance();
        surface = createSurface(instance, source);
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
        ExtensionList extensions;
        extensions.add(INSTANCE_EXTENSIONS);
        if (isPresenting) {
            extensions.add(SURFACE_EXTENSIONS);
        }
        VkApplicationInfo applicationInfo;
        applicationInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
        applicationInfo.pApplicationName = "mined";
        applicationInfo.applicationVersion = APPLICATION_VERSION;
        applicationInfo.pEngineName = "mined";
        applicationInfo.engineVersion = APPLICATION_VERSION;
        applicationInfo.apiVersion = VULKAN_API_VERSION_1_1;
        VkInstanceCreateInfo info;
        info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
        info.flags = INSTANCE_FLAGS;
        info.pApplicationInfo = &applicationInfo;
        info.enabledExtensionCount = extensions.count;
        info.ppEnabledExtensionNames = extensions.names.ptr;
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
        assert(bestRank != RANK_UNUSABLE);
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
        uint family = 0;
        while (family < familyCount && !((families[family].queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0 && isPresentable(candidate, family))) {
            family += 1;
        }
        if (family < familyCount) {
            return family;
        } else {
            return NO_QUEUE_FAMILY;
        }
    }

    void createDevice() {
        float queuePriority = 1.0f;
        VkDeviceQueueCreateInfo queueInfo;
        queueInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        queueInfo.queueFamilyIndex = graphicsQueueFamily;
        queueInfo.queueCount = 1;
        queueInfo.pQueuePriorities = &queuePriority;
        ExtensionList extensions;
        extensions.add(DEVICE_EXTENSIONS);
        if (isPresenting) {
            extensions.add(SWAPCHAIN_EXTENSIONS);
        }
        VkPhysicalDeviceFeatures features;
        features.multiDrawIndirect = VULKAN_TRUE;
        features.drawIndirectFirstInstance = VULKAN_TRUE;
        VkDeviceCreateInfo info;
        info.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        info.queueCreateInfoCount = 1;
        info.pQueueCreateInfos = &queueInfo;
        info.pEnabledFeatures = &features;
        info.enabledExtensionCount = extensions.count;
        info.ppEnabledExtensionNames = extensions.names.ptr;
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
