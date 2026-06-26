module client.graphics.highlight;

import std.stdio;
import core.stdc.string : memcpy;
import bindings.vk;
import client.graphics.fog : createShader;

/// Wireframe outline around the voxel the player is aiming at.
/// Drawn as a line list in subpass 0 with depth testing so hidden
/// edges are occluded by terrain.
struct HighlightPipeline {
    VkPipelineLayout pipelineLayout;
    VkPipeline pipeline;

    bool init(VkDevice device, VkRenderPass renderPass) {
        static immutable ubyte[] vertSpv = cast(immutable(ubyte)[]) import("highlight.vert.spv");
        static immutable ubyte[] fragSpv = cast(immutable(ubyte)[]) import("highlight.frag.spv");

        VkShaderModule vertShader;
        VkShaderModule fragShader;
        if (!createShader(device, vertSpv, vertShader)) {
            return false;
        }
        if (!createShader(device, fragSpv, fragShader)) {
            return false;
        }

        VkPushConstantRange pcr;
        pcr.stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_VERTEX_BIT;
        pcr.offset = 0;
        pcr.size = 80; // mat4 + vec4

        VkPipelineLayoutCreateInfo plci;
        plci.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
        plci.pushConstantRangeCount = 1;
        plci.pPushConstantRanges = &pcr;
        VkResult res = vkCreatePipelineLayout(device, &plci, null, &pipelineLayout);
        if (res != VkResult.VK_SUCCESS) {
            return false;
        }

        VkPipelineShaderStageCreateInfo[2] stages;
        stages[0].sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        stages[0].stage = VkShaderStageFlagBits.VK_SHADER_STAGE_VERTEX_BIT;
        stages[0].mod = vertShader;
        stages[0].pName = "main";
        stages[1].sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        stages[1].stage = VkShaderStageFlagBits.VK_SHADER_STAGE_FRAGMENT_BIT;
        stages[1].mod = fragShader;
        stages[1].pName = "main";

        VkPipelineVertexInputStateCreateInfo vi;
        vi.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;

        VkPipelineInputAssemblyStateCreateInfo ia;
        ia.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
        ia.topology = VkPrimitiveTopology.VK_PRIMITIVE_TOPOLOGY_LINE_LIST;

        VkPipelineViewportStateCreateInfo vp;
        vp.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
        vp.viewportCount = 1;
        vp.scissorCount = 1;

        VkPipelineRasterizationStateCreateInfo rs;
        rs.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
        rs.polygonMode = VkPolygonMode.VK_POLYGON_MODE_FILL;
        rs.cullMode = VkCullModeFlagBits.VK_CULL_MODE_NONE;
        rs.frontFace = VkFrontFace.VK_FRONT_FACE_COUNTER_CLOCKWISE;
        // Float fields default to NaN in D; the spec requires these be 0.
        rs.depthBiasConstantFactor = 0;
        rs.depthBiasClamp = 0;
        rs.depthBiasSlopeFactor = 0;
        rs.lineWidth = 1.0f;

        VkPipelineMultisampleStateCreateInfo ms;
        ms.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
        ms.rasterizationSamples = 1;

        VkPipelineDepthStencilStateCreateInfo dssci;
        dssci.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
        dssci.depthTestEnable = 1;
        dssci.depthWriteEnable = 0;
        dssci.depthCompareOp = VkCompareOp.VK_COMPARE_OP_GREATER;

        VkPipelineColorBlendAttachmentState cba;
        cba.colorWriteMask = 0xf;
        VkPipelineColorBlendStateCreateInfo cb;
        cb.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
        cb.attachmentCount = 1;
        cb.pAttachments = &cba;

        VkDynamicState[2] dyn = [
            VkDynamicState.VK_DYNAMIC_STATE_VIEWPORT,
            VkDynamicState.VK_DYNAMIC_STATE_SCISSOR,
        ];
        VkPipelineDynamicStateCreateInfo ds;
        ds.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
        ds.dynamicStateCount = 2;
        ds.pDynamicStates = dyn.ptr;

        VkGraphicsPipelineCreateInfo gpci;
        gpci.sType = VkStructureType.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
        gpci.stageCount = 2;
        gpci.pStages = stages.ptr;
        gpci.pVertexInputState = &vi;
        gpci.pInputAssemblyState = &ia;
        gpci.pViewportState = &vp;
        gpci.pRasterizationState = &rs;
        gpci.pMultisampleState = &ms;
        gpci.pDepthStencilState = &dssci;
        gpci.pColorBlendState = &cb;
        gpci.pDynamicState = &ds;
        gpci.layout = pipelineLayout;
        gpci.renderPass = renderPass;
        gpci.subpass = 0;

        res = vkCreateGraphicsPipelines(device, 0, 1, &gpci, null, &pipeline);

        vkDestroyShaderModule(device, vertShader, null);
        vkDestroyShaderModule(device, fragShader, null);

        if (res != VkResult.VK_SUCCESS) {
            writefln("highlight pipeline create failed: %s", res);
            return false;
        }
        return true;
    }

    void draw(VkCommandBuffer cmd, float[16] mvp, float[3] voxelCoords, float dimension) {
        float[20] pc;
        memcpy(pc.ptr, mvp.ptr, 64);
        pc[16] = voxelCoords[0];
        pc[17] = voxelCoords[1];
        pc[18] = voxelCoords[2];
        pc[19] = dimension;
        vkCmdBindPipeline(cmd, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
        vkCmdPushConstants(cmd, pipelineLayout,
            VkShaderStageFlagBits.VK_SHADER_STAGE_VERTEX_BIT, 0, 80, pc.ptr);
        vkCmdDraw(cmd, 24, 1, 0, 0);
    }

    void cleanup(VkDevice device) {
        if (pipeline) {
            vkDestroyPipeline(device, pipeline, null);
        }
        if (pipelineLayout) {
            vkDestroyPipelineLayout(device, pipelineLayout, null);
        }
    }
}
