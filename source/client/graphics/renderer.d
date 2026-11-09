module client.graphics.renderer;

import core.stdc.string : memcpy;
import bindings.platform : VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT, VK_ACCESS_HOST_READ_BIT, VK_ACCESS_TRANSFER_READ_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_BUFFER_USAGE_TRANSFER_DST_BIT, VK_ERROR_OUT_OF_DATE_KHR, VK_FORMAT_B8G8R8A8_SRGB, VK_IMAGE_ASPECT_COLOR_BIT, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, VK_STRUCTURE_TYPE_PRESENT_ID_KHR, VkPresentIdKHR, VkImage, VkImageLayout, VkImageMemoryBarrier, VkImageSubresourceRange, VK_PIPELINE_BIND_POINT_GRAPHICS, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_QUERY_RESULT_64_BIT, VK_QUERY_TYPE_TIMESTAMP, VK_SHADER_STAGE_VERTEX_BIT, VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, VK_STRUCTURE_TYPE_MEMORY_BARRIER, VK_STRUCTURE_TYPE_PRESENT_INFO_KHR, VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO, VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO, VK_STRUCTURE_TYPE_SUBMIT_INFO, VK_SUBOPTIMAL_KHR, VK_SUBPASS_CONTENTS_INLINE, VK_SUCCESS, VkBufferImageCopy, VkClearValue, VkCommandBuffer, VkCommandBufferBeginInfo, VkDescriptorSet, VkDevice, VkDeviceSize, VkDrawIndirectCommand, VkExtent2D, VkExtent3D, VkImageSubresourceLayers, VkMemoryBarrier, VkPhysicalDevice, VkPhysicalDeviceProperties, VkPipelineStageFlags, VkPresentInfoKHR, VkQueryPool, VkQueryPoolCreateInfo, VkRect2D, VkRenderPassBeginInfo, VkResult, VkSubmitInfo, VkViewport, vkAcquireNextImageKHR, vkBeginCommandBuffer, vkCmdBeginRenderPass, vkCmdBindDescriptorSets, vkCmdBindPipeline, vkCmdCopyImageToBuffer, vkCmdDrawIndirect, vkCmdEndRenderPass, vkCmdNextSubpass, vkCmdPipelineBarrier, vkCmdPushConstants, vkCmdResetQueryPool, vkCmdSetScissor, vkCmdSetViewport, vkCmdWriteTimestamp, vkCreateQueryPool, vkDestroyQueryPool, vkDeviceWaitIdle, vkEndCommandBuffer, vkGetPhysicalDeviceProperties, vkGetQueryPoolResults, vkQueuePresentKHR, vkQueueSubmit, vkResetCommandBuffer, vkResetFences, vkWaitForFences;
import base.array : Array;
import base.clock : Deadline, MILLISECONDS_PER_SECOND, NANOSECONDS_PER_MILLISECOND, nowMilliseconds;
import base.maybe : Maybe;
import base.numbers : lowerOf;
import base.parallel : ParallelJob;
import base.units : Time;
import client.graphics.base : SwapchainState;
import client.graphics.core : SurfaceSource, VulkanCore;
import client.graphics.crosshair : CrosshairPipeline;
import client.graphics.fog : FogPipeline;
import client.graphics.highlight : HighlightPipeline;
import client.graphics.overlay : HudPipeline, MarkerPipeline;
import client.graphics.post : PostChain;
import client.hud : HudVertex, Marker;
import client.text : GlyphAtlas;
import client.graphics.pipeline : GpuBuffer, QUEUE_FAMILY_IGNORED, VULKAN_TRUE, expectSuccess;
import client.graphics.uniforms : CommonUniforms, HighlightTarget, LinearColor, PostSettings, commonUniforms, findHighlightTarget, perceivedFog, postSettings, unseenMaterials;
import common.material : MaterialSet, glowing, seeThrough;
import client.graphics.voxels.cull : CullPipeline;
import client.graphics.voxels.meshes : ChunkMeshes, Replaced;
import client.graphics.voxels.surface : FACES_BINDING, LayoutPush, SurfacePipeline, TRANSFORMS_BINDING;
import client.images : PixelOrder;
import client.meshing : meshJob;
import client.world : LocalWorld;
import common.node : ChunkLayout;
import plugins.api.api : Material;
import plugins.api.flags : Flags;

enum float CLEAR_DEPTH = 0.0f;
enum ulong NO_TIMEOUT = ulong.max;
enum double MESH_BUDGET_MILLISECONDS = 2.0;
enum uint PIXEL_BYTES = 4;
enum uint OFFSCREEN_IMAGE = 0;
enum uint TIMESTAMP_COUNT = 3;
enum uint FRAME_START_STAMP = 0;
enum uint CULL_END_STAMP = 1;
enum uint FRAME_END_STAMP = 2;
enum ulong PRESENTS_AHEAD = 1;
enum ulong PRESENT_WAIT_NANOSECONDS = 100_000_000;

enum CaptureMark : ubyte {
    wanted,
    copying,
    ready,
}

enum SubmitKind : ubyte {
    offscreen,
    presenting,
}

struct GpuTimes {
    double frameMs = 0;
    double cullMs = 0;
}

struct FrameTimes {
    GpuTimes gpu;
    double fenceWaitMs = 0;
    double chunkUpdateMs = 0;
    double acquireMs = 0;
    double presentMs = 0;
}

struct GpuTimer {
    VkQueryPool pool;
    double millisecondsPerTick = 0;

    void setup(VkPhysicalDevice physicalDevice, VkDevice device) {
        VkPhysicalDeviceProperties properties;
        vkGetPhysicalDeviceProperties(physicalDevice, &properties);
        millisecondsPerTick = properties.limits.timestampPeriod / NANOSECONDS_PER_MILLISECOND;
        VkQueryPoolCreateInfo info;
        info.sType = VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO;
        info.queryType = VK_QUERY_TYPE_TIMESTAMP;
        info.queryCount = TIMESTAMP_COUNT;
        expectSuccess(vkCreateQueryPool(device, &info, null, &pool));
    }

    void begin(VkCommandBuffer commands) {
        vkCmdResetQueryPool(commands, pool, 0, TIMESTAMP_COUNT);
        vkCmdWriteTimestamp(commands, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, pool, FRAME_START_STAMP);
    }

    void markCullEnd(VkCommandBuffer commands) {
        vkCmdWriteTimestamp(commands, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, pool, CULL_END_STAMP);
    }

    void end(VkCommandBuffer commands) {
        vkCmdWriteTimestamp(commands, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, pool, FRAME_END_STAMP);
    }

    GpuTimes read(VkDevice device, GpuTimes previous) {
        ulong[TIMESTAMP_COUNT] stamps;
        VkResult result = vkGetQueryPoolResults(device, pool, 0, TIMESTAMP_COUNT, stamps.sizeof, stamps.ptr, ulong.sizeof, VK_QUERY_RESULT_64_BIT);
        if (result == VK_SUCCESS) {
            return GpuTimes((stamps[FRAME_END_STAMP] - stamps[FRAME_START_STAMP]) * millisecondsPerTick, (stamps[CULL_END_STAMP] - stamps[FRAME_START_STAMP]) * millisecondsPerTick);
        } else {
            return previous;
        }
    }

    void cleanup(VkDevice device) {
        vkDestroyQueryPool(device, pool, null);
    }
}

struct Renderer {
    VulkanCore core;
    SwapchainState swapchain;
    SurfacePipeline voxels;
    ChunkMeshes meshes;
    CullPipeline cull;
    FogPipeline fog;
    HighlightPipeline highlight;
    CrosshairPipeline crosshair;
    HudPipeline hud;
    MarkerPipeline marker;
    const(HudVertex)[] hudVertices;
    const(Marker)[] markers;
    const(GlyphAtlas)* atlas;
    GpuTimer timer;
    FrameTimes frameTimes;
    GpuBuffer readback;
    Array!ubyte captured;
    VkExtent2D capturedExtent;
    VkExtent2D copiedExtent;
    LinearColor fogLinear = LinearColor(0, 0, 0, 1);
    ChunkLayout layout;
    MaterialSet unseen;
    PostChain post;
    Maybe!double previousFrame;
    Maybe!uint worldEpoch;
    ubyte dimension;
    uint backlog;
    ulong presentCount;
    Flags!CaptureMark captureMarks;

    const(char)* setup(SurfaceSource source, ubyte chunkDimension) {
        prepare(chunkDimension);
        const(char)* problem = core.setup(source);
        if (problem is null) {
            swapchain.setup(core.physicalDevice, core.device, core.surface, core.graphicsQueueFamily);
            ensureReadback();
            setupPipelines();
        }
        return problem;
    }

    void ensureReadback() {
        VkDeviceSize size = cast(VkDeviceSize) swapchain.extent.width * swapchain.extent.height * PIXEL_BYTES;
        if (swapchain.isReadable && readback.size != size) {
            readback.destroy(core.device);
            readback = GpuBuffer.makeReadable(core.physicalDevice, core.device, size, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
        }
    }

    const(ubyte)[] capturedImage() const {
        if (captureMarks.has(CaptureMark.ready)) {
            return captured.slice();
        } else {
            return null;
        }
    }

    PixelOrder capturedOrder() const {
        if (swapchain.format == VK_FORMAT_B8G8R8A8_SRGB) {
            return PixelOrder.bgra;
        } else {
            return PixelOrder.rgba;
        }
    }

    const(char)* setupOffscreen(VkExtent2D extent, ubyte chunkDimension) {
        prepare(chunkDimension);
        const(char)* problem = core.setupOffscreen();
        if (problem is null) {
            swapchain.setupOffscreen(core.physicalDevice, core.device, core.graphicsQueueFamily, extent);
            readback = GpuBuffer.makeMapped(core.physicalDevice, core.device, cast(VkDeviceSize) extent.width * extent.height * PIXEL_BYTES, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
            setupPipelines();
        }
        return problem;
    }

    void prepare(ubyte chunkDimension) {
        dimension = chunkDimension;
    }

    void setupPipelines() {
        meshes.setup(core.physicalDevice, core.device, dimension);
        voxels.setup(core.physicalDevice, core.device, swapchain.renderPass, core.graphicsQueue, swapchain.commandPool, swapchain.depthView, swapchain.glowView);
        cull.setup(core.device, voxels.commonUbo.buffer);
        bindMeshBuffers();
        fog.setup(core.device, swapchain.renderPass, voxels.commonLayout);
        highlight.setup(core.device, swapchain.renderPass, voxels.commonLayout);
        post.setup(core.physicalDevice, core.device, swapchain);
        crosshair.setup(core.device, post.compositePass);
        hud.setup(core.physicalDevice, core.device, post.compositePass);
        marker.setup(core.device, swapchain.renderPass, voxels.commonLayout);
        timer.setup(core.physicalDevice, core.device);
    }

    void bindMeshBuffers() {
        voxels.bindStorage(core.device, FACES_BINDING, meshes.faces.buffer);
        voxels.bindStorage(core.device, TRANSFORMS_BINDING, meshes.transforms.buffer);
        cull.bindBuffers(core.device, meshes);
    }

    void render(ref LocalWorld world) {
        captureMarks.clear(CaptureMark.ready);
        if (swapchain.isMinimized()) {
            recreateSwapchain();
        }
        if (!swapchain.isMinimized()) {
            renderFrame(world);
        }
    }

    uint meshBacklog() const {
        return backlog;
    }

    void renderFrame(ref LocalWorld world) {
        layout = world.graph.layout;
        unseen = unseenMaterials(world);
        fogLinear = perceivedFog(world);
        double waitStart = nowMilliseconds();
        expectSuccess(vkWaitForFences(core.device, 1, &swapchain.inFlightFence, VULKAN_TRUE, NO_TIMEOUT));
        double updateStart = nowMilliseconds();
        frameTimes.fenceWaitMs = updateStart - waitStart;
        frameTimes.gpu = timer.read(core.device, frameTimes.gpu);
        if (captureMarks.has(CaptureMark.copying)) {
            takeCopy();
        }
        CommonUniforms uniforms = commonUniforms(world, fogLinear, cast(float) swapchain.extent.width / cast(float) swapchain.extent.height);
        voxels.updateCommonUbo(uniforms);
        hud.upload(hudVertices);
        updateChunks(world);
        frameTimes.chunkUpdateMs = nowMilliseconds() - updateStart;
        Maybe!HighlightTarget target = findHighlightTarget(world);
        PostSettings settings = postSettings(world, frameTime(updateStart));
        if (swapchain.isOffscreen) {
            expectSuccess(vkResetFences(core.device, 1, &swapchain.inFlightFence));
            recordCommands(OFFSCREEN_IMAGE, target, settings);
            submit(SubmitKind.offscreen);
        } else {
            double presentStart = nowMilliseconds();
            uint imageIndex;
            VkResult acquired = vkAcquireNextImageKHR(core.device, swapchain.swapchain, NO_TIMEOUT, swapchain.imageAvailableSemaphore, null, &imageIndex);
            if (acquired == VK_ERROR_OUT_OF_DATE_KHR) {
                recreateSwapchain();
            } else {
                expectAcquired(acquired);
                expectSuccess(vkResetFences(core.device, 1, &swapchain.inFlightFence));
                frameTimes.acquireMs = nowMilliseconds() - presentStart;
                recordCommands(imageIndex, target, settings);
                submit(SubmitKind.presenting);
                present(imageIndex);
            }
            frameTimes.presentMs = nowMilliseconds() - presentStart;
        }
    }

    Time frameTime(double now) {
        Time elapsed = Time(0);
        if (previousFrame.exists) {
            elapsed = Time(cast(float)((now - previousFrame.value) / MILLISECONDS_PER_SECOND));
        }
        previousFrame = Maybe!double.of(now);
        return elapsed;
    }

    void updateChunks(ref LocalWorld world) {
        if (!worldEpoch.exists || world.epoch != worldEpoch.value) {
            meshes.forgetWorld();
            worldEpoch = Maybe!uint.of(world.epoch);
        }
        meshes.beginFrame();
        meshes.forget(world.unloaded.slice());
        world.unloaded.clear();
        meshes.list(world.nearby[world.published], world.listVersion);
        meshChanged(world);
        if (meshes.replaced.has(Replaced.faces) || meshes.replaced.has(Replaced.drawBuffers)) {
            bindMeshBuffers();
        }
    }

    void meshChanged(ref LocalWorld world) {
        if (world.graph.chunks.hasChanges()) {
            meshes.batch.prepare(world.graph, world.streamer.workerCount + 1, meshes.dimension);
            ParallelJob job = ParallelJob(&meshJob, &meshes.batch, Deadline.at(nowMilliseconds() + MESH_BUDGET_MILLISECONDS), world.graph.chunks.pending().length);
            world.streamer.runParallel(&job);
            foreach (_; 0 .. job.count) {
                world.graph.chunks.takeChanged();
            }
            meshes.applyBatch(world.nearby[world.published]);
            meshes.batch.requeueWaiting(world.graph);
        }
        backlog = cast(uint) world.graph.chunks.pending().length;
    }

    void recordCommands(uint imageIndex, Maybe!HighlightTarget target, PostSettings settings) {
        VkCommandBuffer commands = swapchain.commandBuffer;
        vkResetCommandBuffer(commands, 0);
        VkCommandBufferBeginInfo beginInfo;
        beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        vkBeginCommandBuffer(commands, &beginInfo);
        timer.begin(commands);
        meshes.recordUploads(commands);
        cull.record(commands, meshes.drawableCount);
        timer.markCullEnd(commands);
        if (atlas !is null) {
            hud.recordAtlasUpload(commands, *atlas);
        }
        VkClearValue[3] clears;
        clears[0].color.float32 = [fogLinear.red, fogLinear.green, fogLinear.blue, fogLinear.alpha];
        clears[1].depthStencil.depth = CLEAR_DEPTH;
        VkRenderPassBeginInfo passInfo;
        passInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
        passInfo.renderPass = swapchain.renderPass;
        passInfo.framebuffer = swapchain.sceneFramebuffer;
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
        LayoutPush layoutPush = LayoutPush(layout.dimension, layout.cellRatio, glowing.words, unseen.words, seeThrough.words);
        vkCmdPushConstants(commands, voxels.pipelineLayout, VK_SHADER_STAGE_VERTEX_BIT, 0, LayoutPush.sizeof, &layoutPush);
        uint drawn = 0;
        while (drawn < meshes.drawableCount) {
            uint batch = lowerOf(meshes.drawableCount - drawn, core.maxDrawIndirectCount);
            vkCmdDrawIndirect(commands, meshes.commands.buffer, cast(VkDeviceSize) drawn * VkDrawIndirectCommand.sizeof, batch, VkDrawIndirectCommand.sizeof);
            drawn += batch;
        }
        if (target.exists) {
            highlight.draw(commands, voxels.commonSet, target.value.model, target.value.low, target.value.high);
        }
        marker.draw(commands, voxels.commonSet, markers);
        vkCmdNextSubpass(commands, VK_SUBPASS_CONTENTS_INLINE);
        fog.draw(commands, voxels.commonSet);
        vkCmdEndRenderPass(commands);
        post.recordReduce(commands);
        post.beginComposite(commands, imageIndex, swapchain.extent, settings);
        vkCmdNextSubpass(commands, VK_SUBPASS_CONTENTS_INLINE);
        crosshair.draw(commands, cast(float) swapchain.extent.width / cast(float) swapchain.extent.height);
        hud.draw(commands);
        vkCmdEndRenderPass(commands);
        post.advance();
        if (swapchain.isOffscreen) {
            recordReadback(commands, swapchain.offscreenImage);
        } else if (captureMarks.has(CaptureMark.wanted) && swapchain.isReadable) {
            recordPresentedReadback(commands, swapchain.images[imageIndex]);
            captureMarks.set(CaptureMark.copying);
            copiedExtent = swapchain.extent;
        }
        timer.end(commands);
        vkEndCommandBuffer(commands);
    }

    void takeCopy() {
        size_t bytes = cast(size_t) copiedExtent.width * copiedExtent.height * PIXEL_BYTES;
        captured.resize(bytes);
        memcpy(captured.ptr, readback.mapped, bytes);
        capturedExtent = copiedExtent;
        captureMarks.set(CaptureMark.ready);
        captureMarks.clear(CaptureMark.copying);
    }

    void recordPresentedReadback(VkCommandBuffer commands, VkImage image) {
        imageBarrier(commands, image, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT, VK_ACCESS_TRANSFER_READ_BIT, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT);
        recordReadback(commands, image);
        imageBarrier(commands, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, VK_ACCESS_TRANSFER_READ_BIT, 0, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT);
    }

    void recordReadback(VkCommandBuffer commands, VkImage image) {
        VkBufferImageCopy region;
        region.imageSubresource = VkImageSubresourceLayers(VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1);
        region.imageExtent = VkExtent3D(swapchain.extent.width, swapchain.extent.height, 1);
        vkCmdCopyImageToBuffer(commands, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback.buffer, 1, &region);
        VkMemoryBarrier barrier;
        barrier.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER;
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = VK_ACCESS_HOST_READ_BIT;
        vkCmdPipelineBarrier(commands, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_HOST_BIT, 0, 1, &barrier, 0, null, 0, null);
    }

    void submit(SubmitKind kind) {
        VkPipelineStageFlags waitStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        VkSubmitInfo submitInfo;
        submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submitInfo.commandBufferCount = 1;
        submitInfo.pCommandBuffers = &swapchain.commandBuffer;
        if (kind == SubmitKind.presenting) {
            submitInfo.waitSemaphoreCount = 1;
            submitInfo.pWaitSemaphores = &swapchain.imageAvailableSemaphore;
            submitInfo.pWaitDstStageMask = &waitStage;
            submitInfo.signalSemaphoreCount = 1;
            submitInfo.pSignalSemaphores = &swapchain.renderFinishedSemaphore;
        }
        expectSuccess(vkQueueSubmit(core.graphicsQueue, 1, &submitInfo, swapchain.inFlightFence));
    }

    void present(uint imageIndex) {
        VkPresentInfoKHR presentInfo;
        presentInfo.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
        presentInfo.waitSemaphoreCount = 1;
        presentInfo.pWaitSemaphores = &swapchain.renderFinishedSemaphore;
        presentInfo.swapchainCount = 1;
        presentInfo.pSwapchains = &swapchain.swapchain;
        presentInfo.pImageIndices = &imageIndex;
        ulong presentId = presentCount + 1;
        VkPresentIdKHR ids;
        ids.sType = VK_STRUCTURE_TYPE_PRESENT_ID_KHR;
        ids.swapchainCount = 1;
        ids.pPresentIds = &presentId;
        if (core.isPresentWaitable()) {
            presentInfo.pNext = &ids;
        }
        VkResult presented = vkQueuePresentKHR(core.graphicsQueue, &presentInfo);
        presentCount = presentId;
        if (presented == VK_ERROR_OUT_OF_DATE_KHR || presented == VK_SUBOPTIMAL_KHR) {
            recreateSwapchain();
        } else {
            expectSuccess(presented);
        }
    }

    const(ubyte)[] capture() {
        expectSuccess(vkWaitForFences(core.device, 1, &swapchain.inFlightFence, VULKAN_TRUE, NO_TIMEOUT));
        return (cast(const(ubyte)*) readback.mapped)[0 .. readback.size];
    }

    void waitForDisplay() {
        if (core.isPresentWaitable() && presentCount > PRESENTS_AHEAD) {
            core.waitForPresent(core.device, swapchain.swapchain, presentCount - PRESENTS_AHEAD, PRESENT_WAIT_NANOSECONDS);
        }
    }

    void recreateSwapchain() {
        swapchain.recreate(core.device);
        post.rebuild(core.physicalDevice, core.device, swapchain);
        presentCount = 0;
        captureMarks.clear(CaptureMark.copying);
        if (!swapchain.isMinimized()) {
            ensureReadback();
            voxels.updateInputDescriptors(core.device, swapchain.depthView, swapchain.glowView);
        }
    }

    void cleanup() {
        vkDeviceWaitIdle(core.device);
        timer.cleanup(core.device);
        marker.cleanup(core.device);
        hud.cleanup(core.device);
        crosshair.cleanup(core.device);
        post.cleanup(core.device);
        highlight.cleanup(core.device);
        fog.cleanup(core.device);
        cull.cleanup(core.device);
        voxels.cleanup(core.device);
        meshes.cleanup();
        readback.destroy(core.device);
        captured.release();
        swapchain.cleanup(core.device);
        core.cleanup();
    }
}

void imageBarrier(VkCommandBuffer commands, VkImage image, VkImageLayout from, VkImageLayout to, uint sourceAccess, uint destinationAccess, uint sourceStage, uint destinationStage) {
    VkImageMemoryBarrier barrier;
    barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.srcAccessMask = sourceAccess;
    barrier.dstAccessMask = destinationAccess;
    barrier.oldLayout = from;
    barrier.newLayout = to;
    barrier.srcQueueFamilyIndex = QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = QUEUE_FAMILY_IGNORED;
    barrier.image = image;
    barrier.subresourceRange = VkImageSubresourceRange(VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1);
    vkCmdPipelineBarrier(commands, sourceStage, destinationStage, 0, 0, null, 0, null, 1, &barrier);
}

void expectAcquired(VkResult acquired) {
    if (acquired != VK_SUBOPTIMAL_KHR) {
        expectSuccess(acquired);
    }
}
