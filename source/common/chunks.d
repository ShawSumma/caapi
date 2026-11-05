module common.chunks;

import base.array : Array;
import base.maybe : MaybeIndex;
import base.slab : FreeIndices, Slab;
import common.node : Chunk, ChunkSlot;
import geometry.honeycomb : CORNER_COUNT;

immutable Chunk FRESH_CHUNK = Chunk.init;

struct ChunkStore {
    Slab!Chunk records;
    Slab!(MaybeIndex!uint) blocks;
    FreeIndices freeBlocks;
    Array!ChunkSlot changed;
    Array!ChunkSlot restores;
    size_t changedHead;
    uint blockCount;

    void ensureSlots(uint count) {
        blocks.ensure(count);
    }

    MaybeIndex!uint blockOf(uint slot) const {
        return *blocks.at(slot);
    }

    bool has(uint slot) const {
        return blockOf(slot).exists;
    }

    const(Chunk)* at(ChunkSlot chunk) const {
        MaybeIndex!uint block = blockOf(chunk.slot);
        if (block.exists) {
            return records.at(indexOf(block.value, chunk));
        } else {
            return &FRESH_CHUNK;
        }
    }

    Chunk* existing(ChunkSlot chunk) {
        return records.at(indexOf(blockOf(chunk.slot).value, chunk));
    }

    Chunk* writable(ChunkSlot chunk) {
        MaybeIndex!uint* block = blocks.at(chunk.slot);
        if (!block.exists) {
            if (!freeBlocks.isEmpty()) {
                *block = MaybeIndex!uint.of(freeBlocks.takeLowest());
            } else {
                *block = MaybeIndex!uint.of(blockCount);
                blockCount += 1;
                records.ensure(cast(size_t) blockCount * CORNER_COUNT);
            }
        }
        return records.at(indexOf(block.value, chunk));
    }

    void releaseBlock(uint slot) {
        MaybeIndex!uint* block = blocks.at(slot);
        uint index = block.value;
        foreach (corner; 0 .. CORNER_COUNT) {
            Chunk* chunk = records.at(cast(size_t) index * CORNER_COUNT + corner);
            chunk.releaseVoxels();
            *chunk = Chunk.init;
        }
        freeBlocks.add(index);
        *block = MaybeIndex!uint.init;
        while (blockCount > 0 && freeBlocks.contains(blockCount - 1)) {
            freeBlocks.drop(blockCount - 1);
            blockCount -= 1;
        }
        records.trim(cast(size_t) blockCount * CORNER_COUNT);
        records.note(index, CORNER_COUNT);
    }

    void discardFreed(ref uint calls) {
        records.discardNoted(freeBlocks, blockCount, CORNER_COUNT, calls);
    }

    void queue(ChunkSlot chunk) {
        writable(chunk).markQueued();
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
            existing(taken).unmarkQueued();
        }
        if (changedHead == changed.length) {
            changed.clear();
            changedHead = 0;
        }
        return taken;
    }

    void release() {
        foreach (index; 0 .. cast(size_t) blockCount * CORNER_COUNT) {
            records.at(index).releaseVoxels();
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
    return cast(size_t) block * CORNER_COUNT + chunk.corner;
}
