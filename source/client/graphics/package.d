module client.graphics;

import std.stdio;
import std.math : sin, cos, sqrt, PI, log, pow, isNaN;
import std.typecons : Nullable;
import core.stdc.string : memcpy;
import bindings.vk;
import client.graphics.core;
import client.graphics.base;
import client.graphics.voxels;
import client.graphics.fog : FogPipeline;
import client.graphics.frustum : Frustum;
import client.worldgen_driver : WorldgenDriver;
import common.collision_math : Ray;
import common.dodeca : Vertex, Side, sideReflection, sideIsFacing;
import common.graph_ray_casting : GraphCastHit, rayCast;
import common.math : Matrix4, MPoint, MIsometry, MVector;
import common.graph : Graph, NodeId;
import common.node : Chunk, ChunkId, ChunkState;
import common.proto : Position;
import common.traversal : ensureAndCollectNearby, NearbyNode;
import common.voxel_math : Coords, CoordSign;
import common.world : Material;

struct Renderer {
    VulkanCore core;
    SwapchainState swapState;
    SurfacePipeline voxels;
    SurfaceExtraction extract;
    FogPipeline fog;
    WorldgenDriver worldgenDriver;
    uint dimension = 12;
    float time = 0;
    Position camPos;
    Graph graph;
    float viewRadius = 5.0f;
    float renderRadius = 4.5f;

    uint maxSlots = 2^^16;
    uint concurrency = 128;

    uint[ChunkId] slotMap;
    uint[ChunkId] slotGeneration;
    uint nextSlot = 0;
    uint[] freeSlotsBuf;
    uint freeCount;
    uint[] activeSlotsBuf;
    uint activeCount;
    ExtractTask[] tasksBuf;
    uint tasksLen;

    float[] nodeTfLocal;
    uint[] slotTaskLocal;
    ubyte[] slotUsedBuf;
    ChunkId[] removeBuf;

    Nullable!uint lastLoggedSecond;
    NearbyNode[] cachedNodes;

    void rotateCamera(float yawDelta, float pitchDelta, float rollDelta = 0) {
        if (yawDelta != 0) {
            camPos.local = camPos.local * rotationY(yawDelta);
        }
        if (pitchDelta != 0) {
            camPos.local = camPos.local * rotationX(pitchDelta);
        }
        if (rollDelta != 0) {
            camPos.local = camPos.local * rotationZ(rollDelta);
        }
        if (yawDelta != 0 || pitchDelta != 0 || rollDelta != 0) {
            camPos.local = camPos.local.renormalized();
        }
    }

    void moveCamera(float dx, float dy, float dz) {
        if (dx == 0 && dy == 0 && dz == 0) {
            return;
        }
        float[3] v = [dx, dy, dz];
        camPos.local = camPos.local * MIsometry!float.translationAlong(v);
        migratePosition();
        camPos.local = camPos.local.renormalized();
    }

    void migratePosition() {
        foreach (_; 0 .. 12) {
            MVector!float col3 = MVector!float(
                camPos.local.mat.data[3][0], camPos.local.mat.data[3][1],
                camPos.local.mat.data[3][2], camPos.local.mat.data[3][3]);
            MPoint!float p = MPoint!float(col3);
            bool any = false;
            Side facing;
            foreach (sideIdx; 0 .. 12) {
                Side side = cast(Side) sideIdx;
                if (sideIsFacing(side, p)) {
                    facing = side;
                    any = true;
                    break;
                }
            }
            if (!any) {
                return;
            }
            NodeId neighbor = graph.ensureNeighbor(camPos.node, facing);
            if (neighbor == NodeId.init) {
                return;
            }
            camPos.node = neighbor;
            camPos.local = sideReflection(facing) * camPos.local;
        }
    }

    bool init(void* window) {
        freeSlotsBuf = new uint[maxSlots];
        activeSlotsBuf = new uint[maxSlots];
        slotUsedBuf = new ubyte[maxSlots];
        removeBuf = new ChunkId[maxSlots];
        tasksBuf = new ExtractTask[concurrency];

        if (!core.init(window)) {
            return false;
        }
        if (!swapState.init(core.physicalDevice, core.device, core.surface, core.graphicsQueueFamily)) {
            return false;
        }

        graph = Graph.create(cast(ubyte) dimension);

        if (!extract.init(core.physicalDevice, core.device, dimension, concurrency, maxSlots)) {
            return false;
        }

        Surface[] empty;
        float[16][] transforms;
        transforms.length = maxSlots;

        if (!voxels.init(core.physicalDevice, core.device, swapState.renderPass,
                         empty, transforms,
                         core.graphicsQueue, swapState.commandPool,
                         extract.facesBuf.buffer,
                         swapState.depthView)) {
            return false;
        }

        if (!fog.init(core.device, swapState.renderPass, voxels.commonLayout)) {
            return false;
        }

        if (extract.tfReady) {
            extract.bindTransformOutput(core.device, voxels.transformsVbo.buffer);
            nodeTfLocal = new float[extract.maxNodes * 16];
            slotTaskLocal = new uint[maxSlots * 4];
        }

        worldgenDriver = WorldgenDriver.create();

        camPos.node = NodeId.ROOT;
        camPos.local = MIsometry!float.translationAlong([0.0f, 1.4f, 0.0f]);

        writeln("Renderer initialized successfully");
        return true;
    }

    void render(float dt) {
        time += dt;

        cachedNodes = ensureAndCollectNearby(graph, camPos.node, camPos.local, renderRadius);
        worldgenDriver.drive(cachedNodes, camPos.local, renderRadius, graph, cast(ubyte) dimension);

        tasksLen = 0;
        activeCount = 0;

        vkWaitForFences(core.device, 1, &swapState.inFlightFence, 1, ulong.max);

        slotUsedBuf[] = 0;

        VkExtent2D extent = swapState.extent;
        float aspect = cast(float) extent.width / cast(float) extent.height;
        Frustum frustum = Frustum.fromVfov(45.0f * (PI / 180.0f), aspect);
        MIsometry!float camInverse = camPos.local.inverse();

        void* voxelsMapped = null;
        uint nodeIndex = 0;

        foreach (ref nn; cachedNodes) {
            if (!graph.contains(nn.id)) {
                continue;
            }
            uint thisNodeIndex = nodeIndex;
            bool nodeUploaded = false;
            nodeIndex++;

            foreach (vIdx; 0 .. 20) {
                Vertex v = cast(Vertex) vIdx;
                Chunk* c = &graph[nn.id].chunks.values[v];
                if (c.state != ChunkState.Populated || c.voxels.isSolid()) {
                    continue;
                }

                ChunkId chunkId = ChunkId(nn.id, v);
                uint slot;
                bool needsExtract = false;
                bool slotHasData = false;

                if (uint* p = chunkId in slotMap) {
                    slot = *p;
                    uint* gen = chunkId in slotGeneration;
                    if (gen is null || *gen != c.generation) {
                        needsExtract = true;
                    }
                    slotHasData = gen !is null;
                } else {
                    needsExtract = true;
                    if (freeCount > 0) {
                        freeCount--;
                        slot = freeSlotsBuf[freeCount];
                    } else if (nextSlot < maxSlots) {
                        slot = nextSlot++;
                    } else {
                        continue;
                    }
                    slotMap[chunkId] = slot;
                }

                if (needsExtract && tasksLen < concurrency) {
                    if (voxelsMapped is null) {
                        voxelsMapped = extract.mapVoxels(core.device);
                    }
                    extract.uploadVoxels(
                        voxelsMapped, tasksLen,
                        cast(const(ushort)[]) c.voxels.denseData);

                    tasksBuf[tasksLen] = ExtractTask(
                        extract.indirectOffset(slot),
                        extract.faceOffset(slot),
                        tasksLen,
                        slot);
                    tasksLen++;
                    slotGeneration[chunkId] = c.generation;
                    slotHasData = true;
                }

                if (!slotHasData) {
                    continue;
                }

                if (!nodeUploaded) {
                    foreach (col; 0 .. 4) {
                        foreach (row; 0 .. 4) {
                            nodeTfLocal[thisNodeIndex * 16 + col * 4 + row] = nn.transform.mat.data[col][row];
                        }
                    }
                    nodeUploaded = true;
                }
                slotTaskLocal[activeCount * 4] = thisNodeIndex;
                slotTaskLocal[activeCount * 4 + 1] = vIdx;
                slotTaskLocal[activeCount * 4 + 2] = slot;
                slotTaskLocal[activeCount * 4 + 3] = 0;
                slotUsedBuf[slot] = true;
                activeSlotsBuf[activeCount++] = slot;
            }
        }
        if (voxelsMapped !is null) {
            extract.unmapVoxels(core.device);
        }

        if (nodeIndex > 0) {
            memcpy(extract.nodeTransformsMapped, nodeTfLocal.ptr, nodeIndex * 64);
        }
        if (activeCount > 0) {
            memcpy(extract.slotTasksMapped, slotTaskLocal.ptr, activeCount * 16);
        }

        uint removeLen = 0;
        foreach (cid, slot; slotMap) {
            if (!slotUsedBuf[slot]) {
                removeBuf[removeLen++] = cid;
                freeSlotsBuf[freeCount++] = slot;
            }
        }
        foreach (i; 0 .. removeLen) {
            slotMap.remove(removeBuf[i]);
            slotGeneration.remove(removeBuf[i]);
        }

        uint currentSecond = cast(uint) time;
        if (lastLoggedSecond.isNull || currentSecond != lastLoggedSecond.get) {
            lastLoggedSecond = currentSecond;
            writefln("[t=%ss] active=%d slots=%d new=%d graph=%d",
                currentSecond, activeCount, nextSlot,
                tasksLen, graph.len);
            stdout.flush();
        }

        float[16] proj = frustum.projection(1.0e-4f);
        float[16] view = matToFlat(camPos.local.inverse().mat);
        float[16] vp = matMul(proj, view);
        float[16] invp = matInverse(proj);
        float fogDensity = pow(log(1.0f / 1e-3f), 1.0f / 5.0f) / 75.0f;

        float[4] lightCam = [0.3f, 0.8f, 0.4f, 0];
        float[4] lightNode;
        foreach (row; 0 .. 4) {
            lightNode[row] = 0;
            foreach (k; 0 .. 4) {
                lightNode[row] += camPos.local.mat.data[k][row] * lightCam[k];
            }
        }
        float llen = sqrt(
            lightNode[0] * lightNode[0] +
            lightNode[1] * lightNode[1] +
            lightNode[2] * lightNode[2]);
        if (llen > 0) {
            foreach (i; 0 .. 3) {
                lightNode[i] /= llen;
            }
        }
        lightNode[3] = 0;
        voxels.updateCommonUbo(core.device, vp, invp, fogDensity, time, lightNode);

        vkResetFences(core.device, 1, &swapState.inFlightFence);
        uint imageIndex;
        vkAcquireNextImageKHR(core.device, swapState.swapchain, ulong.max,
            swapState.imageAvailableSemaphore, VK_NULL_HANDLE, &imageIndex);

        VkCommandBuffer cmd = swapState.commandBuffer;
        vkResetCommandBuffer(cmd, 0);
        VkCommandBufferBeginInfo bi;
        bi.sType = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        vkBeginCommandBuffer(cmd, &bi);

        if (tasksLen > 0) {
            extract.recordExtract(core.device, cmd, tasksBuf[0 .. tasksLen]);
        }
        if (extract.tfReady && activeCount > 0) {
            extract.recordTransformCompute(cmd, activeCount, voxels.transformsVbo.buffer);
        }

        VkClearValue[2] clears;
        clears[0].color.float32 = [0.5f, 0.65f, 0.9f, 1.0f];
        clears[1].depthStencil.depth = 0.0f;

        VkRenderPassBeginInfo rp;
        rp.sType = VkStructureType.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
        rp.renderPass = swapState.renderPass;
        rp.framebuffer = swapState.framebuffers[imageIndex];
        rp.renderArea.extent = extent;
        rp.clearValueCount = 2;
        rp.pClearValues = clears.ptr;
        vkCmdBeginRenderPass(cmd, &rp, VkSubpassContents.VK_SUBPASS_CONTENTS_INLINE);

        vkCmdBindPipeline(cmd, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS,
            voxels.pipeline);

        VkViewport viewport;
        viewport.x = 0;
        viewport.y = 0;
        viewport.width = cast(float) extent.width;
        viewport.height = cast(float) extent.height;
        viewport.minDepth = 0;
        viewport.maxDepth = 1;
        vkCmdSetViewport(cmd, 0, 1, &viewport);

        VkRect2D scissor;
        scissor.extent = extent;
        vkCmdSetScissor(cmd, 0, 1, &scissor);

        VkDescriptorSet[2] dsets = [voxels.commonSet, voxels.staticSet];
        vkCmdBindDescriptorSets(cmd,
            VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS,
            voxels.pipelineLayout, 0, 2, dsets.ptr, 0, null);

        VkDeviceSize vboOff = 0;
        vkCmdBindVertexBuffers(cmd, 0, 1, &voxels.transformsVbo.buffer, &vboOff);

        uint dim = dimension;
        vkCmdPushConstants(cmd, voxels.pipelineLayout,
            VkShaderStageFlagBits.VK_SHADER_STAGE_VERTEX_BIT, 0, 4, &dim);

        uint[] activeSlots = activeSlotsBuf[0 .. activeCount];
        if (activeCount > 0) {
            extract.recordPackIndirect(cmd, activeSlots);
            vkCmdDrawIndirect(cmd, extract.packedIndirectBuf.buffer,
                0, activeCount, INDIRECT_SIZE);
        }

        vkCmdNextSubpass(cmd, VkSubpassContents.VK_SUBPASS_CONTENTS_INLINE);
        fog.draw(cmd, fog.pipelineLayout, voxels.commonSet);

        vkCmdEndRenderPass(cmd);
        vkEndCommandBuffer(cmd);

        uint waitStage = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        VkSubmitInfo si;
        si.sType = VkStructureType.VK_STRUCTURE_TYPE_SUBMIT_INFO;
        si.waitSemaphoreCount = 1;
        si.pWaitSemaphores = &swapState.imageAvailableSemaphore;
        si.pWaitDstStageMask = &waitStage;
        si.commandBufferCount = 1;
        si.pCommandBuffers = &cmd;
        si.signalSemaphoreCount = 1;
        si.pSignalSemaphores = &swapState.renderFinishedSemaphore;
        vkQueueSubmit(core.graphicsQueue, 1, &si, swapState.inFlightFence);

        VkPresentInfoKHR pi;
        pi.sType = VkStructureType.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
        pi.waitSemaphoreCount = 1;
        pi.pWaitSemaphores = &swapState.renderFinishedSemaphore;
        pi.swapchainCount = 1;
        pi.pSwapchains = &swapState.swapchain;
        pi.pImageIndices = &imageIndex;
        vkQueuePresentKHR(core.graphicsQueue, &pi);
    }

    void breakBlock() {
        Ray ray = Ray.create(
            MPoint!float.origin(),
            MVector!float(0, 0, -1, 0).normalizedDirection());
        bool oob;
        GraphCastHit hit = rayCast(graph, camPos.node, camPos.local, ray, 5.0f, oob);
        if (isNaN(hit.tanhDistance)) {
            return;
        }
        Chunk* c = &graph[hit.chunk.node].chunks.values[hit.chunk.vertex];
        if (c.state != ChunkState.Populated) {
            return;
        }
        ulong idx = hit.voxelCoords.toIndex(cast(ubyte) dimension);
        c.voxels.dataMut(cast(ubyte) dimension)[idx] = Material.Void;
        c.generation++;
    }

    void placeBlock(ushort material) {
        Ray ray = Ray.create(
            MPoint!float.origin(),
            MVector!float(0, 0, -1, 0).normalizedDirection());
        bool oob;
        GraphCastHit hit = rayCast(graph, camPos.node, camPos.local, ray, 5.0f, oob);
        if (isNaN(hit.tanhDistance)) {
            return;
        }
        Chunk* c = &graph[hit.chunk.node].chunks.values[hit.chunk.vertex];
        if (c.state != ChunkState.Populated) {
            return;
        }
        ubyte[3] coords = hit.voxelCoords.data;
        if (hit.faceSign == CoordSign.Plus) {
            coords[hit.faceAxis] = cast(ubyte)(coords[hit.faceAxis] + 1);
        } else {
            coords[hit.faceAxis] = cast(ubyte)(coords[hit.faceAxis] - 1);
        }
        if (coords[hit.faceAxis] < dimension) {
            size_t idx = Coords(coords).toIndex(cast(ubyte) dimension);
            c.voxels.dataMut(cast(ubyte) dimension)[idx] = cast(Material) material;
            c.generation++;
        }
    }

    void cleanup() {
        if (core.device !is null) {
            vkDeviceWaitIdle(core.device);
            fog.cleanup(core.device);
            voxels.cleanup(core.device);
            extract.cleanup(core.device);
            swapState.cleanup(core.device);
        }
        core.cleanup();
    }
}

float[16] matToFlat(M)(M m) {
    float[16] r;
    foreach (col; 0 .. 4) {
        foreach (row; 0 .. 4) {
            r[col * 4 + row] = m.data[col][row];
        }
    }
    return r;
}

MIsometry!float rotationY(float angle) {
    float c = cos(angle);
    float s = sin(angle);
    Matrix4!float m;
    m.data[0][0] = c;
    m.data[2][0] = -s;
    m.data[1][1] = 1;
    m.data[0][2] = s;
    m.data[2][2] = c;
    m.data[3][3] = 1;
    return MIsometry!float(m);
}

MIsometry!float rotationX(float angle) {
    float c = cos(angle);
    float s = sin(angle);
    Matrix4!float m;
    m.data[0][0] = 1;
    m.data[1][1] = c;
    m.data[2][1] = s;
    m.data[1][2] = -s;
    m.data[2][2] = c;
    m.data[3][3] = 1;
    return MIsometry!float(m);
}

MIsometry!float rotationZ(float angle) {
    float c = cos(angle);
    float s = sin(angle);
    Matrix4!float m;
    m.data[0][0] = c;
    m.data[1][0] = -s;
    m.data[0][1] = s;
    m.data[1][1] = c;
    m.data[2][2] = 1;
    m.data[3][3] = 1;
    return MIsometry!float(m);
}

float[16] matMul(float[16] a, float[16] b) {
    float[16] r = 0;
    foreach (col; 0 .. 4) {
        foreach (row; 0 .. 4) {
            float s = 0;
            foreach (k; 0 .. 4) {
                s += a[k * 4 + row] * b[col * 4 + k];
            }
            r[col * 4 + row] = s;
        }
    }
    return r;
}

float[16] matInverse(float[16] m) {
    float a00 = m[0];
    float a01 = m[1];
    float a02 = m[2];
    float a03 = m[3];
    float a10 = m[4];
    float a11 = m[5];
    float a12 = m[6];
    float a13 = m[7];
    float a20 = m[8];
    float a21 = m[9];
    float a22 = m[10];
    float a23 = m[11];
    float a30 = m[12];
    float a31 = m[13];
    float a32 = m[14];
    float a33 = m[15];

    float b00 = a00 * a11 - a01 * a10;
    float b01 = a00 * a12 - a02 * a10;
    float b02 = a00 * a13 - a03 * a10;
    float b03 = a01 * a12 - a02 * a11;
    float b04 = a01 * a13 - a03 * a11;
    float b05 = a02 * a13 - a03 * a12;
    float b06 = a20 * a31 - a21 * a30;
    float b07 = a20 * a32 - a22 * a30;
    float b08 = a20 * a33 - a23 * a30;
    float b09 = a21 * a32 - a22 * a31;
    float b10 = a21 * a33 - a23 * a31;
    float b11 = a22 * a33 - a23 * a32;

    float det = b00 * b11 - b01 * b10 + b02 * b09
              + b03 * b08 - b04 * b07 + b05 * b06;
    if (det == 0) {
        return m;
    }
    float id = 1.0f / det;

    float[16] inv;
    inv[0] = (a11 * b11 - a12 * b10 + a13 * b09) * id;
    inv[1] = (-a01 * b11 + a02 * b10 - a03 * b09) * id;
    inv[2] = (a31 * b05 - a32 * b04 + a33 * b03) * id;
    inv[3] = (-a21 * b05 + a22 * b04 - a23 * b03) * id;
    inv[4] = (-a10 * b11 + a12 * b08 - a13 * b07) * id;
    inv[5] = (a00 * b11 - a02 * b08 + a03 * b07) * id;
    inv[6] = (-a30 * b05 + a32 * b02 - a33 * b01) * id;
    inv[7] = (a20 * b05 - a22 * b02 + a23 * b01) * id;
    inv[8] = (a10 * b10 - a11 * b08 + a13 * b06) * id;
    inv[9] = (-a00 * b10 + a01 * b08 - a03 * b06) * id;
    inv[10] = (a30 * b04 - a31 * b02 + a33 * b00) * id;
    inv[11] = (-a20 * b04 + a21 * b02 - a23 * b00) * id;
    inv[12] = (-a10 * b09 + a11 * b07 - a12 * b06) * id;
    inv[13] = (a00 * b09 - a01 * b07 + a02 * b06) * id;
    inv[14] = (-a30 * b03 + a31 * b01 - a32 * b00) * id;
    inv[15] = (a20 * b03 - a21 * b01 + a22 * b00) * id;
    return inv;
}
