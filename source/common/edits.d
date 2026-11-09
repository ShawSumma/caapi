module common.edits;

import base.array : Array;
import base.hashmap : HashMap;
import base.units : Time;
import common.biology.wild : WildGenes;
import common.node : Chunk, ChunkId;
import plugins.api.api : Material;

struct CellEdit {
    uint cell;
    Material material;
}

enum RecordKind : ubyte {
    beacon,
    collector,
    planted,
    placedLiving,
}

struct BlockRecord {
    WildGenes genes;
    Time placed;
    uint cell;
    RecordKind kind;
}

struct ChunkEdits {
    Array!CellEdit cells;
    Array!BlockRecord records;

    void keep(BlockRecord record) {
        drop(record.cell);
        records.append(record);
    }

    void drop(uint cell) {
        size_t index = 0;
        while (index < records.length && records.ptr[index].cell != cell) {
            index += 1;
        }
        if (index < records.length) {
            records.ptr[index] = records.ptr[records.length - 1];
            records.length -= 1;
        }
    }

    void set(uint cell, Material material) {
        size_t index = 0;
        while (index < cells.length && cells.ptr[index].cell != cell) {
            index += 1;
        }
        if (index < cells.length) {
            cells.ptr[index].material = material;
        } else {
            cells.append(CellEdit(cell, material));
        }
    }
}

struct EditStore {
    HashMap!(ChunkId, ChunkEdits) chunks;
    size_t cellCount;

    ChunkEdits* ensure(ChunkId chunk) {
        ChunkEdits* found = chunks.find(chunk);
        if (found is null) {
            chunks.insert(chunk, ChunkEdits.init);
            found = chunks.find(chunk);
        }
        return found;
    }

    void record(ChunkId chunk, uint cell, Material material) {
        ChunkEdits* found = ensure(chunk);
        size_t before = found.cells.length;
        found.set(cell, material);
        cellCount += found.cells.length - before;
    }

    void keepRecord(ChunkId chunk, BlockRecord record) {
        ensure(chunk).keep(record);
    }

    void dropRecord(ChunkId chunk, uint cell) {
        ChunkEdits* found = chunks.find(chunk);
        if (found !is null) {
            found.drop(cell);
        }
    }

    const(ChunkEdits)* editsOf(ChunkId chunk) const {
        return chunks.find(chunk);
    }

    BlockRecord* recordAt(ChunkId chunk, uint cell) {
        ChunkEdits* found = chunks.find(chunk);
        if (found is null) {
            return null;
        } else {
            size_t index = 0;
            while (index < found.records.length && found.records.ptr[index].cell != cell) {
                index += 1;
            }
            if (index < found.records.length) {
                return &found.records.ptr[index];
            } else {
                return null;
            }
        }
    }

    void release() {
        foreach (ref const chunk, ref edits; chunks) {
            edits.cells.release();
            edits.records.release();
        }
        chunks.release();
        cellCount = 0;
    }
}

void applyEdits(ref const ChunkEdits edits, Chunk* chunk, ubyte dimension) {
    Material[] cells = chunk.denseVoxels(dimension);
    foreach (edit; edits.cells.slice()) {
        cells[edit.cell] = edit.material;
    }
    chunk.markEdited();
}
