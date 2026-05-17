# Mined

Mined is a hyperbolic voxel engine written in D. It renders a world built on hyperbolic geometry — specifically an order-4 dodecahedral honeycomb ({5,3,4}) — where space is tiled by right-angled dodecahedral cells. Each dodecahedral node contains 20 chunks (one per vertex), and chunks are connected through a graph structure that encodes the hyperbolic adjacency relationships.

The engine is a port of a Rust codebase. The reference lives at `../hypermine`. When in doubt about how something should work, check the corresponding Rust code there. The D code mirrors the Rust module structure fairly closely, but there are intentional differences (see below).

## Building and Running

```
dub build
```

The `preBuildCommands` in `dub.sdl` handle everything:
1. Builds SDL3 as a static library (X11 only, no Wayland, no audio/joystick/haptic)
2. Compiles all GLSL shaders to SPIR-V via `glslc`
3. Compiles and links the D code

Dependencies live in `deps/` as git submodules: `SDL3` and `Vulkan-Headers`.

Shaders that use `#include` need `-I source/shaders` passed to `glslc`. The vertex shader and compute shader need this; the fragment shader currently does not. If you add `#include "common.h"` to a shader, update the corresponding `glslc` line in `dub.sdl`.

The compute shader (`extract.comp`) requires `--target-env=vulkan1.1` for subgroup operations.

SPIR-V binaries in `source/shaders/spv/` are embedded into the D binary via `stringImportPaths`. After modifying a shader, you must either `dub build --force` (which re-runs preBuildCommands) or manually run the `glslc` command, because `dub` won't detect shader source changes on its own.

## Testing Visually

Run on Xephyr to avoid stealing keyboard focus:

```
DISPLAY=:7 ./mined --script tests/short_forward.script
```

A persistent Xephyr instance should already be running on `:7`. Do NOT restart it between runs. Test scripts live in `tests/` and support timed input events and screenshots:

```
0.2  screenshot /tmp/shot.png
0.5  down w
1.5  screenshot /tmp/after.png
2.0  up w
2.5  quit
```

Screenshots are taken via ImageMagick's `import -window` command. Read the resulting PNG files to visually inspect the output.

## Architecture Overview

### Hyperbolic Geometry (`source/common/`)

The world is NOT Euclidean. Space is hyperbolic, meaning:
- Parallel lines diverge
- The volume of a ball grows exponentially with radius
- The number of reachable nodes grows exponentially with graph distance

Key types:
- **`MVector!float`** — 4D Minkowski vector (x, y, z, w) where w²-x²-y²-z² = 1 for points on the hyperboloid
- **`MIsometry!float`** — 4x4 Lorentz transformation matrix (hyperbolic rigid motion). These are NOT Euclidean rotation matrices. The determinant of a 4x4 isometry is ±1, but the 3x3 sub-block determinant is NOT ±1 for Lorentz boosts.
- **`MPoint!float`** — a point in hyperbolic space (on the hyperboloid model)
- **`Position`** — a node ID plus a local isometry within that node

The Beltrami-Klein projection maps hyperbolic space to a ball model for rendering. This is a perspective projection where the near plane is at depth 1.0 and far is at 0.0 (reverse-Z). The depth comparison is `VK_COMPARE_OP_GREATER`.

### The Graph (`source/common/graph.d`)

The world is organized as a graph of **nodes**. Each node is a right-angled dodecahedron with 12 sides and 20 vertices. Nodes are connected through their sides to neighboring nodes. The graph is lazily expanded as the player moves through space.

Each node contains 20 **chunks** (one per vertex of the dodecahedron). Each chunk is a cubic grid of voxels (`dimension³`, default 12). The chunk's coordinate system is mapped into the dodecahedral cell by a `vertexChunkToNode` transform.

### Chunk Transforms and Winding

Each visible chunk gets a 4x4 transform matrix (`vertexChunkToNode * nodeToCamera`) passed as a per-instance vertex attribute. Roughly half of these transforms have negative determinant because the dodecahedral vertex positions include reflections.

The vertex shader handles this by checking `determinant(transform)` and flipping the face axis by ±3 when negative. This reverses vertex positions, UV mapping, and AO corner lookups simultaneously. Backface culling is currently disabled (`VK_CULL_MODE_NONE`) because winding is not fully consistent.

### Voxel Data and Margins (`source/common/node.d`, `source/common/margins.d`)

Voxel data is stored as a `(dimension+2)³` array — the inner `dimension³` holds actual voxels, and the 1-voxel-thick margin on each face holds data copied from the boundary. This margin allows the surface extraction compute shader to check neighbors across chunk boundaries without special-casing edges.

`initializeMargins` copies each chunk's own boundary voxels into its margins (self-continuation). `fixMargins` exchanges boundary data between neighboring chunks for correct cross-chunk AO. Currently only `initializeMargins` is used; `fixMargins` is defined but not called — wiring it up would improve AO accuracy at chunk boundaries where geometry differs between neighbors.

The voxel data is packed for GPU upload by `packVoxelsForExtraction` in `surface_extraction.d`, which creates the (dim+2)³ padded array with margins filled by copying boundary voxels outward.

### Surface Extraction (`source/shaders/extract.comp`, `source/client/graphics/voxels/surface_extraction.d`)

Surface extraction runs as a Vulkan compute shader. Each thread examines one voxel-axis pair, emits a face if there's a solid/void boundary, computes per-vertex ambient occlusion, and writes a packed `Surface` struct to an SSBO. An atomic counter tracks the face count, and a `VkDrawIndirectCommand` buffer is filled so the draw call doesn't need a CPU readback.

The `Surface` struct (defined in `source/shaders/surface-extraction/surface.h`) packs position (3×8 bits), axis+winding+flip (8 bits), material (16 bits), and 4 corner occlusion values (4×2 bits) into two uint32s.

**Ambient Occlusion Algorithm**: For each corner vertex of a face, the shader checks the 4 voxels touching that vertex on the solid side of the face (in the 2×2 grid formed by the u/v axes of the face plane). The count of solid voxels maps to an occlusion level: `level = 4 - count`. This per-world-vertex approach guarantees that adjacent coplanar faces produce identical AO values at shared edges, eliminating seam artifacts. The `inward` flag in the compute shader is inverted relative to the reference — `info.inward = self_mat == 0` — so the occlusion call passes `!info.inward` to get the correct solid side.

There is also a `cpuExtract` function in `cpu_extract.d` that implements the same algorithm on the CPU. It is NOT used in the rendering path (the compute shader does all extraction), but exists as a reference/fallback.

### Rendering Pipeline (`source/client/graphics/`)

The renderer uses raw Vulkan (no helper libraries). The binding declarations are minimal and hand-written in `source/bindings/vk.d` — only the subset of Vulkan actually used is declared. If you need a new Vulkan function, struct, or enum value, add it there.

**Per-frame rendering flow:**
1. BFS traversal of the graph from the camera position to find visible chunks
2. Upload chunk transforms to VBO
3. Record command buffer: reset counters → compute extract dispatch → barrier → draw indirect
4. All visible chunks share one SSBO of surfaces and draw with `vkCmdDrawIndirect`

**Descriptor sets:**
- Set 0, binding 0: Common UBO (mat4 view_projection, mat4 inverse_projection, float fog_density, float time, vec4 light_dir) — 160 bytes, std140
- Set 1, binding 0: Surfaces SSBO (array of Surface structs)
- Set 1, binding 1: Texture array (sampler2DArray, 39 layers for materials excluding Void)

**Shaders:**
- `voxels.vert` — unpacks Surface struct, looks up position/axis/occlusion, applies chunk transform + view-projection. The `transform` is a per-instance mat4 vertex attribute.
- `voxels.frag` — `color = texture(textures, texcoords) * occlusion`. Currently all texture layers are a uniform gray (16×16 RGBA). Real material textures are not yet loaded.
- `extract.comp` — surface extraction compute shader (described above)
- `cube.vert`/`cube.frag` — debug cube rendering (not used in normal path)

### Worldgen (`source/common/worldgen/`, `source/client/worldgen_driver.d`)

The worldgen currently produces a skeleton structure: three perpendicular 1-voxel-thick beams meeting at each chunk's low corner (coord 1 on each axis). This places edges at dodecahedral vertices, producing the visible honeycomb wireframe pattern. The `makeTestVoxels` function in `cpu_extract.d` generates this pattern.

The full terrain generation system (`generateVoxels`, `generateTerrain`, `chooseMaterial`) exists in `source/common/worldgen/mod_.d` but is fed zero-initialized enviro factors from the worldgen driver, so it produces only the thin boundary shell. Wiring up proper node state propagation (sky/land classification, elevation, temperature, rainfall) through the graph would enable real terrain.

### Input and Simulation

The main loop (`source/main.d`) handles SDL3 events, drives the simulation, and calls the renderer. WASD moves the camera in hyperbolic space. Mouse look is implemented. The simulation tick applies hyperbolic translation to the camera's `Position` (node + local isometry).

`--script` mode replaces real-time input with a deterministic script: fixed dt (0.016s), timed key events, screenshots, and quit. This is essential for reproducible visual testing.

## Coding Conventions

- **D language** — use D idioms, not C-style code where D has a better way
- **Brace every control-flow body**, even single-statement `if`/`for`/`foreach` — always use `{ }`
- **Vulkan bindings** are minimal — only declare what you use, in `source/bindings/vk.d`
- **No Wayland** — SDL3 is built with X11 only
- **Shader changes** require manual SPIR-V recompilation or `dub build --force`

## Known Issues and Future Work

- Backface culling is disabled; winding should be fixed so it can be re-enabled
- `fixMargins` is not called between neighboring chunks — AO at chunk boundaries assumes self-continuation rather than reading actual neighbor data
- Texture array uses uniform gray for all 39 material layers; real per-material textures need to be loaded
- Worldgen enviro factors are all zero — terrain generation produces only boundary shells instead of real terrain with elevation/biomes
- No fog shader (the reference has exponential hyperbolic-distance fog via a fullscreen post-process)
- The `light_dir` uniform is computed and uploaded but not used by any shader
