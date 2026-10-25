# mined

A voxel engine on the hyperbolic {5,3,4} honeycomb, written in D (betterC, LDC). Worlds are plugins, shared
libraries loaded at startup that call the engine through a table of functions; Lua runs the test scripts.

## Commands

- Build: `dub build -q -b release --compiler=ldc2` (add `-c headless` for the headless tools)
- Unit tests: `dub test -q --compiler=ldc2`
- Behavior tests: `dub run -q -b release --compiler=ldc2 -c headless -- --out /dev/stdout tests`
- Repaint check: `dub run -q -b release --compiler=ldc2 -c headless -- --worldgen structure city --check-repaint --out /dev/stdout` (also `backrooms`, and `planet`, which covers strokes)
- Material census (cells of each material in the terrain world around the origin):
  `dub run -q -b release --compiler=ldc2 -c headless -- --material-census 5 --out /dev/stdout`
- Structure slice (generated voxels in each quarter around the root at one height, `#` solid and `.` open):
  `dub run -q -b release --compiler=ldc2 -c headless -- --worldgen structure backrooms --slice 1 --out /dev/stdout`
- Load and flight benchmark: `dub run -q -b release --compiler=ldc2 -- --bench-load [--profile] --out /dev/stdout`
  (reports chunks loaded within 2 and 4 units of the camera per leg; use those to judge loading while moving, and
  what keeps the rest within 4 from loading: generating, building, unscanned, scanned, unlisted, unmade)
- World digest (a hash of the generated terrain; compare before and after any change meant to keep output identical):
  `dub run -q -b release --compiler=ldc2 -c headless -- --world-digest --out /dev/stdout`
- Generation and nearby search benchmarks: `-- --bench-gen [radius] --out /dev/stdout` and
  `-- --bench-nearby [radius] [iterations] --out /dev/stdout` (same `dub run` prefix as above)
- Hash map benchmark (NodeId churn at 2M live keys, including the slowest batch of 1024 changes):
  `dub run -q -b release --compiler=ldc2 -c headless -- --bench-hashmap --out /dev/stdout`
- Screenshot: `dub run -q -b release --compiler=ldc2 -- --screenshot screenshots/<new name>.png --out /dev/stdout tests/visual/<script>.lua`
- Run through `dub run`, never the built binaries directly.
- A debug build (no `-b release`) keeps asserts; release builds drop them.

## Testing

- Behavior tests generate the world on demand around the body. A test that calls `world:live()` loads it a budget at a
  time the way the game does; anything about streaming, loading order or frame budgets needs a live test.
- Benchmarks: repeat runs and compare against a baseline measured the same way. Never store the numbers.
- A flight leg where `published` stops rising while restarts climb and `unlisted` grows is the nearby rebuild failing.
  Rare failures need 20 or more legs; raise `BENCH_FLIGHT_LEGS` temporarily.
- Don't `printf` from the windowed binary while the report goes to `/dev/stdout`; the report is a second handle on the
  same file and the two overwrite each other.
- Screenshots go to new filenames, compared by eye against earlier ones.

## Lua

- Booleans are named `is_` or `has_gi`. `and`, `or` and conditions take only booleans; write `~= nil` out.

## Worlds

- No randomness outside the API. Inside a tile use `pick`; for choices neighboring tiles must agree on, use hashes
  with salts.
- Every plane rolls rises from its vertices with its world's odds, so horospheres stack on horospheres. Trees are
  endless columns that must clear every plane below them; keep their odds low.

## Geometry

- Things more than about 2 units (about 45 cells) from the viewer shrink to specks, and vertical lines spread apart
  with height. Anything meant to be seen whole stays within that.
- From altitude h the ground fills only 2*atan(e^-h) around straight down, and an endless column at distance d shows
  within that angle above its foot. Aim screenshots accordingly.
- Node transforms are float32; a node more than about 8 units from the frame origin has almost no distance information
  left, and moving the frame toward it turns that into garbage. Re-derive transforms from the camera node
  (`NearbyScratch.rederive`) before using them near the camera.
- Rebasing keeps a transform's float error in its center's Minkowski norm, about cosh^2(d) x epsilon from wherever it
  was made. Anything that keeps old transforms checks them against the rounding allowed at their current distance
  (`isOffHyperboloid`).
- The nearby set follows the surfaces and grows about e^1 per unit, so its outer unit holds most nodes. The shell table
  in `--bench-load` shows the cost per shell.
- A nearby rebuild copies the kept part of the old set a slice per frame (`continueKeeping`). Until it finishes, the
  published set's transforms must not change, so rebases wait.
- `gravityAt` reads only the horospheres already stored for the body's node (`isGravityKnown`); with none stored it
  would give the root plane's up. The controller keeps its up until they are stored, and anything that places the body
  calls `ensureGravityAt`.
- `pathBetween` (behind `refIn`, `planeOfHorosphereIn`, `nodeToNode`) walks both nodes up the first-parent tree to
  where they meet, which can be far above two nearby nodes. Its result matches going through the root.

## Threading

- Only the main thread changes the graph. Parallel jobs (`WorkerPool.run`) read it through `graph.threadViews`, one
  `GraphView` per thread that works out missing nodes as virtual ones, and write only their own outputs or the chunk
  they were given. Something several threads may claim is claimed with one atomic swap. No mutexes.
- A chunk record is one 64-bit word with its state and flags in the top byte. A parallel pass changes a neighbor's
  state or queued flag only through `casState` / `claimQueued`.
- Background tasks (chunk voxels, buildings) work from snapshots (`ChunkParams`, `BuildingPlan`) and hand results back
  through lock-free queues. A task may only be submitted while its result has room in the result queue.
- Long tasks call a yield between slices so a waiting job gets every thread quickly.
- Never read GPU-mapped buffers back on the CPU; keep what the CPU needs on the host side.

## Memory

- Per-slot and per-block stores are slabs mapped from the system. The eviction sweep gives back the pages of freed
  records (`Slab.note`, `discardNoted`, a budget of `DISCARDS_PER_FRAME`), so a freed record must be reset to its
  all-zero init or never read before it is written again.
- The bench memory line's "free but held" is memory malloc keeps after frees. `malloc_trim` returns it but takes about
  80-90 ms with malloc's locks held, so it isn't called.
- Anything a tile paints must be repaintable from its key. A tile drops once nothing pins it and it has been idle
  `TILE_IDLE_SWEEPS` sweeps, and comes back by being painted again.
- The load radius comes from the fog (`FOG_LOAD_THRESHOLD` in `world.d`), not from the render radius directly.
- A horosphere lives while nodes list it, horospheres rise from it, tiles it painted are alive (`Horosphere.tiles`), or
  the world opened it. It references its foot node, so far nodes that are unloaded but not evicted drop their horosphere
  lists; otherwise the foot node would keep its own horosphere alive forever.

## Code structure

Layers depend only on the ones above them: `base` on nothing, `geometry` on `base`, `common` on both and the plugin
API, `client` on all.

- `source/main.d`: windowed game, screenshots and the load/flight benchmark.
- `source/headless.d`, `source/worldcheck.d`: script runner and world checks and benchmarks without a window.
- `source/unittests.d`: the unit test runner; it imports every module with tests, in layer order.
- `source/bindings/`: `lua.c` (all of Lua as one ImportC module) and `platform.c` (Vulkan with its Xlib or Metal surface, X11 and the XInput 2 calls).
- `source/base/`: containers (`array.d`, `hashmap.d`, `slab.d` with `RunPool` and `FreeIndices`, `allocator.d`),
  `pages.d` (memory mapped from the system, given back a page at a time), `parallel.d` (worker pool, futex waits,
  lock-free queue), `clock.d`, `crash.d` (backtraces), `murmur.d`, `splitmix.d` (the seeded mixer behind worldgen
  rolls and the API's `pick`), `names.d`, `units.d`, `vector3.d`, `numbers.d` (`lowerOf`, `higherOf`, `clamped`).
- `source/geometry/`: `lorentz.d` (hyperboloid points and motions), `honeycomb.d` (the {5,3,4} cell, its faces and
  corner cubes), `cube.d` (cells and axis maps), `ray.d`.
- `source/common/`
  - `graph.d`: node topology and the parts it is made of; `chunks.d`: chunk blocks and the mesh queue;
    `view.d`: `GraphView` and the per-thread views.
  - `node.d`: chunk layout and voxels; `neighbors.d`: cells across chunk borders; `material.d`, `settings.d`;
    `position.d`: a node and the motion within it.
  - `traversal.d`: the nearby search; `eviction.d`: unloading nodes, chunks and tiles.
  - `character/`: collision and movement; `raycast/`: ray casts.
  - `worldgen/`: `generation.d` (node state, chunk generation), `climate.d`, `plane.d`, `horospheres.d` (the root's
    plane and what rises from every plane, as planes or upright columns, which of them reach each node, and the
    grounds and gravity they give), `structure.d` (sites and lines), `blueprint.d` (what each tile painted: brushes on
    lines and strokes), `strokes.d` (tapered strokes along geodesics drawn with the API's pen, and the index from each
    node they reach back to the tile that drew them), `store.d` (structure per node, buildings, and the pins that keep
    a tile until the nodes it paints have built), `building.d` (a node's brushes and strokes, pulled from the tiles that
    reach it), `spawn.d`.
- `source/client/`
  - `game.d`: the player, movement modes and stepping the world; `camera.d`: the view's heading and pitch.
  - `arguments.d`: command line values and exit statuses shared by both programs; `config.d`: the settings file;
    `png.d`: screenshots.
  - `world.d`: `LocalWorld`, the per-frame update and its budget split between nearby search, streaming and eviction,
    and the fog, whose reach sets how far the world loads.
  - `streaming.d`: which chunks to load and when; `tasks.d`: worker queues for chunks and buildings; `arrivals.d`:
    joining arrived chunks to their neighbors in parallel passes.
  - `structures.d`: the main-thread host of the world API (the root and placed structures); `tiles.d`: tiles planned
    and painted on the worker threads, each with its own host of the API: faces of planes, and segments of upright
    horospheres drawn with the pen.
  - `plugins.d`: loads every library in `lib/`, calls its `plugin` entry point and keeps the worlds it registers.
  - `script.d`, `lua.d`: the test script API; `sampler.d`: the profiler; `meshing.d`, `graphics/`: rendering.
  - `cocoa.d`: the macOS window (AppKit through the Objective-C runtime, a `CAMetalLayer` for MoltenVK), reporting
    keys as X keysyms so `main.d` handles input the same way on both platforms.
- `source/shaders/`: GLSL, compiled into `spv/` by the windowed build.
- `plugins/`: dub sub-packages declared in `dub.sdl`. Source libraries are shared code compiled into each plugin that
  uses them; each plugin is a shared library built into `lib/` before the engine, whose `plugin` function (named by
  `pragma(mangle, ENTRY)`) registers its worlds by name.
  - `api/`: `plugins.api.api`, the world API: sites, boxes, materials, the pen, the `Api` table of functions a world
    calls, and the `Registry` a plugin registers worlds with. The engine links it too.
  - Source libraries: `turtle/` (a site and a pen wrapped around the API, and the helpers every plugin shares:
    `lowerOf`, `higherOf`, `clamped`, `upright`, `cornersOf`), `box/` (the square tower and the hut), `buildings/`
    (building types on `building.d`, chosen through `types.d`), `connector/` (the tower from a lower surface up to
    the horosphere risen from it, meeting each at its own kind of floor), `blocks/` (city blocks and streets),
    `rooms/` (the backrooms' layers along the same streets, `levels.d` holding the layers and biomes),
    `horospheres/` (the kinds of horosphere with their tags and tiles: wild terrain, city, backrooms and the tree,
    which `tree.d` draws a segment at a time without end).
  - Plugins, one world each: `planet` (the terrain world: wild terrain at the root with every kind rising, `road`,
    and a tree beside the spawn), `road` (the viaduct), `city`, `backrooms`, `tower`, `crown`, `trail`; `fixtures`
    holds the worlds the behavior tests load.
- `tests/`: behavior tests (`lib/` helpers and shared constants, `visual/` screenshot scripts, `live/` tests that
  load the world live).
- `tools/gridvolume.py`: compares the volumes of chunk cells for uniform and geometric grid spacings.
