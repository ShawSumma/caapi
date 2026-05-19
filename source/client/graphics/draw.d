module client.graphics.draw;

import std.math : sin, cos, tan, sqrt, PI;
import bindings.vk;

struct Mat4 {
    float[16] m = 0;

    static Mat4 identity() {
        Mat4 r;
        r.m[0] = 1;
        r.m[5] = 1;
        r.m[10] = 1;
        r.m[15] = 1;
        return r;
    }

    static Mat4 mul(Mat4 a, Mat4 b) {
        Mat4 r;
        foreach (col; 0 .. 4) {
            foreach (row; 0 .. 4) {
                float s = 0;
                foreach (k; 0 .. 4) {
                    s += a.m[k * 4 + row] * b.m[col * 4 + k];
                }
                r.m[col * 4 + row] = s;
            }
        }
        return r;
    }

    static Mat4 perspective(float fovY, float aspect, float near, float far) {
        Mat4 r;
        float f = 1.0f / tan(fovY * 0.5f);
        r.m[0] = f / aspect;
        r.m[5] = -f;
        r.m[10] = far / (near - far);
        r.m[11] = -1;
        r.m[14] = (near * far) / (near - far);
        return r;
    }

    static Mat4 lookAt(float[3] eye, float[3] target, float[3] up) {
        float[3] f = normalize([target[0]-eye[0], target[1]-eye[1], target[2]-eye[2]]);
        float[3] s = normalize(cross(f, up));
        float[3] u = cross(s, f);
        Mat4 r;
        r.m[0] = s[0];
        r.m[4] = s[1];
        r.m[8] = s[2];
        r.m[12] = -dot(s, eye);
        r.m[1] = u[0];
        r.m[5] = u[1];
        r.m[9] = u[2];
        r.m[13] = -dot(u, eye);
        r.m[2] = -f[0];
        r.m[6] = -f[1];
        r.m[10] = -f[2];
        r.m[14] = dot(f, eye);
        r.m[15] = 1;
        return r;
    }
}

float[3] normalize(float[3] v) {
    float l = sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2]);
    if (l == 0) {
        return v;
    }
    return [v[0]/l, v[1]/l, v[2]/l];
}
float[3] cross(float[3] a, float[3] b) {
    return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]];
}
float dot(float[3] a, float[3] b) {
    return a[0]*b[0] + a[1]*b[1] + a[2]*b[2];
}

void renderFrame(VkDevice device, VkQueue queue,
                 VkSwapchainKHR swapchain,
                 VkCommandBuffer cmd,
                 VkRenderPass renderPass,
                 VkFramebuffer[] framebuffers,
                 VkExtent2D extent,
                 VkSemaphore imageAvailable,
                 VkSemaphore renderFinished,
                 VkFence inFlightFence,
                 VkPipeline pipeline,
                 VkPipelineLayout layout,
                 ulong vertexBuffer,
                 ulong indexBuffer,
                 uint indexCount,
                 float time,
                 float chunkSize) {
    vkWaitForFences(device, 1, &inFlightFence, 1, ulong.max);
    vkResetFences(device, 1, &inFlightFence);

    uint imageIndex;
    vkAcquireNextImageKHR(device, swapchain, ulong.max, imageAvailable, VK_NULL_HANDLE, &imageIndex);

    vkResetCommandBuffer(cmd, 0);

    VkCommandBufferBeginInfo beginInfo;
    beginInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    vkBeginCommandBuffer(cmd, &beginInfo);

    VkClearValue[2] clears;
    clears[0].color.float32 = [0.05f, 0.07f, 0.12f, 1.0f];
    clears[1].depthStencil.depth = 0.0f;

    VkRenderPassBeginInfo rpBegin;
    rpBegin.sType = VkStructureType.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    rpBegin.renderPass = renderPass;
    rpBegin.framebuffer = framebuffers[imageIndex];
    rpBegin.renderArea.offset = VkOffset2D(0, 0);
    rpBegin.renderArea.extent = extent;
    rpBegin.clearValueCount = 2;
    rpBegin.pClearValues = clears.ptr;

    vkCmdBeginRenderPass(cmd, &rpBegin, VkSubpassContents.VK_SUBPASS_CONTENTS_INLINE);

    vkCmdBindPipeline(cmd, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);

    VkViewport viewport;
    viewport.x = 0;
    viewport.y = 0;
    viewport.width = cast(float) extent.width;
    viewport.height = cast(float) extent.height;
    viewport.minDepth = 0;
    viewport.maxDepth = 1;
    vkCmdSetViewport(cmd, 0, 1, &viewport);

    VkRect2D scissor;
    scissor.offset = VkOffset2D(0, 0);
    scissor.extent = extent;
    vkCmdSetScissor(cmd, 0, 1, &scissor);

    float aspect = cast(float) extent.width / cast(float) extent.height;
    Mat4 proj = Mat4.perspective(60.0f * (cast(float) PI / 180.0f), aspect, 0.1f, 200.0f);
    float r = chunkSize * 2.0f;
    float cx = chunkSize * 0.5f + cos(time * 0.5f) * r;
    float cz = chunkSize * 0.5f + sin(time * 0.5f) * r;
    float cy = chunkSize * 1.2f;
    float[3] eye = [cx, cy, cz];
    float[3] center = [chunkSize * 0.5f, chunkSize * 0.5f, chunkSize * 0.5f];
    float[3] up = [0, 1, 0];
    Mat4 view = Mat4.lookAt(eye, center, up);
    Mat4 mvp = Mat4.mul(proj, view);

    vkCmdPushConstants(cmd, layout, VkShaderStageFlagBits.VK_SHADER_STAGE_VERTEX_BIT, 0, 64, mvp.m.ptr);

    VkDeviceSize offset = 0;
    vkCmdBindVertexBuffers(cmd, 0, 1, &vertexBuffer, &offset);
    vkCmdBindIndexBuffer(cmd, indexBuffer, 0, VkIndexType.VK_INDEX_TYPE_UINT32);
    vkCmdDrawIndexed(cmd, indexCount, 1, 0, 0, 0);

    vkCmdEndRenderPass(cmd);
    vkEndCommandBuffer(cmd);

    uint waitStage = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSubmitInfo submitInfo;
    submitInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.waitSemaphoreCount = 1;
    submitInfo.pWaitSemaphores = &imageAvailable;
    submitInfo.pWaitDstStageMask = &waitStage;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &cmd;
    submitInfo.signalSemaphoreCount = 1;
    submitInfo.pSignalSemaphores = &renderFinished;

    vkQueueSubmit(queue, 1, &submitInfo, inFlightFence);

    VkPresentInfoKHR presentInfo;
    presentInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
    presentInfo.waitSemaphoreCount = 1;
    presentInfo.pWaitSemaphores = &renderFinished;
    presentInfo.swapchainCount = 1;
    presentInfo.pSwapchains = &swapchain;
    presentInfo.pImageIndices = &imageIndex;

    vkQueuePresentKHR(queue, &presentInfo);
}
