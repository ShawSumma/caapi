# mined

A voxel engine on the hyperbolic {5,3,4} honeycomb, written in D (betterC, LDC) with Lua for structures.

## Commands

- Build: `dub build -q -b release --compiler=ldc2` (add `-c headless` for the headless tools)
- Unit tests: `dub test -q --compiler=ldc2`
- Behavior tests: `dub run -q -b release --compiler=ldc2 -c headless -- --out /dev/stdout tests`
- Repaint check: `dub run -q -b release --compiler=ldc2 -c headless -- --worldgen structure city --check-repaint --out /dev/stdout` (also `planet`)
- Load and flight benchmark: `dub run -q -b release --compiler=ldc2 -- --bench-load [--profile] --out /dev/stdout`
- Screenshot: `dub run -q -b release --compiler=ldc2 -- --screenshot screenshots/<new name>.png --out /dev/stdout tests/visual/<script>.lua`
- Run through `dub run`, never the built binaries directly.
- A debug build (no `-b release`) keeps asserts; release builds drop them.

## Testing

- Behavior tests generate the world on demand around the body. A test that calls `world:live()` loads it a budget at a
  time the way the game does; anything about streaming, loading order or frame budgets needs a live test.
- Benchmarks: repeat runs and compare against a baseline measured the same way. Never store the numbers.
- Screenshots go to new filenames, compared by eye against earlier ones.

## Threading

- Only the main thread changes the graph. Parallel jobs (`WorkerPool.run`) read it through `graph.threadViews`, one
  `GraphView` per thread that works out missing nodes as virtual ones, and write only their own outputs or the chunk
  they were given. Something several threads may claim is claimed with one atomic swap. No mutexes.
- Background tasks (chunk voxels, buildings) work from snapshots (`ChunkParams`, `BuildingPlan`) and hand results back
  through lock-free queues. A task may only be submitted while its result has room in the result queue.
- Long tasks call a yield between slices so a waiting job gets every thread quickly.
- Never read GPU-mapped buffers back on the CPU; keep what the CPU needs on the host side.

## Code structure

Layers depend only on the ones above them: `base` on nothing, `geometry` on `base`, `common` on both, `client` on all.

- `source/main.d`: windowed game, screenshots and the load/flight benchmark.
- `source/headless.d`, `source/worldcheck.d`: script runner and world checks and benchmarks without a window.
- `source/base/`: containers (`array.d`, `hashmap.d`, `slab.d` with `RunPool`, `allocator.d`), `parallel.d` (worker
  pool, futex waits, lock-free queue), `clock.d`, `crash.d` (backtraces), `murmur.d`, `names.d`, `units.d`,
  `vector3.d`, `numbers.d`.
- `source/geometry/`: `lorentz.d` (hyperboloid points and motions), `honeycomb.d` (the {5,3,4} cell, its faces and
  corner cubes), `cube.d` (cells and axis maps), `ray.d`.
- `source/common/`
  - `graph.d`: node topology and the parts it is made of; `chunks.d`: chunk blocks and the mesh queue;
    `view.d`: `GraphView` and the per-thread views.
  - `node.d`: chunk layout and voxels; `neighbors.d`: cells across chunk borders; `material.d`, `settings.d`.
  - `traversal.d`: the nearby search; `eviction.d`: unloading nodes, chunks and tiles.
  - `character/`: collision and movement; `raycast/`: ray casts.
  - `worldgen/`: `generation.d` (node state, chunk generation), `climate.d`, `plane.d`, `sky.d` (skies and the
    worlds near each node), `structure.d` (sites and lines), `blueprint.d` (painted brushes), `store.d` (structure
    per node, buildings), `building.d`, `spawn.d`.
- `source/client/`
  - `game.d`: the player, movement modes and stepping the world.
  - `world.d`: `LocalWorld`, the per-frame update and its budget split between nearby search, streaming and eviction.
  - `streaming.d`: which chunks to load and when; `tasks.d`: worker queues for chunks and buildings; `arrivals.d`:
    joining arrived chunks to their neighbors in parallel passes.
  - `structures.d`: the Lua structure host on the main thread; `tiles.d`: tiles planned and painted on every thread.
  - `script.d`, `lua.d`: the test script API; `sampler.d`: the profiler; `meshing.d`, `graphics/`: rendering.
- `source/shaders/`: GLSL, compiled into `spv/` by the windowed build.
- `structures/`: embedded Lua structures. `tests/`: behavior tests (`lib/` helpers, `visual/` screenshot scripts,
  `live/` tests that load the world live).
