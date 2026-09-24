module client.graphics.core;

import bindings.platform : Display, VK_QUEUE_GRAPHICS_BIT, VK_STRUCTURE_TYPE_APPLICATION_INFO, VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR, VK_SUCCESS, VkApplicationInfo, VkBool32, VkDevice, VkDeviceCreateInfo, VkDeviceQueueCreateInfo, VkInstance, VkInstanceCreateInfo, VkPhysicalDevice, VkQueue, VkQueueFamilyProperties, VkSurfaceKHR, VkXlibSurfaceCreateInfoKHR, Window, vkCreateDevice, vkCreateInstance, vkCreateXlibSurfaceKHR, vkDestroyDevice, vkDestroyInstance, vkDestroySurfaceKHR, vkDeviceWaitIdle, vkEnumeratePhysicalDevices, vkGetDeviceQueue, vkGetPhysicalDeviceQueueFamilyProperties, vkGetPhysicalDeviceSurfaceSupportKHR;

enum uint VULKAN_API_VERSION_1_1 = (1 << 22) | (1 << 12);
enum uint MAX_PHYSICAL_DEVICES = 16;
enum uint MAX_QUEUE_FAMILIES = 32;
enum uint NO_QUEUE_FAMILY = uint.max;
enum uint APPLICATION_VERSION = 1;

struct VulkanCore {
    VkInstance instance;
    VkPhysicalDevice physicalDevice;
    VkDevice device;
    VkQueue graphicsQueue;
    VkSurfaceKHR surface;
    uint graphicsQueueFamily = NO_QUEUE_FAMILY;

    bool setup(Display* display, Window window) {
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
        info.enabledExtensionCount = extensions.length;
        info.ppEnabledExtensionNames = extensions.ptr;
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
        if (deviceCount > 0) {
            physicalDevice = devices[0];
            VkQueueFamilyProperties[MAX_QUEUE_FAMILIES] families;
            uint familyCount = MAX_QUEUE_FAMILIES;
            vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &familyCount, families.ptr);
            foreach (i; 0 .. familyCount) {
                VkBool32 presentSupport = 0;
                vkGetPhysicalDeviceSurfaceSupportKHR(physicalDevice, i, surface, &presentSupport);
                if (graphicsQueueFamily == NO_QUEUE_FAMILY && (families[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0 && presentSupport != 0) {
                    graphicsQueueFamily = i;
                }
            }
        }
        return graphicsQueueFamily != NO_QUEUE_FAMILY;
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
        VkDeviceCreateInfo info;
        info.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        info.queueCreateInfoCount = 1;
        info.pQueueCreateInfos = &queueInfo;
        info.enabledExtensionCount = extensions.length;
        info.ppEnabledExtensionNames = extensions.ptr;
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
