module client.graphics;

import core.stdc.math : coshf, cosf, logf, powf, sinf, sinhf, sqrtf;
import core.stdc.stdio : FILE, fclose, fflush, fopen, fwrite, printf;
import core.stdc.stdio : snprintf, stdout;
import core.stdc.string : memcpy;
import common.array : Array, allocSlice, freeSlice;
import common.clock : nowMs;
import bindings.vk;
import client.graphics.core;
import client.graphics.base;
import client.graphics.voxels;
import client.graphics.field : PerceptionField, PRODUCER_NONE;
import client.graphics.field : PRODUCER_DIFFUSION, PRODUCER_CYCLIC;
import client.graphics.pipeline : GpuBuffer;
import common.chunk_slot_map : ChunkSlotMap, ChunkSlot, ChunkSlotLookup;
import client.graphics.fog : FogPipeline;
import client.graphics.highlight : HighlightPipeline;
import client.graphics.frustum : Frustum;
import client.worldgen_driver : WorldgenDriver, getChunkNeighbor;
import common.collision_math : Ray;
import common.dodeca : Vertex, Side, sideReflection, sideIsFacing;
import common.dodeca : BOUNDING_SPHERE_RADIUS, CHUNK_BOUNDING_SPHERE_RADIUS;
import common.dodeca : vertexChunkBoundingSphereCenter, vertexChunkToNode;
import common.graph_ray_casting : GraphCastHit, rayCast;
import common.math : Matrix4, MPoint, MIsometry, MVector, MDirection;
import common.graph : Graph, NodeId, NO_SLOT;
import common.node : Chunk, ChunkId, ChunkState, Node;
import common.proto : Position;
import common.traversal : ensureAndCollectNearby, NearbyNode, NearbyScratch;
import common.margins : fixMargins, neighborAxisPermutation;
import common.voxel_math : ChunkDirection, Coords, CoordSign;
import common.world : Material;
import common.worldgen : ChunkParams, chunkRngSeed, generateVoxels;
import common.node : VoxelData;
import client.graphics.voxels.worldgen_gpu : WorldgenGpu, WorldgenParamsGPU;

enum float PI = 3.14159265358979323846f;

size_t voxelIndexOf(ubyte dim, size_t x, size_t y, size_t z) {
    size_t lwm = cast(size_t) dim + 2;
    return (x + 1) + (y + 1) * lwm + (z + 1) * lwm * lwm;
}

bool isNaN(float v) {
    return v != v;
}

struct Renderer {
    VulkanCore core;
    SwapchainState swapState;
    SurfacePipeline voxels;
    SurfaceExtraction extract;
    FogPipeline fog;
    HighlightPipeline highlight;
    PerceptionField field;
    WorldgenDriver worldgenDriver;
    uint dimension = 12;
    float time = 0;
    Position camPos;
    Graph graph;
    float viewRadius = 5.0f;
    float renderRadius = 4.5f;
    float reach = 10.0f;
    // Skip all GPU work; world generation and simulation still run. Used by
    // headless replays so they aren't paced (or stalled) by presentation.
    bool headless = false;
    const(char)* capturePath;
    bool captureDone;

    uint maxSlots = 2^^16;
    uint concurrency = 128;

    // Channels 0, 1, 2 drive red, green, blue; 3 and 4 start out of sight.
    // Turning a triple about its shared diagonal relabels which channel drives
    // which primary — a third of a turn is an exact relabel, a sixth stops
    // between primaries. The diagonal is the axis, so black and white are
    // fixed points of every rotation and stay reserved for free.
    //
    // rotBase is where the space rests; rotGain is how far the field turns it.
    float[4] rotBase = [0, 0, 0, 0];
    float[4] rotGain = [
        2.0f * PI / 3.0f,
        PI / 3.0f,
        PI / 3.0f,
        0,
    ];

    // Sixths of a turn, so cycling walks primaries -> secondaries -> relabel.
    uint rotStep = 0;

    // When set, a screen-space spiral selects the mapping per fragment instead
    // of using channelMapIndex, so perception varies across the view.
    bool trip = false;
    // What fills the field texture: none, diffusion, or the cyclic automaton.
    uint producer = PRODUCER_DIFFUSION;
    // How it is sampled: 0 screen-space, 1 triplanar, 2 volumetric noise,
    // 3 surface normal. Orthogonal to the producer — 2 and 3 never touch the
    // texture at all.
    uint fieldMode = 1;
    // How far the field pushes the rotations, and the spatial frequency it is
    // sampled at.
    float tripGain = 6.5f;
    float tripScale = 0.28f;

    // Written into the renderer's own buffer so the caller can print it
    // without owning storage. Valid until the next call.
    char[16] channelMapLabel;

    const(char)* channelMapName() {
        snprintf(channelMapLabel.ptr, channelMapLabel.length, "%u/6 turn", rotStep);
        return channelMapLabel.ptr;
    }

    void cycleChannelMap() {
        rotStep = (rotStep + 1) % 6;
        rotBase[0] = rotStep * (PI / 3.0f);
    }

    ChunkSlotMap chunkSlots;
    uint nextSlot = 0;
    uint[] freeSlotsBuf;
    uint freeCount;
    uint[] activeSlotsBuf;
    uint activeCount;
    ExtractTask[] tasksBuf;
    uint tasksLen;

    // Per-slot chunk identity for the vertex stage: chunk index within its
    // node in the low 5 bits, a hash of the node id above. Written straight to
    // mapped memory as slots are filled, so nothing is copied in bulk.
    GpuBuffer chunkInfoBuf;
    void* chunkInfoMapped;

    float[] nodeTfLocal;
    uint[] slotTaskLocal;
    ubyte[] slotUsedBuf;
    ChunkId[] removeBuf;

    // Per-second frame timing: average and worst-case per pipeline stage.
    // Smoothness problems live in the max column, not the average.
    static immutable string[9] STAGE_NAMES =
        ["ens", "drv", "wait", "loop", "prep", "acq", "rec", "pres", "total"];
    double[9] stageSum = 0;
    double[9] stageMax = 0;
    uint statFrames = 0;

    uint lastLoggedSecond = 0;
    bool hasLoggedSecond = false;

    // Temporary breakdown of the `loop` stage while it is being tuned.
    double[4] subSum = 0;
    uint visibleNodes = 0;
    NearbyNode[] cachedNodes;
    NearbyScratch nearbyScratch;
    NodeId lastNearbyNode;
    MPoint!float lastNearbyPos;
    bool hasNearby = false;
    uint nearbyVersion = 0;

    // The nearby set is collected with this much extra radius so it stays
    // valid until the camera has translated NEARBY_PADDING away from the
    // collection point; rotation never invalidates it. Node count grows
    // exponentially with radius in hyperbolic space, so this must stay small:
    // 0.05 costs ~10% more nodes, while e.g. 0.25 would cost ~65% more.
    enum float NEARBY_PADDING = 0.05f;

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
        freeSlotsBuf = allocSlice!uint(maxSlots);
        activeSlotsBuf = allocSlice!uint(maxSlots);
        slotUsedBuf = allocSlice!ubyte(maxSlots);
        removeBuf = allocSlice!ChunkId(maxSlots);
        tasksBuf = allocSlice!ExtractTask(concurrency);
        chunkSlots.init(maxSlots);

        if (!core.init(window)) {
            return false;
        }
        if (!swapState.init(
                core.physicalDevice,
                core.device,
                core.surface,
                core.graphicsQueueFamily,
            )) {
            return false;
        }

        graph = Graph.create(cast(ubyte) dimension);

        if (!extract.init(core.physicalDevice, core.device, dimension, concurrency, maxSlots)) {
            return false;
        }

        if (!field.init(core.physicalDevice, core.device)) {
            return false;
        }

        Surface[] empty;
        float[16][] transforms = allocSlice!(float[16])(maxSlots);
        scope(exit) {
            freeSlice(transforms);
        }

        // The 20 chunk-to-node isometries are constant, so upload them once
        // and let the vertex stage put chunk-local positions into node space.
        float[20 * 16] chunkToNode;
        foreach (v; 0 .. 20) {
            float[16] m = matToFlat(vertexChunkToNode(cast(Vertex) v));
            memcpy(chunkToNode.ptr + v * 16, m.ptr, 16 * float.sizeof);
        }

        uint[] chunkInfoInit = allocSlice!uint(maxSlots);
        scope(exit) {
            freeSlice(chunkInfoInit);
        }
        chunkInfoBuf = GpuBuffer.create(
            core.physicalDevice, core.device, cast(void[]) chunkInfoInit,
            VkBufferUsageFlagBits.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
        vkMapMemory(core.device, chunkInfoBuf.memory, 0, maxSlots * 4, 0, &chunkInfoMapped);

        if (!voxels.init(core.physicalDevice, core.device, swapState.renderPass,
                         empty, transforms,
                         extract.facesBuf.buffer,
                         swapState.depthView,
                         field.views[0], field.sampler,
                         chunkToNode[])) {
            return false;
        }

        if (!fog.init(core.device, swapState.renderPass, voxels.commonLayout)) {
            return false;
        }

        if (!highlight.init(core.device, swapState.renderPass)) {
            return false;
        }

        if (extract.tfReady) {
            extract.bindTransformOutput(core.device, voxels.transformsVbo.buffer);
            nodeTfLocal = allocSlice!float(extract.maxNodes * 16);
            slotTaskLocal = allocSlice!uint(maxSlots * 4);
        }

        worldgenDriver = WorldgenDriver.create();

        camPos.node = NodeId.ROOT;
        camPos.local = MIsometry!float.translationAlong([0.0f, 1.4f, 0.0f]);

        printf("Renderer initialized successfully\n");
        return true;
    }

    void render(float dt) {
        time += dt;

        if (swapState.extent.width == 0 || swapState.extent.height == 0) {
            // Minimized; try to rebuild and skip the frame if still zero-sized.
            if (!swapState.recreate(core.device)) {
                return;
            }
            voxels.updateDepthDescriptor(core.device, swapState.depthView);
        }

        double a0 = nowMs();
        MPoint!float camPoint = camPos.local * MPoint!float.origin();
        bool camMoved = !hasNearby || camPos.node != lastNearbyNode
            || nearbyScratch.creationCapped
            || -lastNearbyPos.mip(camPoint.vec) > coshf(NEARBY_PADDING);
        if (camMoved) {
            cachedNodes = ensureAndCollectNearby(
                nearbyScratch,
                graph,
                camPos.node,
                camPos.local,
                renderRadius + NEARBY_PADDING,
            );
            lastNearbyNode = camPos.node;
            lastNearbyPos = camPoint;
            hasNearby = true;
            nearbyVersion = nearbyVersion + 1;
        }
        double a1 = nowMs();
        worldgenDriver.drive(
            cachedNodes,
            camPos.local,
            renderRadius,
            graph,
            cast(ubyte) dimension,
            nearbyVersion,
        );
        double a2 = nowMs();

        if (headless) {
            return;
        }

        tasksLen = 0;
        activeCount = 0;
        uint inFrustumCount = 0;

        vkWaitForFences(core.device, 1, &swapState.inFlightFence, 1, ulong.max);
        double a3 = nowMs();

        slotUsedBuf[] = 0;

        VkExtent2D extent = swapState.extent;
        float aspect = cast(float) extent.width / cast(float) extent.height;
        Frustum frustum = Frustum.fromVfov(45.0f * (PI / 180.0f), aspect);
        MIsometry!float camInverse = camPos.local.inverse();
        MDirection!float[5] fplanes = frustum.planes();

        // The Minkowski form is isometry-invariant, so pushing the five
        // planes into node space once is exactly equivalent to pulling every
        // node into camera space — and saves a 4x4 product per node, which is
        // the whole cost of the cull at large radii.
        MDirection!float[5] worldPlanes;
        foreach (i; 0 .. 5) {
            worldPlanes[i] = MDirection!float(camPos.local * fplanes[i].vec);
        }

        void* voxelsMapped = null;
        uint nodeIndex = 0;

        // Everything inside a node fits in a sphere of the node's own bounding
        // radius plus a chunk's; cull whole nodes before touching their chunks.
        enum float NODE_CULL_RADIUS = BOUNDING_SPHERE_RADIUS + CHUNK_BOUNDING_SPHERE_RADIUS;
        float nodeCullSinh = sinhf(NODE_CULL_RADIUS);
        float chunkCullSinh = sinhf(CHUNK_BOUNDING_SPHERE_RADIUS);

        // Cull against the compact centre array first. Only survivors touch
        // the 88-byte NearbyNode or the node slab, so rejected nodes cost one
        // 16-byte read instead of pulling a full isometry through cache.
        double b0 = nowMs();
        const(MVector!float)[] centers = nearbyScratch.centers.slice();
        foreach (nodeSlot; 0 .. cachedNodes.length) {
            MPoint!float nodeCenter = MPoint!float(centers[nodeSlot]);
            if (frustum.sphereOutsideSinh(worldPlanes, nodeCenter, nodeCullSinh)) {
                continue;
            }

            visibleNodes = visibleNodes + 1;
            NearbyNode nn = cachedNodes[nodeSlot];
            if (nn.slot == NO_SLOT) {
                continue;
            }
            Node* node = &graph.nodeAt(nn.slot);
            // Most nodes reaching here have nothing drawable yet: worldgen
            // has not caught up, or every chunk is solid. One test beats
            // twenty.
            uint renderable = node.renderableMask;
            if (renderable == 0) {
                continue;
            }

            uint thisNodeIndex = nodeIndex;
            bool nodeUploaded = false;
            nodeIndex = nodeIndex + 1;

            foreach (vIdx; 0 .. 20) {
                if ((renderable & (1u << vIdx)) == 0) {
                    continue;
                }
                Vertex v = cast(Vertex) vIdx;
                Chunk* c = &node.chunks.values[v];

                MPoint!float chunkCenter =
                    nn.transform * vertexChunkBoundingSphereCenter(v);
                if (frustum.sphereOutsideSinh(worldPlanes, chunkCenter, chunkCullSinh)) {
                    continue;
                }

                ChunkId chunkId = ChunkId(nn.id, v);
                uint slot;
                bool needsExtract = false;
                bool slotHasData = false;

                ChunkSlotLookup resident = chunkSlots.lookup(chunkId);
                if (resident.found) {
                    slot = resident.value.slot;
                    slotHasData = resident.value.hasData;
                    if (!slotHasData || resident.value.generation != c.generation) {
                        needsExtract = true;
                    }
                } else {
                    needsExtract = true;
                    if (freeCount > 0) {
                        freeCount = freeCount - 1;
                        slot = freeSlotsBuf[freeCount];
                    } else if (nextSlot < maxSlots) {
                        slot = nextSlot;
                        nextSlot = nextSlot + 1;
                    } else {
                        continue;
                    }
                    ChunkSlot fresh;
                    fresh.slot = slot;
                    fresh.generation = 0;
                    fresh.hasData = false;
                    chunkSlots.set(chunkId, fresh);
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
                    tasksLen = tasksLen + 1;
                    ChunkSlot extracted;
                    extracted.slot = slot;
                    extracted.generation = c.generation;
                    extracted.hasData = true;
                    chunkSlots.set(chunkId, extracted);
                    slotHasData = true;
                }

                if (!slotHasData) {
                    continue;
                }

                if (!nodeUploaded) {
                    foreach (col; 0 .. 4) {
                        foreach (row; 0 .. 4) {
                            nodeTfLocal[thisNodeIndex * 16 + col * 4 + row] =
                                nn.transform.mat.data[col][row];
                        }
                    }
                    nodeUploaded = true;
                }
                slotTaskLocal[activeCount * 4] = thisNodeIndex;
                slotTaskLocal[activeCount * 4 + 1] = vIdx;
                slotTaskLocal[activeCount * 4 + 2] = slot;
                slotTaskLocal[activeCount * 4 + 3] = 0;

                // Indexed by slot, matching the instance-rate transform.
                // The node id is stable as the graph grows, so this identity
                // survives both chunk seams and the camera changing nodes.
                (cast(uint*) chunkInfoMapped)[slot] =
                    (vIdx & 31) | (cast(uint) nn.id.hashOf() << 5);
                slotUsedBuf[slot] = true;
                activeSlotsBuf[activeCount] = slot;
                activeCount = activeCount + 1;
                inFrustumCount = inFrustumCount + 1;
            }
        }
        double b1 = nowMs();
        if (voxelsMapped !is null) {
            extract.unmapVoxels(core.device);
        }

        if (nodeIndex > 0) {
            memcpy(extract.nodeTransformsMapped, nodeTfLocal.ptr, nodeIndex * 64);
        }
        if (activeCount > 0) {
            memcpy(extract.slotTasksMapped, slotTaskLocal.ptr, activeCount * 16);
        }

        double b2 = nowMs();
        // A flat scan of the table rather than a walk over scattered nodes.
        // Removals are collected first because backward-shift deletion moves
        // entries around, which would disturb an in-progress scan.
        uint removeLen = 0;
        foreach (i; 0 .. chunkSlots.capacity) {
            if (!chunkSlots.isFilled(i)) {
                continue;
            }
            uint slot = chunkSlots.valueAt(i).slot;
            if (!slotUsedBuf[slot]) {
                removeBuf[removeLen] = chunkSlots.keyAt(i);
                removeLen = removeLen + 1;
                freeSlotsBuf[freeCount] = slot;
                freeCount = freeCount + 1;
            }
        }
        foreach (i; 0 .. removeLen) {
            chunkSlots.remove(removeBuf[i]);
        }

        // Rewrite the active list in ascending slot order. The draw is
        // indirect and the vertex stage indexes transforms and chunk info by
        // slot, so draw order is free — and sorted runs let the indirect pack
        // collapse thousands of 16-byte copies into a handful.
        uint sortedCount = 0;
        foreach (slot; 0 .. nextSlot) {
            if (slotUsedBuf[slot] != 0) {
                activeSlotsBuf[sortedCount] = slot;
                sortedCount = sortedCount + 1;
            }
        }
        assert(sortedCount == activeCount, "active slot bookkeeping diverged");

        double b3 = nowMs();
        subSum[0] = subSum[0] + (b1 - b0);
        subSum[1] = subSum[1] + (b2 - b1);
        subSum[2] = subSum[2] + (b3 - b2);

        float[16] proj = frustum.projection(1.0e-4f);
        float[16] view = matToFlat(camPos.local.inverse().mat);
        float[16] vp = matMul(proj, view);
        float[16] invp = matInverse(proj);

        // Find the voxel the player is aiming at and build the outline's mvp.
        bool hasTarget = false;
        float[16] targetMvp;
        float[3] targetVoxel;
        GraphCastHit targetHit = castCenterRay(reach);
        if (!isNaN(targetHit.tanhDistance)) {
            foreach (ref nn; cachedNodes) {
                if (nn.id == targetHit.chunk.node) {
                    float[16] chunkTf = matMul(
                        matToFlat(nn.transform.mat),
                        matToFlat(vertexChunkToNode(targetHit.chunk.vertex)),
                    );
                    targetMvp = matMul(vp, chunkTf);
                    targetVoxel = [
                        cast(float) targetHit.voxelCoords.data[0],
                        cast(float) targetHit.voxelCoords.data[1],
                        cast(float) targetHit.voxelCoords.data[2],
                    ];
                    hasTarget = true;
                    break;
                }
            }
        }
        double a4 = nowMs();
        subSum[3] = subSum[3] + (a4 - b3);

        float fogDensity = powf(logf(1.0f / 1e-3f), 1.0f / 5.0f) / 75.0f;

        float[4] lightCam = [0.3f, 0.8f, 0.4f, 0];
        float[4] lightNode;
        foreach (row; 0 .. 4) {
            lightNode[row] = 0;
            foreach (k; 0 .. 4) {
                lightNode[row] = lightNode[row]
                    + camPos.local.mat.data[k][row] * lightCam[k];
            }
        }
        float llen = sqrtf(
            lightNode[0] * lightNode[0] +
            lightNode[1] * lightNode[1] +
            lightNode[2] * lightNode[2]);
        if (llen > 0) {
            foreach (i; 0 .. 3) {
                lightNode[i] = lightNode[i] / llen;
            }
        }
        lightNode[3] = 0;
        float tripEnabled = 0.0f;
        if (trip) {
            tripEnabled = 1.0f;
        }
        float[4] tripParams = [
            tripEnabled,
            tripGain,
            tripScale,
            cast(float) fieldMode,
        ];
        float[4] viewportParams = [
            cast(float) extent.width,
            cast(float) extent.height,
            0,
            0,
        ];
        float[4] fieldInfo = [cast(float) producer, 0, 0, 0];
        voxels.updateCommonUbo(
            core.device,
            vp,
            invp,
            fogDensity,
            time,
            lightNode,
            rotBase,
            rotGain,
            tripParams,
            viewportParams,
            fieldInfo,
        );

        double a5 = nowMs();

        uint imageIndex = 0;
        if (!swapState.offscreen) {
            VkResult acquireRes = vkAcquireNextImageKHR(
                core.device,
                swapState.swapchain,
                ulong.max,
                swapState.imageAvailableSemaphore,
                VK_NULL_HANDLE,
                &imageIndex,
            );
            if (acquireRes == VkResult.VK_ERROR_OUT_OF_DATE_KHR) {
                recreateSwapchain();
                return;
            }
            if (acquireRes != VkResult.VK_SUCCESS && acquireRes != VkResult.VK_SUBOPTIMAL_KHR) {
                printf("vkAcquireNextImageKHR failed: %d\n", cast(int) acquireRes);
                return;
            }
        }
        vkResetFences(core.device, 1, &swapState.inFlightFence);
        double a6 = nowMs();

        VkCommandBuffer cmd = swapState.commandBuffer;
        vkResetCommandBuffer(cmd, 0);
        VkCommandBufferBeginInfo bi;
        bi.sType = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        vkBeginCommandBuffer(cmd, &bi);

        uint[] activeSlots = activeSlotsBuf[0 .. activeCount];
        if (tasksLen > 0) {
            extract.recordExtract(core.device, cmd, tasksBuf[0 .. tasksLen]);
        }
        if (extract.tfReady && activeCount > 0) {
            extract.recordTransformCompute(cmd, activeCount, voxels.transformsVbo.buffer);
        }
        // vkCmdCopyBuffer is illegal inside a render pass.
        if (activeCount > 0) {
            extract.recordPackIndirect(cmd, activeSlots);
        }

        uint activeProducer = PRODUCER_NONE;
        if (trip) {
            activeProducer = producer;
        }
        field.recordSteps(cmd, activeProducer, dt);

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

        ulong[2] vertexBufs = [voxels.transformsVbo.buffer, chunkInfoBuf.buffer];
        VkDeviceSize[2] vertexOffs = [0, 0];
        vkCmdBindVertexBuffers(cmd, 0, 2, vertexBufs.ptr, vertexOffs.ptr);

        uint dim = dimension;
        vkCmdPushConstants(cmd, voxels.pipelineLayout,
            VkShaderStageFlagBits.VK_SHADER_STAGE_VERTEX_BIT, 0, 4, &dim);

        if (activeCount > 0) {
            if (core.multiDrawIndirect) {
                vkCmdDrawIndirect(cmd, extract.packedIndirectBuf.buffer,
                    0, activeCount, INDIRECT_SIZE);
            } else {
                foreach (i; 0 .. activeCount) {
                    vkCmdDrawIndirect(cmd, extract.packedIndirectBuf.buffer,
                        cast(VkDeviceSize) i * INDIRECT_SIZE, 1, INDIRECT_SIZE);
                }
            }
        }

        if (hasTarget) {
            highlight.draw(cmd, targetMvp, targetVoxel, cast(float) dimension);
        }

        vkCmdNextSubpass(cmd, VkSubpassContents.VK_SUBPASS_CONTENTS_INLINE);
        fog.draw(cmd, fog.pipelineLayout, voxels.commonSet);

        vkCmdEndRenderPass(cmd);
        vkEndCommandBuffer(cmd);

        uint waitStage = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        VkSubmitInfo si;
        si.sType = VkStructureType.VK_STRUCTURE_TYPE_SUBMIT_INFO;
        if (!swapState.offscreen) {
            si.waitSemaphoreCount = 1;
            si.pWaitSemaphores = &swapState.imageAvailableSemaphore;
            si.pWaitDstStageMask = &waitStage;
            si.signalSemaphoreCount = 1;
            si.pSignalSemaphores = &swapState.renderFinishedSemaphores[imageIndex];
        }
        si.commandBufferCount = 1;
        si.pCommandBuffers = &cmd;
        vkQueueSubmit(core.graphicsQueue, 1, &si, swapState.inFlightFence);
        double a7 = nowMs();

        if (capturePath !is null && !captureDone) {
            captureSwapchainImage(imageIndex);
        }

        if (!swapState.offscreen) {
            VkPresentInfoKHR pi;
            pi.sType = VkStructureType.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
            pi.waitSemaphoreCount = 1;
            pi.pWaitSemaphores = &swapState.renderFinishedSemaphores[imageIndex];
            pi.swapchainCount = 1;
            pi.pSwapchains = &swapState.swapchain;
            pi.pImageIndices = &imageIndex;
            VkResult presentRes = vkQueuePresentKHR(core.graphicsQueue, &pi);
            if (presentRes == VkResult.VK_ERROR_OUT_OF_DATE_KHR
                || presentRes == VkResult.VK_SUBOPTIMAL_KHR) {
                recreateSwapchain();
            }
        }
        double a8 = nowMs();

        double[9] stages = [
            a1 - a0,
            a2 - a1,
            a3 - a2,
            a4 - a3,
            a5 - a4,
            a6 - a5,
            a7 - a6,
            a8 - a7,
            a8 - a0,
        ];
        foreach (i; 0 .. 9) {
            stageSum[i] = stageSum[i] + stages[i];
            if (stages[i] > stageMax[i]) {
                stageMax[i] = stages[i];
            }
        }
        statFrames = statFrames + 1;

        uint currentSecond = cast(uint) time;
        if (!hasLoggedSecond || currentSecond != lastLoggedSecond) {
            lastLoggedSecond = currentSecond;
            hasLoggedSecond = true;
            reportStageTimings(currentSecond);
        }
    }

    void reportStageTimings(uint currentSecond) {
        printf(
            "[t=%us] frames=%u active=%u slots=%u graph=%zu nearby=%zu",
            currentSecond,
            statFrames,
            activeCount,
            nextSlot,
            cast(size_t) graph.len,
            cachedNodes.length,
        );
        foreach (i; 0 .. 9) {
            double avg = 0;
            if (statFrames > 0) {
                avg = stageSum[i] / statFrames;
            }
            printf(" %s=%.1f/%.1f", STAGE_NAMES[i].ptr, avg, stageMax[i]);
        }
        double frames = statFrames;
        if (frames < 1) {
            frames = 1;
        }
        printf(" | cull=%.2f mapcpy=%.2f sweep=%.2f target=%.2f visnodes=%.0f",
            subSum[0] / frames, subSum[1] / frames, subSum[2] / frames,
            subSum[3] / frames, visibleNodes / frames);
        printf("\n");
        fflush(stdout);
        subSum[] = 0;
        visibleNodes = 0;

        stageSum[] = 0;
        stageMax[] = 0;
        statFrames = 0;
    }

    // Debug readback of the just-rendered frame as a 32-bit BMP.
    void captureSwapchainImage(uint imageIndex) {
        vkWaitForFences(core.device, 1, &swapState.inFlightFence, 1, ulong.max);

        VkExtent2D ext = swapState.extent;
        VkDeviceSize byteSize = cast(VkDeviceSize) ext.width * ext.height * 4;

        VkBufferCreateInfo bci;
        bci.sType = VkStructureType.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
        bci.size = byteSize;
        bci.usage = VkBufferUsageFlagBits.VK_BUFFER_USAGE_TRANSFER_DST_BIT;
        bci.sharingMode = VkSharingMode.VK_SHARING_MODE_EXCLUSIVE;
        ulong buf;
        vkCreateBuffer(core.device, &bci, null, &buf);

        VkMemoryRequirements req;
        vkGetBufferMemoryRequirements(core.device, buf, &req);
        VkPhysicalDeviceMemoryProperties mp;
        vkGetPhysicalDeviceMemoryProperties(core.physicalDevice, &mp);
        uint mti = uint.max;
        enum wanted = VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
                    | VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
        foreach (i; 0 .. mp.memoryTypeCount) {
            if ((req.memoryTypeBits & (1u << i))
                && (mp.memoryTypes[i].propertyFlags & wanted) == wanted) {
                mti = i;
                break;
            }
        }
        VkMemoryAllocateInfo mai;
        mai.sType = VkStructureType.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        mai.allocationSize = req.size;
        mai.memoryTypeIndex = mti;
        VkDeviceMemory mem;
        vkAllocateMemory(core.device, &mai, null, &mem);
        vkBindBufferMemory(core.device, buf, mem, 0);

        VkCommandBufferAllocateInfo cbai;
        cbai.sType = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        cbai.commandPool = swapState.commandPool;
        cbai.level = VkCommandBufferLevel.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        cbai.commandBufferCount = 1;
        VkCommandBuffer cmd;
        vkAllocateCommandBuffers(core.device, &cbai, &cmd);

        VkCommandBufferBeginInfo bi;
        bi.sType = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        vkBeginCommandBuffer(cmd, &bi);

        VkImageMemoryBarrier toSrc;
        toSrc.sType = VkStructureType.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        toSrc.srcAccessMask = VkAccessFlagBits.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        toSrc.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        toSrc.oldLayout = VkImageLayout.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        if (swapState.offscreen) {
            toSrc.oldLayout = VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        }
        toSrc.newLayout = VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        toSrc.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        toSrc.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        toSrc.image = swapState.images[imageIndex];
        toSrc.subresourceRange.aspectMask = VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT;
        toSrc.subresourceRange.levelCount = 1;
        toSrc.subresourceRange.layerCount = 1;
        vkCmdPipelineBarrier(cmd,
            VkPipelineStageFlagBits.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_TRANSFER_BIT,
            0, 0, null, 0, null, 1, &toSrc);

        VkBufferImageCopy region;
        region.imageSubresource.aspectMask = VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT;
        region.imageSubresource.layerCount = 1;
        region.imageExtent = VkExtent3D(ext.width, ext.height, 1);
        vkCmdCopyImageToBuffer(cmd, swapState.images[imageIndex],
            VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, buf, 1, &region);

        if (!swapState.offscreen) {
            VkImageMemoryBarrier toPresent = toSrc;
            toPresent.srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
            toPresent.dstAccessMask = 0;
            toPresent.oldLayout = VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
            toPresent.newLayout = VkImageLayout.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
            vkCmdPipelineBarrier(cmd,
                VkPipelineStageFlagBitsExt.VK_PIPELINE_STAGE_TRANSFER_BIT,
                VkPipelineStageFlagBits.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                0, 0, null, 0, null, 1, &toPresent);
        }

        vkEndCommandBuffer(cmd);
        VkSubmitInfo si;
        si.sType = VkStructureType.VK_STRUCTURE_TYPE_SUBMIT_INFO;
        si.commandBufferCount = 1;
        si.pCommandBuffers = &cmd;
        vkQueueSubmit(core.graphicsQueue, 1, &si, VK_NULL_HANDLE);
        vkQueueWaitIdle(core.graphicsQueue);

        void* mapped;
        vkMapMemory(core.device, mem, 0, byteSize, 0, &mapped);
        const(ubyte)[] pixels = (cast(const(ubyte)*) mapped)[0 .. cast(size_t) byteSize];

        bool isRgba = swapState.format == VkFormat.VK_FORMAT_R8G8B8A8_UNORM
                   || swapState.format == VkFormat.VK_FORMAT_R8G8B8A8_SRGB;

        uint w = ext.width;
        uint h = ext.height;
        uint dataSize = w * h * 4;
        ubyte[] bmp = allocSlice!ubyte(54 + dataSize);
        scope(exit) {
            freeSlice(bmp);
        }
        void put32(size_t off, uint v) {
            bmp[off] = v & 0xff;
            bmp[off + 1] = (v >> 8) & 0xff;
            bmp[off + 2] = (v >> 16) & 0xff;
            bmp[off + 3] = (v >> 24) & 0xff;
        }
        bmp[0] = 'B';
        bmp[1] = 'M';
        put32(2, 54 + dataSize);
        put32(10, 54);
        put32(14, 40);
        put32(18, w);
        put32(22, h);
        bmp[26] = 1;
        bmp[28] = 32;
        put32(34, dataSize);

        foreach (y; 0 .. h) {
            size_t srcRow = cast(size_t) (h - 1 - y) * w * 4;
            size_t dstRow = 54 + cast(size_t) y * w * 4;
            if (isRgba) {
                foreach (x; 0 .. w) {
                    bmp[dstRow + x * 4] = pixels[srcRow + x * 4 + 2];
                    bmp[dstRow + x * 4 + 1] = pixels[srcRow + x * 4 + 1];
                    bmp[dstRow + x * 4 + 2] = pixels[srcRow + x * 4];
                    bmp[dstRow + x * 4 + 3] = pixels[srcRow + x * 4 + 3];
                }
            } else {
                memcpy(bmp.ptr + dstRow, pixels.ptr + srcRow, w * 4);
            }
        }
        vkUnmapMemory(core.device, mem);
        vkFreeCommandBuffers(core.device, swapState.commandPool, 1, &cmd);
        vkDestroyBuffer(core.device, buf, null);
        vkFreeMemory(core.device, mem, null);

        FILE* target = fopen(capturePath, "wb");
        if (target is null) {
            printf("capture failed: cannot open %s\n", capturePath);
            return;
        }
        fwrite(bmp.ptr, 1, bmp.length, target);
        fclose(target);
        printf(
            "captured frame -> %s (%ux%u format=%d)\n",
            capturePath,
            w,
            h,
            cast(int) swapState.format,
        );
        captureDone = true;
    }

    // Generates every chunk in range both ways and compares voxel for voxel.
    // Trees are excluded: they are a sequential, order-dependent pass on the
    // CPU and are not in the shader yet, so chunks containing them are counted
    // separately rather than silently reported as failures.
    void compareWorldgen(float radius) {
        WorldgenGpu gpu;
        if (!gpu.init(core.physicalDevice, core.device, core.graphicsQueueFamily,
                dimension)) {
            printf("gpucheck: GPU worldgen init failed\n");
            return;
        }
        scope(exit) {
            gpu.cleanup(core.device);
        }

        MIsometry!float identity = MIsometry!float.identity();
        NearbyScratch scratch;
        scope(exit) {
            scratch.release();
        }
        NearbyNode[] nearby =
            ensureAndCollectNearby(scratch, graph, NodeId.ROOT, identity, radius);

        ubyte dim = cast(ubyte) dimension;
        size_t padded = cast(size_t) dim + 2;
        size_t voxelCount = padded * padded * padded;

        size_t chunksChecked = 0;
        size_t chunksMatching = 0;
        size_t chunksWithTrees = 0;
        size_t totalVoxelMismatches = 0;
        size_t firstBadChunk = size_t.max;
        uint firstBadCpu = 0;
        uint firstBadGpu = 0;
        size_t firstBadIndex = 0;

        foreach (ref nn; nearby) {
            foreach (vIdx; 0 .. 20) {
                Vertex vertex = cast(Vertex) vIdx;
                ChunkId chunkId = ChunkId(nn.id, vertex);
                ChunkParams cp = ChunkParams.create(graph, chunkId);

                VoxelData cpuVoxels = generateVoxels(cp);
                WorldgenParamsGPU gp = WorldgenGpu.buildParams(cp, chunkRngSeed(cp));
                const(uint)[] gpuVoxels = gpu.generate(core.device, core.graphicsQueue, gp);

                chunksChecked = chunksChecked + 1;

                // Interior only: the margin ring is filled by a separate
                // initializeMargins pass on the CPU that the shader does not
                // reproduce.
                bool hasTrees = false;
                size_t mismatches = 0;
                foreach (x; 0 .. dim) {
                    foreach (y; 0 .. dim) {
                        foreach (z; 0 .. dim) {
                            size_t i = voxelIndexOf(dim, x, y, z);
                            uint cpuMat = cast(uint) cpuVoxels.get(i);
                            uint gpuMat = gpuVoxels[i];
                            if (cpuMat == cast(uint) Material.Wood
                                    || cpuMat == cast(uint) Material.Leaves) {
                                hasTrees = true;
                            }
                            if (cpuMat != gpuMat) {
                                mismatches = mismatches + 1;
                                if (firstBadChunk == size_t.max) {
                                    firstBadChunk = chunksChecked - 1;
                                    firstBadCpu = cpuMat;
                                    firstBadGpu = gpuMat;
                                    firstBadIndex = i;
                                }
                            }
                        }
                    }
                }

                if (hasTrees) {
                    chunksWithTrees = chunksWithTrees + 1;
                }
                if (mismatches == 0) {
                    chunksMatching = chunksMatching + 1;
                }
                totalVoxelMismatches = totalVoxelMismatches + mismatches;
            }
        }

        printf(
            "gpucheck: chunks=%zu matching=%zu withTrees=%zu voxelMismatches=%zu\n",
            chunksChecked,
            chunksMatching,
            chunksWithTrees,
            totalVoxelMismatches,
        );
        if (firstBadChunk != size_t.max) {
            printf(
                "gpucheck: first mismatch chunk=%zu voxel=%zu cpu=%u gpu=%u\n",
                firstBadChunk,
                firstBadIndex,
                firstBadCpu,
                firstBadGpu,
            );
        }
        fflush(stdout);
    }

    void recreateSwapchain() {
        if (!swapState.recreate(core.device)) {
            return;
        }
        voxels.updateDepthDescriptor(core.device, swapState.depthView);
    }

    GraphCastHit castCenterRay(float reachDistance) {
        Ray ray = Ray.create(
            MPoint!float.origin(),
            MVector!float(0, 0, -1, 0).normalizedDirection(),
        );
        return rayCast(graph, camPos.node, camPos.local, ray, reachDistance);
    }

    uint castHits;
    uint castMisses;

    void breakBlock() {
        GraphCastHit hit = castCenterRay(reach);
        if (isNaN(hit.tanhDistance)) {
            castMisses = castMisses + 1;
            printf("break: miss (%u/%u hit)\n", castHits, castHits + castMisses);
            return;
        }
        castHits = castHits + 1;
        setVoxel(hit.chunk, hit.voxelCoords, Material.Void);
    }

    void placeBlock(ushort material) {
        GraphCastHit hit = castCenterRay(reach);
        if (isNaN(hit.tanhDistance)) {
            castMisses = castMisses + 1;
            printf("place: miss (%u/%u hit)\n", castHits, castHits + castMisses);
            return;
        }
        castHits = castHits + 1;
        ChunkId targetChunk = hit.chunk;
        Coords coords = hit.voxelCoords;
        int faceStep = -1;
        if (hit.faceSign == CoordSign.Plus) {
            faceStep = 1;
        }
        int stepped = coords[hit.faceAxis] + faceStep;
        if (stepped >= 0 && stepped < dimension) {
            coords[hit.faceAxis] = cast(ubyte) stepped;
        } else {
            // The cell in front of the hit face lies in the neighboring chunk.
            // Chunk neighbors meet mirrored, so the crossing lands on the
            // neighbor's boundary layer for the same direction, with its axes
            // permuted the same way fixMargins matches them up.
            ChunkDirection dir = ChunkDirection(hit.faceAxis, hit.faceSign);
            ChunkId neighbor = getChunkNeighbor(graph, hit.chunk, dir.axis, dir.sign);
            if (neighbor.node == NodeId.init || !graph.contains(neighbor.node)) {
                return;
            }
            coords[hit.faceAxis] = Coords.boundaryCoord(cast(ubyte) dimension, dir.sign);
            coords = neighborAxisPermutation(hit.chunk.vertex, dir) * coords;
            targetChunk = neighbor;
        }
        setVoxel(targetChunk, coords, cast(Material) material);
    }

    // Write one voxel and keep the margin copies of adjacent chunks in sync
    // so their surfaces re-extract correctly when a boundary voxel changes.
    bool setVoxel(ChunkId chunkId, Coords coords, Material material) {
        if (!graph.contains(chunkId.node)) {
            return false;
        }
        Chunk* c = &graph[chunkId.node].chunks.values[chunkId.vertex];
        if (c.state != ChunkState.Populated) {
            return false;
        }
        ubyte dim = cast(ubyte) dimension;
        c.voxels.dataMut(dim)[coords.toIndex(dim)] = material;
        c.generation = c.generation + 1;
        // dataMut may have promoted a solid chunk to dense, which makes it
        // drawable.
        graph[chunkId.node].setChunkRenderable(chunkId.vertex, !c.voxels.isSolid());

        foreach (dir; ChunkDirection.ALL) {
            if (coords[dir.axis] != Coords.boundaryCoord(dim, dir.sign)) {
                continue;
            }
            ChunkId neighbor = getChunkNeighbor(graph, chunkId, dir.axis, dir.sign);
            if (neighbor.node == NodeId.init || !graph.contains(neighbor.node)) {
                continue;
            }
            Chunk* nc = &graph[neighbor.node].chunks.values[neighbor.vertex];
            if (nc.state != ChunkState.Populated) {
                continue;
            }
            fixMargins(dim, chunkId.vertex, c.voxels, dir, nc.voxels);
            nc.generation = nc.generation + 1;
        }
        return true;
    }

    void cleanup() {
        if (core.device !is null) {
            vkDeviceWaitIdle(core.device);
            highlight.cleanup(core.device);
            chunkSlots.cleanup();
            chunkInfoBuf.cleanup(core.device);
            field.cleanup(core.device);
            fog.cleanup(core.device);
            voxels.cleanup(core.device);
            extract.cleanup(core.device);
            swapState.cleanup(core.device);
        }
        core.cleanup();
        freeSlice(freeSlotsBuf);
        freeSlice(activeSlotsBuf);
        freeSlice(slotUsedBuf);
        freeSlice(removeBuf);
        freeSlice(tasksBuf);
        freeSlice(nodeTfLocal);
        freeSlice(slotTaskLocal);
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
    float c = cosf(angle);
    float s = sinf(angle);
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
    float c = cosf(angle);
    float s = sinf(angle);
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
    float c = cosf(angle);
    float s = sinf(angle);
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
                s = s + a[k * 4 + row] * b[col * 4 + k];
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
