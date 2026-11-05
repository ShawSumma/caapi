module client.graphics.voxels.drawlist;

import base.maybe : MaybeIndex;
import client.graphics.matrices : MATRIX_FLOATS, flatten;
import geometry.honeycomb : CORNER_COUNT, Corner, cubeCenter, cubeToNode;
import geometry.lorentz : Point;
import plugins.api.flags : Flags;

enum uint NOT_LISTED = uint.max;

struct CubeFrame {
    float[MATRIX_FLOATS] cubeToNode;
    Point!float center;
}

struct ListedNode {
    uint bits = NOT_LISTED;

    bool isListed() const {
        return bits != NOT_LISTED;
    }

    uint index() const {
        assert(isListed);
        return bits;
    }
}

struct DrawableRecord {
    ListedNode node;
    uint corner;
    uint faceOffset;
    uint faceCount;
}

enum ChunkMark : ubyte {
    drawable,
    nodeMissing,
    unlisted,
}

struct RenderChunk {
    uint faceOffset;
    uint faceCount;
    uint drawable;
    uint slot;
    Flags!ChunkMark marks;
}

CubeFrame[CORNER_COUNT] cubeFrameTable() {
    CubeFrame[CORNER_COUNT] table;
    foreach (index; 0 .. CORNER_COUNT) {
        Corner corner = cast(Corner) index;
        table[index] = CubeFrame(flatten(corner.cubeToNode), corner.cubeCenter);
    }
    return table;
}

ListedNode recordedNode(MaybeIndex!uint node) {
    if (node.exists) {
        return ListedNode(node.value);
    } else {
        return ListedNode.init;
    }
}

mixin template DrawList() {
    import base.allocator : RangeAllocator;
    import base.array : Array;
    import base.maybe : Maybe, MaybeIndex;
    import base.slab : Slab;
    import client.graphics.matrices : flatten;
    import client.graphics.voxels.drawlist : ChunkMark, DrawableRecord, ListedNode, RenderChunk, recordedNode;
    import client.meshing : MeshBatch, MeshRecord, Quad;
    import common.eviction : Unloaded;
    import common.node : ChunkSlot;
    import common.traversal : NearbyScratch;
    import geometry.honeycomb : CORNER_COUNT, Corner;
    import plugins.api.flags : Flags;

    Slab!RenderChunk chunks;
    Array!(MaybeIndex!uint) renderBlocks;
    Array!uint freeRenderBlocks;
    Array!uint drawableChunks;
    Array!DrawableRecord drawableRecords;
    Array!(Maybe!uint) placedVersions;
    Array!uint unlisted;
    MeshBatch batch;
    RangeAllocator allocator;
    Maybe!uint listedVersion;
    uint listedNodes;
    uint renderBlockCount;
    uint meshedChunks;

    uint drawableCount() const {
        return cast(uint) drawableChunks.length;
    }

    void replaceNodes(uint capacity) {
        growNodes(capacity);
        placedVersions.resize(capacity);
        placedVersions.slice()[] = Maybe!uint.init;
    }

    void forgetWorld() {
        chunks.release();
        renderBlocks.clear();
        freeRenderBlocks.clear();
        renderBlockCount = 0;
        drawableChunks.clear();
        drawableRecords.clear();
        placedVersions.slice()[] = Maybe!uint.init;
        unlisted.clear();
        uint capacity = allocator.capacity;
        allocator.release();
        allocator.grow(capacity);
        listedVersion = Maybe!uint.init;
        listedNodes = 0;
        meshedChunks = 0;
    }

    void list(ref const NearbyScratch nearby, uint listVersion) {
        Maybe!uint current = Maybe!uint.of(listVersion);
        if (current != listedVersion) {
            listedVersion = current;
            refreshDrawableNodes(nearby);
        } else if (nearby.nodes.length > listedNodes) {
            refreshUnlisted(nearby);
        }
        listedNodes = cast(uint) nearby.nodes.length;
    }

    MaybeIndex!uint placeNode(ref const NearbyScratch nearby, uint chunkIndex) {
        uint render = chunkIndex / CORNER_COUNT;
        MaybeIndex!uint node = nearby.indexOf(chunks.at(chunkIndex).slot);
        if (node.exists) {
            if (placedVersions.ptr[render] != listedVersion) {
                storeNode(render, flatten(nearby.nodes.ptr[node.value].transform.m));
                placedVersions.ptr[render] = listedVersion;
            }
            return MaybeIndex!uint.of(render);
        } else {
            return MaybeIndex!uint.init;
        }
    }

    void refreshDrawableNodes(ref const NearbyScratch nearby) {
        foreach (chunkIndex; unlisted.slice()) {
            chunks.at(chunkIndex).marks.clear(ChunkMark.unlisted);
        }
        unlisted.clear();
        foreach (drawable, chunkIndex; drawableChunks.slice()) {
            MaybeIndex!uint node = placeNode(nearby, chunkIndex);
            setDrawableNode(cast(uint) drawable, recordedNode(node));
            noteNode(chunkIndex, node);
        }
    }

    void setDrawableNode(uint drawable, ListedNode node) {
        drawableRecords.ptr[drawable].node = node;
        storeDrawableNode(drawable, node);
    }

    void setDrawable(uint drawable, DrawableRecord record) {
        drawableRecords.ptr[drawable] = record;
        storeDrawable(drawable, record);
    }

    void noteNode(uint chunkIndex, MaybeIndex!uint node) {
        RenderChunk* entry = chunks.at(chunkIndex);
        entry.marks.put(ChunkMark.nodeMissing, !node.exists);
        if (!node.exists && !entry.marks.has(ChunkMark.unlisted)) {
            entry.marks.set(ChunkMark.unlisted);
            unlisted.append(chunkIndex);
        }
    }

    void refreshUnlisted(ref const NearbyScratch nearby) {
        size_t kept = 0;
        foreach (chunkIndex; unlisted.slice()) {
            RenderChunk* entry = chunks.at(chunkIndex);
            if (entry.marks.has(ChunkMark.drawable) && entry.marks.has(ChunkMark.nodeMissing)) {
                MaybeIndex!uint node = placeNode(nearby, chunkIndex);
                if (node.exists) {
                    setDrawableNode(entry.drawable, ListedNode(node.value));
                    entry.marks.clear(ChunkMark.nodeMissing);
                }
            }
            if (entry.marks.has(ChunkMark.drawable) && entry.marks.has(ChunkMark.nodeMissing)) {
                unlisted.ptr[kept] = chunkIndex;
                kept += 1;
            } else {
                entry.marks.clear(ChunkMark.unlisted);
            }
        }
        unlisted.length = kept;
    }

    void applyRecords(ref const NearbyScratch nearby) {
        foreach (worker; batch.workers.slice()) {
            foreach (record; worker.records.slice()) {
                apply(nearby, record, worker.faces.ptr[record.offset .. record.offset + record.count]);
            }
        }
    }

    uint renderIndexFor(uint block, Corner corner) {
        if (renderBlocks.length <= block) {
            renderBlocks.resize(block + 1);
        }
        if (!renderBlocks.ptr[block].exists) {
            uint render = renderBlockCount;
            if (freeRenderBlocks.length > 0) {
                render = freeRenderBlocks.ptr[freeRenderBlocks.length - 1];
                freeRenderBlocks.length -= 1;
            } else {
                renderBlockCount += 1;
                chunks.ensure(cast(size_t) renderBlockCount * CORNER_COUNT);
            }
            renderBlocks.ptr[block] = MaybeIndex!uint.of(render);
        }
        return renderBlocks.ptr[block].value * CORNER_COUNT + corner;
    }

    void apply(ref const NearbyScratch nearby, MeshRecord record, const(Quad)[] meshed) {
        uint chunkIndex = renderIndexFor(record.block.value, record.slot.corner);
        if (renderBlockCount > nodeCapacity) {
            replaceNodes(cast(uint) grownCapacity(nodeCapacity, renderBlockCount));
            refreshDrawableNodes(nearby);
        }
        RenderChunk* entry = chunks.at(chunkIndex);
        if (entry.faceCount > 0) {
            allocator.release(entry.faceOffset, entry.faceCount);
        }
        entry.faceCount = cast(uint) meshed.length;
        entry.slot = record.slot.slot;
        meshedChunks += 1;
        if (meshed.length == 0) {
            removeDrawable(chunkIndex);
        } else {
            entry.faceOffset = allocateFaces(entry.faceCount);
            uploadFaces(meshed, entry.faceOffset);
            writeDrawable(chunkIndex, record.slot, placeNode(nearby, chunkIndex));
        }
    }

    void forget(const(Unloaded)[] unloaded) {
        foreach (released; unloaded) {
            if (released.block.exists && released.block.value < renderBlocks.length && renderBlocks.ptr[released.block.value].exists) {
                uint render = renderBlocks.ptr[released.block.value].value;
                foreach (corner; 0 .. CORNER_COUNT) {
                    uint chunkIndex = render * CORNER_COUNT + corner;
                    RenderChunk* entry = chunks.at(chunkIndex);
                    if (entry.faceCount > 0) {
                        allocator.release(entry.faceOffset, entry.faceCount);
                    }
                    removeDrawable(chunkIndex);
                    Flags!ChunkMark kept;
                    kept.put(ChunkMark.unlisted, entry.marks.has(ChunkMark.unlisted));
                    *entry = RenderChunk.init;
                    entry.marks = kept;
                }
                freeRenderBlocks.append(render);
                placedVersions.ptr[render] = Maybe!uint.init;
                renderBlocks.ptr[released.block.value] = MaybeIndex!uint.init;
            }
        }
    }

    uint allocateFaces(uint count) {
        Maybe!uint offset = allocator.allocate(count);
        if (!offset.exists) {
            growFaces(count);
            offset = allocator.allocate(count);
            assert(offset.exists);
        }
        return offset.value;
    }

    void writeDrawable(uint chunkIndex, ChunkSlot slot, MaybeIndex!uint node) {
        RenderChunk* entry = chunks.at(chunkIndex);
        if (!entry.marks.has(ChunkMark.drawable)) {
            makeDrawableRoom();
            entry.drawable = drawableCount;
            entry.marks.set(ChunkMark.drawable);
            drawableChunks.append(chunkIndex);
            drawableRecords.append(DrawableRecord.init);
        }
        setDrawable(entry.drawable, DrawableRecord(recordedNode(node), slot.corner, entry.faceOffset, entry.faceCount));
        noteNode(chunkIndex, node);
    }

    void removeDrawable(uint chunkIndex) {
        RenderChunk* entry = chunks.at(chunkIndex);
        if (entry.marks.has(ChunkMark.drawable)) {
            uint last = drawableCount - 1;
            uint movedChunk = drawableChunks.ptr[last];
            setDrawable(entry.drawable, drawableRecords.ptr[last]);
            drawableChunks.ptr[entry.drawable] = movedChunk;
            chunks.at(movedChunk).drawable = entry.drawable;
            drawableChunks.length = last;
            drawableRecords.length = last;
            entry.marks.clear(ChunkMark.drawable);
        }
    }

    void releaseDrawList() {
        batch.release();
        drawableChunks.release();
        drawableRecords.release();
        placedVersions.release();
        unlisted.release();
        allocator.release();
        chunks.release();
        renderBlocks.release();
        freeRenderBlocks.release();
    }
}
