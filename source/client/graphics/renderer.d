module client.graphics.renderer;

import core.stdc.math : logf, powf;
import core.sys.posix.time : CLOCK_MONOTONIC, clock_gettime, timespec;
import bindings.platform : Display, VK_ACCESS_HOST_READ_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_BUFFER_USAGE_TRANSFER_DST_BIT, VK_ERROR_OUT_OF_DATE_KHR, VK_IMAGE_ASPECT_COLOR_BIT, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, VK_PIPELINE_BIND_POINT_GRAPHICS, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_SHADER_STAGE_VERTEX_BIT, VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, VK_STRUCTURE_TYPE_MEMORY_BARRIER, VK_STRUCTURE_TYPE_PRESENT_INFO_KHR, VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO, VK_STRUCTURE_TYPE_SUBMIT_INFO, VK_SUBOPTIMAL_KHR, VK_SUBPASS_CONTENTS_INLINE, VK_SUCCESS, VkBufferImageCopy, VkClearValue, VkCommandBuffer, VkCommandBufferBeginInfo, VkDescriptorSet, VkDeviceSize, VkDrawIndirectCommand, VkExtent2D, VkExtent3D, VkImageSubresourceLayers, VkMemoryBarrier, VkPipelineStageFlags, VkPresentInfoKHR, VkRect2D, VkRenderPassBeginInfo, VkResult, VkSubmitInfo, VkViewport, Window, vkAcquireNextImageKHR, vkBeginCommandBuffer, vkCmdBeginRenderPass, vkCmdBindDescriptorSets, vkCmdBindPipeline, vkCmdBindVertexBuffers, vkCmdCopyImageToBuffer, vkCmdDrawIndirect, vkCmdEndRenderPass, vkCmdNextSubpass, vkCmdPipelineBarrier, vkCmdPushConstants, vkCmdSetScissor, vkCmdSetViewport, vkDeviceWaitIdle, vkEndCommandBuffer, vkQueuePresentKHR, vkQueueSubmit, vkResetCommandBuffer, vkResetFences, vkWaitForFences;
import client.graphics.base : SwapchainState;
import client.graphics.core : VulkanCore;
import client.graphics.crosshair : CrosshairPipeline;
import client.graphics.fog : FogPipeline;
import client.graphics.frustum : FRUSTUM_PLANE_COUNT, Frustum, frustumFromVerticalFov, sphereOutside;
import client.graphics.highlight : HighlightPipeline;
import client.graphics.pipeline : GpuBuffer, VULKAN_TRUE, createMappedBuffer, destroyBuffer;
import client.graphics.voxels.chunk_meshes : ChunkMeshes, TRANSFORM_FLOATS;
import client.graphics.voxels.surface : SurfacePipeline;
import client.local_world : LocalWorld, castCenterRay;
import common.chunk_neighbors : ChunkSlot;
import common.dodeca : BOUNDING_SPHERE_RADIUS, CHUNK_BOUNDING_SPHERE_RADIUS, VERTEX_COUNT, Vertex, vertexChunkBoundingSphereCenter, vertexChunkToNode;
import common.graph : NO_SLOT;
import common.graph_ray_casting : GraphCastHit;
import common.math : MDirection, MIsometry, MPoint, MVector, Matrix4, PI, isNan;
import common.node : Chunk, ChunkState, Node;

enum float VERTICAL_HALF_FOV_RADIANS = 45.0f * (PI / 180.0f);
enum float NEAR_PLANE = 1.0e-4f;
enum float FOG_VISIBILITY_THRESHOLD = 1e-3f;
enum float FOG_EXPONENT = 5.0f;
enum float NODE_CULL_RADIUS = BOUNDING_SPHERE_RADIUS + CHUNK_BOUNDING_SPHERE_RADIUS;
enum float CLEAR_DEPTH = 0.0f;
enum uint DIMENSION_PUSH_BYTES = 4;
enum ulong NO_TIMEOUT = ulong.max;
enum double MESH_BUDGET_MILLISECONDS = 1.0;
enum double NANOSECONDS_PER_MILLISECOND = 1e6;
enum double MILLISECONDS_PER_SECOND = 1e3;
enum uint PIXEL_BYTES = 4;
enum uint COFACTOR_COUNT = 12;

enum float SRGB_LINEAR_LIMIT = 0.04045f;
enum float SRGB_LINEAR_SLOPE = 12.92f;
enum float SRGB_OFFSET = 0.055f;
enum float SRGB_GAMMA = 2.4f;
enum uint COLOR_CHANNELS = 3;

immutable float[4] SKY_SRGB = [
    0.5f,
    0.65f,
    0.9f,
    1.0f,
];

struct HighlightTarget {
    float[16] mvp;
    float[3] voxel;
    bool found;
}

struct Renderer {
    VulkanCore core;
    SwapchainState swapchain;
    SurfacePipeline voxels;
    ChunkMeshes meshes;
    FogPipeline fog;
    HighlightPipeline highlight;
    CrosshairPipeline crosshair;
    GpuBuffer readback;
    float[TRANSFORM_FLOATS][VERTEX_COUNT] vertexMatrices;
    float[VERTEX_COUNT] vertexOrientations;
    float[4] skyLinear;
    uint dimension;

    bool setup(Display* display, Window window, ubyte chunkDimension) {
        prepare(chunkDimension);
        bool ok = core.setup(display, window);
        if (ok) {
            ok = swapchain.setup(core.physicalDevice, core.device, core.surface, core.graphicsQueueFamily);
        }
        return ok && setupPipelines();
    }

    bool setupOffscreen(VkExtent2D extent, ubyte chunkDimension) {
        prepare(chunkDimension);
        bool ok = core.setupOffscreen();
        if (ok) {
            ok = swapchain.setupOffscreen(core.physicalDevice, core.device, core.graphicsQueueFamily, extent);
        }
        if (ok) {
            readback = createMappedBuffer(core.physicalDevice, core.device, cast(VkDeviceSize) extent.width * extent.height * PIXEL_BYTES, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
            ok = readback.ready;
        }
        return ok && setupPipelines();
    }

    void prepare(ubyte chunkDimension) {
        dimension = chunkDimension;
        skyLinear = SKY_SRGB;
        foreach (channel; 0 .. COLOR_CHANNELS) {
            skyLinear[channel] = srgbToLinear(SKY_SRGB[channel]);
        }
        foreach (vertexIndex; 0 .. VERTEX_COUNT) {
            vertexMatrices[vertexIndex] = flatten(vertexChunkToNode(cast(Vertex) vertexIndex));
            vertexOrientations[vertexIndex] = determinant(vertexMatrices[vertexIndex]);
        }
    }

    bool setupPipelines() {
        bool ok = meshes.setup(core.physicalDevice, core.device, cast(ubyte) dimension);
        if (ok) {
            ok = voxels.setup(core.physicalDevice, core.device, swapchain.renderPass, core.graphicsQueue, swapchain.commandPool, swapchain.depthView);
        }
        if (ok) {
            voxels.bindFaces(core.device, meshes.faces.buffer);
            ok = fog.setup(core.device, swapchain.renderPass, voxels.commonLayout);
        }
        if (ok) {
            ok = highlight.setup(core.device, swapchain.renderPass);
        }
        if (ok) {
            ok = crosshair.setup(core.device, swapchain.renderPass);
        }
        return ok;
    }

    bool render(LocalWorld* world) {
        bool healthy = true;
        if (swapchainMinimized()) {
            healthy = recreateSwapchain();
        }
        if (healthy && !swapchainMinimized()) {
            healthy = renderFrame(world);
        }
        return healthy;
    }

    bool swapchainMinimized() const {
        return swapchain.extent.width == 0 || swapchain.extent.height == 0;
    }

    uint meshBacklog() const {
        return meshes.backlog;
    }

    bool renderFrame(LocalWorld* world) {
        bool ok = vkWaitForFences(core.device, 1, &swapchain.inFlightFence, VULKAN_TRUE, NO_TIMEOUT) == VK_SUCCESS;
        if (ok) {
            VkExtent2D extent = swapchain.extent;
            Frustum frustum = frustumFromVerticalFov(VERTICAL_HALF_FOV_RADIANS, cast(float) extent.width / cast(float) extent.height);
            MIsometry!float cameraInverse = world.cameraPosition.local.inverse();
            float[16] projection = frustum.projection(NEAR_PLANE);
            float[16] viewProjection = matrixMultiply(projection, flatten(cameraInverse.mat));
            ok = collectChunks(world, cameraInverse, frustum.planes(), determinant(viewProjection));
            HighlightTarget target = findHighlightTarget(world, viewProjection);
            voxels.updateCommonUbo(viewProjection, matrixInverse(projection), skyLinear, powf(logf(1.0f / FOG_VISIBILITY_THRESHOLD), 1.0f / FOG_EXPONENT) / world.renderRadius, FOG_EXPONENT);
            if (ok && swapchain.offscreen) {
                vkResetFences(core.device, 1, &swapchain.inFlightFence);
                recordCommands(0, target);
                ok = submit(false);
            } else if (ok) {
                uint imageIndex;
                VkResult acquired = vkAcquireNextImageKHR(core.device, swapchain.swapchain, NO_TIMEOUT, swapchain.imageAvailableSemaphore, null, &imageIndex);
                if (acquired == VK_ERROR_OUT_OF_DATE_KHR) {
                    ok = recreateSwapchain();
                } else if (acquired == VK_SUCCESS || acquired == VK_SUBOPTIMAL_KHR) {
                    vkResetFences(core.device, 1, &swapchain.inFlightFence);
                    recordCommands(imageIndex, target);
                    ok = submit(true) && present(imageIndex);
                } else {
                    ok = false;
                }
            }
        }
        return ok;
    }

    bool collectChunks(LocalWorld* world, MIsometry!float cameraInverse, MDirection!float[FRUSTUM_PLANE_COUNT] planes, float viewOrientation) {
        meshes.beginFrame(world.graph.nodeCount * VERTEX_COUNT);
        double meshingMs = 0;
        bool ok = true;
        foreach (nearbyNode; world.cachedNodes) {
            if (nearbyNode.slot != NO_SLOT) {
                MPoint!float nodeCenter = MPoint!float(MVector!float(nearbyNode.transform.mat.data[3][0], nearbyNode.transform.mat.data[3][1], nearbyNode.transform.mat.data[3][2], nearbyNode.transform.mat.data[3][3]));
                bool nodeVisible = !sphereOutside(planes[], cameraInverse * nodeCenter, NODE_CULL_RADIUS);
                float[16] nodeMatrix = flatten(nearbyNode.transform.mat);
                float nodeOrientation = viewOrientation * determinant(nodeMatrix);
                const(Node)* node = world.graph.nodeAt(nearbyNode.slot);
                foreach (vertexIndex; 0 .. VERTEX_COUNT) {
                    Vertex vertex = cast(Vertex) vertexIndex;
                    const(Chunk)* chunk = &node.chunks[vertex];
                    uint chunkIndex = nearbyNode.slot * VERTEX_COUNT + vertexIndex;
                    if (chunk.state == ChunkState.Populated && !chunk.voxels.isSolid()) {
                        meshes.markSeen(chunkIndex);
                        if (meshes.needsMesh(chunk, chunkIndex) && meshingMs < MESH_BUDGET_MILLISECONDS) {
                            double start = nowMilliseconds();
                            ok = ok && meshes.mesh(&world.graph, ChunkSlot(nearbyNode.slot, vertex), chunkIndex);
                            meshingMs += nowMilliseconds() - start;
                        } else if (meshes.needsMesh(chunk, chunkIndex)) {
                            meshes.backlog += 1;
                        }
                        if (nodeVisible && meshes.chunks.at(chunkIndex).faceCount > 0 && !sphereOutside(planes[], cameraInverse * (nearbyNode.transform * vertexChunkBoundingSphereCenter(vertex)), CHUNK_BOUNDING_SPHERE_RADIUS)) {
                            ok = ok && meshes.addDraw(chunkIndex, matrixMultiply(nodeMatrix, vertexMatrices[vertexIndex]), nodeOrientation * vertexOrientations[vertexIndex] < 0);
                        }
                    }
                }
            }
        }
        meshes.releaseUnseen();
        if (meshes.facesReplaced) {
            voxels.bindFaces(core.device, meshes.faces.buffer);
        }
        return ok;
    }

    HighlightTarget findHighlightTarget(LocalWorld* world, float[16] viewProjection) {
        HighlightTarget target;
        GraphCastHit hit = castCenterRay(world);
        if (!isNan(hit.tanhDistance)) {
            foreach (nearbyNode; world.cachedNodes) {
                if (!target.found && nearbyNode.id == hit.chunk.node) {
                    target.mvp = matrixMultiply(viewProjection, matrixMultiply(flatten(nearbyNode.transform.mat), vertexMatrices[hit.chunk.vertex]));
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
        meshes.recordUploads(commands);
        VkClearValue[2] clears;
        clears[0].color.float32 = skyLinear;
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
        vkCmdBindVertexBuffers(commands, 0, 1, &meshes.instances.buffer, &vertexOffset);
        vkCmdPushConstants(commands, voxels.pipelineLayout, VK_SHADER_STAGE_VERTEX_BIT, 0, DIMENSION_PUSH_BYTES, &dimension);
        uint drawn = 0;
        while (drawn < meshes.drawCount) {
            uint batch = meshes.drawCount - drawn;
            if (batch > core.maxDrawIndirectCount) {
                batch = core.maxDrawIndirectCount;
            }
            vkCmdDrawIndirect(commands, meshes.indirect.buffer, cast(VkDeviceSize) drawn * VkDrawIndirectCommand.sizeof, batch, VkDrawIndirectCommand.sizeof);
            drawn += batch;
        }
        if (target.found) {
            highlight.draw(commands, target.mvp, target.voxel, cast(float) dimension);
        }
        vkCmdNextSubpass(commands, VK_SUBPASS_CONTENTS_INLINE);
        fog.draw(commands, voxels.commonSet);
        crosshair.draw(commands, cast(float) swapchain.extent.width / cast(float) swapchain.extent.height);
        vkCmdEndRenderPass(commands);
        if (swapchain.offscreen) {
            recordReadback(commands);
        }
        vkEndCommandBuffer(commands);
    }

    void recordReadback(VkCommandBuffer commands) {
        VkBufferImageCopy region;
        region.imageSubresource = VkImageSubresourceLayers(VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1);
        region.imageExtent = VkExtent3D(swapchain.extent.width, swapchain.extent.height, 1);
        vkCmdCopyImageToBuffer(commands, swapchain.offscreenImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback.buffer, 1, &region);
        VkMemoryBarrier barrier;
        barrier.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER;
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = VK_ACCESS_HOST_READ_BIT;
        vkCmdPipelineBarrier(commands, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_HOST_BIT, 0, 1, &barrier, 0, null, 0, null);
    }

    bool submit(bool presenting) {
        VkPipelineStageFlags waitStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        VkSubmitInfo submitInfo;
        submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submitInfo.commandBufferCount = 1;
        submitInfo.pCommandBuffers = &swapchain.commandBuffer;
        if (presenting) {
            submitInfo.waitSemaphoreCount = 1;
            submitInfo.pWaitSemaphores = &swapchain.imageAvailableSemaphore;
            submitInfo.pWaitDstStageMask = &waitStage;
            submitInfo.signalSemaphoreCount = 1;
            submitInfo.pSignalSemaphores = &swapchain.renderFinishedSemaphore;
        }
        return vkQueueSubmit(core.graphicsQueue, 1, &submitInfo, swapchain.inFlightFence) == VK_SUCCESS;
    }

    bool present(uint imageIndex) {
        VkPresentInfoKHR presentInfo;
        presentInfo.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
        presentInfo.waitSemaphoreCount = 1;
        presentInfo.pWaitSemaphores = &swapchain.renderFinishedSemaphore;
        presentInfo.swapchainCount = 1;
        presentInfo.pSwapchains = &swapchain.swapchain;
        presentInfo.pImageIndices = &imageIndex;
        VkResult presented = vkQueuePresentKHR(core.graphicsQueue, &presentInfo);
        bool ok = presented == VK_SUCCESS;
        if (presented == VK_ERROR_OUT_OF_DATE_KHR || presented == VK_SUBOPTIMAL_KHR) {
            ok = recreateSwapchain();
        }
        return ok;
    }

    const(ubyte)[] capture() {
        const(ubyte)[] result = null;
        if (vkWaitForFences(core.device, 1, &swapchain.inFlightFence, VULKAN_TRUE, NO_TIMEOUT) == VK_SUCCESS) {
            result = (cast(const(ubyte)*) readback.mapped)[0 .. readback.size];
        }
        return result;
    }

    bool recreateSwapchain() {
        bool ok = swapchain.recreate(core.device);
        if (ok) {
            voxels.updateDepthDescriptor(core.device, swapchain.depthView);
        }
        return ok || swapchainMinimized();
    }

    void cleanup() {
        if (core.device !is null) {
            vkDeviceWaitIdle(core.device);
            crosshair.cleanup(core.device);
            highlight.cleanup(core.device);
            fog.cleanup(core.device);
            voxels.cleanup(core.device);
            meshes.cleanup();
            destroyBuffer(core.device, &readback);
            swapchain.cleanup(core.device);
        }
        core.cleanup();
    }
}

double nowMilliseconds() {
    timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec * MILLISECONDS_PER_SECOND + now.tv_nsec / NANOSECONDS_PER_MILLISECOND;
}

float srgbToLinear(float encoded) {
    float result = encoded / SRGB_LINEAR_SLOPE;
    if (encoded > SRGB_LINEAR_LIMIT) {
        result = powf((encoded + SRGB_OFFSET) / (1.0f + SRGB_OFFSET), SRGB_GAMMA);
    }
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

float[COFACTOR_COUNT] cofactors(float[16] m) {
    float[COFACTOR_COUNT] b = [
        m[0] * m[5] - m[1] * m[4],
        m[0] * m[6] - m[2] * m[4],
        m[0] * m[7] - m[3] * m[4],
        m[1] * m[6] - m[2] * m[5],
        m[1] * m[7] - m[3] * m[5],
        m[2] * m[7] - m[3] * m[6],
        m[8] * m[13] - m[9] * m[12],
        m[8] * m[14] - m[10] * m[12],
        m[8] * m[15] - m[11] * m[12],
        m[9] * m[14] - m[10] * m[13],
        m[9] * m[15] - m[11] * m[13],
        m[10] * m[15] - m[11] * m[14],
    ];
    return b;
}

float determinantOf(float[COFACTOR_COUNT] b) {
    return b[0] * b[11] - b[1] * b[10] + b[2] * b[9] + b[3] * b[8] - b[4] * b[7] + b[5] * b[6];
}

float determinant(float[16] m) {
    return determinantOf(cofactors(m));
}

float[16] matrixInverse(float[16] m) {
    float[COFACTOR_COUNT] b = cofactors(m);
    float inverseDeterminant = 1.0f / determinantOf(b);
    float[16] result = [
        (m[5] * b[11] - m[6] * b[10] + m[7] * b[9]) * inverseDeterminant,
        (-m[1] * b[11] + m[2] * b[10] - m[3] * b[9]) * inverseDeterminant,
        (m[13] * b[5] - m[14] * b[4] + m[15] * b[3]) * inverseDeterminant,
        (-m[9] * b[5] + m[10] * b[4] - m[11] * b[3]) * inverseDeterminant,
        (-m[4] * b[11] + m[6] * b[8] - m[7] * b[7]) * inverseDeterminant,
        (m[0] * b[11] - m[2] * b[8] + m[3] * b[7]) * inverseDeterminant,
        (-m[12] * b[5] + m[14] * b[2] - m[15] * b[1]) * inverseDeterminant,
        (m[8] * b[5] - m[10] * b[2] + m[11] * b[1]) * inverseDeterminant,
        (m[4] * b[10] - m[5] * b[8] + m[7] * b[6]) * inverseDeterminant,
        (-m[0] * b[10] + m[1] * b[8] - m[3] * b[6]) * inverseDeterminant,
        (m[12] * b[4] - m[13] * b[2] + m[15] * b[0]) * inverseDeterminant,
        (-m[8] * b[4] + m[9] * b[2] - m[11] * b[0]) * inverseDeterminant,
        (-m[4] * b[9] + m[5] * b[7] - m[6] * b[6]) * inverseDeterminant,
        (m[0] * b[9] - m[1] * b[7] + m[2] * b[6]) * inverseDeterminant,
        (-m[12] * b[3] + m[13] * b[1] - m[14] * b[0]) * inverseDeterminant,
        (m[8] * b[3] - m[9] * b[1] + m[10] * b[0]) * inverseDeterminant,
    ];
    return result;
}
