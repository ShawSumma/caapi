module web.renderer;

import core.stdc.stdlib : free;
import base.allocator : NO_OFFSET, RangeAllocator;
import base.array : Array, grownCapacity;
import base.clock : nowMilliseconds;
import base.maybe : Maybe;
import base.parallel : ParallelJob;
import base.slab : Slab;
import client.graphics.frustum : FRUSTUM_PLANE_COUNT;
import client.graphics.matrices : MATRIX_FLOATS, determinant, flatten, matrixMultiply;
import client.graphics.uniforms : COLOR_CHANNELS, CommonUniforms, GLOW_WORDS, HighlightTarget, commonUniforms, findHighlightTarget, glowingMaterials, srgbToLinear;
import client.graphics.voxels.textures : TEXTURE_LAYERS, TEXTURE_MIPS, TEXTURE_SIZE, makeTexturePixels;
import client.hud : HudVertex, Marker;
import client.meshing : MeshBatch, MeshRecord, Quad, meshJob;
import client.world : LocalWorld;
import common.eviction : Unloaded;
import common.node : ChunkLayout, ChunkSlot;
import common.traversal : NOT_COLLECTED, NearbyScratch;
import geometry.honeycomb : CORNER_COUNT, Corner, cubeCenter, cubeToNode;
import plugins.api.api : Material;
import plugins.api.flags : Flags;

enum double MESH_BUDGET_MILLISECONDS = 3.0;
enum uint POINT_FLOATS = 4;
enum uint VERTICES_PER_FACE = 6;
enum uint INITIAL_FACE_CAPACITY = 2 ^^ 20;
enum uint INITIAL_NODE_CAPACITY = 2 ^^ 12;
enum uint NO_VERSION = uint.max;

enum string NATIVE_VERSION_LINE = "#version 450";
enum string WEB_VERSION_LINE = "#version 300 es";
enum string INCLUDE_START = "#include \"";

struct ShaderHeader {
    string name;
    string text;
}

immutable ShaderHeader[6] SHADER_HEADERS = [
    ShaderHeader("target.h", import("target.h")),
    ShaderHeader("common.h", import("common.h")),
    ShaderHeader("draw.h", import("draw.h")),
    ShaderHeader("face.h", import("face.h")),
    ShaderHeader("clip.h", import("clip.h")),
    ShaderHeader("depth.h", import("depth.h")),
];

string headerNamed()(string name) {
    size_t index = 0;
    while (index < SHADER_HEADERS.length && SHADER_HEADERS[index].name != name) {
        index += 1;
    }
    assert(index < SHADER_HEADERS.length);
    return SHADER_HEADERS[index].text;
}

string expanded()(string source) {
    string result;
    size_t start = 0;
    while (start < source.length) {
        size_t end = start;
        while (end < source.length && source[end] != '\n') {
            end += 1;
        }
        string line = source[start .. end];
        if (line.length > INCLUDE_START.length && line[0 .. INCLUDE_START.length] == INCLUDE_START) {
            result ~= expanded(headerNamed(line[INCLUDE_START.length .. $ - 1]));
        } else {
            result ~= line;
            result ~= "\n";
        }
        start = end + 1;
    }
    return result;
}

string webShader()(string source) {
    return WEB_VERSION_LINE ~ expanded(source[NATIVE_VERSION_LINE.length .. $]);
}

enum Program : uint {
    voxels,
    highlight,
    marker,
    fog,
    crosshair,
    hud,
    present,
}

struct ProgramSource {
    string vertex;
    string fragment;
}

immutable ProgramSource[Program.max + 1] PROGRAM_SOURCES = [
    Program.voxels: ProgramSource(webShader(import("voxels.vert")), webShader(import("voxels.frag"))),
    Program.highlight: ProgramSource(webShader(import("highlight.vert")), webShader(import("highlight.frag"))),
    Program.marker: ProgramSource(webShader(import("marker.vert")), webShader(import("marker.frag"))),
    Program.fog: ProgramSource(webShader(import("fullscreen.vert")), webShader(import("fog.frag"))),
    Program.crosshair: ProgramSource(webShader(import("crosshair.vert")), webShader(import("crosshair.frag"))),
    Program.hud: ProgramSource(webShader(import("hud.vert")), webShader(import("hud.frag"))),
    Program.present: ProgramSource(webShader(import("fullscreen.vert")), webShader(import("present.frag"))),
];

struct VisibleChunk {
    float[MATRIX_FLOATS] transform;
    uint firstVertex;
    uint vertexCount;
    float reversed;
    uint unused;
}

extern (C) nothrow @nogc {
    void web_gl_program(uint program, const(char)* vertex, uint vertexLength, const(char)* fragment, uint fragmentLength);
    void web_gl_setup(const(ubyte)* pixels, uint size, uint mips, uint layers, uint faceCapacity);
    void web_gl_grow_faces(uint capacity);
    void web_gl_upload_faces(uint offset, uint count, const(Quad)* faces);
    void web_gl_begin(const(CommonUniforms)* uniforms, uint bytes, float red, float green, float blue);
    void web_gl_voxels(const(VisibleChunk)* chunks, uint count, uint dimension, float cellRatio, const(uint)* glowing, uint framedMaterial);
    void web_gl_highlight(const(float)* model, const(float)* low, const(float)* high);
    void web_gl_marker(const(float)* model, float half, uint color);
    void web_gl_finish(float widthOverHeight, const(HudVertex)* hud, uint hudVertices);
}

float minkowski(float[POINT_FLOATS] a, float[POINT_FLOATS] b) {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2] - a[3] * b[3];
}

float[POINT_FLOATS] transformed(ref const float[MATRIX_FLOATS] matrix, float[POINT_FLOATS] point) {
    float[POINT_FLOATS] result = 0;
    foreach (row; 0 .. POINT_FLOATS) {
        foreach (column; 0 .. POINT_FLOATS) {
            result[row] += matrix[column * POINT_FLOATS + row] * point[column];
        }
    }
    return result;
}

bool isInFrustum(ref const CommonUniforms uniforms, float[POINT_FLOATS] center) {
    uint plane = 0;
    while (plane < FRUSTUM_PLANE_COUNT && !(minkowski(uniforms.frustumPlanes[plane], center) < -uniforms.cullSinhRadius)) {
        plane += 1;
    }
    return plane == FRUSTUM_PLANE_COUNT;
}

struct CubeFrame {
    float[MATRIX_FLOATS] cubeToNode;
    float[POINT_FLOATS] center;
}

struct DrawableRecord {
    uint node;
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

struct WebMeshes {
    CubeFrame[CORNER_COUNT] cubeFrames;
    Array!(float[MATRIX_FLOATS]) nodes;
    Slab!RenderChunk chunks;
    Array!uint renderBlocks;
    Array!uint freeRenderBlocks;
    Array!uint drawableChunks;
    Array!DrawableRecord drawableRecords;
    Array!uint placedVersions;
    Array!uint unlisted;
    MeshBatch batch;
    RangeAllocator allocator;
    uint listedVersion = NO_VERSION;
    uint listedNodes;
    uint renderBlockCount;
    ubyte dimension;

    void setup(ubyte chunkDimension) {
        dimension = chunkDimension;
        foreach (index; 0 .. CORNER_COUNT) {
            Corner corner = cast(Corner) index;
            cubeFrames[index] = CubeFrame(flatten(corner.cubeToNode), corner.cubeCenter.v.c);
        }
        allocator.grow(INITIAL_FACE_CAPACITY);
        replaceNodes(INITIAL_NODE_CAPACITY);
    }

    void replaceNodes(uint capacity) {
        nodes.resize(capacity);
        placedVersions.resize(capacity);
        placedVersions.slice()[] = NO_VERSION;
    }

    uint nodeCapacity() const {
        return cast(uint) nodes.length;
    }

    uint drawableCount() const {
        return cast(uint) drawableChunks.length;
    }

    void forgetWorld() {
        chunks.release();
        renderBlocks.clear();
        freeRenderBlocks.clear();
        renderBlockCount = 0;
        drawableChunks.clear();
        drawableRecords.clear();
        placedVersions.slice()[] = NO_VERSION;
        unlisted.clear();
        uint capacity = allocator.capacity;
        allocator.release();
        allocator.grow(capacity);
        listedVersion = NO_VERSION;
        listedNodes = 0;
    }

    void list(ref const NearbyScratch nearby, uint listVersion) {
        if (listVersion != listedVersion) {
            listedVersion = listVersion;
            refreshDrawableNodes(nearby);
        } else if (nearby.nodes.length > listedNodes) {
            refreshUnlisted(nearby);
        }
        listedNodes = cast(uint) nearby.nodes.length;
    }

    uint placeNode(ref const NearbyScratch nearby, uint chunkIndex) {
        uint render = chunkIndex / CORNER_COUNT;
        uint node = nearby.indexOf(chunks.at(chunkIndex).slot);
        if (node == NOT_COLLECTED) {
            return NOT_COLLECTED;
        } else {
            if (placedVersions.ptr[render] != listedVersion) {
                nodes.ptr[render] = flatten(nearby.nodes.ptr[node].transform.m);
                placedVersions.ptr[render] = listedVersion;
            }
            return render;
        }
    }

    void refreshDrawableNodes(ref const NearbyScratch nearby) {
        foreach (chunkIndex; unlisted.slice()) {
            chunks.at(chunkIndex).marks.clear(ChunkMark.unlisted);
        }
        unlisted.clear();
        foreach (drawable, chunkIndex; drawableChunks.slice()) {
            uint node = placeNode(nearby, chunkIndex);
            drawableRecords.ptr[drawable].node = node;
            noteNode(chunkIndex, node);
        }
    }

    void noteNode(uint chunkIndex, uint node) {
        RenderChunk* entry = chunks.at(chunkIndex);
        entry.marks.put(ChunkMark.nodeMissing, node == NOT_COLLECTED);
        if (node == NOT_COLLECTED && !entry.marks.has(ChunkMark.unlisted)) {
            entry.marks.set(ChunkMark.unlisted);
            unlisted.append(chunkIndex);
        }
    }

    void refreshUnlisted(ref const NearbyScratch nearby) {
        size_t kept = 0;
        foreach (chunkIndex; unlisted.slice()) {
            RenderChunk* entry = chunks.at(chunkIndex);
            if (entry.marks.has(ChunkMark.drawable) && entry.marks.has(ChunkMark.nodeMissing)) {
                uint node = placeNode(nearby, chunkIndex);
                if (node != NOT_COLLECTED) {
                    drawableRecords.ptr[entry.drawable].node = node;
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

    void applyBatch(ref const NearbyScratch nearby) {
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
        if (renderBlocks.ptr[block] == 0) {
            uint render = renderBlockCount;
            if (freeRenderBlocks.length > 0) {
                render = freeRenderBlocks.ptr[freeRenderBlocks.length - 1];
                freeRenderBlocks.length -= 1;
            } else {
                renderBlockCount += 1;
                chunks.ensure(cast(size_t) renderBlockCount * CORNER_COUNT);
            }
            renderBlocks.ptr[block] = render + 1;
        }
        return (renderBlocks.ptr[block] - 1) * CORNER_COUNT + corner;
    }

    void apply(ref const NearbyScratch nearby, MeshRecord record, const(Quad)[] meshed) {
        uint chunkIndex = renderIndexFor(record.block, record.slot.corner);
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
        if (meshed.length == 0) {
            removeDrawable(chunkIndex);
        } else {
            entry.faceOffset = allocateFaces(entry.faceCount);
            web_gl_upload_faces(entry.faceOffset, entry.faceCount, meshed.ptr);
            writeDrawable(chunkIndex, record.slot, placeNode(nearby, chunkIndex));
        }
    }

    void forget(const(Unloaded)[] unloaded) {
        foreach (released; unloaded) {
            if (released.block < renderBlocks.length && renderBlocks.ptr[released.block] != 0) {
                uint render = renderBlocks.ptr[released.block] - 1;
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
                placedVersions.ptr[render] = NO_VERSION;
                renderBlocks.ptr[released.block] = 0;
            }
        }
    }

    uint allocateFaces(uint count) {
        uint offset = allocator.allocate(count);
        if (offset != NO_OFFSET) {
            return offset;
        } else {
            uint capacity = cast(uint) grownCapacity(allocator.capacity, allocator.capacity + count);
            web_gl_grow_faces(capacity);
            allocator.grow(capacity);
            return allocator.allocate(count);
        }
    }

    void writeDrawable(uint chunkIndex, ChunkSlot slot, uint node) {
        RenderChunk* entry = chunks.at(chunkIndex);
        if (!entry.marks.has(ChunkMark.drawable)) {
            entry.drawable = drawableCount;
            entry.marks.set(ChunkMark.drawable);
            drawableChunks.append(chunkIndex);
            drawableRecords.append(DrawableRecord.init);
        }
        drawableRecords.ptr[entry.drawable] = DrawableRecord(node, slot.corner, entry.faceOffset, entry.faceCount);
        noteNode(chunkIndex, node);
    }

    void removeDrawable(uint chunkIndex) {
        RenderChunk* entry = chunks.at(chunkIndex);
        if (entry.marks.has(ChunkMark.drawable)) {
            uint last = drawableCount - 1;
            uint movedChunk = drawableChunks.ptr[last];
            drawableRecords.ptr[entry.drawable] = drawableRecords.ptr[last];
            drawableChunks.ptr[entry.drawable] = movedChunk;
            chunks.at(movedChunk).drawable = entry.drawable;
            drawableChunks.length = last;
            drawableRecords.length = last;
            entry.marks.clear(ChunkMark.drawable);
        }
    }

    void collectVisible(ref const CommonUniforms uniforms, ref Array!VisibleChunk visible) const {
        visible.clear();
        foreach (record; drawableRecords.slice()) {
            if (record.node != NOT_COLLECTED && record.faceCount > 0) {
                const(float[MATRIX_FLOATS])* node = &nodes.ptr[record.node];
                const(CubeFrame)* frame = &cubeFrames[record.corner];
                if (isInFrustum(uniforms, transformed(uniforms.cameraInverse, transformed(*node, frame.center)))) {
                    float[MATRIX_FLOATS] transform = matrixMultiply(*node, frame.cubeToNode);
                    float reversed = 0;
                    if (uniforms.viewParity * determinant(transform) < 0) {
                        reversed = 1;
                    }
                    visible.append(VisibleChunk(transform, record.faceOffset * VERTICES_PER_FACE, record.faceCount * VERTICES_PER_FACE, reversed, 0));
                }
            }
        }
    }
}

struct WebRenderer {
    WebMeshes meshes;
    Array!VisibleChunk visible;
    float[4] fogLinear = [0, 0, 0, 1];
    uint width;
    uint height;
    uint worldEpoch = NO_VERSION;
    uint backlog;

    void setup(ubyte chunkDimension, uint pixelsWide, uint pixelsHigh) {
        width = pixelsWide;
        height = pixelsHigh;
        meshes.setup(chunkDimension);
        foreach (index, source; PROGRAM_SOURCES) {
            web_gl_program(cast(uint) index, source.vertex.ptr, cast(uint) source.vertex.length, source.fragment.ptr, cast(uint) source.fragment.length);
        }
        ubyte[] pixels = makeTexturePixels();
        web_gl_setup(pixels.ptr, TEXTURE_SIZE, TEXTURE_MIPS, TEXTURE_LAYERS, meshes.allocator.capacity);
        free(pixels.ptr);
    }

    void resize(uint pixelsWide, uint pixelsHigh) {
        width = pixelsWide;
        height = pixelsHigh;
    }

    float aspect() const {
        return cast(float) width / cast(float) height;
    }

    void updateChunks(ref LocalWorld world) {
        if (world.epoch != worldEpoch) {
            meshes.forgetWorld();
            worldEpoch = world.epoch;
        }
        meshes.forget(world.unloaded.slice());
        world.unloaded.clear();
        meshes.list(world.nearby[world.published], world.listVersion);
        meshChanged(world);
    }

    void meshChanged(ref LocalWorld world) {
        if (world.graph.chunks.hasChanges()) {
            meshes.batch.prepare(world.graph, world.streamer.pool.participants(), meshes.dimension);
            ParallelJob job = ParallelJob(&meshJob, &meshes.batch, nowMilliseconds() + MESH_BUDGET_MILLISECONDS, world.graph.chunks.pending().length);
            world.streamer.runParallel(&job);
            foreach (_; 0 .. job.count) {
                world.graph.chunks.takeChanged();
            }
            meshes.applyBatch(world.nearby[world.published]);
            meshes.batch.requeueWaiting(world.graph);
        }
        backlog = cast(uint) world.graph.chunks.pending().length;
    }

    void render(ref LocalWorld world, const(HudVertex)[] hudVertices, const(Marker)[] markers) {
        foreach (channel; 0 .. COLOR_CHANNELS) {
            fogLinear[channel] = srgbToLinear(world.fogColor[channel]);
        }
        CommonUniforms uniforms = commonUniforms(world, fogLinear, aspect());
        updateChunks(world);
        meshes.collectVisible(uniforms, visible);
        web_gl_begin(&uniforms, CommonUniforms.sizeof, fogLinear[0], fogLinear[1], fogLinear[2]);
        uint[GLOW_WORDS] glowing = glowingMaterials();
        ChunkLayout layout = world.graph.layout;
        web_gl_voxels(visible.ptr, cast(uint) visible.length, layout.dimension, layout.cellRatio, glowing.ptr, Material.glass);
        Maybe!HighlightTarget target = world.findHighlightTarget();
        if (target.exists) {
            web_gl_highlight(target.value.model.ptr, target.value.low.ptr, target.value.high.ptr);
        }
        foreach (ref marker; markers) {
            float[MATRIX_FLOATS] model = flatten(marker.frame.m);
            web_gl_marker(model.ptr, marker.half, marker.color);
        }
        web_gl_finish(aspect(), hudVertices.ptr, cast(uint) hudVertices.length);
    }
}
