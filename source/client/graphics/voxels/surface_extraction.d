module client.graphics.voxels.surface_extraction;

import std.stdio;
import bindings.vk;
import client.graphics.pipeline : GpuBuffer;
import client.graphics.voxels.surface : Surface;

enum uint FACE_SIZE = 8;
enum uint INDIRECT_SIZE = 16;

private uint roundUp(uint value, uint alignment) {
    return (value + alignment - 1) / alignment * alignment;
}

/// Pack a (dim+2)³ array of u16 materials into u32 pairs (matches extract.comp layout).
uint[] packVoxelsForExtraction(const(ubyte)[] voxels, uint dim) {
    uint paddedDim = dim + 2;
    uint paddedSize = paddedDim * paddedDim * paddedDim;
    auto padded = new ushort[paddedSize];
    for (uint z = 0; z < dim; z++) {
        for (uint y = 0; y < dim; y++) {
            for (uint x = 0; x < dim; x++) {
                uint src = x + y * dim + z * dim * dim;
                uint dst = (x + 1) + (y + 1) * paddedDim + (z + 1) * paddedDim * paddedDim;
                padded[dst] = voxels[src];
            }
        }
    }
    for (uint z = 0; z < dim; z++) {
        for (uint y = 0; y < dim; y++) {
            padded[0       + (y+1)*paddedDim + (z+1)*paddedDim*paddedDim] = padded[1   + (y+1)*paddedDim + (z+1)*paddedDim*paddedDim];
            padded[(dim+1) + (y+1)*paddedDim + (z+1)*paddedDim*paddedDim] = padded[dim + (y+1)*paddedDim + (z+1)*paddedDim*paddedDim];
        }
    }
    for (uint z = 0; z < dim; z++) {
        for (uint x = 0; x < paddedDim; x++) {
            padded[x + 0*paddedDim       + (z+1)*paddedDim*paddedDim] = padded[x + 1*paddedDim   + (z+1)*paddedDim*paddedDim];
            padded[x + (dim+1)*paddedDim + (z+1)*paddedDim*paddedDim] = padded[x + dim*paddedDim + (z+1)*paddedDim*paddedDim];
        }
    }
    for (uint y = 0; y < paddedDim; y++) {
        for (uint x = 0; x < paddedDim; x++) {
            padded[x + y*paddedDim + 0*paddedDim*paddedDim]       = padded[x + y*paddedDim + 1*paddedDim*paddedDim];
            padded[x + y*paddedDim + (dim+1)*paddedDim*paddedDim] = padded[x + y*paddedDim + dim*paddedDim*paddedDim];
        }
    }
    auto pairs = new uint[(paddedSize + 1) / 2];
    for (uint i = 0; i + 1 < paddedSize; i += 2) {
        pairs[i / 2] = padded[i] | (cast(uint) padded[i + 1] << 16);
    }
    if (paddedSize % 2 == 1) {
        pairs[paddedSize / 2] = padded[paddedSize - 1];
    }
    return pairs;
}

struct ExtractTask {
    ulong indirectOffset;
    ulong faceOffset;
    uint index;       // scratch slot index (0..concurrency-1)
    uint drawId;      // first_instance = transform slot
}

/// GPU compute surface extraction with per-slot descriptor sets.
/// Matches hypermine's SurfaceExtraction + ScratchBuffer + DrawBuffer.
struct SurfaceExtraction {
    // Pipeline
    VkShaderModule compShader;
    VkDescriptorSetLayout paramsLayout;
    VkDescriptorSetLayout dataLayout;
    VkPipelineLayout pipelineLayout;
    VkPipeline pipeline;
    VkDescriptorPool descPool;
    VkDescriptorSet paramsSet;
    VkDescriptorSet[] dataSets;  // one per concurrency slot

    // Scratch buffers (for extraction tasks)
    GpuBuffer paramsBuf;
    GpuBuffer voxelsBuf;    // concurrency * voxelBufUnit
    GpuBuffer stateBuf;     // concurrency * stateBufUnit

    // Draw buffers (persistent, one slot per chunk)
    GpuBuffer indirectBuf;  // maxSlots * INDIRECT_SIZE
    GpuBuffer facesBuf;     // maxSlots * faceBufUnit

    uint dimension;
    uint concurrency;
    uint maxSlots;
    uint voxelBufUnit;
    uint stateBufUnit;
    uint faceBufUnit;
    uint maxFaces;

    bool init(VkPhysicalDevice phys, VkDevice device, uint dim, uint conc, uint slots) {
        dimension = dim;
        concurrency = conc;
        maxSlots = slots;
        maxFaces = 3 * (dim * dim * dim + dim * dim);
        enum ALIGN = 16; // minStorageBufferOffsetAlignment
        voxelBufUnit = roundUp(cast(uint)((dim + 2) * (dim + 2) * (dim + 2)) * 2, ALIGN);
        stateBufUnit = roundUp(4, ALIGN);
        faceBufUnit = roundUp(maxFaces * FACE_SIZE, ALIGN);

        static immutable ubyte[] compSpv = cast(immutable(ubyte)[]) import("extract.comp.spv");
        VkShaderModuleCreateInfo smci;
        smci.sType = VkStructureType.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
        smci.codeSize = compSpv.length;
        smci.pCode = cast(const(uint)*) compSpv.ptr;
        if (vkCreateShaderModule(device, &smci, null, &compShader) != VkResult.VK_SUCCESS) {
            return false;
        }

        // Layouts
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

        // Descriptor pool: 1 params + concurrency data sets
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

        // Allocate params set
        VkDescriptorSetAllocateInfo pai;
        pai.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        pai.descriptorPool = descPool;
        pai.descriptorSetCount = 1;
        pai.pSetLayouts = &paramsLayout;
        vkAllocateDescriptorSets(device, &pai, &paramsSet);

        // Allocate per-slot data sets
        auto dataLayouts = new VkDescriptorSetLayout[concurrency];
        dataLayouts[] = dataLayout;
        dataSets = new VkDescriptorSet[concurrency];
        VkDescriptorSetAllocateInfo dai;
        dai.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        dai.descriptorPool = descPool;
        dai.descriptorSetCount = concurrency;
        dai.pSetLayouts = dataLayouts.ptr;
        vkAllocateDescriptorSets(device, &dai, dataSets.ptr);

        // Buffers
        int[4] dimData = [cast(int) dim, 0, 0, 0];
        paramsBuf = GpuBuffer.create(phys, device, cast(void[]) dimData[],
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);

        auto voxelsSize = voxelBufUnit * concurrency;
        ubyte[] voxInit = new ubyte[voxelsSize];
        voxelsBuf = GpuBuffer.create(phys, device, voxInit,
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);

        auto stateSize = stateBufUnit * concurrency;
        ubyte[] stateInit = new ubyte[stateSize];
        stateBuf = GpuBuffer.create(phys, device, stateInit,
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_TRANSFER_DST_BIT);

        ubyte[] indirInit = new ubyte[INDIRECT_SIZE * maxSlots];
        indirectBuf = GpuBuffer.create(phys, device, indirInit,
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT |
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_TRANSFER_DST_BIT);

        ulong facesSize = cast(ulong) faceBufUnit * maxSlots;
        ubyte[] facesInitData = new ubyte[facesSize];
        facesBuf = GpuBuffer.create(phys, device, facesInitData,
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);

        // Write params descriptor
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

        // Pipeline layout
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
        writefln("Extract: facesBuf=0x%x (%d bytes) indirBuf=0x%x voxBuf=0x%x",
            facesBuf.buffer, facesSize, indirectBuf.buffer, voxelsBuf.buffer);
        return true;
    }

    /// Upload voxel data into scratch slot.
    void uploadVoxels(VkDevice device, uint scratchIndex, const(ubyte)[] voxelData) {
        import core.stdc.string : memcpy;
        auto packed = packVoxelsForExtraction(voxelData, dimension);
        if (packed is null) {
            return;
        }
        ulong offset = cast(ulong) scratchIndex * voxelBufUnit;
        ulong size = packed.length * 4;
        if (size > voxelBufUnit) {
            size = voxelBufUnit;
        }
        void* mapped;
        auto res = vkMapMemory(device, voxelsBuf.memory, offset, size, 0, &mapped);
        if (res != VkResult.VK_SUCCESS) {
            writefln("uploadVoxels: vkMapMemory failed at offset %d size %d: %s", offset, size, res);
            return;
        }
        memcpy(mapped, packed.ptr, size);
        vkUnmapMemory(device, voxelsBuf.memory);
    }

    /// Record extraction for a batch of tasks.
    void recordExtract(VkDevice device, VkCommandBuffer cmd, ExtractTask[] tasks) {
        if (tasks.length == 0) {
            return;
        }

        // Fill state buffer with zeros
        vkCmdFillBuffer(cmd, stateBuf.buffer, 0, stateBufUnit * concurrency, 0);

        // Update per-task descriptor sets and initialize indirect commands
        foreach (ref task; tasks) {
            // Update descriptor set for this scratch slot
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

            // Initialize indirect command
            uint firstVertex = cast(uint)(task.faceOffset / FACE_SIZE) * 6;
            vkCmdFillBuffer(cmd, indirectBuf.buffer, task.indirectOffset, 4, 0);
            vkCmdFillBuffer(cmd, indirectBuf.buffer, task.indirectOffset + 4, 4, 1);
            vkCmdFillBuffer(cmd, indirectBuf.buffer, task.indirectOffset + 8, 4, firstVertex);
            vkCmdFillBuffer(cmd, indirectBuf.buffer, task.indirectOffset + 12, 4, task.drawId);
        }

        // Barrier: fills → compute
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

        // Bind compute pipeline and params
        vkCmdBindPipeline(cmd, cast(VkPipelineBindPoint) 1, pipeline);
        vkCmdBindDescriptorSets(cmd, cast(VkPipelineBindPoint) 1, pipelineLayout, 0, 1, &paramsSet, 0, null);

        uint gx = (3 * dimension + 3) / 4;
        uint gy = (dimension + 3) / 4;
        uint gz = (dimension + 3) / 4;

        // Dispatch per task with per-slot descriptor set
        foreach (ref task; tasks) {
            vkCmdBindDescriptorSets(cmd, cast(VkPipelineBindPoint) 1, pipelineLayout,
                1, 1, &dataSets[task.index], 0, null);
            vkCmdDispatch(cmd, gx, gy, gz);
        }

        // Barrier: compute → vertex shader + draw indirect
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
        postBar[1].dstAccessMask = VkAccessFlagBits.VK_ACCESS_INDIRECT_COMMAND_READ_BIT;
        vkCmdPipelineBarrier(cmd, VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
            VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_VERTEX_SHADER_BIT |
            VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT,
            0, 0, null, 2, postBar.ptr, 0, null);
    }

    ulong faceOffset(uint slot) { return cast(ulong) slot * faceBufUnit; }
    ulong indirectOffset(uint slot) { return cast(ulong) slot * INDIRECT_SIZE; }

    void cleanup(VkDevice device) {
        if (pipeline) { vkDestroyPipeline(device, pipeline, null); }
        if (pipelineLayout) { vkDestroyPipelineLayout(device, pipelineLayout, null); }
        if (descPool) { vkDestroyDescriptorPool(device, descPool, null); }
        if (paramsLayout) { vkDestroyDescriptorSetLayout(device, paramsLayout, null); }
        if (dataLayout) { vkDestroyDescriptorSetLayout(device, dataLayout, null); }
        if (compShader) { vkDestroyShaderModule(device, compShader, null); }
        paramsBuf.cleanup(device);
        voxelsBuf.cleanup(device);
        stateBuf.cleanup(device);
        indirectBuf.cleanup(device);
        facesBuf.cleanup(device);
    }
}
