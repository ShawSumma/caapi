module client.graphics.voxels.meshes;

import core.stdc.string : memcpy;
import bindings.platform : VK_ACCESS_SHADER_READ_BIT, VK_ACCESS_TRANSFER_READ_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, VK_BUFFER_USAGE_TRANSFER_DST_BIT, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_VERTEX_SHADER_BIT, VK_STRUCTURE_TYPE_MEMORY_BARRIER, VkBuffer, VkBufferCopy, VkBufferUsageFlags, VkCommandBuffer, VkDevice, VkDeviceSize, VkDrawIndirectCommand, VkMemoryBarrier, VkPhysicalDevice, vkCmdCopyBuffer, vkCmdPipelineBarrier;
import base.allocator : NO_OFFSET, RangeAllocator;
import base.array : Array, grownCapacity;
import base.slab : Slab;
import client.graphics.matrices : MATRIX_FLOATS, flatten;
import client.graphics.pipeline : GpuBuffer;
import client.meshing : MeshBatch, MeshRecord, Quad;
import common.eviction : Unloaded;
import common.node : ChunkSlot;
import common.traversal : NOT_COLLECTED, NearbyScratch;
import geometry.honeycomb : CORNER_COUNT, Corner, cubeCenter, cubeToNode;
import plugins.api.flags : Flags;

enum uint INITIAL_FACE_CAPACITY = 2 ^^ 20;
enum uint INITIAL_STAGING_FACES = 2 ^^ 16;
enum uint INITIAL_DRAWABLE_CAPACITY = 2 ^^ 14;
enum uint INITIAL_NODE_CAPACITY = 2 ^^ 16;
enum uint NO_VERSION = uint.max;
enum uint POINT_FLOATS = 4;

struct CubeFrame {
    float[MATRIX_FLOATS] cubeToNode;
    float[POINT_FLOATS] center;
}

struct DrawableRecord {
    uint node;
    uint corner;
    uint faceOffset;
    uint faceCount;
}

struct DrawTransform {
    float[MATRIX_FLOATS] transform;
    float[POINT_FLOATS] reversed;
}

enum ChunkMark : ubyte {
    drawable,
    nodeMissing,
    unlisted,
}

enum Replaced : ubyte {
    faces,
    drawBuffers,
}

struct RenderChunk {
    uint faceOffset;
    uint faceCount;
    uint drawable;
    uint slot;
    Flags!ChunkMark marks;
}

struct BufferCopy {
    VkBuffer source;
    VkBuffer destination;
    VkDeviceSize size;
}

struct ChunkMeshes {
    GpuBuffer faces;
    GpuBuffer staging;
    GpuBuffer cubeFrames;
    GpuBuffer nodes;
    GpuBuffer drawables;
    GpuBuffer transforms;
    GpuBuffer commands;
    Slab!RenderChunk chunks;
    Array!uint renderBlocks;
    Array!uint freeRenderBlocks;
    Array!uint drawableChunks;
    Array!DrawableRecord drawableRecords;
    Array!uint placedVersions;
    Array!uint unlisted;
    Array!VkBufferCopy uploads;
    Array!BufferCopy growthCopies;
    Array!GpuBuffer retired;
    MeshBatch batch;
    RangeAllocator allocator;
    VkPhysicalDevice physicalDevice;
    VkDevice device;
    uint listedVersion = NO_VERSION;
    uint listedNodes;
    uint drawableCapacity;
    uint nodeCapacity;
    uint stagedFaces;
    uint stagingCapacity;
    uint renderBlockCount;
    uint meshedChunks;
    ubyte dimension;
    Flags!Replaced replaced;

    void setup(VkPhysicalDevice physical, VkDevice logical, ubyte chunkDimension) {
        physicalDevice = physical;
        device = logical;
        dimension = chunkDimension;
        CubeFrame[CORNER_COUNT] table;
        foreach (index; 0 .. CORNER_COUNT) {
            Corner corner = cast(Corner) index;
            table[index] = CubeFrame(flatten(corner.cubeToNode), corner.cubeCenter.v.c);
        }
        cubeFrames = GpuBuffer.makeFilled(physicalDevice, device, table[], VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
        faces = GpuBuffer.makeDeviceLocal(physicalDevice, device, cast(VkDeviceSize) INITIAL_FACE_CAPACITY * Quad.sizeof, faceUsage());
        allocator.grow(INITIAL_FACE_CAPACITY);
        staging = GpuBuffer.makeMapped(physicalDevice, device, cast(VkDeviceSize) INITIAL_STAGING_FACES * Quad.sizeof, VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
        stagingCapacity = INITIAL_STAGING_FACES;
        growDrawBuffers(INITIAL_DRAWABLE_CAPACITY);
        replaceNodes(INITIAL_NODE_CAPACITY);
    }

    void replaceNodes(uint capacity) {
        nodes = replacedMapped(nodes, cast(VkDeviceSize) capacity * MATRIX_FLOATS * float.sizeof);
        nodeCapacity = capacity;
        placedVersions.resize(capacity);
        placedVersions.slice()[] = NO_VERSION;
    }

    uint drawableCount() const {
        return cast(uint) drawableChunks.length;
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

    void forgetWorld() {
        chunks.release();
        renderBlocks.clear();
        freeRenderBlocks.clear();
        renderBlockCount = 0;
        drawableChunks.clear();
        drawableRecords.clear();
        placedVersions.slice()[] = NO_VERSION;
        unlisted.clear();
        allocator.release();
        allocator.grow(cast(uint)(faces.size / Quad.sizeof));
        listedVersion = NO_VERSION;
        listedNodes = 0;
        meshedChunks = 0;
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

    void list(ref const NearbyScratch nearby, uint listVersion) {
        if (listVersion != listedVersion) {
            listedVersion = listVersion;
            refreshDrawableNodes(nearby);
        } else if (nearby.nodes.length > listedNodes) {
            refreshUnlisted(nearby);
        }
        listedNodes = cast(uint) nearby.nodes.length;
    }

    uint placeNode(ref const NearbyScratch nearby, uint chunkIndex) {
        uint render = chunkIndex / CORNER_COUNT;
        uint node = nearby.indexOf(chunks.at(chunkIndex).slot);
        if (node == NOT_COLLECTED) {
            return NOT_COLLECTED;
        } else {
            if (placedVersions.ptr[render] != listedVersion) {
                (cast(float[MATRIX_FLOATS]*) nodes.mapped)[render] = flatten(nearby.nodes.ptr[node].transform.m);
                placedVersions.ptr[render] = listedVersion;
            }
            return render;
        }
    }

    void refreshDrawableNodes(ref const NearbyScratch nearby) {
        foreach (chunkIndex; unlisted.slice()) {
            chunks.at(chunkIndex).marks.clear(ChunkMark.unlisted);
        }
        unlisted.clear();
        foreach (drawable, chunkIndex; drawableChunks.slice()) {
            uint node = placeNode(nearby, chunkIndex);
            setDrawableNode(cast(uint) drawable, node);
            noteNode(chunkIndex, node);
        }
    }

    void setDrawableNode(uint drawable, uint node) {
        drawableRecords.ptr[drawable].node = node;
        (cast(DrawableRecord*) drawables.mapped)[drawable].node = node;
    }

    void setDrawable(uint drawable, DrawableRecord record) {
        drawableRecords.ptr[drawable] = record;
        (cast(DrawableRecord*) drawables.mapped)[drawable] = record;
    }

    void noteNode(uint chunkIndex, uint node) {
        RenderChunk* entry = chunks.at(chunkIndex);
        entry.marks.put(ChunkMark.nodeMissing, node == NOT_COLLECTED);
        if (node == NOT_COLLECTED && !entry.marks.has(ChunkMark.unlisted)) {
            entry.marks.set(ChunkMark.unlisted);
            unlisted.append(chunkIndex);
        }
    }

    void refreshUnlisted(ref const NearbyScratch nearby) {
        size_t kept = 0;
        foreach (chunkIndex; unlisted.slice()) {
            RenderChunk* entry = chunks.at(chunkIndex);
            if (entry.marks.has(ChunkMark.drawable) && entry.marks.has(ChunkMark.nodeMissing)) {
                uint node = placeNode(nearby, chunkIndex);
                if (node != NOT_COLLECTED) {
                    setDrawableNode(entry.drawable, node);
                    entry.marks.clear(ChunkMark.nodeMissing);
                }
            }
            if (entry.marks.has(ChunkMark.drawable) && entry.marks.has(ChunkMark.nodeMissing)) {
                unlisted.ptr[kept] = chunkIndex;
                kept += 1;
            } else {
                entry.marks.clear(ChunkMark.unlisted);
            }
        }
        unlisted.length = kept;
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
        foreach (worker; batch.workers.slice()) {
            foreach (record; worker.records.slice()) {
                apply(nearby, record, worker.faces.ptr[record.offset .. record.offset + record.count]);
            }
        }
    }

    uint faceCountOf(uint block, Corner corner) const {
        if (block < renderBlocks.length && renderBlocks.ptr[block] != 0) {
            return chunks.at((renderBlocks.ptr[block] - 1) * CORNER_COUNT + corner).faceCount;
        } else {
            return 0;
        }
    }

    uint renderIndexFor(uint block, Corner corner) {
        if (renderBlocks.length <= block) {
            renderBlocks.resize(block + 1);
        }
        if (renderBlocks.ptr[block] == 0) {
            uint render = renderBlockCount;
            if (freeRenderBlocks.length > 0) {
                render = freeRenderBlocks.ptr[freeRenderBlocks.length - 1];
                freeRenderBlocks.length -= 1;
            } else {
                renderBlockCount += 1;
                chunks.ensure(cast(size_t) renderBlockCount * CORNER_COUNT);
            }
            renderBlocks.ptr[block] = render + 1;
        }
        return (renderBlocks.ptr[block] - 1) * CORNER_COUNT + corner;
    }

    void apply(ref const NearbyScratch nearby, MeshRecord record, const(Quad)[] meshed) {
        uint chunkIndex = renderIndexFor(record.block, record.slot.corner);
        if (renderBlockCount > nodeCapacity) {
            replaceNodes(cast(uint) grownCapacity(nodeCapacity, renderBlockCount));
            refreshDrawableNodes(nearby);
        }
        RenderChunk* entry = chunks.at(chunkIndex);
        if (entry.faceCount > 0) {
            allocator.release(entry.faceOffset, entry.faceCount);
        }
        entry.faceCount = cast(uint) meshed.length;
        entry.slot = record.slot.slot;
        meshedChunks += 1;
        if (meshed.length == 0) {
            removeDrawable(chunkIndex);
        } else {
            entry.faceOffset = allocateFaces(entry.faceCount);
            stage(meshed, entry.faceOffset);
            writeDrawable(chunkIndex, record.slot, placeNode(nearby, chunkIndex));
        }
    }

    void forget(const(Unloaded)[] unloaded) {
        foreach (released; unloaded) {
            if (released.block < renderBlocks.length && renderBlocks.ptr[released.block] != 0) {
                uint render = renderBlocks.ptr[released.block] - 1;
                foreach (corner; 0 .. CORNER_COUNT) {
                    uint chunkIndex = render * CORNER_COUNT + corner;
                    RenderChunk* entry = chunks.at(chunkIndex);
                    if (entry.faceCount > 0) {
                        allocator.release(entry.faceOffset, entry.faceCount);
                    }
                    removeDrawable(chunkIndex);
                    Flags!ChunkMark kept;
                    kept.put(ChunkMark.unlisted, entry.marks.has(ChunkMark.unlisted));
                    *entry = RenderChunk.init;
                    entry.marks = kept;
                }
                freeRenderBlocks.append(render);
                placedVersions.ptr[render] = NO_VERSION;
                renderBlocks.ptr[released.block] = 0;
            }
        }
    }

    uint allocateFaces(uint count) {
        uint offset = allocator.allocate(count);
        if (offset != NO_OFFSET) {
            return offset;
        } else {
            growFaces(count);
            return allocator.allocate(count);
        }
    }

    void writeDrawable(uint chunkIndex, ChunkSlot slot, uint node) {
        RenderChunk* entry = chunks.at(chunkIndex);
        if (!entry.marks.has(ChunkMark.drawable)) {
            if (drawableCount == drawableCapacity) {
                growDrawBuffers(drawableCapacity * 2);
            }
            entry.drawable = drawableCount;
            entry.marks.set(ChunkMark.drawable);
            drawableChunks.append(chunkIndex);
            drawableRecords.append(DrawableRecord.init);
        }
        setDrawable(entry.drawable, DrawableRecord(node, slot.corner, entry.faceOffset, entry.faceCount));
        noteNode(chunkIndex, node);
    }

    void removeDrawable(uint chunkIndex) {
        RenderChunk* entry = chunks.at(chunkIndex);
        if (entry.marks.has(ChunkMark.drawable)) {
            uint last = drawableCount - 1;
            uint movedChunk = drawableChunks.ptr[last];
            setDrawable(entry.drawable, drawableRecords.ptr[last]);
            drawableChunks.ptr[entry.drawable] = movedChunk;
            chunks.at(movedChunk).drawable = entry.drawable;
            drawableChunks.length = last;
            drawableRecords.length = last;
            entry.marks.clear(ChunkMark.drawable);
        }
    }

    void stage(const(Quad)[] meshed, uint deviceOffset) {
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
        batch.release();
        retired.release();
        uploads.release();
        growthCopies.release();
        drawableChunks.release();
        drawableRecords.release();
        placedVersions.release();
        unlisted.release();
        allocator.release();
        chunks.release();
        renderBlocks.release();
        freeRenderBlocks.release();
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
