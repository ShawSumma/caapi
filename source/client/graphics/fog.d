module client.graphics.fog;

import std.stdio;
import bindings.vk;

struct FogPipeline {
    VkPipelineLayout pipelineLayout;
    VkPipeline pipeline;

    bool init(VkDevice device, VkRenderPass renderPass, VkDescriptorSetLayout commonLayout) {
        static immutable ubyte[] vertSpv = cast(immutable(ubyte)[]) import("fullscreen.vert.spv");
        static immutable ubyte[] fragSpv = cast(immutable(ubyte)[]) import("fog.frag.spv");

        VkShaderModule vertShader, fragShader;
        if (!createShader(device, vertSpv, vertShader)) {
            return false;
        }
        if (!createShader(device, fragSpv, fragShader)) {
            return false;
        }

        VkPipelineLayoutCreateInfo plci;
        plci.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
        plci.setLayoutCount = 1;
        plci.pSetLayouts = &commonLayout;
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
        ia.topology = VkPrimitiveTopology.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;

        VkPipelineViewportStateCreateInfo vp;
        vp.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
        vp.viewportCount = 1;
        vp.scissorCount = 1;

        VkPipelineRasterizationStateCreateInfo rs;
        rs.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
        rs.polygonMode = VkPolygonMode.VK_POLYGON_MODE_FILL;
        rs.cullMode = VkCullModeFlagBits.VK_CULL_MODE_NONE;
        rs.frontFace = VkFrontFace.VK_FRONT_FACE_COUNTER_CLOCKWISE;
        rs.depthBiasConstantFactor = 0;
        rs.depthBiasClamp = 0;
        rs.depthBiasSlopeFactor = 0;
        rs.lineWidth = 1.0f;

        VkPipelineMultisampleStateCreateInfo ms;
        ms.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
        ms.rasterizationSamples = 1;

        VkPipelineDepthStencilStateCreateInfo dssci;
        dssci.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
        dssci.depthTestEnable = 0;
        dssci.depthWriteEnable = 0;

        VkPipelineColorBlendAttachmentState cba;
        cba.blendEnable = 1;
        cba.srcColorBlendFactor = VkBlendFactor.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
        cba.dstColorBlendFactor = VkBlendFactor.VK_BLEND_FACTOR_SRC_ALPHA;
        cba.colorBlendOp = VkBlendOp.VK_BLEND_OP_ADD;
        cba.srcAlphaBlendFactor = 0;
        cba.dstAlphaBlendFactor = 0;
        cba.alphaBlendOp = VkBlendOp.VK_BLEND_OP_ADD;
        cba.colorWriteMask = 0x7;

        VkPipelineColorBlendStateCreateInfo cb;
        cb.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
        cb.attachmentCount = 1;
        cb.pAttachments = &cba;

        VkDynamicState[2] dyn = [VkDynamicState.VK_DYNAMIC_STATE_VIEWPORT, VkDynamicState.VK_DYNAMIC_STATE_SCISSOR];
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
        gpci.subpass = 1;

        res = vkCreateGraphicsPipelines(device, 0, 1, &gpci, null, &pipeline);

        vkDestroyShaderModule(device, vertShader, null);
        vkDestroyShaderModule(device, fragShader, null);

        if (res != VkResult.VK_SUCCESS) {
            writefln("fog pipeline create failed: %s", res);
            return false;
        }
        return true;
    }

    void draw(VkCommandBuffer cmd, VkPipelineLayout layout, VkDescriptorSet commonSet) {
        vkCmdBindPipeline(cmd, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
        vkCmdBindDescriptorSets(cmd, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS,
            pipelineLayout, 0, 1, &commonSet, 0, null);
        vkCmdDraw(cmd, 3, 1, 0, 0);
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

bool createShader(VkDevice device, const(ubyte)[] spv, ref VkShaderModule mod) {
    VkShaderModuleCreateInfo ci;
    ci.sType = VkStructureType.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    ci.codeSize = spv.length;
    ci.pCode = cast(const(uint)*) spv.ptr;
    return vkCreateShaderModule(device, &ci, null, &mod) == VkResult.VK_SUCCESS;
}
