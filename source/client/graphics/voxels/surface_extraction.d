module client.graphics.voxels.surface_extraction;

import std.stdio;
import bindings.vk;
import client.graphics.pipeline : GpuBuffer;
import client.graphics.voxels.surface : Surface;

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

struct WorldgenParamsGPU {
align(1):
    float[16] chunkToNode;
    float[4] surfaceNormal;
    float[4] roadPlaneNormal;
    float[4] scalars;
    uint[2] rngSeed;
    float[2] _pad;
    float[4] elev0;
    float[4] elev1;
    float[4] temp0;
    float[4] temp1;
    float[4] rain0;
    float[4] rain1;
    float[4] block0;
    float[4] block1;
}
static assert(WorldgenParamsGPU.sizeof == 256);

struct VoronoiEntryGPU {
    float rain;
    float temp;
    uint material;
    uint _pad;
}
static assert(VoronoiEntryGPU.sizeof == 16);

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

    VkShaderModule wgenShader;
    VkDescriptorSetLayout wgenParamsLayout;
    VkPipelineLayout wgenPipelineLayout;
    VkPipeline wgenPipeline;
    VkDescriptorPool wgenDescPool;
    VkDescriptorSet[] wgenParamsSets;
    GpuBuffer wgenParamsBuf;
    GpuBuffer voronoiTableBuf;
    bool wgenReady;

    bool init(VkPhysicalDevice phys, VkDevice device, uint dim, uint conc, uint slots) {
        dimension = dim;
        concurrency = conc;
        maxSlots = slots;
        maxFaces = 3 * (dim * dim * dim + dim * dim);
        enum ALIGN = 16;
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

        VkDescriptorSetLayout[] dataLayouts = new VkDescriptorSetLayout[concurrency];
        dataLayouts[] = dataLayout;
        dataSets = new VkDescriptorSet[concurrency];
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
        ubyte[] voxInit = new ubyte[voxelsSize];
        voxelsBuf = GpuBuffer.create(phys, device, voxInit,
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);

        uint stateSize = stateBufUnit * concurrency;
        ubyte[] stateInit = new ubyte[stateSize];
        stateBuf = GpuBuffer.create(phys, device, stateInit,
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_TRANSFER_DST_BIT);

        ubyte[] indirInit = new ubyte[INDIRECT_SIZE * maxSlots];
        indirectBuf = GpuBuffer.create(phys, device, indirInit,
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT |
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_TRANSFER_SRC_BIT);

        ubyte[] packedInit = new ubyte[INDIRECT_SIZE * maxSlots];
        packedIndirectBuf = GpuBuffer.create(phys, device, packedInit,
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT |
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_TRANSFER_DST_BIT);

        ulong facesSize = cast(ulong) faceBufUnit * maxSlots;
        ubyte[] facesInitData = new ubyte[facesSize];
        facesBuf = GpuBuffer.create(phys, device, facesInitData,
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
        packBuf = new uint[(paddedSize + 1) / 2];

        writefln("Extract: facesBuf=0x%x (%d bytes) indirBuf=0x%x voxBuf=0x%x",
            facesBuf.buffer, facesSize, indirectBuf.buffer, voxelsBuf.buffer);

        wgenReady = initWorldgen(phys, device);
        if (wgenReady) {
            writeln("GPU worldgen initialized");
        }
        return true;
    }

    bool initWorldgen(VkPhysicalDevice phys, VkDevice device) {
        import common.worldgen.terraingen : TerrainVoronoiEntry = VoronoiEntryGPU, buildVoronoiTableGPU;

        static immutable ubyte[] wgenSpv = cast(immutable(ubyte)[]) import("worldgen.comp.spv");
        VkShaderModuleCreateInfo smci;
        smci.sType = VkStructureType.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
        smci.codeSize = wgenSpv.length;
        smci.pCode = cast(const(uint)*) wgenSpv.ptr;
        if (vkCreateShaderModule(device, &smci, null, &wgenShader) != VkResult.VK_SUCCESS) {
            return false;
        }

        VkDescriptorSetLayoutBinding[3] wgb;
        wgb[0].binding = 0;
        wgb[0].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        wgb[0].descriptorCount = 1;
        wgb[0].stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT;
        wgb[1].binding = 1;
        wgb[1].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC;
        wgb[1].descriptorCount = 1;
        wgb[1].stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT;
        wgb[2].binding = 2;
        wgb[2].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        wgb[2].descriptorCount = 1;
        wgb[2].stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT;
        VkDescriptorSetLayoutCreateInfo wgci;
        wgci.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
        wgci.bindingCount = 3;
        wgci.pBindings = wgb.ptr;
        vkCreateDescriptorSetLayout(device, &wgci, null, &wgenParamsLayout);

        VkDescriptorSetLayout[2] wgLayouts = [wgenParamsLayout, dataLayout];
        VkPipelineLayoutCreateInfo wgplci;
        wgplci.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
        wgplci.setLayoutCount = 2;
        wgplci.pSetLayouts = wgLayouts.ptr;
        vkCreatePipelineLayout(device, &wgplci, null, &wgenPipelineLayout);

        VkComputePipelineCreateInfo wgcpci;
        wgcpci.sType = VkStructureType.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
        wgcpci.stage.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        wgcpci.stage.stage = VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT;
        wgcpci.stage.mod = wgenShader;
        wgcpci.stage.pName = "main";
        wgcpci.layout = wgenPipelineLayout;
        if (vkCreateComputePipelines(device, 0, 1, &wgcpci, null, &wgenPipeline) != VkResult.VK_SUCCESS) {
            return false;
        }

        VkDescriptorPoolSize[2] wgps;
        wgps[0].type = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC;
        wgps[0].descriptorCount = 1;
        wgps[1].type = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        wgps[1].descriptorCount = 1;
        VkDescriptorPoolSize wgps2;
        wgps2.type = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        wgps2.descriptorCount = 1;
        VkDescriptorPoolSize[3] allps = [wgps[0], wgps[1], wgps2];
        VkDescriptorPoolCreateInfo wgdpci;
        wgdpci.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        wgdpci.maxSets = 1;
        wgdpci.poolSizeCount = 3;
        wgdpci.pPoolSizes = allps.ptr;
        vkCreateDescriptorPool(device, &wgdpci, null, &wgenDescPool);

        wgenParamsSets = new VkDescriptorSet[1];
        VkDescriptorSetAllocateInfo wgdai;
        wgdai.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        wgdai.descriptorPool = wgenDescPool;
        wgdai.descriptorSetCount = 1;
        wgdai.pSetLayouts = &wgenParamsLayout;
        vkAllocateDescriptorSets(device, &wgdai, wgenParamsSets.ptr);

        uint wgenParamsSize = roundUp(WorldgenParamsGPU.sizeof, 256) * concurrency;
        ubyte[] wpInit = new ubyte[wgenParamsSize];
        wgenParamsBuf = GpuBuffer.create(phys, device, wpInit,
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);

        TerrainVoronoiEntry[] voronoiData = buildVoronoiTableGPU();
        voronoiTableBuf = GpuBuffer.create(phys, device, cast(void[]) voronoiData,
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);

        VkDescriptorBufferInfo[3] wgbi;
        wgbi[0].buffer = paramsBuf.buffer;
        wgbi[0].range = 16;
        wgbi[1].buffer = wgenParamsBuf.buffer;
        wgbi[1].range = WorldgenParamsGPU.sizeof;
        wgbi[2].buffer = voronoiTableBuf.buffer;
        wgbi[2].range = VK_WHOLE_SIZE;

        VkWriteDescriptorSet[3] wgw;
        foreach (i; 0 .. 3) {
            wgw[i].sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
            wgw[i].dstSet = wgenParamsSets[0];
            wgw[i].dstBinding = cast(uint) i;
            wgw[i].descriptorCount = 1;
            wgw[i].pBufferInfo = &wgbi[i];
        }
        wgw[0].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        wgw[1].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC;
        wgw[2].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        vkUpdateDescriptorSets(device, 3, wgw.ptr, 0, null);

        return true;
    }

    uint uploadWorldgenParams(VkDevice device, uint scratchIndex, const ref WorldgenParamsGPU params) {
        uint offset = roundUp(WorldgenParamsGPU.sizeof, 256) * scratchIndex;
        void* mapped;
        vkMapMemory(device, wgenParamsBuf.memory, offset, WorldgenParamsGPU.sizeof, 0, &mapped);
        import core.stdc.string : memcpy;
        memcpy(mapped, &params, WorldgenParamsGPU.sizeof);
        vkUnmapMemory(device, wgenParamsBuf.memory);
        return offset;
    }

    void recordWorldgen(VkDevice device, VkCommandBuffer cmd, ExtractTask[] tasks, uint[] wgenOffsets) {
        if (tasks.length == 0 || !wgenReady) {
            return;
        }

        foreach (ref task; tasks) {
            vkCmdFillBuffer(cmd, voxelsBuf.buffer,
                cast(ulong) task.index * voxelBufUnit, voxelBufUnit, 0);
        }

        VkBufferMemoryBarrier clearBar;
        clearBar.sType = VkStructureType.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
        clearBar.srcAccessMask = 0x1000;
        clearBar.dstAccessMask = VkAccessFlagBits.VK_ACCESS_SHADER_READ_BIT | VkAccessFlagBits.VK_ACCESS_SHADER_WRITE_BIT;
        clearBar.srcQueueFamilyIndex = ~0u;
        clearBar.dstQueueFamilyIndex = ~0u;
        clearBar.buffer = voxelsBuf.buffer;
        clearBar.size = VK_WHOLE_SIZE;
        vkCmdPipelineBarrier(cmd, 0x1000, VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
            0, 0, null, 1, &clearBar, 0, null);

        foreach (i, ref task; tasks) {
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
            foreach (j; 0 .. 4) {
                writes[j].sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
                writes[j].dstSet = dataSets[task.index];
                writes[j].dstBinding = cast(uint) j;
                writes[j].descriptorCount = 1;
                writes[j].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
                writes[j].pBufferInfo = &infos[j];
            }
            vkUpdateDescriptorSets(device, 4, writes.ptr, 0, null);
        }

        vkCmdBindPipeline(cmd, cast(VkPipelineBindPoint) 1, wgenPipeline);

        uint gx = (dimension + 3) / 4;
        uint gy = (dimension + 3) / 4;
        uint gz = (dimension + 3) / 4;

        foreach (i, ref task; tasks) {
            uint dynOffset = wgenOffsets[i];
            vkCmdBindDescriptorSets(cmd, cast(VkPipelineBindPoint) 1, wgenPipelineLayout,
                0, 1, &wgenParamsSets[0], 1, &dynOffset);
            vkCmdBindDescriptorSets(cmd, cast(VkPipelineBindPoint) 1, wgenPipelineLayout,
                1, 1, &dataSets[task.index], 0, null);
            vkCmdDispatch(cmd, gx, gy, gz);
        }

        VkBufferMemoryBarrier wgenBar;
        wgenBar.sType = VkStructureType.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
        wgenBar.srcAccessMask = VkAccessFlagBits.VK_ACCESS_SHADER_WRITE_BIT;
        wgenBar.dstAccessMask = VkAccessFlagBits.VK_ACCESS_SHADER_READ_BIT;
        wgenBar.srcQueueFamilyIndex = ~0u;
        wgenBar.dstQueueFamilyIndex = ~0u;
        wgenBar.buffer = voxelsBuf.buffer;
        wgenBar.size = VK_WHOLE_SIZE;
        vkCmdPipelineBarrier(cmd, VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
            VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
            0, 0, null, 1, &wgenBar, 0, null);
    }

    void uploadVoxels(void* voxelsMapped, uint scratchIndex, const(ushort)[] paddedData) {
        import core.stdc.string : memcpy;
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
        uint count = cast(uint) activeSlots.length;
        VkBufferCopy[4096] copies = void;
        foreach (i; 0 .. count) {
            copies[i].srcOffset = cast(VkDeviceSize) activeSlots[i] * INDIRECT_SIZE;
            copies[i].dstOffset = cast(VkDeviceSize) i * INDIRECT_SIZE;
            copies[i].size = INDIRECT_SIZE;
        }
        vkCmdCopyBuffer(cmd, indirectBuf.buffer, packedIndirectBuf.buffer, count, copies.ptr);

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
