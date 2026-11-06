module common.node;

import core.atomic : atomicLoad, cas;
import core.stdc.math : coshf, floorf, logf, powf;
import core.stdc.stdlib : free, malloc;
import base.maybe : Maybe;
import base.vector3 : Vec3;
import common.graph : NodeId;
import common.material : MATERIAL_COUNT, isSeeThrough;
import geometry.honeycomb : CORNER_COUNT, Corner, NODE_RADIUS, cubeScale;
import plugins.api.api : Material;

enum float DENSITY_EXPONENT = -4.0f / 3.0f;
enum uint FLAG_SHIFT = 56;
enum ulong VOXEL_MASK = (1UL << FLAG_SHIFT) - 1;
enum uint STATE_SHIFT = FLAG_SHIFT;
enum uint PREDICTED_SHIFT = FLAG_SHIFT + 2;
enum ulong FIELD_MASK = 3;
enum ulong DEFERRED_BIT = 1UL << (FLAG_SHIFT + 4);
enum ulong QUEUED_BIT = 1UL << (FLAG_SHIFT + 5);
enum ulong EDITED_BIT = 1UL << (FLAG_SHIFT + 6);

struct ChunkId {
    NodeId node;
    Corner corner;

    size_t toHash() const {
        return node.toHash() + corner;
    }
}

struct ChunkSlot {
    uint slot;
    Corner corner;

    static ChunkSlot fromIndex(size_t index) {
        return ChunkSlot(cast(uint)(index / CORNER_COUNT), cast(Corner)(index % CORNER_COUNT));
    }
}

struct ChunkLayout {
    float kleinToCube;
    float cellRatio;
    float cubeSpan;
    ubyte dimension;

    static ChunkLayout make(ubyte dimension) {
        float cellRatio = powf(coshf(NODE_RADIUS), DENSITY_EXPONENT / dimension);
        return ChunkLayout(1 / cubeScale(), cellRatio, 1.0f - powf(cellRatio, dimension), dimension);
    }

    float gridToCube(float grid) const {
        return (1.0f - powf(cellRatio, grid)) / cubeSpan;
    }

    float cubeToGrid(float cube) const {
        float remaining = 1.0f - cube * cubeSpan;
        if (remaining > 0) {
            return logf(remaining) / logf(cellRatio);
        } else {
            return float.infinity;
        }
    }

    float gridToKlein(float grid) const {
        return gridToCube(grid) / kleinToCube;
    }

    float kleinToGrid(float klein) const {
        return cubeToGrid(klein * kleinToCube);
    }

    Vec3!float cellCenter(Vec3!int cell) const {
        return Vec3!float(cellCenterAlong(cell.x), cellCenterAlong(cell.y), cellCenterAlong(cell.z));
    }

    float cellCenterAlong(int cell) const {
        return gridToCube(cell + 0.5f);
    }

    Maybe!int kleinToCell(float klein) const {
        float grid = floorf(kleinToGrid(klein));
        if (grid >= 0.0f && grid < cast(float) dimension) {
            return Maybe!int.of(cast(int) grid);
        } else {
            return Maybe!int.init;
        }
    }
}

size_t cellCount(ubyte dimension) {
    return cast(size_t) dimension * dimension * dimension;
}

size_t cellIndex(ubyte dimension, uint x, uint y, uint z) {
    return x + dimension * (y + cast(size_t) dimension * z);
}

struct Voxels {
    size_t bits;

    static Voxels filled(Material material) {
        return Voxels(material);
    }

    bool isUniform() const {
        return bits < MATERIAL_COUNT;
    }

    bool isFilledWith(Material material) const {
        return bits == material;
    }

    bool isOpaqueFill() const {
        return isUniform() && !isSeeThrough(cast(Material) bits);
    }

    Material fill() const {
        assert(isUniform());
        return cast(Material) bits;
    }

    Material at(size_t index) const {
        if (isUniform()) {
            return cast(Material) bits;
        } else {
            return (cast(const(Material)*) bits)[index];
        }
    }

    const(Material)[] cells(ubyte dimension) const {
        assert(!isUniform());
        return (cast(const(Material)*) bits)[0 .. cellCount(dimension)];
    }

    Material[] toDense(ubyte dimension) {
        size_t count = cellCount(dimension);
        if (isUniform()) {
            Material* memory = cast(Material*) malloc(count);
            memory[0 .. count] = cast(Material) bits;
            bits = cast(size_t) memory;
        }
        return (cast(Material*) bits)[0 .. count];
    }

    void compress(ubyte dimension) {
        if (!isUniform()) {
            const(Material)[] all = cells(dimension);
            size_t index = 1;
            while (index < all.length && all[index] == all[0]) {
                index += 1;
            }
            if (index == all.length) {
                Material first = all[0];
                release();
                bits = first;
            }
        }
    }

    void release() {
        if (!isUniform()) {
            free(cast(void*) bits);
            bits = Material.none;
        }
    }
}

enum ChunkState : ubyte {
    fresh,
    generating,
    populated,
    dropped,
}

enum Occupancy : ubyte {
    unknown,
    full,
    empty,
}

enum Materials : ubyte {
    resolved,
    deferred,
}

struct Chunk {
    ulong word;

    const(Voxels) voxels() const {
        return Voxels(cast(size_t)(word & VOXEL_MASK));
    }

    void voxels(Voxels value) {
        assert((value.bits & ~VOXEL_MASK) == 0);
        word = (word & ~VOXEL_MASK) | value.bits;
    }

    void releaseVoxels() {
        Voxels held = voxels;
        held.release();
        voxels = held;
    }

    Material[] denseVoxels(ubyte dimension) {
        Voxels held = voxels;
        Material[] cells = held.toDense(dimension);
        voxels = held;
        return cells;
    }

    ChunkState state() const {
        return cast(ChunkState)((word >> STATE_SHIFT) & FIELD_MASK);
    }

    void state(ChunkState value) {
        word = (word & ~(FIELD_MASK << STATE_SHIFT)) | (cast(ulong) value << STATE_SHIFT);
    }

    ChunkState loadState() const {
        return cast(ChunkState)((atomicLoad(*cast(const(shared(ulong))*) &word) >> STATE_SHIFT) & FIELD_MASK);
    }

    bool casState(ChunkState expected, ChunkState wanted) {
        ulong seen = atomicLoad(*cast(shared(ulong)*) &word);
        while (((seen >> STATE_SHIFT) & FIELD_MASK) == expected) {
            ulong changed = (seen & ~(FIELD_MASK << STATE_SHIFT)) | (cast(ulong) wanted << STATE_SHIFT);
            bool won = cas(cast(shared(ulong)*) &word, seen, changed);
            if (won) {
                return true;
            }
            seen = atomicLoad(*cast(shared(ulong)*) &word);
        }
        return false;
    }

    Occupancy predicted() const {
        return cast(Occupancy)((word >> PREDICTED_SHIFT) & FIELD_MASK);
    }

    void predicted(Occupancy value) {
        word = (word & ~(FIELD_MASK << PREDICTED_SHIFT)) | (cast(ulong) value << PREDICTED_SHIFT);
    }

    bool hasDeferredMaterials() const {
        return (word & DEFERRED_BIT) != 0;
    }

    void materials(Materials value) {
        if (value == Materials.deferred) {
            word |= DEFERRED_BIT;
        } else {
            word &= ~DEFERRED_BIT;
        }
    }

    bool isQueued() const {
        return (word & QUEUED_BIT) != 0;
    }

    void markQueued() {
        word |= QUEUED_BIT;
    }

    void unmarkQueued() {
        word &= ~QUEUED_BIT;
    }

    bool claimQueued() {
        ulong seen = atomicLoad(*cast(shared(ulong)*) &word);
        while ((seen & QUEUED_BIT) == 0) {
            bool won = cas(cast(shared(ulong)*) &word, seen, seen | QUEUED_BIT);
            if (won) {
                return true;
            }
            seen = atomicLoad(*cast(shared(ulong)*) &word);
        }
        return false;
    }

    bool isEdited() const {
        return (word & EDITED_BIT) != 0;
    }

    void markEdited() {
        word |= EDITED_BIT;
    }
}

static assert(Chunk.sizeof == 8);
