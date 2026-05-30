# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Mined is a hyperbolic voxel engine — a Minecraft-like where space is hyperbolic (H3) instead of Euclidean. Written in D with Vulkan rendering and GLSL compute shaders. The world is tiled by regular dodecahedra (12-sided cells), each subdivided into 20 tetrahedral chunks of voxels.

## Build and run

```bash
dub build          # builds everything (SDL3, shaders via glslc, then D code)
dub build --force  # force rebuild when deps change
./mined             # run (needs Vulkan GPU + X11 display)
```

Build prerequisites: `dub` (D package manager), `cmake`, `glslc` (from Vulkan SDK or shaderc), Vulkan runtime + dev libs.
c
Pre-build steps are automatic via `dub.sdl`: cmake builds a static SDL3, then `glslc` compiles all GLSL shaders to `source/shaders/spv/*.spv`.

### Test scripts

Tests use `--script` to drive the engine headlessly:
```bash
DISPLAY=:7 ./mined --script tests/screenshot.script
```
Script files are timestamped commands (screenshot, key_down/key_up, quit).

## Code style

The codebase follows a philosophy of radical explicitness, influenced by functional programming and Kotlin: data is transparent, flow is explicit, allocation is minimal, indirection is avoided. Magic is usually bad.

### Strictures

- **No `auto`**. Every variable's type is spelled out — you never have to trace or hover to know what something is.
- **No classes, no interfaces, no inheritance.** All data types are structs (value types). No vtables, no polymorphism, no hidden dispatch.
- **No exceptions for control flow.** Errors are handled structurally (e.g. `OptionalNodeId` with a `bool valid` field, sentinel values like `NodeId.init`). The few `catch` blocks exist only at I/O boundaries.
- **No comments** unless the *why* is non-obvious.
- **Always use braces** for control-flow bodies, even single-statement ones.

### Patterns

- **Free functions over methods.** Structs hold data and provide accessors/operators. Logic lives in module-level functions that take structs by `ref` (e.g. `fixMargins`, `runCharacterStep`, `checkCollision`).
- **`const ref` and `ref` to make mutation visible.** You can scan a function signature and immediately know what it reads vs. writes.
- **Static factory methods over constructors.** `VoxelData.solid(mat)`, `Graph.create(dimension)` — the call site reads like intent.
- **Fixed-size arrays over dynamic allocation.** Where the bound is known, use stack arrays (`ParentResult[3]`, `float[3]`, `T[20]`) not heap-allocated slices.
- **Selective imports.** `import common.dodeca : Side;` so you always know where a symbol comes from.
- **Explicit casts.** `cast(ubyte)`, `cast(CoordAxis)` — no implicit conversions hiding intent.

### Bindings

- Hand-written Vulkan bindings (`source/bindings/vk.d`, ~1000 lines) — no bindbc-vulkan. SDL3 uses C header imports via `-P-I` flags.

## Architecture

### Hyperbolic geometry core (`source/common/`)

The world lives in the hyperboloid model of H3. Key math types in `common.math`:
- `MVector` — 4D Minkowski-space vector (signature +,+,+,−)
- `MPoint` — normalized point on the hyperboloid (w² = x² + y² + z² + 1)
- `MDirection` — unit spacelike vector
- `MIsometry` — 4×4 matrix preserving the Minkowski inner product; represents rigid motions in H3
- `Matrix4` — raw 4×4 matrix

`MVector.mip()` is the Minkowski inner product: `x·x + y·y + z·z − w·w`. Distances use `cosh(d) = −p.mip(q)`.

### Dodecahedral tiling (`common.dodeca`)

Space is tiled by regular dodecahedra. `Side` (A–L, 12 faces) and `Vertex` (A–T, 20 vertices) are the fundamental enums. Side reflections (`sideReflection`) map between adjacent cells. Each dodecahedral cell contains 20 tetrahedral chunks (one per vertex).

### Graph (`common.graph`)

`Graph` is an adjacency structure of dodecahedral cells. Each cell is a `NodeContainer` identified by `NodeId` (128-bit hash). Neighbors are linked via `Side` reflections. The graph expands lazily via `ensureNeighbor` / `ensureNearby` (BFS from camera position up to a distance threshold).

### Chunks and voxels (`common.node`, `common.chunks`)

Each `Node` holds 20 `Chunk`s (one per `Vertex`). `VoxelData` is either `Solid` (single material) or `Dense` (flat array of `Material` values, dimension³ entries). `ChunkState` tracks lifecycle: Fresh → Generating → Populated.

### Positions (`common.proto`)

`Position` = `NodeId` + `MIsometry!float` (local transform within that cell). Camera migration (`migratePosition`) detects when the local transform crosses a face and hops to the neighbor.

### World generation (`common.worldgen/`, `source/shaders/worldgen.comp`)

Terrain uses horosphere-based elevation with Voronoi material selection in (temperature, rainfall) space. CPU path in `common.worldgen.mod_`, GPU path via `worldgen.comp` compute shader. `WorldgenDriver` manages per-frame chunk generation budget.

### Rendering (`source/client/graphics/`)

Vulkan renderer with:
- **Surface extraction** (`extract.comp`): compute shader converts dense voxel data into face lists (GPU-side marching)
- **Voxel drawing** (`voxels.vert/frag`): indirect draw from extracted surfaces, with per-chunk transforms uploaded as vertex buffer
- **Fog** (`fog.frag`): fullscreen post-pass for distance fog
- Slot allocator: up to `MAX_SLOTS` (4096) chunk slots, `CONCURRENCY` (128) extraction tasks per frame

### Client/Server split (`source/client/`, `source/server/`)

`ClientSim` and `Sim` are parallel simulation structs. `Renderer` currently runs an integrated client (no network). The server path (`source/server/`) exists but the main loop drives the client directly.
