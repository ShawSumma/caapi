module client.graphics.voxels.surface_extraction;

import core.stdc.stdio : printf;
import core.stdc.string : memcpy;
import common.array : allocSlice, freeSlice;
import bindings.vk;
import client.graphics.pipeline : GpuBuffer;
import common.dodeca : Vertex, vertexChunkToNode;
import common.math : Matrix4;

enum uint FACE_SIZE = 8;
enum uint INDIRECT_SIZE = 16;

uint roundUp(uint value, uint alignment) {
    return (value + alignment - 1) / alignment * alignment;
}

uint packPaddedVoxelsInto(const(ushort)[] padded, uint dim, uint[] outBuf) {
    uint paddedSize = (dim + 2) * (dim + 2) * (dim + 2);
    if (padded.length < paddedSize) {
        return 0;
    }
    uint pairCount = (paddedSize + 1) / 2;
    for (uint i = 0; i + 1 < paddedSize; i += 2) {
        outBuf[i / 2] = padded[i] | (cast(uint) padded[i + 1] << 16);
    }
    if (paddedSize % 2 == 1) {
        outBuf[paddedSize / 2] = padded[paddedSize - 1];
    }
    return pairCount;
}

struct ExtractTask {
    ulong indirectOffset;
    ulong faceOffset;
    uint index;
    uint drawId;
}

struct SurfaceExtraction {
    VkShaderModule compShader;
    VkDescriptorSetLayout paramsLayout;
    VkDescriptorSetLayout dataLayout;
    VkPipelineLayout pipelineLayout;
    VkPipeline pipeline;
    VkDescriptorPool descPool;
    VkDescriptorSet paramsSet;
    VkDescriptorSet[] dataSets;

    GpuBuffer paramsBuf;
    GpuBuffer voxelsBuf;
    GpuBuffer stateBuf;

    GpuBuffer indirectBuf;
    GpuBuffer packedIndirectBuf;
    GpuBuffer facesBuf;

    uint dimension;
    uint concurrency;
    uint maxSlots;
    uint voxelBufUnit;
    uint stateBufUnit;
    uint faceBufUnit;
    uint maxFaces;
    uint[] packBuf;

    VkShaderModule tfCompShader;
    VkDescriptorSetLayout tfLayout;
    VkPipelineLayout tfPipelineLayout;
    VkPipeline tfPipeline;
    VkDescriptorPool tfDescPool;
    VkDescriptorSet tfDescSet;
    GpuBuffer nodeTransformsBuf;
    GpuBuffer vertexTransformsBuf;
    GpuBuffer slotTasksBuf;
    void* nodeTransformsMapped;
    void* slotTasksMapped;
    bool tfReady;
    uint maxNodes;

    VkBufferCopy[] packIndirectCopies;

    bool init(VkPhysicalDevice phys, VkDevice device, uint dim, uint conc, uint slots) {
        dimension = dim;
        concurrency = conc;
        maxSlots = slots;
        maxFaces = 3 * (dim * dim * dim + dim * dim);
        voxelBufUnit = roundUp(cast(uint)((dim + 2) * (dim + 2) * (dim + 2)) * 2, 16);
        stateBufUnit = roundUp(4, 16);
        faceBufUnit = roundUp(maxFaces * FACE_SIZE, 16);

        static immutable ubyte[] compSpv = cast(immutable(ubyte)[]) import("extract.comp.spv");
        VkShaderModuleCreateInfo smci;
        smci.sType = VkStructureType.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
        smci.codeSize = compSpv.length;
        smci.pCode = cast(const(uint)*) compSpv.ptr;
        if (vkCreateShaderModule(device, &smci, null, &compShader) != VkResult.VK_SUCCESS) {
            return false;
        }

        VkDescriptorSetLayoutBinding pb;
        pb.binding = 0;
        pb.descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        pb.descriptorCount = 1;
        pb.stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT;
        VkDescriptorSetLayoutCreateInfo pci;
        pci.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
        pci.bindingCount = 1;
        pci.pBindings = &pb;
        vkCreateDescriptorSetLayout(device, &pci, null, &paramsLayout);

        VkDescriptorSetLayoutBinding[4] db;
        foreach (i; 0 .. 4) {
            db[i].binding = cast(uint) i;
            db[i].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
            db[i].descriptorCount = 1;
            db[i].stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT;
        }
        VkDescriptorSetLayoutCreateInfo dci;
        dci.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
        dci.bindingCount = 4;
        dci.pBindings = db.ptr;
        vkCreateDescriptorSetLayout(device, &dci, null, &dataLayout);

        VkDescriptorPoolSize[2] sizes;
        sizes[0].type = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        sizes[0].descriptorCount = 1;
        sizes[1].type = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        sizes[1].descriptorCount = 4 * concurrency;
        VkDescriptorPoolCreateInfo dpci;
        dpci.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        dpci.maxSets = 1 + concurrency;
        dpci.poolSizeCount = 2;
        dpci.pPoolSizes = sizes.ptr;
        vkCreateDescriptorPool(device, &dpci, null, &descPool);

        VkDescriptorSetAllocateInfo pai;
        pai.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        pai.descriptorPool = descPool;
        pai.descriptorSetCount = 1;
        pai.pSetLayouts = &paramsLayout;
        vkAllocateDescriptorSets(device, &pai, &paramsSet);

        VkDescriptorSetLayout[] dataLayouts = allocSlice!VkDescriptorSetLayout(concurrency);
        scope(exit) {
            freeSlice(dataLayouts);
        }
        dataLayouts[] = dataLayout;
        dataSets = allocSlice!VkDescriptorSet(concurrency);
        VkDescriptorSetAllocateInfo dai;
        dai.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        dai.descriptorPool = descPool;
        dai.descriptorSetCount = concurrency;
        dai.pSetLayouts = dataLayouts.ptr;
        vkAllocateDescriptorSets(device, &dai, dataSets.ptr);

        int[4] dimData = [cast(int) dim, 0, 0, 0];
        paramsBuf = GpuBuffer.create(phys, device, cast(void[]) dimData[],
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);

        uint voxelsSize = voxelBufUnit * concurrency;
        voxelsBuf = GpuBuffer.createZeroed(phys, device, voxelsSize,
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);

        uint stateSize = stateBufUnit * concurrency;
        stateBuf = GpuBuffer.createZeroed(phys, device, stateSize,
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_TRANSFER_DST_BIT);

        indirectBuf = GpuBuffer.createZeroed(phys, device, INDIRECT_SIZE * maxSlots,
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT |
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_TRANSFER_SRC_BIT);

        packedIndirectBuf = GpuBuffer.createZeroed(phys, device, INDIRECT_SIZE * maxSlots,
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT |
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_TRANSFER_DST_BIT);

        // Deliberately not zeroed. It is gigabytes, and the extract shader
        // writes a slot's faces before any draw reads them: the draw count
        // comes from indirectBuf, which is zeroed and refilled per extract.
        // Leaving it untouched keeps the pages unfaulted, so resident memory
        // tracks the slots actually used instead of the worst case.
        ulong facesSize = cast(ulong) faceBufUnit * maxSlots;
        facesBuf = GpuBuffer.createHostVisible(phys, device, facesSize,
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);

        VkDescriptorBufferInfo pi;
        pi.buffer = paramsBuf.buffer;
        pi.range = VK_WHOLE_SIZE;
        VkWriteDescriptorSet pw;
        pw.sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        pw.dstSet = paramsSet;
        pw.dstBinding = 0;
        pw.descriptorCount = 1;
        pw.descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        pw.pBufferInfo = &pi;
        vkUpdateDescriptorSets(device, 1, &pw, 0, null);

        VkDescriptorSetLayout[2] layouts = [paramsLayout, dataLayout];
        VkPipelineLayoutCreateInfo plci;
        plci.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
        plci.setLayoutCount = 2;
        plci.pSetLayouts = layouts.ptr;
        if (vkCreatePipelineLayout(device, &plci, null, &pipelineLayout) != VkResult.VK_SUCCESS) {
            return false;
        }

        VkComputePipelineCreateInfo cpci;
        cpci.sType = VkStructureType.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
        cpci.stage.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        cpci.stage.stage = VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT;
        cpci.stage.mod = compShader;
        cpci.stage.pName = "main";
        cpci.layout = pipelineLayout;
        if (vkCreateComputePipelines(device, 0, 1, &cpci, null, &pipeline) != VkResult.VK_SUCCESS) {
            return false;
        }
        uint paddedSize = (dim + 2) * (dim + 2) * (dim + 2);
        packBuf = allocSlice!uint((paddedSize + 1) / 2);

        packIndirectCopies = allocSlice!VkBufferCopy(maxSlots);

        printf(
            "Extract: facesBuf=0x%llx (%zu bytes) indirBuf=0x%llx voxBuf=0x%llx\n",
            cast(ulong) facesBuf.buffer,
            cast(size_t) facesSize,
            cast(ulong) indirectBuf.buffer,
            cast(ulong) voxelsBuf.buffer,
        );

        tfReady = initTransformCompute(phys, device, slots);
        if (tfReady) {
            printf("GPU transform compute initialized\n");
        }
        return true;
    }

    bool initTransformCompute(VkPhysicalDevice phys, VkDevice device, uint slots) {
        maxNodes = slots;

        static immutable ubyte[] tfSpv = cast(immutable(ubyte)[]) import("transforms.comp.spv");
        VkShaderModuleCreateInfo smci;
        smci.sType = VkStructureType.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
        smci.codeSize = tfSpv.length;
        smci.pCode = cast(const(uint)*) tfSpv.ptr;
        if (vkCreateShaderModule(device, &smci, null, &tfCompShader) != VkResult.VK_SUCCESS) {
            return false;
        }

        VkDescriptorSetLayoutBinding[4] binds;
        foreach (i; 0 .. 4) {
            binds[i].binding = cast(uint) i;
            binds[i].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
            binds[i].descriptorCount = 1;
            binds[i].stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT;
        }
        VkDescriptorSetLayoutCreateInfo dlci;
        dlci.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
        dlci.bindingCount = 4;
        dlci.pBindings = binds.ptr;
        vkCreateDescriptorSetLayout(device, &dlci, null, &tfLayout);

        VkPushConstantRange pcr;
        pcr.stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT;
        pcr.offset = 0;
        pcr.size = 4;
        VkPipelineLayoutCreateInfo plci;
        plci.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
        plci.setLayoutCount = 1;
        plci.pSetLayouts = &tfLayout;
        plci.pushConstantRangeCount = 1;
        plci.pPushConstantRanges = &pcr;
        vkCreatePipelineLayout(device, &plci, null, &tfPipelineLayout);

        VkComputePipelineCreateInfo cpci;
        cpci.sType = VkStructureType.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
        cpci.stage.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        cpci.stage.stage = VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT;
        cpci.stage.mod = tfCompShader;
        cpci.stage.pName = "main";
        cpci.layout = tfPipelineLayout;
        if (vkCreateComputePipelines(device, 0, 1, &cpci, null, &tfPipeline) != VkResult.VK_SUCCESS) {
            return false;
        }

        VkDescriptorPoolSize poolSize;
        poolSize.type = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        poolSize.descriptorCount = 4;
        VkDescriptorPoolCreateInfo dpci;
        dpci.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        dpci.maxSets = 1;
        dpci.poolSizeCount = 1;
        dpci.pPoolSizes = &poolSize;
        vkCreateDescriptorPool(device, &dpci, null, &tfDescPool);

        VkDescriptorSetAllocateInfo dsai;
        dsai.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        dsai.descriptorPool = tfDescPool;
        dsai.descriptorSetCount = 1;
        dsai.pSetLayouts = &tfLayout;
        vkAllocateDescriptorSets(device, &dsai, &tfDescSet);

        nodeTransformsBuf = GpuBuffer.createHostVisible(phys, device,
            maxNodes * 64, VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
        vkMapMemory(device, nodeTransformsBuf.memory, 0, maxNodes * 64, 0, &nodeTransformsMapped);

        slotTasksBuf = GpuBuffer.createHostVisible(phys, device,
            slots * 16, VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
        vkMapMemory(device, slotTasksBuf.memory, 0, slots * 16, 0, &slotTasksMapped);

        float[20 * 16] vtxData;
        foreach (vi; 0 .. 20) {
            Matrix4!float m = vertexChunkToNode(cast(Vertex) vi);
            foreach (col; 0 .. 4) {
                foreach (row; 0 .. 4) {
                    vtxData[vi * 16 + col * 4 + row] = m.data[col][row];
                }
            }
        }
        vertexTransformsBuf = GpuBuffer.create(phys, device, cast(void[]) vtxData[],
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);

        VkDescriptorBufferInfo[4] infos;
        infos[0].buffer = nodeTransformsBuf.buffer;
        infos[0].range = VK_WHOLE_SIZE;
        infos[1].buffer = vertexTransformsBuf.buffer;
        infos[1].range = VK_WHOLE_SIZE;
        infos[2].buffer = slotTasksBuf.buffer;
        infos[2].range = VK_WHOLE_SIZE;

        VkWriteDescriptorSet[3] writes;
        foreach (i; 0 .. 3) {
            writes[i].sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
            writes[i].dstSet = tfDescSet;
            writes[i].dstBinding = cast(uint) i;
            writes[i].descriptorCount = 1;
            writes[i].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
            writes[i].pBufferInfo = &infos[i];
        }
        vkUpdateDescriptorSets(device, 3, writes.ptr, 0, null);

        return true;
    }

    void bindTransformOutput(VkDevice device, ulong transformsBuf) {
        VkDescriptorBufferInfo info;
        info.buffer = transformsBuf;
        info.range = VK_WHOLE_SIZE;
        VkWriteDescriptorSet w;
        w.sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        w.dstSet = tfDescSet;
        w.dstBinding = 3;
        w.descriptorCount = 1;
        w.descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        w.pBufferInfo = &info;
        vkUpdateDescriptorSets(device, 1, &w, 0, null);
    }

    void recordTransformCompute(VkCommandBuffer cmd, uint activeCount, ulong transformsBuf) {
        if (!tfReady || activeCount == 0) {
            return;
        }

        vkCmdBindPipeline(cmd, cast(VkPipelineBindPoint) 1, tfPipeline);
        vkCmdBindDescriptorSets(cmd, cast(VkPipelineBindPoint) 1, tfPipelineLayout,
            0, 1, &tfDescSet, 0, null);
        vkCmdPushConstants(cmd, tfPipelineLayout,
            VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &activeCount);
        vkCmdDispatch(cmd, (activeCount + 63) / 64, 1, 1);

        VkBufferMemoryBarrier bar;
        bar.sType = VkStructureType.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
        bar.srcAccessMask = VkAccessFlagBits.VK_ACCESS_SHADER_WRITE_BIT;
        bar.dstAccessMask = VkAccessFlagBits.VK_ACCESS_SHADER_READ_BIT;
        bar.srcQueueFamilyIndex = ~0u;
        bar.dstQueueFamilyIndex = ~0u;
        bar.buffer = transformsBuf;
        bar.size = VK_WHOLE_SIZE;
        vkCmdPipelineBarrier(cmd,
            VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
            VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_VERTEX_SHADER_BIT,
            0, 0, null, 1, &bar, 0, null);
    }

    void uploadVoxels(void* voxelsMapped, uint scratchIndex, const(ushort)[] paddedData) {
        uint count = packPaddedVoxelsInto(paddedData, dimension, packBuf);
        if (count == 0) {
            return;
        }
        ulong offset = cast(ulong) scratchIndex * voxelBufUnit;
        ulong size = count * 4;
        if (size > voxelBufUnit) {
            size = voxelBufUnit;
        }
        memcpy(cast(ubyte*) voxelsMapped + offset, packBuf.ptr, size);
    }

    void* mapVoxels(VkDevice device) {
        void* mapped;
        vkMapMemory(device, voxelsBuf.memory, 0, voxelBufUnit * concurrency, 0, &mapped);
        return mapped;
    }

    void unmapVoxels(VkDevice device) {
        vkUnmapMemory(device, voxelsBuf.memory);
    }

    void recordExtract(VkDevice device, VkCommandBuffer cmd, ExtractTask[] tasks) {
        if (tasks.length == 0) {
            return;
        }

        vkCmdFillBuffer(cmd, stateBuf.buffer, 0, stateBufUnit * concurrency, 0);

        foreach (ref task; tasks) {
            VkDescriptorBufferInfo[4] infos;
            infos[0].buffer = voxelsBuf.buffer;
            infos[0].offset = cast(ulong) task.index * voxelBufUnit;
            infos[0].range = voxelBufUnit;
            infos[1].buffer = stateBuf.buffer;
            infos[1].offset = cast(ulong) task.index * stateBufUnit;
            infos[1].range = stateBufUnit;
            infos[2].buffer = indirectBuf.buffer;
            infos[2].offset = task.indirectOffset;
            infos[2].range = INDIRECT_SIZE;
            infos[3].buffer = facesBuf.buffer;
            infos[3].offset = task.faceOffset;
            infos[3].range = faceBufUnit;

            VkWriteDescriptorSet[4] writes;
            foreach (i; 0 .. 4) {
                writes[i].sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
                writes[i].dstSet = dataSets[task.index];
                writes[i].dstBinding = cast(uint) i;
                writes[i].descriptorCount = 1;
                writes[i].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
                writes[i].pBufferInfo = &infos[i];
            }
            vkUpdateDescriptorSets(device, 4, writes.ptr, 0, null);

            uint firstVertex = cast(uint)(task.faceOffset / FACE_SIZE) * 6;
            vkCmdFillBuffer(cmd, indirectBuf.buffer, task.indirectOffset, 4, 0);
            vkCmdFillBuffer(cmd, indirectBuf.buffer, task.indirectOffset + 4, 4, 1);
            vkCmdFillBuffer(cmd, indirectBuf.buffer, task.indirectOffset + 8, 4, firstVertex);
            vkCmdFillBuffer(cmd, indirectBuf.buffer, task.indirectOffset + 12, 4, task.drawId);
        }

        VkBufferMemoryBarrier[2] preBar;
        preBar[0].sType = VkStructureType.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
        preBar[0].srcAccessMask = 0x1000;
        preBar[0].dstAccessMask = VkAccessFlagBits.VK_ACCESS_SHADER_READ_BIT | VkAccessFlagBits.VK_ACCESS_SHADER_WRITE_BIT;
        preBar[0].srcQueueFamilyIndex = ~0u;
        preBar[0].dstQueueFamilyIndex = ~0u;
        preBar[0].buffer = stateBuf.buffer;
        preBar[0].size = VK_WHOLE_SIZE;
        preBar[1] = preBar[0];
        preBar[1].buffer = indirectBuf.buffer;
        vkCmdPipelineBarrier(cmd, 0x1000, VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
            0, 0, null, 2, preBar.ptr, 0, null);

        vkCmdBindPipeline(cmd, cast(VkPipelineBindPoint) 1, pipeline);
        vkCmdBindDescriptorSets(cmd, cast(VkPipelineBindPoint) 1, pipelineLayout, 0, 1, &paramsSet, 0, null);

        uint gx = ((dimension + 1) * 3 + 3) / 4;
        uint gy = ((dimension + 1) + 3) / 4;
        uint gz = ((dimension + 1) + 3) / 4;

        foreach (ref task; tasks) {
            vkCmdBindDescriptorSets(cmd, cast(VkPipelineBindPoint) 1, pipelineLayout,
                1, 1, &dataSets[task.index], 0, null);
            vkCmdDispatch(cmd, gx, gy, gz);
        }

        VkBufferMemoryBarrier[2] postBar;
        postBar[0].sType = VkStructureType.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
        postBar[0].srcAccessMask = VkAccessFlagBits.VK_ACCESS_SHADER_WRITE_BIT;
        postBar[0].dstAccessMask = VkAccessFlagBits.VK_ACCESS_SHADER_READ_BIT;
        postBar[0].srcQueueFamilyIndex = ~0u;
        postBar[0].dstQueueFamilyIndex = ~0u;
        postBar[0].buffer = facesBuf.buffer;
        postBar[0].size = VK_WHOLE_SIZE;
        postBar[1] = postBar[0];
        postBar[1].buffer = indirectBuf.buffer;
        postBar[1].dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        vkCmdPipelineBarrier(cmd, VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
            VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_VERTEX_SHADER_BIT |
            VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_TRANSFER_BIT,
            0, 0, null, 2, postBar.ptr, 0, null);
    }

    void recordPackIndirect(VkCommandBuffer cmd, const(uint)[] activeSlots) {
        if (activeSlots.length == 0) {
            return;
        }
        // activeSlots arrives in ascending order, so consecutive slots are
        // one contiguous source range. Emitting a region per run instead of
        // per slot matters a lot on MoltenVK, where every VkBufferCopy region
        // becomes its own blit command.
        uint count = cast(uint) activeSlots.length;
        uint regions = 0;
        uint i = 0;
        while (i < count) {
            uint runStart = i;
            while (i + 1 < count && activeSlots[i + 1] == activeSlots[i] + 1) {
                i = i + 1;
            }
            uint runLength = i - runStart + 1;
            packIndirectCopies[regions].srcOffset =
                cast(VkDeviceSize) activeSlots[runStart] * INDIRECT_SIZE;
            packIndirectCopies[regions].dstOffset =
                cast(VkDeviceSize) runStart * INDIRECT_SIZE;
            packIndirectCopies[regions].size =
                cast(VkDeviceSize) runLength * INDIRECT_SIZE;
            regions = regions + 1;
            i = i + 1;
        }
        vkCmdCopyBuffer(cmd, indirectBuf.buffer, packedIndirectBuf.buffer,
            regions, packIndirectCopies.ptr);

        VkBufferMemoryBarrier bar;
        bar.sType = VkStructureType.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
        bar.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        bar.dstAccessMask = VkAccessFlagBits.VK_ACCESS_INDIRECT_COMMAND_READ_BIT;
        bar.srcQueueFamilyIndex = ~0u;
        bar.dstQueueFamilyIndex = ~0u;
        bar.buffer = packedIndirectBuf.buffer;
        bar.size = VK_WHOLE_SIZE;
        vkCmdPipelineBarrier(cmd,
            VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_TRANSFER_BIT,
            VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT,
            0, 0, null, 1, &bar, 0, null);
    }

    ulong faceOffset(uint slot) {
        return cast(ulong) slot * faceBufUnit;
    }

    ulong indirectOffset(uint slot) {
        return cast(ulong) slot * INDIRECT_SIZE;
    }

    void cleanup(VkDevice device) {
        if (pipeline) {
            vkDestroyPipeline(device, pipeline, null);
        }
        if (pipelineLayout) {
            vkDestroyPipelineLayout(device, pipelineLayout, null);
        }
        if (descPool) {
            vkDestroyDescriptorPool(device, descPool, null);
        }
        if (paramsLayout) {
            vkDestroyDescriptorSetLayout(device, paramsLayout, null);
        }
        if (dataLayout) {
            vkDestroyDescriptorSetLayout(device, dataLayout, null);
        }
        if (compShader) {
            vkDestroyShaderModule(device, compShader, null);
        }
        paramsBuf.cleanup(device);
        voxelsBuf.cleanup(device);
        stateBuf.cleanup(device);
        indirectBuf.cleanup(device);
        packedIndirectBuf.cleanup(device);
        facesBuf.cleanup(device);
    }
}
