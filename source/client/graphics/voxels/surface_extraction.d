module client.graphics.voxels.surface_extraction;

import core.stdc.stdlib : free, malloc;
import core.stdc.string : memcpy;
import bindings.platform : VK_ACCESS_INDIRECT_COMMAND_READ_BIT, VK_ACCESS_SHADER_READ_BIT, VK_ACCESS_SHADER_WRITE_BIT, VK_ACCESS_TRANSFER_READ_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, VK_BUFFER_USAGE_TRANSFER_DST_BIT, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, VK_PIPELINE_BIND_POINT_COMPUTE, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_VERTEX_SHADER_BIT, VK_SHADER_STAGE_COMPUTE_BIT, VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, VkBuffer, VkBufferCopy, VkBufferMemoryBarrier, VkCommandBuffer, VkDescriptorBufferInfo, VkDescriptorPool, VkDescriptorPoolCreateInfo, VkDescriptorPoolSize, VkDescriptorSet, VkDescriptorSetAllocateInfo, VkDescriptorSetLayout, VkDescriptorSetLayoutBinding, VkDevice, VkDeviceSize, VkPhysicalDevice, VkPipeline, VkPipelineLayout, VkPushConstantRange, VkShaderModule, VkWriteDescriptorSet, vkAllocateDescriptorSets, vkCmdBindDescriptorSets, vkCmdBindPipeline, vkCmdCopyBuffer, vkCmdDispatch, vkCmdFillBuffer, vkCmdPipelineBarrier, vkCmdPushConstants, vkCreateDescriptorPool, vkDestroyDescriptorPool, vkDestroyDescriptorSetLayout, vkDestroyPipeline, vkDestroyPipelineLayout, vkDestroyShaderModule, vkMapMemory, vkUnmapMemory, vkUpdateDescriptorSets;
import client.graphics.pipeline : GpuBuffer, WHOLE_SIZE, bufferBarrier, bufferWrite, createComputePipeline, createFilledBuffer, createHostVisibleBuffer, createPipelineLayout, createSetLayout, createShader, createZeroedBuffer, destroyBuffer, layoutBinding;
import common.dodeca : VERTEX_COUNT, Vertex, vertexChunkToNode;
import common.math : Matrix4;

enum string EXTRACT_COMP_SPV = import("extract.comp.spv");
enum string TRANSFORMS_COMP_SPV = import("transforms.comp.spv");
enum uint EXTRACT_CONCURRENCY = 128;
enum uint MAX_RENDER_SLOTS = 1 << 16;
enum uint FACE_SIZE = 8;
enum uint INDIRECT_SIZE = 16;
enum uint BUFFER_ALIGNMENT = 16;
enum uint EXTRACT_STATE_BYTES = 4;
enum uint EXTRACT_BINDINGS = 4;
enum uint EXTRACT_WORKGROUP = 4;
enum uint FACE_AXES = 3;
enum uint VERTICES_PER_FACE = 6;
enum uint TRANSFORM_WORKGROUP = 64;
enum uint TRANSFORM_BINDINGS = 4;
enum uint TRANSFORM_OUTPUT_BINDING = 3;
enum uint MATRIX_FLOATS = 16;
enum uint MATRIX_BYTES = 64;
enum uint SLOT_TASK_BYTES = 16;
enum uint COUNT_PUSH_BYTES = 4;
enum uint INDIRECT_VERTEX_COUNT_OFFSET = 0;
enum uint INDIRECT_INSTANCE_COUNT_OFFSET = 4;
enum uint INDIRECT_FIRST_VERTEX_OFFSET = 8;
enum uint INDIRECT_FIRST_INSTANCE_OFFSET = 12;
enum uint INDIRECT_FIELD_BYTES = 4;

struct ExtractTask {
    ulong indirectOffset;
    ulong faceOffset;
    uint index;
    uint drawId;
}

uint roundUp(uint value, uint alignment) {
    return (value + alignment - 1) / alignment * alignment;
}

uint paddedVoxelCount(uint dimension) {
    return (dimension + 2) * (dimension + 2) * (dimension + 2);
}

uint packPaddedVoxels(const(ushort)[] padded, uint dimension, uint* output) {
    uint paddedSize = paddedVoxelCount(dimension);
    uint pairCount = 0;
    if (padded.length >= paddedSize) {
        pairCount = (paddedSize + 1) / 2;
        foreach (pair; 0 .. paddedSize / 2) {
            output[pair] = padded[pair * 2] | (cast(uint) padded[pair * 2 + 1] << 16);
        }
        if (paddedSize % 2 == 1) {
            output[paddedSize / 2] = padded[paddedSize - 1];
        }
    }
    return pairCount;
}

struct SurfaceExtraction {
    VkDescriptorSet[EXTRACT_CONCURRENCY] dataSets;
    GpuBuffer paramsBuffer;
    GpuBuffer voxelsBuffer;
    GpuBuffer stateBuffer;
    GpuBuffer indirectBuffer;
    GpuBuffer packedIndirectBuffer;
    GpuBuffer facesBuffer;
    GpuBuffer nodeTransformsBuffer;
    GpuBuffer vertexTransformsBuffer;
    GpuBuffer slotTasksBuffer;
    VkBufferCopy* packCopies;
    uint* packScratch;
    void* nodeTransformsMapped;
    void* slotTasksMapped;
    VkShaderModule extractShader;
    VkDescriptorSetLayout paramsLayout;
    VkDescriptorSetLayout dataLayout;
    VkPipelineLayout pipelineLayout;
    VkPipeline pipeline;
    VkDescriptorPool descriptorPool;
    VkDescriptorSet paramsSet;
    VkShaderModule transformShader;
    VkDescriptorSetLayout transformLayout;
    VkPipelineLayout transformPipelineLayout;
    VkPipeline transformPipeline;
    VkDescriptorPool transformPool;
    VkDescriptorSet transformSet;
    uint dimension;
    uint voxelUnit;
    uint stateUnit;
    uint faceUnit;

    bool setup(VkPhysicalDevice physicalDevice, VkDevice device, uint chunkDimension) {
        dimension = chunkDimension;
        uint maxFaces = FACE_AXES * (dimension * dimension * dimension + dimension * dimension);
        voxelUnit = roundUp(paddedVoxelCount(dimension) * cast(uint) ushort.sizeof, BUFFER_ALIGNMENT);
        stateUnit = roundUp(EXTRACT_STATE_BYTES, BUFFER_ALIGNMENT);
        faceUnit = roundUp(maxFaces * FACE_SIZE, BUFFER_ALIGNMENT);
        packScratch = cast(uint*) malloc((paddedVoxelCount(dimension) + 1) / 2 * uint.sizeof);
        packCopies = cast(VkBufferCopy*) malloc(MAX_RENDER_SLOTS * VkBufferCopy.sizeof);
        createExtractBuffers(physicalDevice, device);
        bool ok = createExtractPipeline(device);
        if (ok) {
            ok = createTransformCompute(physicalDevice, device);
        }
        return ok;
    }

    void createExtractBuffers(VkPhysicalDevice physicalDevice, VkDevice device) {
        int[4] dimensionData = [
            cast(int) dimension,
            0,
            0,
            0,
        ];
        paramsBuffer = createFilledBuffer(physicalDevice, device, dimensionData[], VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
        voxelsBuffer = createZeroedBuffer(physicalDevice, device, cast(VkDeviceSize) voxelUnit * EXTRACT_CONCURRENCY, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
        stateBuffer = createZeroedBuffer(physicalDevice, device, cast(VkDeviceSize) stateUnit * EXTRACT_CONCURRENCY, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT);
        indirectBuffer = createZeroedBuffer(physicalDevice, device, cast(VkDeviceSize) INDIRECT_SIZE * MAX_RENDER_SLOTS, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
        packedIndirectBuffer = createZeroedBuffer(physicalDevice, device, cast(VkDeviceSize) INDIRECT_SIZE * MAX_RENDER_SLOTS, VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT);
        facesBuffer = createHostVisibleBuffer(physicalDevice, device, cast(VkDeviceSize) faceUnit * MAX_RENDER_SLOTS, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
    }

    bool createExtractPipeline(VkDevice device) {
        extractShader = createShader(device, EXTRACT_COMP_SPV);
        VkDescriptorSetLayoutBinding[1] paramsBindings = [
            layoutBinding(0, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT),
        ];
        paramsLayout = createSetLayout(device, paramsBindings[]);
        VkDescriptorSetLayoutBinding[EXTRACT_BINDINGS] dataBindings;
        foreach (i; 0 .. EXTRACT_BINDINGS) {
            dataBindings[i] = layoutBinding(i, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT);
        }
        dataLayout = createSetLayout(device, dataBindings[]);
        VkDescriptorPoolSize[2] sizes = [
            VkDescriptorPoolSize(VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1),
            VkDescriptorPoolSize(VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, EXTRACT_BINDINGS * EXTRACT_CONCURRENCY),
        ];
        VkDescriptorPoolCreateInfo poolInfo;
        poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        poolInfo.maxSets = 1 + EXTRACT_CONCURRENCY;
        poolInfo.poolSizeCount = sizes.length;
        poolInfo.pPoolSizes = sizes.ptr;
        vkCreateDescriptorPool(device, &poolInfo, null, &descriptorPool);
        VkDescriptorSetAllocateInfo paramsAllocate;
        paramsAllocate.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        paramsAllocate.descriptorPool = descriptorPool;
        paramsAllocate.descriptorSetCount = 1;
        paramsAllocate.pSetLayouts = &paramsLayout;
        vkAllocateDescriptorSets(device, &paramsAllocate, &paramsSet);
        VkDescriptorSetLayout[EXTRACT_CONCURRENCY] dataLayouts = dataLayout;
        VkDescriptorSetAllocateInfo dataAllocate;
        dataAllocate.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        dataAllocate.descriptorPool = descriptorPool;
        dataAllocate.descriptorSetCount = EXTRACT_CONCURRENCY;
        dataAllocate.pSetLayouts = dataLayouts.ptr;
        vkAllocateDescriptorSets(device, &dataAllocate, dataSets.ptr);
        VkDescriptorBufferInfo paramsInfo = VkDescriptorBufferInfo(paramsBuffer.buffer, 0, WHOLE_SIZE);
        VkWriteDescriptorSet paramsWrite = bufferWrite(paramsSet, 0, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, &paramsInfo);
        vkUpdateDescriptorSets(device, 1, &paramsWrite, 0, null);
        VkDescriptorSetLayout[2] setLayouts = [
            paramsLayout,
            dataLayout,
        ];
        pipelineLayout = createPipelineLayout(device, setLayouts[], null);
        if (extractShader !is null && pipelineLayout !is null) {
            pipeline = createComputePipeline(device, extractShader, pipelineLayout);
        }
        return pipeline !is null;
    }

    bool createTransformCompute(VkPhysicalDevice physicalDevice, VkDevice device) {
        transformShader = createShader(device, TRANSFORMS_COMP_SPV);
        VkDescriptorSetLayoutBinding[TRANSFORM_BINDINGS] bindings;
        foreach (i; 0 .. TRANSFORM_BINDINGS) {
            bindings[i] = layoutBinding(i, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT);
        }
        transformLayout = createSetLayout(device, bindings[]);
        VkDescriptorSetLayout[1] setLayouts = [
            transformLayout,
        ];
        VkPushConstantRange[1] pushConstants = [
            VkPushConstantRange(VK_SHADER_STAGE_COMPUTE_BIT, 0, COUNT_PUSH_BYTES),
        ];
        transformPipelineLayout = createPipelineLayout(device, setLayouts[], pushConstants[]);
        if (transformShader !is null && transformPipelineLayout !is null) {
            transformPipeline = createComputePipeline(device, transformShader, transformPipelineLayout);
        }
        VkDescriptorPoolSize poolSize = VkDescriptorPoolSize(VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, TRANSFORM_BINDINGS);
        VkDescriptorPoolCreateInfo poolInfo;
        poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        poolInfo.maxSets = 1;
        poolInfo.poolSizeCount = 1;
        poolInfo.pPoolSizes = &poolSize;
        vkCreateDescriptorPool(device, &poolInfo, null, &transformPool);
        VkDescriptorSetAllocateInfo allocateInfo;
        allocateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        allocateInfo.descriptorPool = transformPool;
        allocateInfo.descriptorSetCount = 1;
        allocateInfo.pSetLayouts = &transformLayout;
        vkAllocateDescriptorSets(device, &allocateInfo, &transformSet);
        nodeTransformsBuffer = createHostVisibleBuffer(physicalDevice, device, cast(VkDeviceSize) MAX_RENDER_SLOTS * MATRIX_BYTES, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
        vkMapMemory(device, nodeTransformsBuffer.memory, 0, nodeTransformsBuffer.size, 0, &nodeTransformsMapped);
        slotTasksBuffer = createHostVisibleBuffer(physicalDevice, device, cast(VkDeviceSize) MAX_RENDER_SLOTS * SLOT_TASK_BYTES, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
        vkMapMemory(device, slotTasksBuffer.memory, 0, slotTasksBuffer.size, 0, &slotTasksMapped);
        float[VERTEX_COUNT * MATRIX_FLOATS] vertexTransforms;
        foreach (vertexIndex; 0 .. VERTEX_COUNT) {
            Matrix4!float chunkToNode = vertexChunkToNode(cast(Vertex) vertexIndex);
            foreach (column; 0 .. 4) {
                foreach (row; 0 .. 4) {
                    vertexTransforms[vertexIndex * MATRIX_FLOATS + column * 4 + row] = chunkToNode.data[column][row];
                }
            }
        }
        vertexTransformsBuffer = createFilledBuffer(physicalDevice, device, vertexTransforms[], VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
        VkDescriptorBufferInfo[3] infos = [
            VkDescriptorBufferInfo(nodeTransformsBuffer.buffer, 0, WHOLE_SIZE),
            VkDescriptorBufferInfo(vertexTransformsBuffer.buffer, 0, WHOLE_SIZE),
            VkDescriptorBufferInfo(slotTasksBuffer.buffer, 0, WHOLE_SIZE),
        ];
        VkWriteDescriptorSet[3] writes;
        foreach (i; 0 .. infos.length) {
            writes[i] = bufferWrite(transformSet, cast(uint) i, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, &infos[i]);
        }
        vkUpdateDescriptorSets(device, writes.length, writes.ptr, 0, null);
        return transformPipeline !is null;
    }

    void bindTransformOutput(VkDevice device, VkBuffer transformsBuffer) {
        VkDescriptorBufferInfo info = VkDescriptorBufferInfo(transformsBuffer, 0, WHOLE_SIZE);
        VkWriteDescriptorSet write = bufferWrite(transformSet, TRANSFORM_OUTPUT_BINDING, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, &info);
        vkUpdateDescriptorSets(device, 1, &write, 0, null);
    }

    void recordTransformCompute(VkCommandBuffer commands, uint activeCount, VkBuffer transformsBuffer) {
        vkCmdBindPipeline(commands, VK_PIPELINE_BIND_POINT_COMPUTE, transformPipeline);
        vkCmdBindDescriptorSets(commands, VK_PIPELINE_BIND_POINT_COMPUTE, transformPipelineLayout, 0, 1, &transformSet, 0, null);
        vkCmdPushConstants(commands, transformPipelineLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, COUNT_PUSH_BYTES, &activeCount);
        vkCmdDispatch(commands, (activeCount + TRANSFORM_WORKGROUP - 1) / TRANSFORM_WORKGROUP, 1, 1);
        VkBufferMemoryBarrier barrier = bufferBarrier(transformsBuffer, VK_ACCESS_SHADER_WRITE_BIT, VK_ACCESS_SHADER_READ_BIT);
        vkCmdPipelineBarrier(commands, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_VERTEX_SHADER_BIT, 0, 0, null, 1, &barrier, 0, null);
    }

    void uploadVoxels(void* voxelsMapped, uint scratchIndex, const(ushort)[] paddedData) {
        ulong size = cast(ulong) packPaddedVoxels(paddedData, dimension, packScratch) * uint.sizeof;
        if (size > voxelUnit) {
            size = voxelUnit;
        }
        memcpy(cast(ubyte*) voxelsMapped + cast(ulong) scratchIndex * voxelUnit, packScratch, size);
    }

    void* mapVoxels(VkDevice device) {
        void* mapped;
        vkMapMemory(device, voxelsBuffer.memory, 0, voxelsBuffer.size, 0, &mapped);
        return mapped;
    }

    void unmapVoxels(VkDevice device) {
        vkUnmapMemory(device, voxelsBuffer.memory);
    }

    void recordExtract(VkDevice device, VkCommandBuffer commands, const(ExtractTask)[] tasks) {
        vkCmdFillBuffer(commands, stateBuffer.buffer, 0, stateBuffer.size, 0);
        foreach (task; tasks) {
            VkDescriptorBufferInfo[EXTRACT_BINDINGS] infos = [
                VkDescriptorBufferInfo(voxelsBuffer.buffer, cast(ulong) task.index * voxelUnit, voxelUnit),
                VkDescriptorBufferInfo(stateBuffer.buffer, cast(ulong) task.index * stateUnit, stateUnit),
                VkDescriptorBufferInfo(indirectBuffer.buffer, task.indirectOffset, INDIRECT_SIZE),
                VkDescriptorBufferInfo(facesBuffer.buffer, task.faceOffset, faceUnit),
            ];
            VkWriteDescriptorSet[EXTRACT_BINDINGS] writes;
            foreach (i; 0 .. EXTRACT_BINDINGS) {
                writes[i] = bufferWrite(dataSets[task.index], i, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, &infos[i]);
            }
            vkUpdateDescriptorSets(device, EXTRACT_BINDINGS, writes.ptr, 0, null);
            uint firstVertex = cast(uint)(task.faceOffset / FACE_SIZE) * VERTICES_PER_FACE;
            vkCmdFillBuffer(commands, indirectBuffer.buffer, task.indirectOffset + INDIRECT_VERTEX_COUNT_OFFSET, INDIRECT_FIELD_BYTES, 0);
            vkCmdFillBuffer(commands, indirectBuffer.buffer, task.indirectOffset + INDIRECT_INSTANCE_COUNT_OFFSET, INDIRECT_FIELD_BYTES, 1);
            vkCmdFillBuffer(commands, indirectBuffer.buffer, task.indirectOffset + INDIRECT_FIRST_VERTEX_OFFSET, INDIRECT_FIELD_BYTES, firstVertex);
            vkCmdFillBuffer(commands, indirectBuffer.buffer, task.indirectOffset + INDIRECT_FIRST_INSTANCE_OFFSET, INDIRECT_FIELD_BYTES, task.drawId);
        }
        VkBufferMemoryBarrier[2] before = [
            bufferBarrier(stateBuffer.buffer, VK_ACCESS_TRANSFER_WRITE_BIT, VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT),
            bufferBarrier(indirectBuffer.buffer, VK_ACCESS_TRANSFER_WRITE_BIT, VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT),
        ];
        vkCmdPipelineBarrier(commands, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, null, before.length, before.ptr, 0, null);
        vkCmdBindPipeline(commands, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
        vkCmdBindDescriptorSets(commands, VK_PIPELINE_BIND_POINT_COMPUTE, pipelineLayout, 0, 1, &paramsSet, 0, null);
        uint groupsX = ((dimension + 1) * FACE_AXES + EXTRACT_WORKGROUP - 1) / EXTRACT_WORKGROUP;
        uint groupsYZ = (dimension + 1 + EXTRACT_WORKGROUP - 1) / EXTRACT_WORKGROUP;
        foreach (task; tasks) {
            vkCmdBindDescriptorSets(commands, VK_PIPELINE_BIND_POINT_COMPUTE, pipelineLayout, 1, 1, &dataSets[task.index], 0, null);
            vkCmdDispatch(commands, groupsX, groupsYZ, groupsYZ);
        }
        VkBufferMemoryBarrier[2] after = [
            bufferBarrier(facesBuffer.buffer, VK_ACCESS_SHADER_WRITE_BIT, VK_ACCESS_SHADER_READ_BIT),
            bufferBarrier(indirectBuffer.buffer, VK_ACCESS_SHADER_WRITE_BIT, VK_ACCESS_TRANSFER_READ_BIT),
        ];
        vkCmdPipelineBarrier(commands, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_VERTEX_SHADER_BIT | VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, after.length, after.ptr, 0, null);
    }

    void recordPackIndirect(VkCommandBuffer commands, const(uint)[] activeSlots) {
        foreach (i, slot; activeSlots) {
            packCopies[i] = VkBufferCopy(cast(VkDeviceSize) slot * INDIRECT_SIZE, cast(VkDeviceSize) i * INDIRECT_SIZE, INDIRECT_SIZE);
        }
        vkCmdCopyBuffer(commands, indirectBuffer.buffer, packedIndirectBuffer.buffer, cast(uint) activeSlots.length, packCopies);
        VkBufferMemoryBarrier barrier = bufferBarrier(packedIndirectBuffer.buffer, VK_ACCESS_TRANSFER_WRITE_BIT, VK_ACCESS_INDIRECT_COMMAND_READ_BIT);
        vkCmdPipelineBarrier(commands, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT, 0, 0, null, 1, &barrier, 0, null);
    }

    ulong faceOffset(uint slot) const {
        return cast(ulong) slot * faceUnit;
    }

    ulong indirectOffset(uint slot) const {
        return cast(ulong) slot * INDIRECT_SIZE;
    }

    void cleanup(VkDevice device) {
        vkDestroyPipeline(device, pipeline, null);
        vkDestroyPipelineLayout(device, pipelineLayout, null);
        vkDestroyDescriptorPool(device, descriptorPool, null);
        vkDestroyDescriptorSetLayout(device, paramsLayout, null);
        vkDestroyDescriptorSetLayout(device, dataLayout, null);
        vkDestroyShaderModule(device, extractShader, null);
        vkDestroyPipeline(device, transformPipeline, null);
        vkDestroyPipelineLayout(device, transformPipelineLayout, null);
        vkDestroyDescriptorPool(device, transformPool, null);
        vkDestroyDescriptorSetLayout(device, transformLayout, null);
        vkDestroyShaderModule(device, transformShader, null);
        destroyBuffer(device, &paramsBuffer);
        destroyBuffer(device, &voxelsBuffer);
        destroyBuffer(device, &stateBuffer);
        destroyBuffer(device, &indirectBuffer);
        destroyBuffer(device, &packedIndirectBuffer);
        destroyBuffer(device, &facesBuffer);
        destroyBuffer(device, &nodeTransformsBuffer);
        destroyBuffer(device, &vertexTransformsBuffer);
        destroyBuffer(device, &slotTasksBuffer);
        free(packScratch);
        free(packCopies);
    }
}
