module client.graphics.voxels.meshes;

import core.stdc.string : memcpy;
import bindings.platform : VK_ACCESS_SHADER_READ_BIT, VK_ACCESS_TRANSFER_READ_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, VK_BUFFER_USAGE_TRANSFER_DST_BIT, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_VERTEX_SHADER_BIT, VK_STRUCTURE_TYPE_MEMORY_BARRIER, VkBuffer, VkBufferCopy, VkBufferUsageFlags, VkCommandBuffer, VkDevice, VkDeviceSize, VkDrawIndirectCommand, VkMemoryBarrier, VkPhysicalDevice, vkCmdCopyBuffer, vkCmdPipelineBarrier;
import base.array : Array, grownCapacity;
import base.maybe : MaybeIndex;
import client.graphics.matrices : MATRIX_FLOATS;
import client.graphics.pipeline : GpuBuffer;
import client.graphics.voxels.drawlist : CubeFrame, DrawList, DrawableRecord, ListedNode, cubeFrameTable;
import client.meshing : Quad;
import common.traversal : NearbyScratch;
import geometry.honeycomb : CORNER_COUNT, Corner;
import geometry.lorentz : Vec4;
import plugins.api.flags : Flags;

enum uint INITIAL_FACE_CAPACITY = 2 ^^ 20;
enum uint INITIAL_STAGING_FACES = 2 ^^ 16;
enum uint INITIAL_DRAWABLE_CAPACITY = 2 ^^ 14;
enum uint INITIAL_NODE_CAPACITY = 2 ^^ 16;

struct DrawTransform {
    float[MATRIX_FLOATS] transform;
    Vec4!float reversed;
}

enum Replaced : ubyte {
    faces,
    drawBuffers,
}

struct BufferCopy {
    VkBuffer source;
    VkBuffer destination;
    VkDeviceSize size;
}

struct ChunkMeshes {
    mixin DrawList;

    GpuBuffer faces;
    GpuBuffer staging;
    GpuBuffer cubeFrames;
    GpuBuffer nodes;
    GpuBuffer drawables;
    GpuBuffer transforms;
    GpuBuffer commands;
    Array!VkBufferCopy uploads;
    Array!BufferCopy growthCopies;
    Array!GpuBuffer retired;
    VkPhysicalDevice physicalDevice;
    VkDevice device;
    uint drawableCapacity;
    uint nodeCapacity;
    uint stagedFaces;
    uint stagingCapacity;
    ubyte dimension;
    Flags!Replaced replaced;

    void setup(VkPhysicalDevice physical, VkDevice logical, ubyte chunkDimension) {
        physicalDevice = physical;
        device = logical;
        dimension = chunkDimension;
        CubeFrame[CORNER_COUNT] table = cubeFrameTable();
        cubeFrames = GpuBuffer.makeFilled(physicalDevice, device, table[], VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
        faces = GpuBuffer.makeDeviceLocal(physicalDevice, device, cast(VkDeviceSize) INITIAL_FACE_CAPACITY * Quad.sizeof, faceUsage());
        allocator.grow(INITIAL_FACE_CAPACITY);
        staging = GpuBuffer.makeMapped(physicalDevice, device, cast(VkDeviceSize) INITIAL_STAGING_FACES * Quad.sizeof, VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
        stagingCapacity = INITIAL_STAGING_FACES;
        growDrawBuffers(INITIAL_DRAWABLE_CAPACITY);
        replaceNodes(INITIAL_NODE_CAPACITY);
    }

    void growNodes(uint capacity) {
        nodes = replacedMapped(nodes, cast(VkDeviceSize) capacity * MATRIX_FLOATS * float.sizeof);
        nodeCapacity = capacity;
    }

    void storeNode(uint render, float[MATRIX_FLOATS] matrix) {
        (cast(float[MATRIX_FLOATS]*) nodes.mapped)[render] = matrix;
    }

    void storeDrawableNode(uint drawable, ListedNode node) {
        (cast(DrawableRecord*) drawables.mapped)[drawable].node = node;
    }

    void storeDrawable(uint drawable, DrawableRecord record) {
        (cast(DrawableRecord*) drawables.mapped)[drawable] = record;
    }

    void makeDrawableRoom() {
        if (drawableCount == drawableCapacity) {
            growDrawBuffers(drawableCapacity * 2);
        }
    }

    GpuBuffer replacedMapped(GpuBuffer old, VkDeviceSize size) {
        retired.append(old);
        replaced.set(Replaced.drawBuffers);
        return GpuBuffer.makeMapped(physicalDevice, device, size, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
    }

    void growDrawBuffers(uint capacity) {
        drawables = replacedMapped(drawables, cast(VkDeviceSize) capacity * DrawableRecord.sizeof);
        memcpy(drawables.mapped, drawableRecords.ptr, drawableRecords.length * DrawableRecord.sizeof);
        retired.append(transforms);
        retired.append(commands);
        transforms = GpuBuffer.makeDeviceLocal(physicalDevice, device, cast(VkDeviceSize) capacity * DrawTransform.sizeof, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
        commands = GpuBuffer.makeDeviceLocal(physicalDevice, device, cast(VkDeviceSize) capacity * VkDrawIndirectCommand.sizeof, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT);
        drawableCapacity = capacity;
    }

    void beginFrame() {
        foreach (i; 0 .. retired.length) {
            retired.ptr[i].destroy(device);
        }
        retired.clear();
        uploads.clear();
        growthCopies.clear();
        stagedFaces = 0;
        replaced = Flags!Replaced.init;
    }

    void applyBatch(ref const NearbyScratch nearby) {
        size_t batchFaces = 0;
        foreach (worker; batch.workers.slice()) {
            batchFaces += worker.faces.length;
        }
        if (batchFaces > stagingCapacity) {
            retired.append(staging);
            stagingCapacity = cast(uint) grownCapacity(stagingCapacity, batchFaces);
            staging = GpuBuffer.makeMapped(physicalDevice, device, cast(VkDeviceSize) stagingCapacity * Quad.sizeof, VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
        }
        applyRecords(nearby);
    }

    uint faceCountOf(MaybeIndex!uint block, Corner corner) const {
        if (block.exists && block.value < renderBlocks.length && renderBlocks.ptr[block.value].exists) {
            return chunks.at(renderBlocks.ptr[block.value].value * CORNER_COUNT + corner).faceCount;
        } else {
            return 0;
        }
    }

    void uploadFaces(const(Quad)[] meshed, uint deviceOffset) {
        memcpy(cast(Quad*) staging.mapped + stagedFaces, meshed.ptr, meshed.length * Quad.sizeof);
        uploads.append(VkBufferCopy(cast(VkDeviceSize) stagedFaces * Quad.sizeof, cast(VkDeviceSize) deviceOffset * Quad.sizeof, meshed.length * Quad.sizeof));
        stagedFaces += cast(uint) meshed.length;
    }

    void growFaces(uint needed) {
        uint capacity = cast(uint) grownCapacity(allocator.capacity, allocator.capacity + needed);
        GpuBuffer larger = GpuBuffer.makeDeviceLocal(physicalDevice, device, cast(VkDeviceSize) capacity * Quad.sizeof, faceUsage());
        growthCopies.append(BufferCopy(faces.buffer, larger.buffer, cast(VkDeviceSize) allocator.capacity * Quad.sizeof));
        retired.append(faces);
        faces = larger;
        allocator.grow(capacity);
        replaced.set(Replaced.faces);
    }

    void recordUploads(VkCommandBuffer commandBuffer) {
        foreach (copy; growthCopies.slice()) {
            VkBufferCopy region = VkBufferCopy(0, 0, copy.size);
            vkCmdCopyBuffer(commandBuffer, copy.source, copy.destination, 1, &region);
            transferBarrier(commandBuffer, VK_ACCESS_TRANSFER_READ_BIT | VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT);
        }
        if (uploads.length > 0) {
            vkCmdCopyBuffer(commandBuffer, staging.buffer, faces.buffer, cast(uint) uploads.length, uploads.ptr);
        }
        if (uploads.length > 0 || growthCopies.length > 0) {
            transferBarrier(commandBuffer, VK_ACCESS_SHADER_READ_BIT, VK_PIPELINE_STAGE_VERTEX_SHADER_BIT | VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT);
        }
    }

    void cleanup() {
        foreach (i; 0 .. retired.length) {
            retired.ptr[i].destroy(device);
        }
        faces.destroy(device);
        staging.destroy(device);
        cubeFrames.destroy(device);
        nodes.destroy(device);
        drawables.destroy(device);
        transforms.destroy(device);
        commands.destroy(device);
        retired.release();
        uploads.release();
        growthCopies.release();
        releaseDrawList();
    }
}

VkBufferUsageFlags faceUsage() {
    return VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
}

void transferBarrier(VkCommandBuffer commandBuffer, uint destinationAccess, uint destinationStage) {
    VkMemoryBarrier barrier;
    barrier.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER;
    barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    barrier.dstAccessMask = destinationAccess;
    vkCmdPipelineBarrier(commandBuffer, VK_PIPELINE_STAGE_TRANSFER_BIT, destinationStage, 0, 1, &barrier, 0, null, 0, null);
}
