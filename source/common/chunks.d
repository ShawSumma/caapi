module common.chunks;

import base.array : Array;
import base.slab : Slab;
import common.node : Chunk, ChunkSlot;
import geometry.honeycomb : CORNER_COUNT;

enum uint NO_BLOCK = 0;

immutable Chunk FRESH_CHUNK = Chunk.init;

struct ChunkStore {
    Slab!Chunk records;
    Slab!uint blocks;
    Array!uint freeBlocks;
    Array!ChunkSlot changed;
    Array!ChunkSlot restores;
    size_t changedHead;
    uint blockCount;

    void ensureSlots(uint count) {
        blocks.ensure(count);
    }

    uint blockOf(uint slot) const {
        return *blocks.at(slot);
    }

    bool has(uint slot) const {
        return blockOf(slot) != NO_BLOCK;
    }

    const(Chunk)* at(ChunkSlot chunk) const {
        uint block = blockOf(chunk.slot);
        return block == NO_BLOCK ? &FRESH_CHUNK : records.at(indexOf(block, chunk));
    }

    Chunk* existing(ChunkSlot chunk) {
        assert(has(chunk.slot));
        return records.at(indexOf(blockOf(chunk.slot), chunk));
    }

    Chunk* writable(ChunkSlot chunk) {
        uint* block = blocks.at(chunk.slot);
        if (*block == NO_BLOCK) {
            if (freeBlocks.length > 0) {
                freeBlocks.length -= 1;
                *block = freeBlocks.ptr[freeBlocks.length];
            } else {
                blockCount += 1;
                records.ensure(cast(size_t) blockCount * CORNER_COUNT);
                *block = blockCount;
            }
        }
        return records.at(indexOf(*block, chunk));
    }

    void releaseBlock(uint slot) {
        uint* block = blocks.at(slot);
        foreach (corner; 0 .. CORNER_COUNT) {
            Chunk* chunk = records.at(cast(size_t)(*block - 1) * CORNER_COUNT + corner);
            chunk.voxels.release();
            *chunk = Chunk.init;
        }
        freeBlocks.append(*block);
        *block = NO_BLOCK;
    }

    void queue(ChunkSlot chunk) {
        writable(chunk).isQueued = true;
        changed.append(chunk);
    }

    const(ChunkSlot)[] pending() const {
        return changed.slice()[changedHead .. $];
    }

    bool hasChanges() const {
        return changedHead < changed.length;
    }

    ChunkSlot takeChanged() {
        ChunkSlot taken = changed.ptr[changedHead];
        changedHead += 1;
        if (has(taken.slot)) {
            existing(taken).isQueued = false;
        }
        if (changedHead == changed.length) {
            changed.clear();
            changedHead = 0;
        }
        return taken;
    }

    void release() {
        foreach (index; 0 .. cast(size_t) blockCount * CORNER_COUNT) {
            records.at(index).voxels.release();
        }
        records.release();
        blocks.release();
        freeBlocks.release();
        changed.release();
        restores.release();
        changedHead = 0;
        blockCount = 0;
    }
}

size_t indexOf(uint block, ChunkSlot chunk) {
    return cast(size_t)(block - 1) * CORNER_COUNT + chunk.corner;
}
