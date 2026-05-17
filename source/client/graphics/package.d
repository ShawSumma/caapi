module client.graphics;

import std.stdio;
import std.math : sin, cos, tan, sqrt, PI;
import bindings.vk;
import client.graphics.core;
import client.graphics.base;
import client.graphics.voxels;
import client.graphics.frustum : Frustum;
import common.dodeca : Vertex, VERTEX_COUNT, vertexChunkToNode, vertexChunkBoundingSphereCenter;
import common.math : MPoint;
import common.graph : Graph, NodeId;
import common.math : MIsometry;
import common.traversal : ensureNearby, nearbyNodes;

struct Renderer {
    VulkanCore core;
    SwapchainState swapState;
    SurfacePipeline voxels;
    SurfaceExtraction extract;
    uint dimension = 12;
    float time = 0;
    float camYaw = 0;
    float camPitch = 0;

    void setCamera(float yaw, float pitch) {
        camYaw = yaw;
        camPitch = pitch;
    }

    bool init(void* window) {
        if (!core.init(window)) {
            return false;
        }
        if (!swapState.init(core.physicalDevice, core.device, core.surface, core.graphicsQueueFamily)) {
            return false;
        }

        // Build test world: one chunk
        auto voxelData = makeTestVoxels(dimension);

        if (!extract.init(core.physicalDevice, core.device, dimension, voxelData)) {
            return false;
        }
        Surface[] empty;

        // Build the hyperbolic graph and traverse nearby nodes. For each node × each
        // of 20 vertex-chunks, store nodeTransform * vertexChunkToNode(v) as the per-
        // instance transform.
        auto graph = Graph.create(cast(ubyte) dimension);
        auto startLocal = MIsometry!float.identity();
        ensureNearby(graph, NodeId.ROOT, startLocal, 1.0f);
        auto nodes = nearbyNodes(graph, NodeId.ROOT, startLocal, 1.0f);
        writefln("Nearby nodes within radius 3: %d", nodes.length);

        float[16][] transforms;
        transforms.length = nodes.length * VERTEX_COUNT;
        foreach (ni, nn; nodes) {
            foreach (i; 0 .. VERTEX_COUNT) {
                auto v = cast(Vertex) i;
                auto m = nn.transform.mat * vertexChunkToNode(v);
                foreach (col; 0 .. 4) {
                    foreach (row; 0 .. 4) {
                        transforms[ni * VERTEX_COUNT + i][col * 4 + row] = m.data[col][row];
                    }
                }
            }
        }

        if (!voxels.init(core.physicalDevice, core.device, swapState.renderPass, empty, transforms,
                         extract.surfacesBuf.buffer)) {
            return false;
        }

        writeln("Renderer initialized successfully");
        return true;
    }

    void render(float dt) {
        time += dt;
        auto extent = swapState.extent;
        float aspect = cast(float) extent.width / cast(float) extent.height;
        // Proper hypermine projection: Beltrami-Klein perspective into unit ball.
        auto frustum = Frustum.fromVfov(45.0f * (cast(float) PI / 180.0f), aspect);
        auto proj = frustum.projection(1.0e-4f);
        // Camera at the center of chunk A (so we're *inside* a chunk, not on a vertex).
        // view = rotateX(pitch) * rotateY(yaw) * translation(chunkCenter -> origin)
        auto chunkCenter = vertexChunkBoundingSphereCenter(Vertex.A);
        auto originPoint = MPoint!float.origin();
        auto toOrigin = MIsometry!float.translation(chunkCenter, originPoint);
        float[16] camOffset = matToFlat(toOrigin.mat);
        auto view = matMul(matMul(rotateX(camPitch), rotateY(camYaw)), camOffset);
        auto vp = matMul(proj, view);
        float[16] invp = 0;
        voxels.updateCommonUbo(core.device, vp, invp, 0.0f, time);

        renderVoxelsFrame(
            core.device,
            core.graphicsQueue,
            swapState.swapchain,
            swapState.commandBuffer,
            swapState.renderPass,
            swapState.framebuffers,
            extent,
            swapState.imageAvailableSemaphore,
            swapState.renderFinishedSemaphore,
            swapState.inFlightFence,
            voxels.pipeline,
            voxels.pipelineLayout,
            voxels.commonSet,
            voxels.staticSet,
            voxels.transformsVbo.buffer,
            voxels.chunkCount,
            dimension,
            &extract,
        );
    }

    void cleanup() {
        if (core.device !is null) {
            vkDeviceWaitIdle(core.device);
            voxels.cleanup(core.device);
            extract.cleanup(core.device);
            swapState.cleanup(core.device);
        }
        core.cleanup();
        writeln("Renderer cleaned up");
    }
}

// ---- math helpers (column-major mat4) ----
private float[16] rotateY(float angle) {
    float[16] m = 0;
    float c = cos(angle);
    float s = sin(angle);
    m[0] = c;  m[2]  = -s;
    m[5] = 1;
    m[8] = s;  m[10] = c;
    m[15] = 1;
    return m;
}

private float[16] matToFlat(M)(M m) {
    float[16] r;
    foreach (col; 0 .. 4) {
        foreach (row; 0 .. 4) {
            r[col * 4 + row] = m.data[col][row];
        }
    }
    return r;
}

private float[16] rotateX(float angle) {
    float[16] m = 0;
    float c = cos(angle);
    float s = sin(angle);
    m[0] = 1;
    m[5] = c;  m[6]  = s;
    m[9] = -s; m[10] = c;
    m[15] = 1;
    return m;
}

private float[16] perspective(float fovY, float aspect, float near, float far) {
    float[16] m = 0;
    float f = 1.0f / tan(fovY * 0.5f);
    m[0] = f / aspect;
    m[5] = -f;
    m[10] = far / (near - far);
    m[11] = -1;
    m[14] = (near * far) / (near - far);
    return m;
}

private float[16] lookAt(float[3] eye, float[3] target, float[3] up) {
    float[3] f = nrm([target[0]-eye[0], target[1]-eye[1], target[2]-eye[2]]);
    float[3] s = nrm(cr(f, up));
    float[3] u = cr(s, f);
    float[16] m = 0;
    m[0] = s[0]; m[4] = s[1]; m[8]  = s[2];  m[12] = -dt(s, eye);
    m[1] = u[0]; m[5] = u[1]; m[9]  = u[2];  m[13] = -dt(u, eye);
    m[2] = -f[0]; m[6] = -f[1]; m[10] = -f[2]; m[14] = dt(f, eye);
    m[15] = 1;
    return m;
}

private float[16] matMul(float[16] a, float[16] b) {
    float[16] r = 0;
    foreach (col; 0 .. 4) {
        foreach (row; 0 .. 4) {
            float s = 0;
            foreach (k; 0 .. 4) {
                s += a[k*4+row] * b[col*4+k];
            }
            r[col*4+row] = s;
        }
    }
    return r;
}

private float[3] nrm(float[3] v) {
    float l = sqrt(v[0]*v[0]+v[1]*v[1]+v[2]*v[2]);
    if (l == 0) {
        return v;
    }
    return [v[0]/l, v[1]/l, v[2]/l];
}
private float[3] cr(float[3] a, float[3] b) {
    return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]];
}
private float dt(float[3] a, float[3] b) { return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]; }

private void renderVoxelsFrame(
    VkDevice device, VkQueue queue,
    VkSwapchainKHR swapchain, VkCommandBuffer cmd,
    VkRenderPass renderPass, VkFramebuffer[] framebuffers, VkExtent2D extent,
    VkSemaphore imageAvailable, VkSemaphore renderFinished, VkFence fence,
    VkPipeline pipeline, VkPipelineLayout layout,
    VkDescriptorSet commonSet, VkDescriptorSet staticSet,
    ulong transformsBuf, uint chunkCount, uint dimension,
    SurfaceExtraction* extract) {

    vkWaitForFences(device, 1, &fence, 1, ulong.max);
    vkResetFences(device, 1, &fence);

    uint imageIndex;
    vkAcquireNextImageKHR(device, swapchain, ulong.max, imageAvailable, VK_NULL_HANDLE, &imageIndex);

    vkResetCommandBuffer(cmd, 0);
    VkCommandBufferBeginInfo bi;
    bi.sType = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    vkBeginCommandBuffer(cmd, &bi);

    // GPU surface extraction (compute) before the render pass begins
    extract.recordExtract(cmd, chunkCount);

    VkClearValue[2] clears;
    clears[0].color.float32 = [0.05f, 0.07f, 0.12f, 1.0f];
    clears[1].depthStencil.depth = 1.0f;

    VkRenderPassBeginInfo rp;
    rp.sType = VkStructureType.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    rp.renderPass = renderPass;
    rp.framebuffer = framebuffers[imageIndex];
    rp.renderArea.extent = extent;
    rp.clearValueCount = 2;
    rp.pClearValues = clears.ptr;
    vkCmdBeginRenderPass(cmd, &rp, VkSubpassContents.VK_SUBPASS_CONTENTS_INLINE);

    vkCmdBindPipeline(cmd, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);

    VkViewport vp;
    vp.x = 0; vp.y = 0;
    vp.width = cast(float) extent.width; vp.height = cast(float) extent.height;
    vp.minDepth = 0; vp.maxDepth = 1;
    vkCmdSetViewport(cmd, 0, 1, &vp);

    VkRect2D scissor;
    scissor.extent = extent;
    vkCmdSetScissor(cmd, 0, 1, &scissor);

    VkDescriptorSet[2] sets = [commonSet, staticSet];
    vkCmdBindDescriptorSets(cmd, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS, layout, 0, 2, sets.ptr, 0, null);

    VkDeviceSize offset = 0;
    vkCmdBindVertexBuffers(cmd, 0, 1, &transformsBuf, &offset);

    uint dim = dimension;
    vkCmdPushConstants(cmd, layout, VkShaderStageFlagBits.VK_SHADER_STAGE_VERTEX_BIT, 0, 4, &dim);

    // Draw indirect: vertex_count was written by compute extraction
    vkCmdDrawIndirect(cmd, extract.indirectBuf.buffer, 0, 1, 16);

    vkCmdEndRenderPass(cmd);
    vkEndCommandBuffer(cmd);

    uint waitStage = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSubmitInfo si;
    si.sType = VkStructureType.VK_STRUCTURE_TYPE_SUBMIT_INFO;
    si.waitSemaphoreCount = 1;
    si.pWaitSemaphores = &imageAvailable;
    si.pWaitDstStageMask = &waitStage;
    si.commandBufferCount = 1;
    si.pCommandBuffers = &cmd;
    si.signalSemaphoreCount = 1;
    si.pSignalSemaphores = &renderFinished;
    vkQueueSubmit(queue, 1, &si, fence);

    VkPresentInfoKHR pi;
    pi.sType = VkStructureType.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
    pi.waitSemaphoreCount = 1;
    pi.pWaitSemaphores = &renderFinished;
    pi.swapchainCount = 1;
    pi.pSwapchains = &swapchain;
    pi.pImageIndices = &imageIndex;
    vkQueuePresentKHR(queue, &pi);
}
