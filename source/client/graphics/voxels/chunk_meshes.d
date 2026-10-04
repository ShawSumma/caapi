module client.graphics.voxels.chunk_meshes;

import core.stdc.string : memcpy;
import bindings.platform : VK_ACCESS_SHADER_READ_BIT, VK_ACCESS_TRANSFER_READ_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, VK_BUFFER_USAGE_TRANSFER_DST_BIT, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_VERTEX_SHADER_BIT, VK_STRUCTURE_TYPE_MEMORY_BARRIER, VkBuffer, VkBufferCopy, VkBufferUsageFlags, VkCommandBuffer, VkDevice, VkDeviceSize, VkDrawIndirectCommand, VkMemoryBarrier, VkPhysicalDevice, vkCmdCopyBuffer, vkCmdPipelineBarrier;
import client.graphics.pipeline : GpuBuffer, createDeviceLocalBuffer, createMappedBuffer, destroyBuffer;
import client.meshing : Face, Mesher;
import common.array : Array;
import common.dodeca : VERTEX_COUNT;
import common.graph : Graph;
import common.node : ChunkSlot;
import common.range_allocator : Allocation, RangeAllocator;
import common.slab : Slab;
import common.traversal : NearbyNode;

enum uint INITIAL_FACE_CAPACITY = 1u << 20;
enum uint INITIAL_DRAW_CAPACITY = 1u << 12;
enum uint INITIAL_STAGING_FACES = 1u << 14;
enum uint TRANSFORM_FLOATS = 16;
enum uint INSTANCE_FLOATS = TRANSFORM_FLOATS + 1;
enum uint INSTANCE_BYTES = INSTANCE_FLOATS * float.sizeof;
enum uint VERTICES_PER_FACE = 6;
enum float REVERSED_WINDING = 1.0f;
enum float NATURAL_WINDING = 0.0f;
enum uint NOT_LISTED = uint.max;

struct RenderChunk {
    uint faceOffset;
    uint faceCount;
    bool listed;
}

struct NearbyEntry {
    uint stamp;
    uint index;
}

struct Drawable {
    uint chunkIndex;
    uint nearbyIndex;
}

struct BufferCopy {
    VkBuffer source;
    VkBuffer destination;
    VkDeviceSize size;
}

struct ChunkMeshes {
    GpuBuffer faces;
    GpuBuffer staging;
    GpuBuffer indirect;
    GpuBuffer instances;
    Slab!RenderChunk chunks;
    Slab!uint facedVertices;
    Slab!NearbyEntry nearby;
    Array!Drawable drawables;
    Array!VkBufferCopy uploads;
    Array!BufferCopy growthCopies;
    Array!GpuBuffer retired;
    RangeAllocator allocator;
    Mesher mesher;
    VkPhysicalDevice physicalDevice;
    VkDevice device;
    uint nearbyVersion = NOT_LISTED;
    uint drawCount;
    uint drawCapacity;
    uint stagedFaces;
    uint stagingCapacity;
    uint meshedChunks;
    bool facesReplaced;

    bool setup(VkPhysicalDevice physical, VkDevice logical, ubyte dimension) {
        physicalDevice = physical;
        device = logical;
        mesher.setup(dimension);
        faces = createDeviceLocalBuffer(physicalDevice, device, cast(VkDeviceSize) INITIAL_FACE_CAPACITY * Face.sizeof, faceUsage());
        allocator.grow(INITIAL_FACE_CAPACITY);
        staging = createMappedBuffer(physicalDevice, device, cast(VkDeviceSize) INITIAL_STAGING_FACES * Face.sizeof, VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
        stagingCapacity = INITIAL_STAGING_FACES;
        indirect = createMappedBuffer(physicalDevice, device, cast(VkDeviceSize) INITIAL_DRAW_CAPACITY * VkDrawIndirectCommand.sizeof, VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT);
        instances = createMappedBuffer(physicalDevice, device, cast(VkDeviceSize) INITIAL_DRAW_CAPACITY * INSTANCE_BYTES, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
        drawCapacity = INITIAL_DRAW_CAPACITY;
        return faces.ready && staging.ready && indirect.ready && instances.ready;
    }

    void forgetWorld() {
        chunks.release();
        facedVertices.release();
        nearby.release();
        drawables.clear();
        allocator.release();
        allocator.grow(cast(uint)(faces.size / Face.sizeof));
        nearbyVersion = NOT_LISTED;
        meshedChunks = 0;
    }

    void beginFrame(uint nodeCount) {
        foreach (i; 0 .. retired.length) {
            destroyBuffer(device, &retired.ptr[i]);
        }
        retired.clear();
        uploads.clear();
        growthCopies.clear();
        chunks.ensure(cast(size_t) nodeCount * VERTEX_COUNT);
        facedVertices.ensure(nodeCount);
        nearby.ensure(nodeCount);
        drawCount = 0;
        stagedFaces = 0;
        facesReplaced = false;
    }

    void listNearby(const(NearbyNode)[] nodes, uint stamp) {
        foreach (drawable; drawables.slice()) {
            chunks.at(drawable.chunkIndex).listed = false;
        }
        drawables.clear();
        nearbyVersion = stamp;
        foreach (i, node; nodes) {
            *nearby.at(node.slot) = NearbyEntry(stamp, cast(uint) i);
            uint mask = *facedVertices.at(node.slot);
            foreach (vertex; 0 .. VERTEX_COUNT) {
                if ((mask & (1u << vertex)) != 0) {
                    list(node.slot * VERTEX_COUNT + vertex, cast(uint) i);
                }
            }
        }
    }

    void list(uint chunkIndex, uint nearbyIndex) {
        chunks.at(chunkIndex).listed = true;
        drawables.append(Drawable(chunkIndex, nearbyIndex));
    }

    bool mesh(const(Graph)* graph, ChunkSlot slot) {
        uint chunkIndex = slot.slot * VERTEX_COUNT + slot.vertex;
        RenderChunk* entry = chunks.at(chunkIndex);
        const(Face)[] meshed = mesher.mesh(graph, slot);
        if (entry.faceCount > 0) {
            allocator.release(entry.faceOffset, entry.faceCount);
        }
        entry.faceCount = cast(uint) meshed.length;
        meshedChunks += 1;
        uint* mask = facedVertices.at(slot.slot);
        *mask &= ~(1u << slot.vertex);
        bool ok = true;
        if (meshed.length > 0) {
            *mask |= 1u << slot.vertex;
            Allocation allocation = allocator.allocate(entry.faceCount);
            if (!allocation.found) {
                ok = growFaces(entry.faceCount);
                allocation = allocator.allocate(entry.faceCount);
            }
            ok = ok && stage(meshed, allocation.offset);
            entry.faceOffset = allocation.offset;
            const(NearbyEntry)* place = nearby.at(slot.slot);
            if (!entry.listed && place.stamp == nearbyVersion) {
                list(chunkIndex, place.index);
            }
        }
        return ok;
    }

    bool stage(const(Face)[] meshed, uint deviceOffset) {
        bool ok = true;
        if (stagedFaces + meshed.length > stagingCapacity) {
            uint grown = stagingCapacity * 2;
            while (grown < stagedFaces + meshed.length) {
                grown *= 2;
            }
            GpuBuffer larger = createMappedBuffer(physicalDevice, device, cast(VkDeviceSize) grown * Face.sizeof, VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
            ok = larger.ready;
            if (ok) {
                memcpy(larger.mapped, staging.mapped, stagedFaces * Face.sizeof);
                retired.append(staging);
                staging = larger;
                stagingCapacity = grown;
            } else {
                retired.append(larger);
            }
        }
        if (ok) {
            memcpy(cast(Face*) staging.mapped + stagedFaces, meshed.ptr, meshed.length * Face.sizeof);
            uploads.append(VkBufferCopy(cast(VkDeviceSize) stagedFaces * Face.sizeof, cast(VkDeviceSize) deviceOffset * Face.sizeof, meshed.length * Face.sizeof));
            stagedFaces += cast(uint) meshed.length;
        }
        return ok;
    }

    bool growFaces(uint needed) {
        uint grown = allocator.capacity * 2;
        while (grown < allocator.capacity + needed) {
            grown *= 2;
        }
        GpuBuffer larger = createDeviceLocalBuffer(physicalDevice, device, cast(VkDeviceSize) grown * Face.sizeof, faceUsage());
        if (larger.ready) {
            growthCopies.append(BufferCopy(faces.buffer, larger.buffer, cast(VkDeviceSize) allocator.capacity * Face.sizeof));
            retired.append(faces);
            faces = larger;
            allocator.grow(grown);
            facesReplaced = true;
        } else {
            retired.append(larger);
        }
        return larger.ready;
    }

    bool addDraw(const(RenderChunk)* entry, float[TRANSFORM_FLOATS] transform, bool reversedWinding) {
        bool ok = true;
        if (drawCount == drawCapacity) {
            ok = growDraws();
        }
        if (ok) {
            VkDrawIndirectCommand command = VkDrawIndirectCommand(entry.faceCount * VERTICES_PER_FACE, 1, entry.faceOffset * VERTICES_PER_FACE, drawCount);
            memcpy(cast(VkDrawIndirectCommand*) indirect.mapped + drawCount, &command, VkDrawIndirectCommand.sizeof);
            float[INSTANCE_FLOATS] instance;
            instance[0 .. TRANSFORM_FLOATS] = transform[];
            instance[TRANSFORM_FLOATS] = NATURAL_WINDING;
            if (reversedWinding) {
                instance[TRANSFORM_FLOATS] = REVERSED_WINDING;
            }
            memcpy(cast(float*) instances.mapped + drawCount * INSTANCE_FLOATS, instance.ptr, INSTANCE_BYTES);
            drawCount += 1;
        }
        return ok;
    }

    bool growDraws() {
        uint grown = drawCapacity * 2;
        GpuBuffer largerIndirect = createMappedBuffer(physicalDevice, device, cast(VkDeviceSize) grown * VkDrawIndirectCommand.sizeof, VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT);
        GpuBuffer largerInstances = createMappedBuffer(physicalDevice, device, cast(VkDeviceSize) grown * INSTANCE_BYTES, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
        bool ok = largerIndirect.ready && largerInstances.ready;
        if (ok) {
            memcpy(largerIndirect.mapped, indirect.mapped, drawCount * VkDrawIndirectCommand.sizeof);
            memcpy(largerInstances.mapped, instances.mapped, drawCount * INSTANCE_BYTES);
            retired.append(indirect);
            retired.append(instances);
            indirect = largerIndirect;
            instances = largerInstances;
            drawCapacity = grown;
        } else {
            retired.append(largerIndirect);
            retired.append(largerInstances);
        }
        return ok;
    }

    void recordUploads(VkCommandBuffer commands) {
        foreach (copy; growthCopies.slice()) {
            VkBufferCopy region = VkBufferCopy(0, 0, copy.size);
            vkCmdCopyBuffer(commands, copy.source, copy.destination, 1, &region);
            transferBarrier(commands, VK_ACCESS_TRANSFER_READ_BIT | VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT);
        }
        if (uploads.length > 0) {
            vkCmdCopyBuffer(commands, staging.buffer, faces.buffer, cast(uint) uploads.length, uploads.ptr);
        }
        if (uploads.length > 0 || growthCopies.length > 0) {
            transferBarrier(commands, VK_ACCESS_SHADER_READ_BIT, VK_PIPELINE_STAGE_VERTEX_SHADER_BIT);
        }
    }

    void cleanup() {
        foreach (i; 0 .. retired.length) {
            destroyBuffer(device, &retired.ptr[i]);
        }
        destroyBuffer(device, &faces);
        destroyBuffer(device, &staging);
        destroyBuffer(device, &indirect);
        destroyBuffer(device, &instances);
        retired.release();
        uploads.release();
        growthCopies.release();
        drawables.release();
        allocator.release();
        chunks.release();
        facedVertices.release();
        nearby.release();
        mesher.release();
    }
}

VkBufferUsageFlags faceUsage() {
    return VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
}

void transferBarrier(VkCommandBuffer commands, uint destinationAccess, uint destinationStage) {
    VkMemoryBarrier barrier;
    barrier.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER;
    barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    barrier.dstAccessMask = destinationAccess;
    vkCmdPipelineBarrier(commands, VK_PIPELINE_STAGE_TRANSFER_BIT, destinationStage, 0, 1, &barrier, 0, null, 0, null);
}
