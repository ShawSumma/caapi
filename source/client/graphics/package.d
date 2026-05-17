module client.graphics;

import std.stdio;
import std.math : sin, cos, tan, sqrt, PI;
import bindings.vk;
import client.graphics.core;
import client.graphics.base;
import client.graphics.voxels;
import client.graphics.frustum : Frustum;
import common.dodeca : Vertex, VERTEX_COUNT, Side, SIDE_COUNT,
    vertexChunkToNode, vertexChunkBoundingSphereCenter,
    sideReflection, sideIsFacing;
import common.math : MPoint, MIsometry, MVector;
import common.graph : Graph, NodeId;
import common.proto : Position;
import common.traversal : ensureNearby, nearbyNodes;

struct Renderer {
    VulkanCore core;
    SwapchainState swapState;
    SurfacePipeline voxels;
    SurfaceExtraction extract;
    uint dimension = 12;
    float time = 0;
    // Hyperbolic camera position: a node id + local isometry within that node.
    // camPos.local maps camera-local frame (origin = camera, -Z forward) to
    // node-local frame. View matrix = camPos.local.inverse(). Yaw/pitch are
    // applied directly to camPos.local so that node migration (reflection)
    // mirrors orientation along with position.
    Position camPos;
    // Graph and visible chunk count are mutated each frame as the camera moves.
    Graph graph;
    float viewRadius = 1.2f;
    uint maxChunks = 0;
    uint currentChunkCount = 0;

    /// Rotate camera in its own local frame: yawDelta around Y, pitchDelta around X.
    void rotateCamera(float yawDelta, float pitchDelta) {
        if (yawDelta != 0) {
            camPos.local = camPos.local * rotationY(yawDelta);
        }
        if (pitchDelta != 0) {
            camPos.local = camPos.local * rotationX(pitchDelta);
        }
        // Cheap to renormalize; without it the 3x3 orientation drifts after
        // many rotation accumulations and small skews compound.
        if (yawDelta != 0 || pitchDelta != 0) {
            camPos.local = camPos.local.renormalized();
        }
    }

    /// Translate camera in its local frame: dz negative = forward, dx positive = right.
    void moveCamera(float dx, float dy, float dz) {
        if (dx == 0 && dy == 0 && dz == 0) {
            return;
        }
        float[3] v = [dx, dy, dz];
        auto step = MIsometry!float.translationAlong(v);
        camPos.local = camPos.local * step;
        migratePosition();
        camPos.local = camPos.local.renormalized();
    }

    private void migratePosition() {
        // Repeatedly find a side facing the current local point and reflect across it
        // until we're inside the node bounds.
        foreach (_; 0 .. SIDE_COUNT) {
            auto col3 = MVector!float(
                camPos.local.mat.data[3][0], camPos.local.mat.data[3][1],
                camPos.local.mat.data[3][2], camPos.local.mat.data[3][3]);
            auto p = MPoint!float(col3);
            Side facing;
            bool any = false;
            foreach (sideIdx; 0 .. SIDE_COUNT) {
                auto side = cast(Side) sideIdx;
                if (sideIsFacing(side, p)) {
                    facing = side;
                    any = true;
                    break;
                }
            }
            if (!any) {
                return;
            }
            auto neighbor = graph.ensureNeighbor(camPos.node, facing);
            if (neighbor == NodeId.init) {
                return;
            }
            camPos.node = neighbor;
            camPos.local = sideReflection(facing) * camPos.local;
        }
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

        // Build the hyperbolic graph. Each frame we re-traverse from the camera
        // position to refresh the visible set; here we just allocate a generous
        // transforms VBO ceiling so we never need to resize.
        graph = Graph.create(cast(ubyte) dimension);
        // At radius 1.0 ~ 400 nodes * 20 chunks; at 2.0 the count climbs quickly in
        // hyperbolic space. Cap at 32k slots — the renderer truncates the BFS output
        // if it overflows.
        maxChunks = 32768;
        float[16][] transforms;
        transforms.length = maxChunks;
        currentChunkCount = 0;

        if (!voxels.init(core.physicalDevice, core.device, swapState.renderPass, empty, transforms,
                         core.graphicsQueue, swapState.commandPool,
                         extract.surfacesBuf.buffer)) {
            return false;
        }

        // Start the camera in the root node, offset into chunk A.
        auto chunkCenter = vertexChunkBoundingSphereCenter(Vertex.A);
        auto originPoint = MPoint!float.origin();
        camPos.node = NodeId.ROOT;
        camPos.local = MIsometry!float.translation(originPoint, chunkCenter);

        writeln("Renderer initialized successfully");
        return true;
    }

    void render(float dt) {
        time += dt;
        // Re-traverse nodes from current camera position and rebuild transforms.
        updateVisibleChunks();
        // Diagnostic: every second of sim time, print the local camera position so we
        // can see if it stays bounded after node migration.
        static int lastSecond = -1;
        int currentSecond = cast(int) time;
        if (currentSecond != lastSecond) {
            lastSecond = currentSecond;
            auto col3 = camPos.local.mat.data[3];
            float mip = col3[3] * col3[3] - col3[0] * col3[0] - col3[1] * col3[1] - col3[2] * col3[2];
            writefln("[t=%ss] node=%s local = (%.3f, %.3f, %.3f, %.3f)  -mip=%.4f  visible=%d  graph=%d",
                currentSecond, camPos.node, col3[0], col3[1], col3[2], col3[3], mip,
                currentChunkCount, graph.len);
            stdout.flush();
        }
        auto extent = swapState.extent;
        float aspect = cast(float) extent.width / cast(float) extent.height;
        // Proper hypermine projection: Beltrami-Klein perspective into unit ball.
        auto frustum = Frustum.fromVfov(45.0f * (cast(float) PI / 180.0f), aspect);
        auto proj = frustum.projection(1.0e-4f);
        // camPos.local maps camera-local frame to node-local frame, so the view
        // matrix is its inverse — applied as a single isometry (orientation already
        // baked in).
        auto worldToCam = camPos.local.inverse();
        float[16] view = matToFlat(worldToCam.mat);
        auto vp = matMul(proj, view);
        float[16] invp = 0;
        // Light direction fixed in camera frame ("above-forward"), transformed
        // to node-local frame via camPos.local so it stays stable across
        // node migrations.
        import std.math : sqrt;
        float[4] lightCam = [0.3f, 0.8f, 0.4f, 0]; // camera-relative
        float[4] lightNode;
        foreach (row; 0 .. 4) {
            lightNode[row] = 0;
            foreach (k; 0 .. 4) {
                lightNode[row] += camPos.local.mat.data[k][row] * lightCam[k];
            }
        }
        // Normalize xyz
        float llen = sqrt(lightNode[0]*lightNode[0] + lightNode[1]*lightNode[1] + lightNode[2]*lightNode[2]);
        if (llen > 0) {
            foreach (i; 0 .. 3) {
                lightNode[i] /= llen;
            }
        }
        lightNode[3] = 0;
        voxels.updateCommonUbo(core.device, vp, invp, 0.0f, time, lightNode);

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
            currentChunkCount,
            dimension,
            &extract,
        );
    }

    private void updateVisibleChunks() {
        ensureNearby(graph, camPos.node, camPos.local, viewRadius);
        auto nodes = nearbyNodes(graph, camPos.node, camPos.local, viewRadius);
        uint count = cast(uint)(nodes.length * VERTEX_COUNT);
        if (count > maxChunks) {
            count = maxChunks;
        }
        // Map the transforms VBO and overwrite.
        void* mapped;
        vkMapMemory(core.device, voxels.transformsVbo.memory, 0, count * 64, 0, &mapped);
        auto buf = cast(float*) mapped;
        uint idx = 0;
        outer: foreach (nn; nodes) {
            foreach (i; 0 .. VERTEX_COUNT) {
                auto v = cast(Vertex) i;
                auto m = nn.transform.mat * vertexChunkToNode(v);
                foreach (col; 0 .. 4) {
                    foreach (row; 0 .. 4) {
                        buf[idx * 16 + col * 4 + row] = m.data[col][row];
                    }
                }
                idx++;
                if (idx >= maxChunks) {
                    break outer;
                }
            }
        }
        vkUnmapMemory(core.device, voxels.transformsVbo.memory);
        currentChunkCount = idx;
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

private float[16] matToFlat(M)(M m) {
    float[16] r;
    foreach (col; 0 .. 4) {
        foreach (row; 0 .. 4) {
            r[col * 4 + row] = m.data[col][row];
        }
    }
    return r;
}

private MIsometry!float rotationY(float angle) {
    import common.math : Matrix4;
    float c = cos(angle);
    float s = sin(angle);
    Matrix4!float m;
    m.data[0][0] = c;  m.data[2][0] = -s;
    m.data[1][1] = 1;
    m.data[0][2] = s;  m.data[2][2] = c;
    m.data[3][3] = 1;
    return MIsometry!float(m);
}

private MIsometry!float rotationX(float angle) {
    import common.math : Matrix4;
    float c = cos(angle);
    float s = sin(angle);
    Matrix4!float m;
    m.data[0][0] = 1;
    m.data[1][1] = c;  m.data[2][1] = s;
    m.data[1][2] = -s; m.data[2][2] = c;
    m.data[3][3] = 1;
    return MIsometry!float(m);
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
    clears[0].color.float32 = [0.52f, 0.70f, 0.85f, 1.0f]; // sky blue
    // Reverse-Z: far plane = 0.0
    clears[1].depthStencil.depth = 0.0f;

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
