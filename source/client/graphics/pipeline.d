module client.graphics.pipeline;

import core.stdc.string : memcpy, memset;
import bindings.vk;

// Both allocators want memory the host can write without flushing, so the
// search for a suitable memory type is shared.
uint findHostVisibleMemoryType(VkPhysicalDevice phys, uint typeBits) {
    VkPhysicalDeviceMemoryProperties memProps;
    vkGetPhysicalDeviceMemoryProperties(phys, &memProps);

    uint hostVisible = VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;
    uint hostCoherent = VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    uint wanted = hostVisible | hostCoherent;

    for (uint i = 0; i < memProps.memoryTypeCount; i = i + 1) {
        bool typeAllowed = (typeBits & (1u << i)) != 0;
        bool hasWanted = (memProps.memoryTypes[i].propertyFlags & wanted) == wanted;
        if (typeAllowed && hasWanted) {
            return i;
        }
    }
    return uint.max;
}

struct GpuBuffer {
    ulong buffer;
    VkDeviceMemory memory;
    VkDeviceSize size;

    static GpuBuffer create(
        VkPhysicalDevice phys,
        VkDevice device,
        const(void)[] data,
        uint usage,
    ) {
        GpuBuffer b = createHostVisible(phys, device, data.length, usage);

        void* mapped;
        vkMapMemory(device, b.memory, 0, data.length, 0, &mapped);
        memcpy(mapped, data.ptr, data.length);
        vkUnmapMemory(device, b.memory);

        return b;
    }

    // Same result as create() with an all-zero source, without the source.
    // The buffers this serves are gigabytes; staging them through a host
    // allocation cost that much again in RSS and a full copy on top.
    static GpuBuffer createZeroed(
        VkPhysicalDevice phys,
        VkDevice device,
        VkDeviceSize sz,
        uint usage,
    ) {
        GpuBuffer b = createHostVisible(phys, device, sz, usage);

        void* mapped;
        vkMapMemory(device, b.memory, 0, sz, 0, &mapped);
        memset(mapped, 0, cast(size_t) sz);
        vkUnmapMemory(device, b.memory);

        return b;
    }

    static GpuBuffer createHostVisible(
        VkPhysicalDevice phys,
        VkDevice device,
        VkDeviceSize sz,
        uint usage,
    ) {
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

        VkMemoryAllocateInfo mai;
        mai.sType = VkStructureType.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        mai.allocationSize = req.size;
        mai.memoryTypeIndex = findHostVisibleMemoryType(phys, req.memoryTypeBits);
        vkAllocateMemory(device, &mai, null, &b.memory);
        vkBindBufferMemory(device, b.buffer, b.memory, 0);

        return b;
    }

    void cleanup(VkDevice device) {
        if (buffer != VK_NULL_HANDLE) {
            vkDestroyBuffer(device, buffer, null);
        }
        if (memory != VK_NULL_HANDLE) {
            vkFreeMemory(device, memory, null);
        }
    }
}
