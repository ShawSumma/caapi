module client.meshing;

import core.stdc.stdlib : free, malloc;
import core.stdc.string : memcpy;
import base.array : Array;
import base.maybe : Maybe, MaybeIndex;
import base.splitmix : SplitMix;
import base.vector3 : Vec3;
import common.graph : Graph;
import common.material : isOccluding, isShownAgainst;
import common.neighbors : acrossBorder, chunkNeighborSlot, indexIn, isCellOccupied, isOutside;
import common.node : Chunk, ChunkSlot, ChunkState, cellIndex;
import geometry.cube : AXIS_COUNT, DIRECTIONS, beyondBoundary, boundaryOf;
import plugins.api.api : Material;
import plugins.api.flags : Flags;

enum uint CORNERS_PER_FACE = 4;
enum uint OCCLUSION_LEVELS = 3;
enum uint COORD_BITS = 8;
enum uint AXIS_SHIFT = 3 * COORD_BITS;
enum uint OCCLUSION_SHIFT = 24;
enum uint OCCLUSION_BITS = 2;
enum uint REVERSED_BIT = 1 << 2;
enum uint FLIPPED_BIT = 1 << 3;
enum uint WINDOW_SHIFT = 16;
enum uint WINDOW_BITS = 8;
enum uint WINDOWS_PER_SIDE = 1 << (WINDOW_BITS / 2);
enum uint CHUNK_SEED_SHIFT = 40;
enum uint CELL_SEED_SHIFT = 2;

enum Facing : ubyte {
    outward,
    inward,
}

enum CornerCell : ubyte {
    edgeB,
    edgeC,
    diagonal,
}

struct Quad {
    uint posAxis;
    uint occlusionMaterial;

    static Quad fromVoxel(Vec3!int voxel, size_t axis, Facing facing, Material material, uint[CORNERS_PER_FACE] occlusion, uint window) {
        uint axisCode = cast(uint) axis;
        if (facing == Facing.inward) {
            axisCode |= REVERSED_BIT;
        }
        if (isDiagonalFlipped(occlusion)) {
            axisCode |= FLIPPED_BIT;
        }
        uint packed = material.id | window << WINDOW_SHIFT;
        foreach (corner; 0 .. CORNERS_PER_FACE) {
            packed |= occlusion[corner] << (OCCLUSION_SHIFT + OCCLUSION_BITS * corner);
        }
        return Quad(cast(uint) voxel.x | cast(uint) voxel.y << COORD_BITS | cast(uint) voxel.z << (2 * COORD_BITS) | axisCode << AXIS_SHIFT, packed);
    }
}

struct ChunkCells {
    const(Material)* padded;
    const(Graph)* graph;
    ChunkSlot chunk;
    ubyte dimension;
    uint stride;
    ulong seed;

    uint windowOf(size_t index, size_t axis) const {
        return cast(uint)(SplitMix(seed ^ (index << CELL_SEED_SHIFT | axis)).next() >> (ulong.sizeof * 8 - WINDOW_BITS));
    }

    bool isOccupied(Vec3!int voxel) const {
        uint outside = 0;
        foreach (axis; 0 .. AXIS_COUNT) {
            if (isOutside(dimension, voxel[axis])) {
                outside += 1;
            }
        }
        if (outside > 1) {
            return (*graph).isCellOccupied(chunk, voxel);
        } else {
            return isOccluding(padded[paddedIndex(dimension, voxel)]);
        }
    }

    uint[CORNERS_PER_FACE] faceOcclusion(Vec3!int base, size_t axis) const {
        size_t bAxis = (axis + 1) % AXIS_COUNT;
        size_t cAxis = (axis + 2) % AXIS_COUNT;
        uint[CORNERS_PER_FACE] result;
        foreach (corner; 0 .. CORNERS_PER_FACE) {
            int stepB = cast(int)(corner & 1) * 2 - 1;
            int stepC = cast(int)(corner >> 1) * 2 - 1;
            Vec3!int edgeB = base;
            edgeB[bAxis] += stepB;
            Vec3!int edgeC = base;
            edgeC[cAxis] += stepC;
            Vec3!int diagonal = edgeB;
            diagonal[cAxis] += stepC;
            Flags!CornerCell occupied;
            occupied.put(CornerCell.edgeB, isOccupied(edgeB));
            occupied.put(CornerCell.edgeC, isOccupied(edgeC));
            occupied.put(CornerCell.diagonal, isOccupied(diagonal));
            result[corner] = cornerOcclusion(occupied);
        }
        return result;
    }

    uint extractQuads(Quad* quads) const {
        size_t side = dimension + 2;
        size_t[AXIS_COUNT] strides = [1, side, side * side];
        uint count = 0;
        foreach (axis; 0 .. AXIS_COUNT) {
            size_t bAxis = (axis + 1) % AXIS_COUNT;
            size_t cAxis = (axis + 2) % AXIS_COUNT;
            size_t step = strides[axis];
            foreach (c; 0 .. dimension) {
                foreach (b; 0 .. dimension) {
                    size_t rowStart = (b + 1) * strides[bAxis] + (c + 1) * strides[cAxis] + step;
                    for (uint a = 0; a <= dimension; a += stride) {
                        size_t index = rowStart + a * step;
                        Maybe!Facing facing = facingAt(padded[index], padded[index - step], a);
                        if (facing.exists) {
                            Vec3!int voxel;
                            voxel[axis] = cast(int) a;
                            voxel[bAxis] = cast(int) b;
                            voxel[cAxis] = cast(int) c;
                            Vec3!int base = voxel;
                            base[axis] -= solidSideStep(facing.value);
                            quads[count] = Quad.fromVoxel(voxel, axis, facing.value, solidMaterial(index, step, facing.value), faceOcclusion(base, axis), windowOf(index, axis));
                            count += 1;
                        }
                    }
                }
            }
        }
        return count;
    }

    Maybe!Facing facingAt(Material self, Material other, uint a) const {
        bool otherShows = isShownAgainst(other, self);
        bool selfShows = isShownAgainst(self, other);
        if (otherShows && (a < dimension || selfShows)) {
            return Maybe!Facing.of(Facing.inward);
        } else if (!otherShows && a > 0 && selfShows) {
            return Maybe!Facing.of(Facing.outward);
        } else {
            return Maybe!Facing.init;
        }
    }

    Material solidMaterial(size_t index, size_t step, Facing facing) const {
        if (facing == Facing.inward) {
            return padded[index - step];
        } else {
            return padded[index];
        }
    }
}

struct Mesher {
    Quad* quads;
    Material* padded;

    void setup(ubyte dimension) {
        quads = cast(Quad*) malloc(maxQuads(dimension) * Quad.sizeof);
        padded = cast(Material*) malloc(paddedCellCount(dimension));
    }

    void release() {
        free(quads);
        free(padded);
        quads = null;
        padded = null;
    }

    const(Quad)[] mesh(ref const Graph graph, ChunkSlot chunk) {
        pad(graph, chunk);
        ulong seed = graph.idAt(chunk.slot).spice() ^ (cast(ulong) chunk.corner << CHUNK_SEED_SHIFT);
        uint stride = 1;
        if (graph.chunks.at(chunk).voxels.isUniform()) {
            stride = graph.layout.dimension;
        }
        ChunkCells cells = ChunkCells(padded, &graph, chunk, graph.layout.dimension, stride, seed);
        return quads[0 .. cells.extractQuads(quads)];
    }

    void pad(ref const Graph graph, ChunkSlot chunk) {
        ubyte dimension = graph.layout.dimension;
        const(Chunk)* own = graph.chunks.at(chunk);
        foreach (z; 0 .. dimension) {
            foreach (y; 0 .. dimension) {
                Material* row = padded + paddedIndex(dimension, Vec3!int(0, y, z));
                if (own.voxels.isUniform()) {
                    row[0 .. dimension] = own.voxels.fill;
                } else {
                    memcpy(row, own.voxels.cells(dimension).ptr + cellIndex(dimension, 0, y, z), dimension);
                }
            }
        }
        foreach (direction; DIRECTIONS) {
            Maybe!ChunkSlot neighbor = graph.chunkNeighborSlot(chunk, direction);
            const(Chunk)* other = null;
            if (neighbor.exists && graph.chunks.at(neighbor.value).state == ChunkState.populated) {
                other = graph.chunks.at(neighbor.value);
            }
            size_t u = (direction.axis + 1) % AXIS_COUNT;
            size_t v = (direction.axis + 2) % AXIS_COUNT;
            Vec3!int past;
            past[direction.axis] = beyondBoundary(dimension, direction.sign);
            Vec3!int inside;
            inside[direction.axis] = boundaryOf(dimension, direction.sign);
            foreach (j; 0 .. dimension) {
                foreach (i; 0 .. dimension) {
                    past[u] = i;
                    past[v] = j;
                    inside[u] = i;
                    inside[v] = j;
                    if (other is null) {
                        padded[paddedIndex(dimension, past)] = own.voxels.at(indexIn(dimension, inside));
                    } else {
                        padded[paddedIndex(dimension, past)] = other.voxels.at(indexIn(dimension, acrossBorder(dimension, chunk.corner, past, direction)));
                    }
                }
            }
        }
    }
}

struct MeshRecord {
    ChunkSlot slot;
    MaybeIndex!uint block;
    uint offset;
    uint count;
}

struct WorkerMeshes {
    Mesher mesher;
    Array!Quad faces;
    Array!MeshRecord records;
    Array!ChunkSlot waiting;
    Array!ChunkSlot dropped;
}

struct MeshBatch {
    Array!WorkerMeshes workers;
    const(Graph)* graph;

    void prepare(ref const Graph source, uint workerCount, ubyte dimension) {
        graph = &source;
        while (workers.length < workerCount) {
            workers.append(WorkerMeshes.init);
            workers.ptr[workers.length - 1].mesher.setup(dimension);
        }
        foreach (i; 0 .. workers.length) {
            workers.ptr[i].faces.clear();
            workers.ptr[i].records.clear();
            workers.ptr[i].waiting.clear();
            workers.ptr[i].dropped.clear();
        }
    }

    void requeueWaiting(ref Graph target) {
        foreach (worker; workers.slice()) {
            foreach (slot; worker.waiting.slice()) {
                target.markChanged(slot);
            }
            foreach (slot; worker.dropped.slice()) {
                Chunk* chunk = target.chunks.existing(slot);
                if (chunk.state == ChunkState.dropped) {
                    chunk.state = ChunkState.generating;
                    target.chunks.restores.append(slot);
                }
            }
        }
    }

    void release() {
        foreach (i; 0 .. workers.length) {
            workers.ptr[i].mesher.release();
            workers.ptr[i].faces.release();
            workers.ptr[i].records.release();
            workers.ptr[i].waiting.release();
            workers.ptr[i].dropped.release();
        }
        workers.release();
    }
}

bool isBesideUnsettled(ref const Graph graph, ChunkSlot slot) {
    foreach (direction; DIRECTIONS) {
        Maybe!ChunkSlot neighbor = graph.chunkNeighborSlot(slot, direction);
        if (neighbor.exists && (graph.chunks.at(neighbor.value).state == ChunkState.generating || graph.chunks.at(neighbor.value).state == ChunkState.dropped)) {
            return true;
        }
    }
    return false;
}

void meshJob(void* context, size_t index, uint worker) {
    MeshBatch* batch = cast(MeshBatch*) context;
    const(Graph)* graph = batch.graph;
    ChunkSlot slot = graph.chunks.pending()[index];
    const(Chunk)* chunk = graph.chunks.at(slot);
    WorkerMeshes* output = &batch.workers.ptr[worker];
    if (chunk.state == ChunkState.populated && !chunk.voxels.isOpaqueFill()) {
        foreach (direction; DIRECTIONS) {
            Maybe!ChunkSlot neighbor = (*graph).chunkNeighborSlot(slot, direction);
            if (neighbor.exists && graph.chunks.at(neighbor.value).state == ChunkState.dropped) {
                output.dropped.append(neighbor.value);
            }
        }
        if ((*graph).isBesideUnsettled(slot)) {
            output.waiting.append(slot);
        } else {
            const(Quad)[] meshed = output.mesher.mesh(*graph, slot);
            output.records.append(MeshRecord(slot, graph.chunks.blockOf(slot.slot), cast(uint) output.faces.length, cast(uint) meshed.length));
            output.faces.appendAll(meshed);
        }
    }
}

size_t paddedIndex(ubyte dimension, Vec3!int cell) {
    size_t side = dimension + 2;
    return (cell.x + 1) + (cell.y + 1) * side + (cell.z + 1) * side * side;
}

size_t paddedCellCount(ubyte dimension) {
    size_t side = dimension + 2;
    return side * side * side;
}

uint maxQuads(ubyte dimension) {
    return AXIS_COUNT * (dimension * dimension * dimension + dimension * dimension);
}

uint cornerOcclusion(Flags!CornerCell occupied) {
    if (occupied.has(CornerCell.edgeB) && occupied.has(CornerCell.edgeC)) {
        return 0;
    } else {
        uint level = OCCLUSION_LEVELS;
        foreach (cell; [CornerCell.edgeB, CornerCell.edgeC, CornerCell.diagonal]) {
            if (occupied.has(cell)) {
                level -= 1;
            }
        }
        return level;
    }
}

bool isDiagonalFlipped(uint[CORNERS_PER_FACE] occlusion) {
    return occlusion[1] + occlusion[2] > occlusion[0] + occlusion[3];
}

int solidSideStep(Facing facing) {
    if (facing == Facing.inward) {
        return 0;
    } else {
        return 1;
    }
}
