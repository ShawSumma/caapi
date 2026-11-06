module web.renderer;

import core.stdc.stdlib : free;
import base.array : Array, grownCapacity;
import base.clock : Deadline, nowMilliseconds;
import base.maybe : Maybe;
import base.parallel : ParallelJob;
import base.vector3 : Vec3;
import client.graphics.frustum : FRUSTUM_PLANE_COUNT;
import client.graphics.matrices : MATRIX_FLOATS, determinant, flatten, matrixMultiply;
import client.graphics.uniforms : CommonUniforms, HighlightTarget, LinearColor, commonUniforms, findHighlightTarget, perceivedFog, unseenMaterials;
import common.material : GLOWING, MaterialSet;
import client.graphics.voxels.drawlist : CubeFrame, DrawList, DrawableRecord, ListedNode, cubeFrameTable;
import client.graphics.voxels.textures : TEXTURE_LAYERS, TEXTURE_MIPS, TEXTURE_SIZE, makeTexturePixels;
import client.hud : HudVertex, Marker;
import client.meshing : Quad, meshJob;
import client.text : ATLAS_HEIGHT, ATLAS_WIDTH, GlyphAtlas;
import client.world : LocalWorld;
import common.node : ChunkLayout;
import common.traversal : NearbyScratch;
import geometry.honeycomb : CORNER_COUNT;
import geometry.lorentz : Vec4;
import plugins.api.api : Material;

enum uint POINT_FLOATS = 4;
enum double MESH_BUDGET_MILLISECONDS = 3.0;
enum uint VERTICES_PER_FACE = 6;
enum uint INITIAL_FACE_CAPACITY = 2 ^^ 20;
enum uint INITIAL_NODE_CAPACITY = 2 ^^ 12;

enum string NATIVE_VERSION_LINE = "#version 450";
enum string WEB_VERSION_LINE = "#version 300 es";
enum string INCLUDE_START = "#include \"";

struct ShaderHeader {
    string name;
    string text;
}

immutable ShaderHeader[7] SHADER_HEADERS = [
    ShaderHeader("warp.h", import("warp.h")),
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
    void web_gl_voxels(const(VisibleChunk)* chunks, uint count, uint dimension, float cellRatio, const(uint)* glowing, const(uint)* unseen, uint framedMaterial);
    void web_gl_highlight(const(float)* model, const(Vec3!float)* low, const(Vec3!float)* high);
    void web_gl_marker(const(float)* model, float half, uint color);
    void web_gl_finish(float widthOverHeight, const(HudVertex)* hud, uint hudVertices);
    void web_gl_atlas(const(ubyte)* pixels, uint width, uint height);
}

Vec4!float transformed(ref const float[MATRIX_FLOATS] matrix, Vec4!float point) {
    Vec4!float result;
    foreach (row; 0 .. POINT_FLOATS) {
        foreach (column; 0 .. POINT_FLOATS) {
            result.c[row] += matrix[column * POINT_FLOATS + row] * point.c[column];
        }
    }
    return result;
}

bool isInFrustum(ref const CommonUniforms uniforms, Vec4!float center) {
    uint plane = 0;
    while (plane < FRUSTUM_PLANE_COUNT && !(uniforms.frustumPlanes[plane].minkowski(center) < -uniforms.cullSinhRadius)) {
        plane += 1;
    }
    return plane == FRUSTUM_PLANE_COUNT;
}

struct WebMeshes {
    mixin DrawList;

    CubeFrame[CORNER_COUNT] cubeFrames;
    Array!(float[MATRIX_FLOATS]) nodes;
    ubyte dimension;

    void setup(ubyte chunkDimension) {
        dimension = chunkDimension;
        cubeFrames = cubeFrameTable();
        allocator.grow(INITIAL_FACE_CAPACITY);
        replaceNodes(INITIAL_NODE_CAPACITY);
    }

    void growNodes(uint capacity) {
        nodes.resize(capacity);
    }

    uint nodeCapacity() const {
        return cast(uint) nodes.length;
    }

    void storeNode(uint render, float[MATRIX_FLOATS] matrix) {
        nodes.ptr[render] = matrix;
    }

    void storeDrawableNode(uint drawable, ListedNode node) {
    }

    void storeDrawable(uint drawable, DrawableRecord record) {
    }

    void makeDrawableRoom() {
    }

    void uploadFaces(const(Quad)[] meshed, uint offset) {
        web_gl_upload_faces(offset, cast(uint) meshed.length, meshed.ptr);
    }

    void growFaces(uint needed) {
        uint capacity = cast(uint) grownCapacity(allocator.capacity, allocator.capacity + needed);
        web_gl_grow_faces(capacity);
        allocator.grow(capacity);
    }

    void collectVisible(ref const CommonUniforms uniforms, ref Array!VisibleChunk visible) const {
        visible.clear();
        foreach (record; drawableRecords.slice()) {
            if (record.node.isListed && record.faceCount > 0) {
                const(float[MATRIX_FLOATS])* node = &nodes.ptr[record.node.index];
                const(CubeFrame)* frame = &cubeFrames[record.corner];
                if (isInFrustum(uniforms, transformed(uniforms.cameraInverse, transformed(*node, frame.center.v)))) {
                    float[MATRIX_FLOATS] transform = matrixMultiply(*node, frame.cubeToNode);
                    float reversed = 0;
                    if (uniforms.viewParity * determinant(transform) < 0) {
                        reversed = 1;
                    }
                    visible.append(VisibleChunk(transform, record.faceOffset * VERTICES_PER_FACE, record.faceCount * VERTICES_PER_FACE, reversed));
                }
            }
        }
    }
}

struct WebRenderer {
    WebMeshes meshes;
    Array!VisibleChunk visible;
    LinearColor fogLinear = LinearColor(0, 0, 0, 1);
    uint width;
    uint height;
    Maybe!uint worldEpoch;
    Maybe!uint uploadedAtlas;
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
        Maybe!uint epoch = Maybe!uint.of(world.epoch);
        if (epoch != worldEpoch) {
            meshes.forgetWorld();
            worldEpoch = epoch;
        }
        meshes.forget(world.unloaded.slice());
        world.unloaded.clear();
        meshes.list(world.nearby[world.published], world.listVersion);
        meshChanged(world);
    }

    void meshChanged(ref LocalWorld world) {
        if (world.graph.chunks.hasChanges()) {
            meshes.batch.prepare(world.graph, world.streamer.pool.participants(), meshes.dimension);
            ParallelJob job = ParallelJob(&meshJob, &meshes.batch, Deadline.at(nowMilliseconds() + MESH_BUDGET_MILLISECONDS), world.graph.chunks.pending().length);
            world.streamer.runParallel(&job);
            foreach (_; 0 .. job.count) {
                world.graph.chunks.takeChanged();
            }
            meshes.applyRecords(world.nearby[world.published]);
            meshes.batch.requeueWaiting(world.graph);
        }
        backlog = cast(uint) world.graph.chunks.pending().length;
    }

    void render(ref LocalWorld world, const(HudVertex)[] hudVertices, const(Marker)[] markers, ref const GlyphAtlas atlas) {
        if (uploadedAtlas != Maybe!uint.of(atlas.revision)) {
            web_gl_atlas(atlas.pixels.ptr, ATLAS_WIDTH, ATLAS_HEIGHT);
            uploadedAtlas = Maybe!uint.of(atlas.revision);
        }
        fogLinear = perceivedFog(world);
        CommonUniforms uniforms = commonUniforms(world, fogLinear, aspect());
        updateChunks(world);
        meshes.collectVisible(uniforms, visible);
        web_gl_begin(&uniforms, CommonUniforms.sizeof, fogLinear.red, fogLinear.green, fogLinear.blue);
        MaterialSet unseen = unseenMaterials(world);
        ChunkLayout layout = world.graph.layout;
        web_gl_voxels(visible.ptr, cast(uint) visible.length, layout.dimension, layout.cellRatio, GLOWING.words.ptr, unseen.words.ptr, Material.glass);
        Maybe!HighlightTarget target = world.findHighlightTarget();
        if (target.exists) {
            web_gl_highlight(target.value.model.ptr, &target.value.low, &target.value.high);
        }
        foreach (ref marker; markers) {
            float[MATRIX_FLOATS] model = flatten(marker.frame.m);
            web_gl_marker(model.ptr, marker.half, marker.color);
        }
        web_gl_finish(aspect(), hudVertices.ptr, cast(uint) hudVertices.length);
    }
}
