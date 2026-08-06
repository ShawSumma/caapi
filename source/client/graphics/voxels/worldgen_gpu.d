module client.graphics.voxels.worldgen_gpu;

import core.stdc.stdio : printf;
import core.stdc.string : memcpy;
import bindings.vk;
import client.graphics.pipeline : GpuBuffer;
import common.array : allocSlice, freeSlice;
import common.dodeca : Side, Vertex, vertexChunkToNode;
import common.math : Matrix4;
import common.node : VoxelData;
import common.world : Material;
import common.worldgen : ChunkParams, TerrainMode, terrainModeFor;
import common.worldgen : TERRAIN_SMOOTHNESS;
import common.worldgen.plane : Plane;
import common.worldgen.terraingen : VoronoiEntryGPU, VORONOI_TABLE_GPU;
import common.worldgen.terraingen : VORONOI_TABLE_LENGTH;

// Mirrors the shader's Params block. std140 puts every member on a 16-byte
// boundary, which the vec4/uvec4 grouping already satisfies.
struct WorldgenParamsGPU {
align(1):
    float[16] chunkToNode;
    float[4] surfaceNormal;
    float[4] roadNormal;
    // dimension, surface exponent, road exponent, terrain smoothness
    float[4] scalars;
    // terrain mode, isRoad, isRoadSupport, unused
    uint[4] flags;
    // splitmix64 seed as (low, high), then padding
    uint[4] rngSeed;
    float[4] elev0;
    float[4] elev1;
    float[4] temp0;
    float[4] temp1;
    float[4] rain0;
    float[4] rain1;
    float[4] block0;
    float[4] block1;
}
static assert(WorldgenParamsGPU.sizeof == 272);

// One-chunk-at-a-time generator. This exists to be checked against the CPU
// path first; batching comes after it is known to agree.
struct WorldgenGpu {
    VkShaderModule shaderModule;
    VkDescriptorSetLayout paramsLayout;
    VkDescriptorSetLayout voxelsLayout;
    VkPipelineLayout pipelineLayout;
    VkPipeline pipeline;
    VkDescriptorPool descPool;
    VkDescriptorSet paramsSet;
    VkDescriptorSet voxelsSet;

    GpuBuffer paramsBuf;
    GpuBuffer voronoiBuf;
    GpuBuffer voxelsBuf;
    void* paramsMapped;
    void* voxelsMapped;

    VkCommandPool commandPool;
    VkCommandBuffer cmd;
    VkFence fence;

    uint dimension;
    uint voxelCount;
    bool ready;

    bool init(VkPhysicalDevice phys, VkDevice device, uint queueFamily, uint dim) {
        dimension = dim;
        uint padded = dim + 2;
        voxelCount = padded * padded * padded;

        static immutable ubyte[] spv =
            cast(immutable(ubyte)[]) import("worldgen.comp.spv");
        VkShaderModuleCreateInfo smci;
        smci.sType = VkStructureType.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
        smci.codeSize = spv.length;
        smci.pCode = cast(const(uint)*) spv.ptr;
        if (vkCreateShaderModule(device, &smci, null, &shaderModule)
                != VkResult.VK_SUCCESS) {
            printf("worldgen: shader module failed\n");
            return false;
        }

        VkDescriptorSetLayoutBinding[2] pb;
        pb[0].binding = 0;
        pb[0].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        pb[0].descriptorCount = 1;
        pb[0].stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT;
        pb[1].binding = 1;
        pb[1].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        pb[1].descriptorCount = 1;
        pb[1].stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT;
        VkDescriptorSetLayoutCreateInfo plci;
        plci.sType =
            VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
        plci.bindingCount = 2;
        plci.pBindings = pb.ptr;
        vkCreateDescriptorSetLayout(device, &plci, null, &paramsLayout);

        VkDescriptorSetLayoutBinding vb;
        vb.binding = 0;
        vb.descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        vb.descriptorCount = 1;
        vb.stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT;
        VkDescriptorSetLayoutCreateInfo vlci;
        vlci.sType =
            VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
        vlci.bindingCount = 1;
        vlci.pBindings = &vb;
        vkCreateDescriptorSetLayout(device, &vlci, null, &voxelsLayout);

        VkDescriptorSetLayout[2] setLayouts = [paramsLayout, voxelsLayout];
        VkPushConstantRange pcr;
        pcr.stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT;
        pcr.offset = 0;
        pcr.size = 4;
        VkPipelineLayoutCreateInfo lci;
        lci.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
        lci.setLayoutCount = 2;
        lci.pSetLayouts = setLayouts.ptr;
        lci.pushConstantRangeCount = 1;
        lci.pPushConstantRanges = &pcr;
        vkCreatePipelineLayout(device, &lci, null, &pipelineLayout);

        VkComputePipelineCreateInfo cpci;
        cpci.sType = VkStructureType.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
        cpci.stage.sType =
            VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        cpci.stage.stage = VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT;
        cpci.stage.mod = shaderModule;
        cpci.stage.pName = "main";
        cpci.layout = pipelineLayout;
        if (vkCreateComputePipelines(device, 0, 1, &cpci, null, &pipeline)
                != VkResult.VK_SUCCESS) {
            printf("worldgen: compute pipeline failed\n");
            return false;
        }

        VkDescriptorPoolSize[2] sizes;
        sizes[0].type = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        sizes[0].descriptorCount = 1;
        sizes[1].type = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        sizes[1].descriptorCount = 2;
        VkDescriptorPoolCreateInfo dpci;
        dpci.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        dpci.maxSets = 2;
        dpci.poolSizeCount = 2;
        dpci.pPoolSizes = sizes.ptr;
        vkCreateDescriptorPool(device, &dpci, null, &descPool);

        VkDescriptorSetAllocateInfo pai;
        pai.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        pai.descriptorPool = descPool;
        pai.descriptorSetCount = 1;
        pai.pSetLayouts = &paramsLayout;
        vkAllocateDescriptorSets(device, &pai, &paramsSet);

        VkDescriptorSetAllocateInfo vai;
        vai.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        vai.descriptorPool = descPool;
        vai.descriptorSetCount = 1;
        vai.pSetLayouts = &voxelsLayout;
        vkAllocateDescriptorSets(device, &vai, &voxelsSet);

        paramsBuf = GpuBuffer.createHostVisible(phys, device,
            WorldgenParamsGPU.sizeof,
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
        vkMapMemory(device, paramsBuf.memory, 0, WorldgenParamsGPU.sizeof, 0,
            &paramsMapped);

        const(void)[] table = cast(const(void)[]) VORONOI_TABLE_GPU[];
        voronoiBuf = GpuBuffer.create(phys, device, table,
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);

        voxelsBuf = GpuBuffer.createZeroed(phys, device, voxelCount * 4,
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
        vkMapMemory(device, voxelsBuf.memory, 0, voxelCount * 4, 0, &voxelsMapped);

        VkDescriptorBufferInfo[3] infos;
        infos[0].buffer = paramsBuf.buffer;
        infos[0].range = WorldgenParamsGPU.sizeof;
        infos[1].buffer = voronoiBuf.buffer;
        infos[1].range = VK_WHOLE_SIZE;
        infos[2].buffer = voxelsBuf.buffer;
        infos[2].range = VK_WHOLE_SIZE;

        VkWriteDescriptorSet[3] writes;
        foreach (i; 0 .. 3) {
            writes[i].sType =
                VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
            writes[i].descriptorCount = 1;
            writes[i].pBufferInfo = &infos[i];
        }
        writes[0].dstSet = paramsSet;
        writes[0].dstBinding = 0;
        writes[0].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        writes[1].dstSet = paramsSet;
        writes[1].dstBinding = 1;
        writes[1].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        writes[2].dstSet = voxelsSet;
        writes[2].dstBinding = 0;
        writes[2].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        vkUpdateDescriptorSets(device, 3, writes.ptr, 0, null);

        VkCommandPoolCreateInfo cpi;
        cpi.sType = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
        cpi.flags =
            VkCommandPoolCreateFlagBits.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
        cpi.queueFamilyIndex = queueFamily;
        vkCreateCommandPool(device, &cpi, null, &commandPool);

        VkCommandBufferAllocateInfo cbai;
        cbai.sType = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        cbai.commandPool = commandPool;
        cbai.level = VkCommandBufferLevel.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        cbai.commandBufferCount = 1;
        vkAllocateCommandBuffers(device, &cbai, &cmd);

        VkFenceCreateInfo fci;
        fci.sType = VkStructureType.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
        vkCreateFence(device, &fci, null, &fence);

        ready = true;
        return true;
    }

    static WorldgenParamsGPU buildParams(const ref ChunkParams cp, ulong rngState) {
        WorldgenParamsGPU p;

        Matrix4!float m = vertexChunkToNode(cp.chunk);
        foreach (col; 0 .. 4) {
            foreach (row; 0 .. 4) {
                p.chunkToNode[col * 4 + row] = m.data[col][row];
            }
        }

        foreach (i; 0 .. 4) {
            p.surfaceNormal[i] = cp.surface.scaledNormal.data[i];
        }
        Plane road = -Plane.fromSide(Side.B);
        foreach (i; 0 .. 4) {
            p.roadNormal[i] = road.scaledNormal.data[i];
        }

        p.scalars[0] = cast(float) cp.dimension;
        p.scalars[1] = cp.surface.exponent;
        p.scalars[2] = road.exponent;
        p.scalars[3] = TERRAIN_SMOOTHNESS;

        TerrainMode mode = terrainModeFor(cp);
        p.flags[0] = cast(uint) mode;
        p.flags[1] = cp.isRoad ? 1 : 0;
        p.flags[2] = cp.isRoadSupport ? 1 : 0;

        // generateTrees bails on a chunk that is still solid, which is exactly
        // the non-dense modes, and the candidate count comes straight from the
        // node's own rainfall.
        uint candidates = 0;
        if (mode == TerrainMode.Dense) {
            float density = cp.env.rainfalls[0] / 100.0f;
            if (density < 0.0f) {
                density = 0.0f;
            }
            if (density > 0.5f) {
                density = 0.5f;
            }
            uint span = cast(uint) cp.dimension - 2;
            candidates = cast(uint)(cast(float)(span * span * span) * density);
        }
        p.flags[3] = candidates;

        p.rngSeed[0] = cast(uint)(rngState & 0xFFFFFFFF);
        p.rngSeed[1] = cast(uint)(rngState >> 32);

        foreach (i; 0 .. 4) {
            p.elev0[i] = cp.env.maxElevations[i];
            p.elev1[i] = cp.env.maxElevations[i + 4];
            p.temp0[i] = cp.env.temperatures[i];
            p.temp1[i] = cp.env.temperatures[i + 4];
            p.rain0[i] = cp.env.rainfalls[i];
            p.rain1[i] = cp.env.rainfalls[i + 4];
            p.block0[i] = cp.env.blockinesses[i];
            p.block1[i] = cp.env.blockinesses[i + 4];
        }
        return p;
    }

    // Dispatches one chunk and blocks until the result is readable. Returns a
    // view of the mapped output, one uint per padded voxel.
    const(uint)[] generate(VkDevice device, VkQueue queue, const ref WorldgenParamsGPU p) {
        memcpy(paramsMapped, &p, WorldgenParamsGPU.sizeof);

        vkResetCommandBuffer(cmd, 0);
        VkCommandBufferBeginInfo bi;
        bi.sType = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        vkBeginCommandBuffer(cmd, &bi);

        vkCmdFillBuffer(cmd, voxelsBuf.buffer, 0, voxelCount * 4, 0);
        VkBufferMemoryBarrier clearBar;
        clearBar.sType = VkStructureType.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
        clearBar.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        clearBar.dstAccessMask = VkAccessFlagBits.VK_ACCESS_SHADER_READ_BIT
            | VkAccessFlagBits.VK_ACCESS_SHADER_WRITE_BIT;
        clearBar.srcQueueFamilyIndex = ~0u;
        clearBar.dstQueueFamilyIndex = ~0u;
        clearBar.buffer = voxelsBuf.buffer;
        clearBar.size = VK_WHOLE_SIZE;
        vkCmdPipelineBarrier(cmd,
            VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_TRANSFER_BIT,
            VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
            0, 0, null, 1, &clearBar, 0, null);

        vkCmdBindPipeline(cmd, cast(VkPipelineBindPoint) 1, pipeline);
        vkCmdBindDescriptorSets(cmd, cast(VkPipelineBindPoint) 1, pipelineLayout,
            0, 1, &paramsSet, 0, null);
        vkCmdBindDescriptorSets(cmd, cast(VkPipelineBindPoint) 1, pipelineLayout,
            1, 1, &voxelsSet, 0, null);

        uint terrainPass = 0;
        vkCmdPushConstants(cmd, pipelineLayout,
            VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &terrainPass);
        uint groups = (dimension + 3) / 4;
        vkCmdDispatch(cmd, groups, groups, groups);

        // Trees read and write voxels the terrain pass produced, so they need
        // the whole grid finished first.
        VkBufferMemoryBarrier treeBar = clearBar;
        treeBar.srcAccessMask = VkAccessFlagBits.VK_ACCESS_SHADER_WRITE_BIT;
        treeBar.dstAccessMask = VkAccessFlagBits.VK_ACCESS_SHADER_READ_BIT
            | VkAccessFlagBits.VK_ACCESS_SHADER_WRITE_BIT;
        vkCmdPipelineBarrier(cmd,
            VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
            VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
            0, 0, null, 1, &treeBar, 0, null);

        uint treePass = 1;
        vkCmdPushConstants(cmd, pipelineLayout,
            VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &treePass);
        vkCmdDispatch(cmd, 1, 1, 1);

        // Host read access / host stage; the minimal vk bindings do not name
        // these, and the fence below is what actually orders the readback.
        enum uint ACCESS_HOST_READ = 0x2000;
        enum uint STAGE_HOST = 0x4000;
        VkBufferMemoryBarrier doneBar = clearBar;
        doneBar.srcAccessMask = VkAccessFlagBits.VK_ACCESS_SHADER_WRITE_BIT;
        doneBar.dstAccessMask = ACCESS_HOST_READ;
        vkCmdPipelineBarrier(cmd,
            VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
            STAGE_HOST,
            0, 0, null, 1, &doneBar, 0, null);

        vkEndCommandBuffer(cmd);

        vkResetFences(device, 1, &fence);
        VkSubmitInfo si;
        si.sType = VkStructureType.VK_STRUCTURE_TYPE_SUBMIT_INFO;
        si.commandBufferCount = 1;
        si.pCommandBuffers = &cmd;
        vkQueueSubmit(queue, 1, &si, fence);
        vkWaitForFences(device, 1, &fence, 1, ulong.max);

        return (cast(const(uint)*) voxelsMapped)[0 .. voxelCount];
    }

    void cleanup(VkDevice device) {
        if (!ready) {
            return;
        }
        vkDestroyFence(device, fence, null);
        vkDestroyCommandPool(device, commandPool, null);
        voxelsBuf.cleanup(device);
        voronoiBuf.cleanup(device);
        paramsBuf.cleanup(device);
        vkDestroyDescriptorPool(device, descPool, null);
        vkDestroyPipeline(device, pipeline, null);
        vkDestroyPipelineLayout(device, pipelineLayout, null);
        vkDestroyDescriptorSetLayout(device, voxelsLayout, null);
        vkDestroyDescriptorSetLayout(device, paramsLayout, null);
        vkDestroyShaderModule(device, shaderModule, null);
        ready = false;
    }
}
