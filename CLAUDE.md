# mined

A voxel engine on the hyperbolic {5,3,4} honeycomb, written in D (betterC, LDC). Worlds are plugins, shared
libraries loaded at startup that call the engine through a table of functions.

## Commands

- Build: `dub build -q -b release --compiler=ldc2` (add `-c headless` for the headless tools)
- Unit tests: `dub test -q --compiler=ldc2`
- Behavior tests (D scripts in `source/scripts/tests.d`; give name prefixes to run some):
  `dub run -q -b release --compiler=ldc2 -c headless -- --tests [prefix ...] --out /dev/stdout`
  (`--views` instead runs the screenshot view scripts without rendering, to check they still run)
- Repaint check (drops every other tile and paints them again; the voxels must come out the same):
  `dub run -q -b release --compiler=ldc2 -c headless -- --worldgen structure city --check-repaint --out /dev/stdout`
  (also `backrooms`, `library`, `lattice`, which covers edge tiles, and `planet`, which covers strokes)
- Forget check (builds around the anchor, moves away until eviction forgets the tiles, lines, edges and pending touches
  there, then builds the anchor again; reports what was left and whether any voxel changed): same worlds,
  `dub run -q -b release --compiler=ldc2 -c headless -- --worldgen structure lattice --check-forget --out /dev/stdout`
- Material census (cells of each material in the terrain world around the origin):
  `dub run -q -b release --compiler=ldc2 -c headless -- --material-census 5 --out /dev/stdout`
- Structure slice (generated voxels in each quarter around the root at one height, `#` solid and `.` open):
  `dub run -q -b release --compiler=ldc2 -c headless -- --worldgen structure backrooms --slice 1 --out /dev/stdout`
- Load and flight benchmark: `dub run -q -b release --compiler=ldc2 -- --bench-load [--profile] [--flight-speed <units/s>] --out /dev/stdout`
  (reports chunks loaded within 2 and 4 units of the camera per leg; use those to judge loading while moving, and
  what keeps the rest within 4 from loading: generating, building, unscanned, scanned, unlisted, unmade; each leg also
  counts frames over 16.7 ms, lists the first few by phase, and gives each published rebuild's frames, nearby time and
  how far the camera moved meanwhile). Add `--worldgen structure <name>` for another world. Flights default to the
  noclip speed (0.6 units/s); `--profile` reports load, flight and the settle after it separately.
- World digest (a hash of the generated terrain; compare before and after any change meant to keep output identical):
  `dub run -q -b release --compiler=ldc2 -c headless -- --world-digest --out /dev/stdout`
- Generation and nearby search benchmarks: `-- --bench-gen [radius] --out /dev/stdout` and
  `-- --bench-nearby [radius] [iterations] --out /dev/stdout` (same `dub run` prefix as above)
- Hash map benchmark (NodeId churn at 2M live keys, including the slowest batch of 1024 changes):
  `dub run -q -b release --compiler=ldc2 -c headless -- --bench-hashmap --out /dev/stdout`
- Screenshot of a view script (`source/scripts/views.d`), rendered offscreen:
  `dub run -q -b release --compiler=ldc2 -- --screenshot screenshots/<new name>.png --out /dev/stdout <view>`
- Run through `dub run`, never the built binaries directly.
- Never open a window: no plain `dub run` of the game and no `--drive`. Only the headless configuration and the
  windowed build's offscreen modes (`--screenshot`, `--bench-load`) may be run. Anything that needs a window is for
  the user to run.
- Release builds keep asserts and bounds checks (`--enable-asserts --boundscheck=on` on every `dflags` line in
  `dub.sdl`); a failed check halts.

## Testing

- Behavior tests generate the world on demand around the body. A test that calls `world.live()` loads it a budget at a
  time the way the game does; anything about streaming, loading order or frame budgets needs a live test.
- A failed `check` stops the script from stepping but does not unwind it, so every loop in a script also stops on
  `world.isFailed`.
- Benchmarks: repeat runs and compare against a baseline measured the same way. Never store the numbers.
- A flight leg where the camera moves more than about a unit per published rebuild, narrowings or abandons climb and
  `unlisted` grows is the nearby rebuild failing. Rare failures need 20 or more legs; raise `BENCH_FLIGHT_LEGS`
  temporarily.
- A rebuild's cost grows with how far the camera moved since the last publish, so anything that slows rebuilds (budget
  taken, bigger sets) pushes it into a slow regime that feeds itself. After touching the nearby search, streaming or
  eviction, check the per-leg rebuild line at `--flight-speed 3`.
- Don't `printf` from the windowed binary while the report goes to `/dev/stdout`; the report is a second handle on the
  same file and the two overwrite each other.
- Screenshots go to new filenames, compared by eye against earlier ones.

## Worlds

- No randomness outside the API. Inside a tile use `pick`; for choices neighboring tiles must agree on, use hashes
  with salts.
- Every plane rolls rises from its vertices with its world's odds, so horospheres stack on horospheres. Trees are
  endless columns that must clear every plane below them; keep their odds low.
- A pentagon's quarters tile the space over it only within half an edge (12 cells) above and below its plane; higher,
  each quarter's column belongs to its own vertex and they pull apart. Floors spanning quarters stay in that slab;
  taller work follows a single line (Babel, branches) or stacks risen planes joined by connectors (the library).
- Brushes on a line apply in an order fixed by their tile's key (`BrushRank`, placed structures first), never by when
  the tile was painted, so tiles dropped and painted again in any order give the same voxels. Strokes are taken in the
  same order.
- `api.tileEdges` runs once per honeycomb edge at its canonical site (`edgeSite`: z along the edge from its lower
  corner) and may paint only within that edge, z from 0 to `edgeCells` - 1, which reaches the four nodes around it.
- A world that fills space instead of following planes loads a ball growing e^2 per unit, and every unit moved brings a
  shell about as big as the ball. Give it fog (`api.fog`) or the nearby rebuild can't keep up.
- An entrance spawns one unit before its spot, facing it; the spot may lie outside the site's column (beyond -12..11
  cells), since it's only a point.

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
- Reach tests written `!(x > t)` pass NaN, and a set that outlives a few units of travel drifts far enough from the
  camera's frame to overflow its transforms. Sets being built are abandoned after `REBUILD_ABANDON_TRAVEL` for that.
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
- Paint-ahead takes candidates in the streamer's scan order (near-camera bands first); anything it misses is painted
  node by node on the main thread.
- Never read GPU-mapped buffers back on the CPU; keep what the CPU needs on the host side.

## Memory

- Per-slot and per-block stores are slabs mapped from the system. The eviction sweep gives back the pages of freed
  records (`Slab.note`, `discardNoted`, a budget of `DISCARDS_PER_FRAME`), so a freed record must be reset to its
  all-zero init or never read before it is written again.
- The bench memory line's "free but held" is memory malloc keeps after frees. `malloc_trim` returns it but takes about
  80-90 ms with malloc's locks held, so it isn't called.
- Anything a tile paints must be repaintable from its key. A tile drops once nothing pins it and it has been idle
  `TILE_IDLE_SWEEPS` sweeps, and comes back by being painted again.
- The load radius comes from the fog (`FOG_LOAD_THRESHOLD` in `world.d`), not from the render radius directly. A
  world's own fog (`Blueprint.fog`) caps the render radius (`LocalWorld.viewRadius`).
- A dropped tile is forgotten once every node around every edge it painted is evicted; an edge goes with its last tile
  (taking its nodes' pending touches), and a line once nothing touches, pins or paints it. Placed structures and
  endless lines are kept.
- Everything made per unit traveled must be freed as fast as it is made, or fast flight leaks. Each eviction phase may
  stop at its deadline only after freeing as much as was made since the last sweep (`madeLive` tiles, `madeNodes`
  nodes). Check a change with `--check-forget` and the bench memory line at `--flight-speed 3` in the lattice, which
  makes about 13 tiles per node.
- `HashMap.previous` holds stale copies below the migration cursor, some over pages already given back; walk a map
  with its `opApply`, never its tables.
- A horosphere lives while nodes list it, horospheres rise from it, tiles it painted are alive (`Horosphere.tiles`), or
  the world opened it. It references its foot node, so far nodes that are unloaded but not evicted drop their horosphere
  lists; otherwise the foot node would keep its own horosphere alive forever.

## Code structure

Layers depend only on the ones above them: `base` on nothing, `geometry` on `base`, `common` on both and the plugin
API, `client` on all.

- `source/main.d`: windowed game (`[` and `]` step through the terrain and every registered world), screenshots and
  the load/flight benchmark.
- `source/headless.d`, `source/worldcheck.d`: script runner and world checks and benchmarks without a window.
- `source/unittests.d`: the unit test runner; it imports every module with tests, in layer order.
- `source/bindings/platform.c`: Vulkan with its Xlib or Metal surface, X11 and the XInput 2 calls, from the system
  headers through ImportC.
- `source/base/`: containers (`array.d`, `hashmap.d`, `slab.d` with `RunPool` and `FreeIndices`, `allocator.d`),
  `pages.d` (memory mapped from the system, given back a page at a time), `parallel.d` (worker pool, futex waits,
  lock-free queue), `clock.d` (timers, and `FrameClock`, which steps the game by the mean of recent frames so uneven
  frame timing doesn't show as uneven motion), `crash.d` (backtraces), `murmur.d`, `splitmix.d` (the seeded mixer behind worldgen
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
    grounds and gravity they give), `structure.d` (sites and lines, and the canonical site of each edge),
    `blueprint.d` (what each tile painted: brushes on lines and strokes; the world's entrance, route and fog), `strokes.d` (tapered strokes along geodesics drawn with the API's pen, and the index from each
    node they reach back to the tile that drew them), `store.d` (structure per node, buildings, and the pins that keep
    a tile until the nodes it paints have built), `building.d` (a node's brushes and strokes, pulled from the tiles that
    reach it), `spawn.d`.
- `source/client/`
  - `game.d`: the player, movement modes and stepping the world; `camera.d`: the view's heading and pitch.
  - `arguments.d`: command line values and exit statuses shared by both programs; `config.d`: the settings file;
    `png.d`: screenshots.
  - `world.d`: `LocalWorld`, the per-frame update and its budget, split between nearby search and streaming after
    taking out what eviction needed the frame before, and the fog, whose reach sets how far the world loads.
  - `streaming.d`: which chunks to load and when; `tasks.d`: worker queues for chunks and buildings; `arrivals.d`:
    joining arrived chunks to their neighbors in parallel passes.
  - `structures.d`: the main-thread host of the world API (the root and placed structures); `tiles.d`: tiles planned
    and painted on the worker threads, each with its own host of the API: faces of planes, segments of upright
    horospheres drawn with the pen, and edges of the honeycomb.
  - `plugins.d`: loads every library in the `lib/` beside the executable, calls its entry point (`ENTRY`, whose name
    carries the API version) and keeps the worlds it registers.
  - `script.d`: the `Script` API the behavior tests and views drive the game through, and the recorder that writes a
    session as D; `drive.d`, `frames.d`, `images.d`: playing a list of drive actions in the window and timing its
    frames; `sampler.d`: the profiler; `meshing.d`, `graphics/`: rendering.
  - `cocoa.d`: the macOS window (AppKit through the Objective-C runtime, a `CAMetalLayer` for MoltenVK), reporting
    keys as X keysyms so `main.d` handles input the same way on both platforms.
- `source/scripts/`: `tests.d` (behavior tests), `views.d` (screenshot views), `drives.d` (drives), each a table of
  named entries, and the helpers they share: `walk.d` (walking constants and checks, building walls and steps) and
  `climb.d` (following a structure's route).
- `source/shaders/`: GLSL, compiled into `spv/` by the windowed build.
- `plugins/`: dub sub-packages declared in `dub.sdl`. Source libraries are shared code compiled into each plugin that
  uses them; each plugin is a shared library built into `lib/` before the engine, whose entry point (named by
  `pragma(mangle, ENTRY)`) registers its worlds by name.
  - `api/`: `plugins.api.api`, the world API: sites, boxes, materials, the pen, the `Api` table of functions a world
    calls, and the `Registry` a plugin registers worlds with. The engine links it too.
  - Source libraries: `turtle/` (a site and a pen wrapped around the API, and the helpers every plugin shares:
    `lowerOf`, `higherOf`, `clamped`, `upright`, `cornersOf`, the salted hash rolls `mixed` and `roll`, and
    `treadAround`, the treads of a square spiral stair around a line), `box/` (the square tower and the hut), `buildings/`
    (building types on `building.d`, chosen through `types.d`), `connector/` (the tower from a lower surface up to
    the horosphere risen from it, meeting each at its own kind of floor), `blocks/` (city blocks and streets),
    `rooms/` (the backrooms' layers along the same streets, `levels.d` holding the layers and biomes),
    `horospheres/` (the kinds of horosphere with their tags and tiles: wild terrain, city, backrooms and the tree,
    which `tree.d` draws a segment at a time without end).
  - Plugins, one world each: `planet` (the terrain world: wild terrain at the root with every kind rising, `road`,
    and a tree beside the spawn), `road` (the viaduct), `city`, `backrooms`, `tower`, `crown`, `trail`, `babel` (an
    endless spiral stair around a hollow core), `library` (galleries of shelves on every face, four stories, rising as
    more library planes joined by connectors, in fog), `palace` (one sunken hall over the root face and its ten
    neighbors, with grand stairs down from its doors), `arbor` (an endless trunk with a spiral stair, and limbs that
    branch along edges without crossing), `lattice` (a beam on every edge with platforms, built for upright gravity
    and turned upside down, in fog); `fixtures` holds small test worlds.
- `.github/workflows/ci.yml`: unit and behavior tests, the repaint and forget checks, and the windowed build on Linux.
