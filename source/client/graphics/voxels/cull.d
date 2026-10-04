module client.graphics.voxels.cull;

import bindings.platform : VK_ACCESS_INDIRECT_COMMAND_READ_BIT, VK_ACCESS_SHADER_READ_BIT, VK_ACCESS_SHADER_WRITE_BIT, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, VK_PIPELINE_BIND_POINT_COMPUTE, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT, VK_PIPELINE_STAGE_VERTEX_SHADER_BIT, VK_SHADER_STAGE_COMPUTE_BIT, VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, VK_STRUCTURE_TYPE_MEMORY_BARRIER, VkBuffer, VkCommandBuffer, VkDescriptorBufferInfo, VkDescriptorPool, VkDescriptorPoolCreateInfo, VkDescriptorPoolSize, VkDescriptorSet, VkDescriptorSetAllocateInfo, VkDescriptorSetLayout, VkDescriptorSetLayoutBinding, VkDevice, VkMemoryBarrier, VkPipeline, VkPipelineLayout, VkPushConstantRange, VkShaderModule, VkWriteDescriptorSet, vkAllocateDescriptorSets, vkCmdBindDescriptorSets, vkCmdBindPipeline, vkCmdDispatch, vkCmdPipelineBarrier, vkCmdPushConstants, vkCreateDescriptorPool, vkDestroyDescriptorPool, vkDestroyDescriptorSetLayout, vkDestroyPipeline, vkDestroyPipelineLayout, vkDestroyShaderModule, vkUpdateDescriptorSets;
import client.graphics.pipeline : WHOLE_SIZE, bufferWrite, createComputePipeline, createPipelineLayout, createSetLayout, createShader, expectSuccess, layoutBinding;
import client.graphics.voxels.meshes : ChunkMeshes;

enum string CULL_COMP_SPV = import("cull.comp.spv");
enum uint CULL_WORKGROUP = 64;
enum uint CULL_STORAGE_BINDINGS = 5;
enum uint COMMON_BINDING = 0;

struct CullPipeline {
    VkDescriptorSetLayout setLayout;
    VkDescriptorPool pool;
    VkDescriptorSet set;
    VkPipelineLayout pipelineLayout;
    VkPipeline pipeline;

    void setup(VkDevice device, VkBuffer commonUbo) {
        VkDescriptorSetLayoutBinding[CULL_STORAGE_BINDINGS + 1] bindings;
        bindings[COMMON_BINDING] = layoutBinding(COMMON_BINDING, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT);
        foreach (i; 1 .. CULL_STORAGE_BINDINGS + 1) {
            bindings[i] = layoutBinding(cast(uint) i, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT);
        }
        setLayout = createSetLayout(device, bindings[]);
        VkDescriptorPoolSize[2] sizes = [
            VkDescriptorPoolSize(VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1),
            VkDescriptorPoolSize(VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, CULL_STORAGE_BINDINGS),
        ];
        VkDescriptorPoolCreateInfo poolInfo;
        poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        poolInfo.maxSets = 1;
        poolInfo.poolSizeCount = sizes.length;
        poolInfo.pPoolSizes = sizes.ptr;
        expectSuccess(vkCreateDescriptorPool(device, &poolInfo, null, &pool));
        VkDescriptorSetAllocateInfo allocateInfo;
        allocateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        allocateInfo.descriptorPool = pool;
        allocateInfo.descriptorSetCount = 1;
        allocateInfo.pSetLayouts = &setLayout;
        expectSuccess(vkAllocateDescriptorSets(device, &allocateInfo, &set));
        VkDescriptorBufferInfo commonInfo = VkDescriptorBufferInfo(commonUbo, 0, WHOLE_SIZE);
        VkWriteDescriptorSet write = bufferWrite(set, COMMON_BINDING, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, &commonInfo);
        vkUpdateDescriptorSets(device, 1, &write, 0, null);
        VkShaderModule shader = createShader(device, CULL_COMP_SPV);
        VkDescriptorSetLayout[1] setLayouts = [
            setLayout,
        ];
        VkPushConstantRange[1] pushConstants = [
            VkPushConstantRange(VK_SHADER_STAGE_COMPUTE_BIT, 0, uint.sizeof),
        ];
        pipelineLayout = createPipelineLayout(device, setLayouts[], pushConstants[]);
        pipeline = createComputePipeline(device, shader, pipelineLayout);
        vkDestroyShaderModule(device, shader, null);
    }

    void bindBuffers(VkDevice device, ref ChunkMeshes meshes) {
        VkDescriptorBufferInfo[CULL_STORAGE_BINDINGS] infos = [
            VkDescriptorBufferInfo(meshes.vertices.buffer, 0, WHOLE_SIZE),
            VkDescriptorBufferInfo(meshes.nodes.buffer, 0, WHOLE_SIZE),
            VkDescriptorBufferInfo(meshes.drawables.buffer, 0, WHOLE_SIZE),
            VkDescriptorBufferInfo(meshes.transforms.buffer, 0, WHOLE_SIZE),
            VkDescriptorBufferInfo(meshes.commands.buffer, 0, WHOLE_SIZE),
        ];
        VkWriteDescriptorSet[CULL_STORAGE_BINDINGS] writes;
        foreach (i; 0 .. CULL_STORAGE_BINDINGS) {
            writes[i] = bufferWrite(set, cast(uint) i + 1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, &infos[i]);
        }
        vkUpdateDescriptorSets(device, writes.length, writes.ptr, 0, null);
    }

    void record(VkCommandBuffer commands, uint drawableCount) {
        vkCmdBindPipeline(commands, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
        vkCmdBindDescriptorSets(commands, VK_PIPELINE_BIND_POINT_COMPUTE, pipelineLayout, 0, 1, &set, 0, null);
        vkCmdPushConstants(commands, pipelineLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, uint.sizeof, &drawableCount);
        vkCmdDispatch(commands, (drawableCount + CULL_WORKGROUP - 1) / CULL_WORKGROUP, 1, 1);
        VkMemoryBarrier barrier;
        barrier.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER;
        barrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
        barrier.dstAccessMask = VK_ACCESS_INDIRECT_COMMAND_READ_BIT | VK_ACCESS_SHADER_READ_BIT;
        vkCmdPipelineBarrier(commands, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT | VK_PIPELINE_STAGE_VERTEX_SHADER_BIT, 0, 1, &barrier, 0, null, 0, null);
    }

    void cleanup(VkDevice device) {
        vkDestroyPipeline(device, pipeline, null);
        vkDestroyPipelineLayout(device, pipelineLayout, null);
        vkDestroyDescriptorPool(device, pool, null);
        vkDestroyDescriptorSetLayout(device, setLayout, null);
    }
}
