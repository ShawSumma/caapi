module client.graphics.voxels.meshes;

import core.stdc.string : memcpy;
import bindings.platform : VK_ACCESS_SHADER_READ_BIT, VK_ACCESS_TRANSFER_READ_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, VK_BUFFER_USAGE_TRANSFER_DST_BIT, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_VERTEX_SHADER_BIT, VK_STRUCTURE_TYPE_MEMORY_BARRIER, VkBuffer, VkBufferCopy, VkBufferUsageFlags, VkCommandBuffer, VkDevice, VkDeviceSize, VkDrawIndirectCommand, VkMemoryBarrier, VkPhysicalDevice, vkCmdCopyBuffer, vkCmdPipelineBarrier;
import client.graphics.matrices : MATRIX_FLOATS, flatten;
import client.graphics.pipeline : GpuBuffer;
import client.meshing : Face, Mesher;
import common.allocator : Allocation, RangeAllocator;
import common.array : Array, grownCapacity;
import common.coords : CHUNK_DIRECTIONS;
import common.dodeca : VERTEX_COUNT, Vertex, chunkBoundingSphereCenter, chunkToNode;
import common.graph : Graph, NO_SLOT;
import common.neighbors : chunkNeighborSlot;
import common.node : Chunk, ChunkSlot, ChunkState;
import common.slab : Slab;
import common.traversal : NearbyNode, NearbyScratch;

enum uint INITIAL_FACE_CAPACITY = 2 ^^ 20;
enum uint INITIAL_STAGING_FACES = 2 ^^ 16;
enum uint INITIAL_DRAWABLE_CAPACITY = 2 ^^ 14;
enum uint INITIAL_NODE_CAPACITY = 2 ^^ 16;
enum uint NO_VERSION = uint.max;
enum uint POINT_FLOATS = 4;

struct ChunkVertex {
    float[MATRIX_FLOATS] chunkToNode;
    float[POINT_FLOATS] sphereCenter;
}

struct DrawableRecord {
    uint node;
    uint vertex;
    uint faceOffset;
    uint faceCount;
}

struct DrawTransform {
    float[MATRIX_FLOATS] transform;
    float[POINT_FLOATS] reversed;
}

struct RenderChunk {
    uint faceOffset;
    uint faceCount;
    uint drawable;
    bool hasDrawable;
}

struct MeshRecord {
    ChunkSlot slot;
    uint offset;
    uint count;
}

struct WorkerMeshes {
    Mesher mesher;
    Array!Face faces;
    Array!MeshRecord records;
}

struct MeshBatch {
    Array!WorkerMeshes workers;
    const(Graph)* graph;
}

void meshJob(void* context, size_t index, uint worker) {
    MeshBatch* batch = cast(MeshBatch*) context;
    const(Graph)* graph = batch.graph;
    ChunkSlot slot = graph.changedChunks.ptr[graph.changedHead + index];
    const(Chunk)* chunk = graph.chunkAt(slot);
    if (chunk.state == ChunkState.populated && !chunk.voxels.isSolid() && !(*graph).isFaceNeighborGenerating(slot)) {
        WorkerMeshes* output = &batch.workers.ptr[worker];
        const(Face)[] meshed = output.mesher.mesh(*graph, slot);
        output.records.append(MeshRecord(slot, cast(uint) output.faces.length, cast(uint) meshed.length));
        output.faces.appendAll(meshed);
    }
}

bool isNeighborGenerating(ref const Graph graph, ChunkSlot chunk, size_t direction) {
    ChunkSlot neighbor = graph.chunkNeighborSlot(chunk, CHUNK_DIRECTIONS[direction]);
    return neighbor.slot != NO_SLOT && graph.chunkAt(neighbor).state == ChunkState.generating;
}

bool isFaceNeighborGenerating(ref const Graph graph, ChunkSlot chunk) {
    size_t direction = 0;
    while (direction < CHUNK_DIRECTIONS.length && !graph.isNeighborGenerating(chunk, direction)) {
        direction += 1;
    }
    return direction < CHUNK_DIRECTIONS.length;
}

struct BufferCopy {
    VkBuffer source;
    VkBuffer destination;
    VkDeviceSize size;
}

struct ChunkMeshes {
    GpuBuffer faces;
    GpuBuffer staging;
    GpuBuffer vertices;
    GpuBuffer nodes;
    GpuBuffer drawables;
    GpuBuffer transforms;
    GpuBuffer commands;
    Slab!RenderChunk chunks;
    Array!uint drawableChunks;
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
    uint meshedChunks;
    ubyte dimension;
    bool hasReplacedFaces;
    bool hasReplacedDrawBuffers;

    void setup(VkPhysicalDevice physical, VkDevice logical, ubyte chunkDimension) {
        physicalDevice = physical;
        device = logical;
        dimension = chunkDimension;
        ChunkVertex[VERTEX_COUNT] table;
        foreach (vertexIndex; 0 .. VERTEX_COUNT) {
            Vertex vertex = cast(Vertex) vertexIndex;
            table[vertexIndex].chunkToNode = flatten(vertex.chunkToNode);
            table[vertexIndex].sphereCenter = vertex.chunkBoundingSphereCenter.vec.data;
        }
        vertices = GpuBuffer.makeFilled(physicalDevice, device, table[], VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
        faces = GpuBuffer.makeDeviceLocal(physicalDevice, device, cast(VkDeviceSize) INITIAL_FACE_CAPACITY * Face.sizeof, faceUsage());
        allocator.grow(INITIAL_FACE_CAPACITY);
        staging = GpuBuffer.makeMapped(physicalDevice, device, cast(VkDeviceSize) INITIAL_STAGING_FACES * Face.sizeof, VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
        stagingCapacity = INITIAL_STAGING_FACES;
        growDrawBuffers(INITIAL_DRAWABLE_CAPACITY);
        nodes = grownMapped(nodes, cast(VkDeviceSize) INITIAL_NODE_CAPACITY * MATRIX_FLOATS * float.sizeof, 0);
        nodeCapacity = INITIAL_NODE_CAPACITY;
    }

    uint drawableCount() const {
        return cast(uint) drawableChunks.length;
    }

    GpuBuffer grownMapped(GpuBuffer old, VkDeviceSize size, size_t preservedBytes) {
        GpuBuffer larger = GpuBuffer.makeMapped(physicalDevice, device, size, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
        memcpy(larger.mapped, old.mapped, preservedBytes);
        retired.append(old);
        hasReplacedDrawBuffers = true;
        return larger;
    }

    void growDrawBuffers(uint capacity) {
        drawables = grownMapped(drawables, cast(VkDeviceSize) capacity * DrawableRecord.sizeof, drawableCount * DrawableRecord.sizeof);
        retired.append(transforms);
        retired.append(commands);
        transforms = GpuBuffer.makeDeviceLocal(physicalDevice, device, cast(VkDeviceSize) capacity * DrawTransform.sizeof, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
        commands = GpuBuffer.makeDeviceLocal(physicalDevice, device, cast(VkDeviceSize) capacity * VkDrawIndirectCommand.sizeof, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT);
        drawableCapacity = capacity;
    }

    void forgetWorld() {
        chunks.release();
        drawableChunks.clear();
        allocator.release();
        allocator.grow(cast(uint)(faces.size / Face.sizeof));
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
        hasReplacedFaces = false;
        hasReplacedDrawBuffers = false;
    }

    void list(ref const NearbyScratch nearby, uint nearbyVersion) {
        if (nearbyVersion != listedVersion) {
            listedVersion = nearbyVersion;
            listedNodes = 0;
        }
        if (nearby.nodes.length > listedNodes) {
            writeNodes(nearby.nodes.slice());
            refreshDrawableNodes(nearby);
        }
    }

    void writeNodes(const(NearbyNode)[] listed) {
        if (listed.length > nodeCapacity) {
            uint capacity = cast(uint) grownCapacity(nodeCapacity, listed.length);
            nodes = grownMapped(nodes, cast(VkDeviceSize) capacity * MATRIX_FLOATS * float.sizeof, listedNodes * MATRIX_FLOATS * float.sizeof);
            nodeCapacity = capacity;
        }
        float[MATRIX_FLOATS]* nodeMatrices = cast(float[MATRIX_FLOATS]*) nodes.mapped;
        foreach (index; listedNodes .. listed.length) {
            nodeMatrices[index] = flatten(listed[index].transform.mat);
        }
        listedNodes = cast(uint) listed.length;
    }

    void refreshDrawableNodes(ref const NearbyScratch nearby) {
        DrawableRecord* records = cast(DrawableRecord*) drawables.mapped;
        foreach (drawable, chunkIndex; drawableChunks.slice()) {
            records[drawable].node = nearby.indexOf(chunkIndex / VERTEX_COUNT);
        }
    }

    void prepareBatch(ref const Graph graph, uint workers) {
        batch.graph = &graph;
        while (batch.workers.length < workers) {
            batch.workers.append(WorkerMeshes.init);
            batch.workers.ptr[batch.workers.length - 1].mesher.setup(dimension);
        }
        foreach (i; 0 .. batch.workers.length) {
            batch.workers.ptr[i].faces.clear();
            batch.workers.ptr[i].records.clear();
        }
    }

    void applyBatch(ref const NearbyScratch nearby) {
        foreach (worker; batch.workers.slice()) {
            foreach (record; worker.records.slice()) {
                apply(nearby, record.slot, worker.faces.ptr[record.offset .. record.offset + record.count]);
            }
        }
    }

    void apply(ref const NearbyScratch nearby, ChunkSlot slot, const(Face)[] meshed) {
        uint chunkIndex = slot.slot * VERTEX_COUNT + slot.vertex;
        RenderChunk* entry = chunks.touch(chunkIndex);
        if (entry.faceCount > 0) {
            allocator.release(entry.faceOffset, entry.faceCount);
        }
        entry.faceCount = cast(uint) meshed.length;
        meshedChunks += 1;
        if (meshed.length == 0) {
            removeDrawable(chunkIndex);
        } else {
            entry.faceOffset = allocateFaces(entry.faceCount);
            stage(meshed, entry.faceOffset);
            writeDrawable(chunkIndex, slot, nearby.indexOf(slot.slot));
        }
    }

    void forget(const(uint)[] slots) {
        foreach (slot; slots) {
            foreach (vertex; 0 .. VERTEX_COUNT) {
                uint chunkIndex = slot * VERTEX_COUNT + vertex;
                RenderChunk* entry = chunks.touch(chunkIndex);
                if (entry.faceCount > 0) {
                    allocator.release(entry.faceOffset, entry.faceCount);
                }
                removeDrawable(chunkIndex);
                *entry = RenderChunk.init;
            }
        }
    }

    uint allocateFaces(uint count) {
        immutable Allocation allocation = allocator.allocate(count);
        if (allocation.isFound) {
            return allocation.offset;
        } else {
            growFaces(count);
            return allocator.allocate(count).offset;
        }
    }

    void writeDrawable(uint chunkIndex, ChunkSlot slot, uint node) {
        RenderChunk* entry = chunks.at(chunkIndex);
        if (!entry.hasDrawable) {
            if (drawableCount == drawableCapacity) {
                growDrawBuffers(drawableCapacity * 2);
            }
            entry.drawable = drawableCount;
            entry.hasDrawable = true;
            drawableChunks.append(chunkIndex);
        }
        DrawableRecord* records = cast(DrawableRecord*) drawables.mapped;
        records[entry.drawable] = DrawableRecord(node, slot.vertex, entry.faceOffset, entry.faceCount);
    }

    void removeDrawable(uint chunkIndex) {
        RenderChunk* entry = chunks.at(chunkIndex);
        if (entry.hasDrawable) {
            DrawableRecord* records = cast(DrawableRecord*) drawables.mapped;
            uint last = drawableCount - 1;
            uint movedChunk = drawableChunks.ptr[last];
            records[entry.drawable] = records[last];
            drawableChunks.ptr[entry.drawable] = movedChunk;
            chunks.at(movedChunk).drawable = entry.drawable;
            drawableChunks.length = last;
            entry.hasDrawable = false;
        }
    }

    void stage(const(Face)[] meshed, uint deviceOffset) {
        uint needed = stagedFaces + cast(uint) meshed.length;
        if (needed > stagingCapacity) {
            uint capacity = cast(uint) grownCapacity(stagingCapacity, needed);
            GpuBuffer larger = GpuBuffer.makeMapped(physicalDevice, device, cast(VkDeviceSize) capacity * Face.sizeof, VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
            memcpy(larger.mapped, staging.mapped, stagedFaces * Face.sizeof);
            retired.append(staging);
            staging = larger;
            stagingCapacity = capacity;
        }
        memcpy(cast(Face*) staging.mapped + stagedFaces, meshed.ptr, meshed.length * Face.sizeof);
        uploads.append(VkBufferCopy(cast(VkDeviceSize) stagedFaces * Face.sizeof, cast(VkDeviceSize) deviceOffset * Face.sizeof, meshed.length * Face.sizeof));
        stagedFaces = needed;
    }

    void growFaces(uint needed) {
        uint capacity = cast(uint) grownCapacity(allocator.capacity, allocator.capacity + needed);
        GpuBuffer larger = GpuBuffer.makeDeviceLocal(physicalDevice, device, cast(VkDeviceSize) capacity * Face.sizeof, faceUsage());
        growthCopies.append(BufferCopy(faces.buffer, larger.buffer, cast(VkDeviceSize) allocator.capacity * Face.sizeof));
        retired.append(faces);
        faces = larger;
        allocator.grow(capacity);
        hasReplacedFaces = true;
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
        vertices.destroy(device);
        nodes.destroy(device);
        drawables.destroy(device);
        transforms.destroy(device);
        commands.destroy(device);
        foreach (i; 0 .. batch.workers.length) {
            batch.workers.ptr[i].mesher.release();
            batch.workers.ptr[i].faces.release();
            batch.workers.ptr[i].records.release();
        }
        batch.workers.release();
        retired.release();
        uploads.release();
        growthCopies.release();
        drawableChunks.release();
        allocator.release();
        chunks.release();
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
