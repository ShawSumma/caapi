module client.graphics.voxels.surface_extraction;

import std.stdio;
import bindings.vk;
import client.graphics.pipeline : GpuBuffer;
import client.graphics.voxels.surface : Surface;

/// Pack a (dim+2)³ array of u16 materials into u32 pairs (matches extract.comp layout).
uint[] packVoxelsForExtraction(const(ubyte)[] voxels, uint dim) {
    uint paddedDim = dim + 2;
    uint paddedSize = paddedDim * paddedDim * paddedDim;
    auto padded = new ushort[paddedSize];
    // Copy core (offset by 1 each axis) from voxels (dim³)
    for (uint z = 0; z < dim; z++) {
        for (uint y = 0; y < dim; y++) {
            for (uint x = 0; x < dim; x++) {
                uint src = x + y * dim + z * dim * dim;
                uint dst = (x + 1) + (y + 1) * paddedDim + (z + 1) * paddedDim * paddedDim;
                padded[dst] = voxels[src];
            }
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

/// Port of hypermine's SurfaceExtraction (compute pipeline).
struct SurfaceExtraction {
    VkShaderModule compShader;
    VkDescriptorSetLayout paramsLayout;
    VkDescriptorSetLayout dataLayout;
    VkPipelineLayout pipelineLayout;
    VkPipeline pipeline;
    VkDescriptorPool descPool;
    VkDescriptorSet paramsSet;
    VkDescriptorSet dataSet;

    GpuBuffer dimensionUbo;
    GpuBuffer voxelsBuf;
    GpuBuffer stateBuf;     // 1 uint (face_count)
    GpuBuffer indirectBuf;  // 4 uints (vertex_count, instance_count, first_vertex, first_instance)
    GpuBuffer surfacesBuf;  // [Surface] output

    uint dimension;
    uint maxFaces;

    bool init(VkPhysicalDevice phys, VkDevice device, uint dim, const(ubyte)[] voxels) {
        dimension = dim;
        maxFaces = 3 * (dim * dim * dim + dim * dim);

        static immutable ubyte[] compSpv = cast(ubyte[]) import("extract.comp.spv");
        VkShaderModuleCreateInfo smci;
        smci.sType = VkStructureType.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
        smci.codeSize = compSpv.length;
        smci.pCode = cast(const(uint)*) compSpv.ptr;
        if (vkCreateShaderModule(device, &smci, null, &compShader) != VkResult.VK_SUCCESS) {
            writeln("compute shader module failed"); return false;
        }

        // set 0 binding 0: dimension UBO (compute)
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

        // set 1 bindings 0..3: voxels, state, indirect, surfaces (all SSBO)
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
        sizes[1].descriptorCount = 4;
        VkDescriptorPoolCreateInfo dpci;
        dpci.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        dpci.maxSets = 2;
        dpci.poolSizeCount = 2;
        dpci.pPoolSizes = sizes.ptr;
        vkCreateDescriptorPool(device, &dpci, null, &descPool);

        VkDescriptorSetLayout[2] layouts = [paramsLayout, dataLayout];
        VkDescriptorSetAllocateInfo dsai;
        dsai.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        dsai.descriptorPool = descPool;
        dsai.descriptorSetCount = 2;
        dsai.pSetLayouts = layouts.ptr;
        VkDescriptorSet[2] sets;
        vkAllocateDescriptorSets(device, &dsai, sets.ptr);
        paramsSet = sets[0];
        dataSet = sets[1];

        // --- Buffers ---
        // Dimension UBO: int dimension; (4 bytes, but std140 padding → 16)
        int[4] dimData = [cast(int) dim, 0, 0, 0];
        dimensionUbo = GpuBuffer.create(phys, device, cast(void[]) dimData[],
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);

        auto packed = packVoxelsForExtraction(voxels, dim);
        voxelsBuf = GpuBuffer.create(phys, device, cast(void[]) packed,
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);

        uint[1] zero1 = [0];
        stateBuf = GpuBuffer.create(phys, device, cast(void[]) zero1[],
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_TRANSFER_DST_BIT);

        // Indirect: VkDrawIndirectCommand initial (vertex_count=0, instance_count=NUM_CHUNKS, first*=0)
        uint[4] indirectInit = [0, 1, 0, 0];
        indirectBuf = GpuBuffer.create(phys, device, cast(void[]) indirectInit[],
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT |
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_TRANSFER_DST_BIT);

        // Allocate room for max possible faces
        Surface[] zeroSurf = new Surface[maxFaces];
        surfacesBuf = GpuBuffer.create(phys, device, cast(void[]) zeroSurf,
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);

        // Write descriptors
        VkDescriptorBufferInfo paramsInfo;
        paramsInfo.buffer = dimensionUbo.buffer;
        paramsInfo.offset = 0;
        paramsInfo.range = VK_WHOLE_SIZE;

        VkDescriptorBufferInfo[4] dataInfos;
        ulong[4] bufHandles = [voxelsBuf.buffer, stateBuf.buffer, indirectBuf.buffer, surfacesBuf.buffer];
        foreach (i; 0 .. 4) {
            dataInfos[i].buffer = bufHandles[i];
            dataInfos[i].offset = 0;
            dataInfos[i].range = VK_WHOLE_SIZE;
        }

        VkWriteDescriptorSet[5] writes;
        writes[0].sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        writes[0].dstSet = paramsSet;
        writes[0].dstBinding = 0;
        writes[0].descriptorCount = 1;
        writes[0].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        writes[0].pBufferInfo = &paramsInfo;
        foreach (i; 0 .. 4) {
            writes[1 + i].sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
            writes[1 + i].dstSet = dataSet;
            writes[1 + i].dstBinding = cast(uint) i;
            writes[1 + i].descriptorCount = 1;
            writes[1 + i].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
            writes[1 + i].pBufferInfo = &dataInfos[i];
        }
        vkUpdateDescriptorSets(device, 5, writes.ptr, 0, null);

        // Pipeline layout
        VkPipelineLayoutCreateInfo plci;
        plci.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
        plci.setLayoutCount = 2;
        plci.pSetLayouts = layouts.ptr;
        if (vkCreatePipelineLayout(device, &plci, null, &pipelineLayout) != VkResult.VK_SUCCESS) {
            return false;
        }

        // Compute pipeline
        VkComputePipelineCreateInfo cpci;
        cpci.sType = VkStructureType.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
        cpci.stage.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        cpci.stage.stage = VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT;
        cpci.stage.mod = compShader;
        cpci.stage.pName = "main";
        cpci.layout = pipelineLayout;
        auto res = vkCreateComputePipelines(device, 0, 1, &cpci, null, &pipeline);
        if (res != VkResult.VK_SUCCESS) {
            writefln("compute pipeline create failed: %s", res); return false;
        }
        writeln("Compute extraction pipeline created");
        return true;
    }

    /// Record extract dispatch + barrier into the command buffer.
    void recordExtract(VkCommandBuffer cmd, uint chunkCount) {
        // Reset face_count and indirect
        vkCmdFillBuffer(cmd, stateBuf.buffer, 0, 4, 0);
        uint[4] indirectReset = [0, chunkCount, 0, 0];
        // For simplicity, fill instance_count too; the shader writes vertex_count.
        vkCmdFillBuffer(cmd, indirectBuf.buffer, 0, 4, 0);            // vertex_count = 0
        vkCmdFillBuffer(cmd, indirectBuf.buffer, 4, 4, chunkCount);   // instance_count = chunkCount
        vkCmdFillBuffer(cmd, indirectBuf.buffer, 8, 8, 0);            // first_*=0

        // Barrier: ensure fills complete before compute reads/writes
        VkBufferMemoryBarrier[2] preBar;
        preBar[0].sType = VkStructureType.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
        preBar[0].srcAccessMask = 0x1000; // VK_ACCESS_TRANSFER_WRITE_BIT
        preBar[0].dstAccessMask = VkAccessFlagBits.VK_ACCESS_SHADER_READ_BIT | VkAccessFlagBits.VK_ACCESS_SHADER_WRITE_BIT;
        preBar[0].srcQueueFamilyIndex = ~0u;
        preBar[0].dstQueueFamilyIndex = ~0u;
        preBar[0].buffer = stateBuf.buffer;
        preBar[0].offset = 0;
        preBar[0].size = VK_WHOLE_SIZE;
        preBar[1] = preBar[0];
        preBar[1].buffer = indirectBuf.buffer;
        vkCmdPipelineBarrier(cmd, 0x1000 /*TRANSFER*/, VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
            0, 0, null, 2, preBar.ptr, 0, null);

        vkCmdBindPipeline(cmd, cast(VkPipelineBindPoint) 1, pipeline);
        VkDescriptorSet[2] sets = [paramsSet, dataSet];
        vkCmdBindDescriptorSets(cmd, cast(VkPipelineBindPoint) 1, pipelineLayout, 0, 2, sets.ptr, 0, null);

        // Dispatch: (3*dim, dim, dim) total threads, workgroup 4x4x4
        uint gx = (3 * dimension + 3) / 4;
        uint gy = (dimension + 3) / 4;
        uint gz = (dimension + 3) / 4;
        vkCmdDispatch(cmd, gx, gy, gz);

        // Barrier: ensure compute writes visible to draw indirect + vertex shader read
        VkBufferMemoryBarrier[2] postBar;
        postBar[0].sType = VkStructureType.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
        postBar[0].srcAccessMask = VkAccessFlagBits.VK_ACCESS_SHADER_WRITE_BIT;
        postBar[0].dstAccessMask = VkAccessFlagBits.VK_ACCESS_SHADER_READ_BIT;
        postBar[0].srcQueueFamilyIndex = ~0u;
        postBar[0].dstQueueFamilyIndex = ~0u;
        postBar[0].buffer = surfacesBuf.buffer;
        postBar[0].offset = 0;
        postBar[0].size = VK_WHOLE_SIZE;
        postBar[1] = postBar[0];
        postBar[1].buffer = indirectBuf.buffer;
        postBar[1].dstAccessMask = VkAccessFlagBits.VK_ACCESS_INDIRECT_COMMAND_READ_BIT;
        vkCmdPipelineBarrier(cmd, VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
            VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_VERTEX_SHADER_BIT |
            VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT,
            0, 0, null, 2, postBar.ptr, 0, null);
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
        dimensionUbo.cleanup(device);
        voxelsBuf.cleanup(device);
        stateBuf.cleanup(device);
        indirectBuf.cleanup(device);
        surfacesBuf.cleanup(device);
    }
}
