module client.graphics.voxels.chunk_meshes;

import core.stdc.string : memcpy;
import bindings.platform : VK_ACCESS_SHADER_READ_BIT, VK_ACCESS_TRANSFER_READ_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, VK_BUFFER_USAGE_TRANSFER_DST_BIT, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_VERTEX_SHADER_BIT, VK_STRUCTURE_TYPE_MEMORY_BARRIER, VkBuffer, VkBufferCopy, VkBufferUsageFlags, VkCommandBuffer, VkDevice, VkDeviceSize, VkDrawIndirectCommand, VkMemoryBarrier, VkPhysicalDevice, vkCmdCopyBuffer, vkCmdPipelineBarrier;
import client.graphics.pipeline : GpuBuffer, createDeviceLocalBuffer, createMappedBuffer, destroyBuffer;
import client.meshing : Face, Mesher;
import common.array : Array;
import common.chunk_neighbors : ChunkSlot;
import common.graph : Graph;
import common.node : Chunk;
import common.range_allocator : Allocation, RangeAllocator;
import common.slab : Slab;

enum uint INITIAL_FACE_CAPACITY = 1u << 20;
enum uint INITIAL_DRAW_CAPACITY = 1u << 12;
enum uint INITIAL_STAGING_FACES = 1u << 14;
enum uint TRANSFORM_FLOATS = 16;
enum uint INSTANCE_FLOATS = TRANSFORM_FLOATS + 1;
enum uint INSTANCE_BYTES = INSTANCE_FLOATS * float.sizeof;
enum uint VERTICES_PER_FACE = 6;
enum float REVERSED_WINDING = 1.0f;
enum float NATURAL_WINDING = 0.0f;

struct RenderChunk {
    uint faceOffset;
    uint faceCount;
    uint generation;
    uint seenFrame;
    uint listIndex;
    bool meshed;
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
    Array!uint meshedChunks;
    Array!VkBufferCopy uploads;
    Array!BufferCopy growthCopies;
    Array!GpuBuffer retired;
    RangeAllocator allocator;
    Mesher mesher;
    VkPhysicalDevice physicalDevice;
    VkDevice device;
    uint frame;
    uint drawCount;
    uint drawCapacity;
    uint stagedFaces;
    uint stagingCapacity;
    uint backlog;
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

    void beginFrame(size_t chunkCount) {
        foreach (i; 0 .. retired.length) {
            destroyBuffer(device, &retired.ptr[i]);
        }
        retired.clear();
        uploads.clear();
        growthCopies.clear();
        chunks.ensure(chunkCount);
        frame += 1;
        drawCount = 0;
        stagedFaces = 0;
        backlog = 0;
        facesReplaced = false;
    }

    bool needsMesh(const(Chunk)* chunk, uint chunkIndex) {
        const(RenderChunk)* entry = chunks.at(chunkIndex);
        return !entry.meshed || entry.generation != chunk.generation;
    }

    bool mesh(const(Graph)* graph, ChunkSlot slot, uint chunkIndex) {
        RenderChunk* entry = chunks.at(chunkIndex);
        const(Face)[] meshed = mesher.mesh(graph, slot);
        if (entry.faceCount > 0) {
            allocator.release(entry.faceOffset, entry.faceCount);
        }
        if (!entry.meshed) {
            entry.meshed = true;
            entry.listIndex = cast(uint) meshedChunks.length;
            meshedChunks.append(chunkIndex);
        }
        entry.generation = graph.nodeAt(slot.slot).chunks[slot.vertex].generation;
        entry.faceCount = cast(uint) meshed.length;
        bool ok = true;
        if (meshed.length > 0) {
            Allocation allocation = allocator.allocate(entry.faceCount);
            if (!allocation.found) {
                ok = growFaces(entry.faceCount);
                allocation = allocator.allocate(entry.faceCount);
            }
            ok = ok && stage(meshed, allocation.offset);
            entry.faceOffset = allocation.offset;
        }
        return ok;
    }

    void markSeen(uint chunkIndex) {
        chunks.at(chunkIndex).seenFrame = frame;
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

    bool addDraw(uint chunkIndex, float[TRANSFORM_FLOATS] transform, bool reversedWinding) {
        const(RenderChunk)* entry = chunks.at(chunkIndex);
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

    void releaseUnseen() {
        size_t i = 0;
        while (i < meshedChunks.length) {
            RenderChunk* entry = chunks.at(meshedChunks.ptr[i]);
            if (entry.seenFrame != frame) {
                if (entry.faceCount > 0) {
                    allocator.release(entry.faceOffset, entry.faceCount);
                }
                *entry = RenderChunk.init;
                meshedChunks.ptr[i] = meshedChunks.ptr[meshedChunks.length - 1];
                meshedChunks.length -= 1;
                if (i < meshedChunks.length) {
                    chunks.at(meshedChunks.ptr[i]).listIndex = cast(uint) i;
                }
            } else {
                i += 1;
            }
        }
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
        meshedChunks.release();
        allocator.release();
        chunks.release();
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
