module client.graphics.pipeline;

import core.stdc.string : memcpy;
import bindings.vk;

struct GpuBuffer {
    ulong buffer;
    VkDeviceMemory memory;
    VkDeviceSize size;

    static GpuBuffer create(VkPhysicalDevice phys, VkDevice device, const(void)[] data, uint usage) {
        GpuBuffer b;
        b.size = data.length;

        VkBufferCreateInfo bci;
        bci.sType = VkStructureType.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
        bci.size = data.length;
        bci.usage = usage;
        bci.sharingMode = VkSharingMode.VK_SHARING_MODE_EXCLUSIVE;
        vkCreateBuffer(device, &bci, null, &b.buffer);

        VkMemoryRequirements req;
        vkGetBufferMemoryRequirements(device, b.buffer, &req);

        VkPhysicalDeviceMemoryProperties memProps;
        vkGetPhysicalDeviceMemoryProperties(phys, &memProps);

        uint memTypeIdx = uint.max;
        uint wanted = VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                      VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
        for (uint i = 0; i < memProps.memoryTypeCount; i++) {
            if ((req.memoryTypeBits & (1u << i)) &&
                (memProps.memoryTypes[i].propertyFlags & wanted) == wanted) {
                memTypeIdx = i;
                break;
            }
        }

        VkMemoryAllocateInfo mai;
        mai.sType = VkStructureType.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        mai.allocationSize = req.size;
        mai.memoryTypeIndex = memTypeIdx;
        vkAllocateMemory(device, &mai, null, &b.memory);
        vkBindBufferMemory(device, b.buffer, b.memory, 0);

        void* mapped;
        vkMapMemory(device, b.memory, 0, req.size, 0, &mapped);
        memcpy(mapped, data.ptr, data.length);
        vkUnmapMemory(device, b.memory);

        return b;
    }

    static GpuBuffer createHostVisible(VkPhysicalDevice phys, VkDevice device, VkDeviceSize sz, uint usage) {
        GpuBuffer b;
        b.size = sz;

        VkBufferCreateInfo bci;
        bci.sType = VkStructureType.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
        bci.size = sz;
        bci.usage = usage;
        bci.sharingMode = VkSharingMode.VK_SHARING_MODE_EXCLUSIVE;
        vkCreateBuffer(device, &bci, null, &b.buffer);

        VkMemoryRequirements req;
        vkGetBufferMemoryRequirements(device, b.buffer, &req);

        VkPhysicalDeviceMemoryProperties memProps;
        vkGetPhysicalDeviceMemoryProperties(phys, &memProps);

        uint memTypeIdx = uint.max;
        uint wanted = VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                      VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
        for (uint i = 0; i < memProps.memoryTypeCount; i++) {
            if ((req.memoryTypeBits & (1u << i)) &&
                (memProps.memoryTypes[i].propertyFlags & wanted) == wanted) {
                memTypeIdx = i;
                break;
            }
        }

        VkMemoryAllocateInfo mai;
        mai.sType = VkStructureType.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        mai.allocationSize = req.size;
        mai.memoryTypeIndex = memTypeIdx;
        vkAllocateMemory(device, &mai, null, &b.memory);
        vkBindBufferMemory(device, b.buffer, b.memory, 0);

        return b;
    }

    void cleanup(VkDevice device) {
        if (buffer) {
            vkDestroyBuffer(device, buffer, null);
        }
        if (memory) {
            vkFreeMemory(device, memory, null);
        }
    }
}
