module client.graphics.renderer;

import core.math : sqrt;
import core.stdc.math : logf, powf;
import core.stdc.stdlib : calloc, free;
import core.stdc.string : memcpy, memset;
import bindings.platform : Display, VK_ERROR_OUT_OF_DATE_KHR, VK_PIPELINE_BIND_POINT_GRAPHICS, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, VK_SHADER_STAGE_VERTEX_BIT, VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, VK_STRUCTURE_TYPE_PRESENT_INFO_KHR, VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO, VK_STRUCTURE_TYPE_SUBMIT_INFO, VK_SUBOPTIMAL_KHR, VK_SUBPASS_CONTENTS_INLINE, VK_SUCCESS, VkClearValue, VkCommandBuffer, VkCommandBufferBeginInfo, VkDescriptorSet, VkDeviceSize, VkExtent2D, VkPipelineStageFlags, VkPresentInfoKHR, VkRect2D, VkRenderPassBeginInfo, VkResult, VkSubmitInfo, VkViewport, Window, vkAcquireNextImageKHR, vkBeginCommandBuffer, vkCmdBeginRenderPass, vkCmdBindDescriptorSets, vkCmdBindPipeline, vkCmdBindVertexBuffers, vkCmdDrawIndirect, vkCmdEndRenderPass, vkCmdNextSubpass, vkCmdPushConstants, vkCmdSetScissor, vkCmdSetViewport, vkDeviceWaitIdle, vkEndCommandBuffer, vkQueuePresentKHR, vkQueueSubmit, vkResetCommandBuffer, vkResetFences, vkWaitForFences;
import client.graphics.base : SwapchainState;
import client.graphics.core : VulkanCore;
import client.graphics.fog : FogPipeline;
import client.graphics.frustum : FRUSTUM_PLANE_COUNT, Frustum, frustumFromVerticalFov, sphereOutside;
import client.graphics.highlight : HighlightPipeline;
import client.graphics.pipeline : VULKAN_TRUE;
import client.graphics.voxels.surface : SurfacePipeline;
import client.graphics.voxels.surface_extraction : EXTRACT_CONCURRENCY, ExtractTask, INDIRECT_SIZE, MATRIX_BYTES, MATRIX_FLOATS, MAX_RENDER_SLOTS, SLOT_TASK_BYTES, SurfaceExtraction;
import client.local_world : LocalWorld, castCenterRay;
import common.array : Array;
import common.dodeca : BOUNDING_SPHERE_RADIUS, CHUNK_BOUNDING_SPHERE_RADIUS, VERTEX_COUNT, Vertex, vertexChunkBoundingSphereCenter, vertexChunkToNode;
import common.graph : NO_SLOT;
import common.graph_ray_casting : GraphCastHit;
import common.math : MDirection, MIsometry, MPoint, MVector, Matrix4, PI, isNan;
import common.node : Chunk, ChunkState, Node;

enum float VERTICAL_FOV_RADIANS = 45.0f * (PI / 180.0f);
enum float NEAR_PLANE = 1.0e-4f;
enum float FOG_VISIBILITY_THRESHOLD = 1e-3f;
enum float FOG_EXPONENT = 5.0f;
enum float FOG_DISTANCE_SCALE = 75.0f;
enum float NODE_CULL_RADIUS = BOUNDING_SPHERE_RADIUS + CHUNK_BOUNDING_SPHERE_RADIUS;
enum float CLEAR_DEPTH = 0.0f;
enum uint NO_RENDER_SLOT = uint.max;
enum uint NO_OWNER = uint.max;
enum uint SLOT_TASK_WORDS = 4;
enum uint DIMENSION_PUSH_BYTES = 4;
enum ulong NO_TIMEOUT = ulong.max;

immutable float[4] LIGHT_DIRECTION_CAMERA = [
    0.3f,
    0.8f,
    0.4f,
    0.0f,
];

immutable float[4] CLEAR_COLOR = [
    0.5f,
    0.65f,
    0.9f,
    1.0f,
];

struct RenderChunk {
    uint slot = NO_RENDER_SLOT;
    uint generation;
    bool hasData;
}

struct HighlightTarget {
    float[16] mvp;
    float[3] voxel;
    bool found;
}

struct Renderer {
    VulkanCore core;
    SwapchainState swapchain;
    SurfacePipeline voxels;
    SurfaceExtraction extraction;
    FogPipeline fog;
    HighlightPipeline highlight;
    ExtractTask[EXTRACT_CONCURRENCY] tasks;
    Array!RenderChunk chunks;
    uint* freeSlots;
    uint* activeSlots;
    uint* slotOwners;
    bool* slotUsed;
    float* nodeTransforms;
    uint* slotTasks;
    float time = 0;
    uint dimension;
    uint nextSlot;
    uint freeCount;
    uint activeCount;
    uint taskCount;
    uint nodeCount;

    bool setup(Display* display, Window window, ubyte chunkDimension) {
        dimension = chunkDimension;
        freeSlots = cast(uint*) calloc(MAX_RENDER_SLOTS, uint.sizeof);
        activeSlots = cast(uint*) calloc(MAX_RENDER_SLOTS, uint.sizeof);
        slotOwners = cast(uint*) calloc(MAX_RENDER_SLOTS, uint.sizeof);
        memset(slotOwners, 0xff, MAX_RENDER_SLOTS * uint.sizeof);
        slotUsed = cast(bool*) calloc(MAX_RENDER_SLOTS, bool.sizeof);
        nodeTransforms = cast(float*) calloc(MAX_RENDER_SLOTS, MATRIX_BYTES);
        slotTasks = cast(uint*) calloc(MAX_RENDER_SLOTS, SLOT_TASK_BYTES);
        bool ok = core.setup(display, window);
        if (ok) {
            ok = swapchain.setup(core.physicalDevice, core.device, core.surface, core.graphicsQueueFamily);
        }
        if (ok) {
            ok = extraction.setup(core.physicalDevice, core.device, dimension);
        }
        if (ok) {
            ok = voxels.setup(core.physicalDevice, core.device, swapchain.renderPass, core.graphicsQueue, swapchain.commandPool, extraction.facesBuffer.buffer, swapchain.depthView, MAX_RENDER_SLOTS);
        }
        if (ok) {
            ok = fog.setup(core.device, swapchain.renderPass, voxels.commonLayout);
        }
        if (ok) {
            ok = highlight.setup(core.device, swapchain.renderPass);
        }
        if (ok) {
            extraction.bindTransformOutput(core.device, voxels.transformsVbo.buffer);
        }
        return ok;
    }

    void render(LocalWorld* world, float dt) {
        time += dt;
        bool ready = true;
        if (swapchain.extent.width == 0 || swapchain.extent.height == 0) {
            ready = recreateSwapchain();
        }
        if (ready) {
            renderFrame(world);
        }
    }

    void renderFrame(LocalWorld* world) {
        vkWaitForFences(core.device, 1, &swapchain.inFlightFence, VULKAN_TRUE, NO_TIMEOUT);
        VkExtent2D extent = swapchain.extent;
        Frustum frustum = frustumFromVerticalFov(VERTICAL_FOV_RADIANS, cast(float) extent.width / cast(float) extent.height);
        MIsometry!float cameraInverse = world.cameraPosition.local.inverse();
        collectVisibleChunks(world, cameraInverse, frustum.planes());
        freeUnusedSlots();
        float[16] projection = frustum.projection(NEAR_PLANE);
        float[16] viewProjection = matrixMultiply(projection, flatten(cameraInverse.mat));
        HighlightTarget target = findHighlightTarget(world, viewProjection);
        voxels.updateCommonUbo(core.device, viewProjection, matrixInverse(projection), powf(logf(1.0f / FOG_VISIBILITY_THRESHOLD), 1.0f / FOG_EXPONENT) / FOG_DISTANCE_SCALE, time, lightDirection(world.cameraPosition.local));
        uint imageIndex;
        VkResult acquired = vkAcquireNextImageKHR(core.device, swapchain.swapchain, NO_TIMEOUT, swapchain.imageAvailableSemaphore, null, &imageIndex);
        if (acquired == VK_ERROR_OUT_OF_DATE_KHR) {
            recreateSwapchain();
        } else if (acquired == VK_SUCCESS || acquired == VK_SUBOPTIMAL_KHR) {
            vkResetFences(core.device, 1, &swapchain.inFlightFence);
            recordCommands(imageIndex, target);
            submitAndPresent(imageIndex);
        }
    }

    uint takeSlot() {
        uint result = NO_RENDER_SLOT;
        if (freeCount > 0) {
            freeCount -= 1;
            result = freeSlots[freeCount];
        } else if (nextSlot < MAX_RENDER_SLOTS) {
            result = nextSlot;
            nextSlot += 1;
        }
        return result;
    }

    void collectVisibleChunks(LocalWorld* world, MIsometry!float cameraInverse, MDirection!float[FRUSTUM_PLANE_COUNT] planes) {
        taskCount = 0;
        activeCount = 0;
        nodeCount = 0;
        memset(slotUsed, 0, MAX_RENDER_SLOTS * bool.sizeof);
        if (chunks.length < world.graph.nodeCount * VERTEX_COUNT) {
            size_t previous = chunks.length;
            chunks.resize(world.graph.nodeCount * VERTEX_COUNT);
            foreach (i; previous .. chunks.length) {
                chunks.ptr[i] = RenderChunk.init;
            }
        }
        void* voxelsMapped = null;
        foreach (nearbyNode; world.cachedNodes) {
            MPoint!float nodeCenter = MPoint!float(MVector!float(nearbyNode.transform.mat.data[3][0], nearbyNode.transform.mat.data[3][1], nearbyNode.transform.mat.data[3][2], nearbyNode.transform.mat.data[3][3]));
            if (nearbyNode.slot != NO_SLOT && !sphereOutside(planes[], cameraInverse * nodeCenter, NODE_CULL_RADIUS)) {
                uint nodeIndex = nodeCount;
                bool nodeUploaded = false;
                nodeCount += 1;
                Node* node = world.graph.nodeAt(nearbyNode.slot);
                foreach (vertexIndex; 0 .. VERTEX_COUNT) {
                    Vertex vertex = cast(Vertex) vertexIndex;
                    Chunk* chunk = &node.chunks[vertex];
                    uint chunkIndex = nearbyNode.slot * VERTEX_COUNT + vertexIndex;
                    RenderChunk* entry = &chunks.ptr[chunkIndex];
                    if (chunk.state == ChunkState.Populated && !chunk.voxels.isSolid() && !sphereOutside(planes[], cameraInverse * (nearbyNode.transform * vertexChunkBoundingSphereCenter(vertex)), CHUNK_BOUNDING_SPHERE_RADIUS)) {
                        if (entry.slot == NO_RENDER_SLOT) {
                            entry.slot = takeSlot();
                            entry.hasData = false;
                            if (entry.slot != NO_RENDER_SLOT) {
                                slotOwners[entry.slot] = chunkIndex;
                            }
                        }
                        if (entry.slot != NO_RENDER_SLOT && (!entry.hasData || entry.generation != chunk.generation) && taskCount < EXTRACT_CONCURRENCY) {
                            if (voxelsMapped is null) {
                                voxelsMapped = extraction.mapVoxels(core.device);
                            }
                            extraction.uploadVoxels(voxelsMapped, taskCount, cast(const(ushort)[]) chunk.voxels.denseData);
                            tasks[taskCount] = ExtractTask(extraction.indirectOffset(entry.slot), extraction.faceOffset(entry.slot), taskCount, entry.slot);
                            taskCount += 1;
                            entry.generation = chunk.generation;
                            entry.hasData = true;
                        }
                        if (entry.slot != NO_RENDER_SLOT && entry.hasData) {
                            if (!nodeUploaded) {
                                memcpy(nodeTransforms + nodeIndex * MATRIX_FLOATS, flatten(nearbyNode.transform.mat).ptr, MATRIX_BYTES);
                                nodeUploaded = true;
                            }
                            uint[SLOT_TASK_WORDS] task = [
                                nodeIndex,
                                vertexIndex,
                                entry.slot,
                                0,
                            ];
                            memcpy(slotTasks + activeCount * SLOT_TASK_WORDS, task.ptr, SLOT_TASK_BYTES);
                            slotUsed[entry.slot] = true;
                            activeSlots[activeCount] = entry.slot;
                            activeCount += 1;
                        }
                    }
                }
            }
        }
        if (voxelsMapped !is null) {
            extraction.unmapVoxels(core.device);
        }
        memcpy(extraction.nodeTransformsMapped, nodeTransforms, nodeCount * MATRIX_BYTES);
        memcpy(extraction.slotTasksMapped, slotTasks, activeCount * SLOT_TASK_BYTES);
    }

    void freeUnusedSlots() {
        foreach (slot; 0 .. nextSlot) {
            if (slotOwners[slot] != NO_OWNER && !slotUsed[slot]) {
                chunks.ptr[slotOwners[slot]] = RenderChunk.init;
                slotOwners[slot] = NO_OWNER;
                freeSlots[freeCount] = slot;
                freeCount += 1;
            }
        }
    }

    HighlightTarget findHighlightTarget(LocalWorld* world, float[16] viewProjection) {
        HighlightTarget target;
        GraphCastHit hit = castCenterRay(world);
        if (!isNan(hit.tanhDistance)) {
            foreach (nearbyNode; world.cachedNodes) {
                if (!target.found && nearbyNode.id == hit.chunk.node) {
                    target.mvp = matrixMultiply(viewProjection, matrixMultiply(flatten(nearbyNode.transform.mat), flatten(vertexChunkToNode(hit.chunk.vertex))));
                    target.voxel = [
                        cast(float) hit.voxelCoords.data[0],
                        cast(float) hit.voxelCoords.data[1],
                        cast(float) hit.voxelCoords.data[2],
                    ];
                    target.found = true;
                }
            }
        }
        return target;
    }

    void recordCommands(uint imageIndex, HighlightTarget target) {
        VkCommandBuffer commands = swapchain.commandBuffer;
        vkResetCommandBuffer(commands, 0);
        VkCommandBufferBeginInfo beginInfo;
        beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        vkBeginCommandBuffer(commands, &beginInfo);
        if (taskCount > 0) {
            extraction.recordExtract(core.device, commands, tasks[0 .. taskCount]);
        }
        if (activeCount > 0) {
            extraction.recordTransformCompute(commands, activeCount, voxels.transformsVbo.buffer);
            extraction.recordPackIndirect(commands, activeSlots[0 .. activeCount]);
        }
        VkClearValue[2] clears;
        clears[0].color.float32 = CLEAR_COLOR;
        clears[1].depthStencil.depth = CLEAR_DEPTH;
        VkRenderPassBeginInfo passInfo;
        passInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
        passInfo.renderPass = swapchain.renderPass;
        passInfo.framebuffer = swapchain.framebuffers[imageIndex];
        passInfo.renderArea.extent = swapchain.extent;
        passInfo.clearValueCount = clears.length;
        passInfo.pClearValues = clears.ptr;
        vkCmdBeginRenderPass(commands, &passInfo, VK_SUBPASS_CONTENTS_INLINE);
        VkViewport viewport = VkViewport(0, 0, cast(float) swapchain.extent.width, cast(float) swapchain.extent.height, 0, 1);
        vkCmdSetViewport(commands, 0, 1, &viewport);
        VkRect2D scissor;
        scissor.extent = swapchain.extent;
        vkCmdSetScissor(commands, 0, 1, &scissor);
        vkCmdBindPipeline(commands, VK_PIPELINE_BIND_POINT_GRAPHICS, voxels.pipeline);
        VkDescriptorSet[2] sets = [
            voxels.commonSet,
            voxels.staticSet,
        ];
        vkCmdBindDescriptorSets(commands, VK_PIPELINE_BIND_POINT_GRAPHICS, voxels.pipelineLayout, 0, sets.length, sets.ptr, 0, null);
        VkDeviceSize vertexOffset = 0;
        vkCmdBindVertexBuffers(commands, 0, 1, &voxels.transformsVbo.buffer, &vertexOffset);
        vkCmdPushConstants(commands, voxels.pipelineLayout, VK_SHADER_STAGE_VERTEX_BIT, 0, DIMENSION_PUSH_BYTES, &dimension);
        if (activeCount > 0) {
            vkCmdDrawIndirect(commands, extraction.packedIndirectBuffer.buffer, 0, activeCount, INDIRECT_SIZE);
        }
        if (target.found) {
            highlight.draw(commands, target.mvp, target.voxel, cast(float) dimension);
        }
        vkCmdNextSubpass(commands, VK_SUBPASS_CONTENTS_INLINE);
        fog.draw(commands, voxels.commonSet);
        vkCmdEndRenderPass(commands);
        vkEndCommandBuffer(commands);
    }

    void submitAndPresent(uint imageIndex) {
        VkPipelineStageFlags waitStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        VkSubmitInfo submitInfo;
        submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submitInfo.waitSemaphoreCount = 1;
        submitInfo.pWaitSemaphores = &swapchain.imageAvailableSemaphore;
        submitInfo.pWaitDstStageMask = &waitStage;
        submitInfo.commandBufferCount = 1;
        submitInfo.pCommandBuffers = &swapchain.commandBuffer;
        submitInfo.signalSemaphoreCount = 1;
        submitInfo.pSignalSemaphores = &swapchain.renderFinishedSemaphore;
        vkQueueSubmit(core.graphicsQueue, 1, &submitInfo, swapchain.inFlightFence);
        VkPresentInfoKHR presentInfo;
        presentInfo.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
        presentInfo.waitSemaphoreCount = 1;
        presentInfo.pWaitSemaphores = &swapchain.renderFinishedSemaphore;
        presentInfo.swapchainCount = 1;
        presentInfo.pSwapchains = &swapchain.swapchain;
        presentInfo.pImageIndices = &imageIndex;
        VkResult presented = vkQueuePresentKHR(core.graphicsQueue, &presentInfo);
        if (presented == VK_ERROR_OUT_OF_DATE_KHR || presented == VK_SUBOPTIMAL_KHR) {
            recreateSwapchain();
        }
    }

    bool recreateSwapchain() {
        bool ok = swapchain.recreate(core.device);
        if (ok) {
            voxels.updateDepthDescriptor(core.device, swapchain.depthView);
        }
        return ok;
    }

    void cleanup() {
        if (core.device !is null) {
            vkDeviceWaitIdle(core.device);
            highlight.cleanup(core.device);
            fog.cleanup(core.device);
            voxels.cleanup(core.device);
            extraction.cleanup(core.device);
            swapchain.cleanup(core.device);
        }
        core.cleanup();
        chunks.release();
        free(freeSlots);
        free(activeSlots);
        free(slotOwners);
        free(slotUsed);
        free(nodeTransforms);
        free(slotTasks);
    }
}

float[4] lightDirection(MIsometry!float cameraLocal) {
    float[4] result = 0;
    foreach (row; 0 .. 4) {
        foreach (k; 0 .. 4) {
            result[row] += cameraLocal.mat.data[k][row] * LIGHT_DIRECTION_CAMERA[k];
        }
    }
    float length = sqrt(result[0] * result[0] + result[1] * result[1] + result[2] * result[2]);
    if (length > 0) {
        foreach (i; 0 .. 3) {
            result[i] /= length;
        }
    }
    result[3] = 0;
    return result;
}

float[16] flatten(Matrix4!float matrix) {
    float[16] result;
    foreach (column; 0 .. 4) {
        foreach (row; 0 .. 4) {
            result[column * 4 + row] = matrix.data[column][row];
        }
    }
    return result;
}

float[16] matrixMultiply(float[16] a, float[16] b) {
    float[16] result = 0;
    foreach (column; 0 .. 4) {
        foreach (row; 0 .. 4) {
            float sum = 0;
            foreach (k; 0 .. 4) {
                sum += a[k * 4 + row] * b[column * 4 + k];
            }
            result[column * 4 + row] = sum;
        }
    }
    return result;
}

float[16] matrixInverse(float[16] m) {
    float b00 = m[0] * m[5] - m[1] * m[4];
    float b01 = m[0] * m[6] - m[2] * m[4];
    float b02 = m[0] * m[7] - m[3] * m[4];
    float b03 = m[1] * m[6] - m[2] * m[5];
    float b04 = m[1] * m[7] - m[3] * m[5];
    float b05 = m[2] * m[7] - m[3] * m[6];
    float b06 = m[8] * m[13] - m[9] * m[12];
    float b07 = m[8] * m[14] - m[10] * m[12];
    float b08 = m[8] * m[15] - m[11] * m[12];
    float b09 = m[9] * m[14] - m[10] * m[13];
    float b10 = m[9] * m[15] - m[11] * m[13];
    float b11 = m[10] * m[15] - m[11] * m[14];
    float determinant = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06;
    float[16] result = m;
    if (determinant != 0) {
        float inverseDeterminant = 1.0f / determinant;
        result[0] = (m[5] * b11 - m[6] * b10 + m[7] * b09) * inverseDeterminant;
        result[1] = (-m[1] * b11 + m[2] * b10 - m[3] * b09) * inverseDeterminant;
        result[2] = (m[13] * b05 - m[14] * b04 + m[15] * b03) * inverseDeterminant;
        result[3] = (-m[9] * b05 + m[10] * b04 - m[11] * b03) * inverseDeterminant;
        result[4] = (-m[4] * b11 + m[6] * b08 - m[7] * b07) * inverseDeterminant;
        result[5] = (m[0] * b11 - m[2] * b08 + m[3] * b07) * inverseDeterminant;
        result[6] = (-m[12] * b05 + m[14] * b02 - m[15] * b01) * inverseDeterminant;
        result[7] = (m[8] * b05 - m[10] * b02 + m[11] * b01) * inverseDeterminant;
        result[8] = (m[4] * b10 - m[5] * b08 + m[7] * b06) * inverseDeterminant;
        result[9] = (-m[0] * b10 + m[1] * b08 - m[3] * b06) * inverseDeterminant;
        result[10] = (m[12] * b04 - m[13] * b02 + m[15] * b00) * inverseDeterminant;
        result[11] = (-m[8] * b04 + m[9] * b02 - m[11] * b00) * inverseDeterminant;
        result[12] = (-m[4] * b09 + m[5] * b07 - m[6] * b06) * inverseDeterminant;
        result[13] = (m[0] * b09 - m[1] * b07 + m[2] * b06) * inverseDeterminant;
        result[14] = (-m[12] * b03 + m[13] * b01 - m[14] * b00) * inverseDeterminant;
        result[15] = (m[8] * b03 - m[9] * b01 + m[10] * b00) * inverseDeterminant;
    }
    return result;
}
