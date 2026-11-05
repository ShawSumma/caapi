# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

mined is a voxel engine in hyperbolic 3-space, written in D (betterC, LDC, no GC, no druntime). The world is the
{5,3,4} honeycomb: right-angled dodecahedra, four around every edge. Each dodecahedron ("node") is split into 20
cubes ("chunks") of 12^3 voxels. Rendering is Vulkan with GPU culling and multi-draw-indirect, on X11 or Cocoa. Worlds
are plugins: shared libraries loaded from `lib/` at startup that build through a table of function pointers. Play today
is walking, flying and editing blocks. `PLAN.md` is a design document for a game: nothing in it is built, and its notes on
the code were a snapshot, so check them against the tree.

Other docs: `README.md` covers dependencies and controls. `UNITS.md` defines the unit system and is required reading
before touching anything dimensional; this file does not repeat it.

## Commands

Always pass `--compiler=ldc2`. The plugins are built first by `preGenerateCommands`, so every command below also
rebuilds them. Headless tools need `--out <file>`; use `--out /dev/stdout` to see the report.

    dub run -b release --compiler=ldc2                 # build and play
    dub build -q -b release --compiler=ldc2            # build the game
    dub test -q --compiler=ldc2                        # unit tests; silent on success

    # behavior tests (scripts/tests.d), all or by name prefix
    dub run -q -b release --compiler=ldc2 -c headless -- --tests --out /dev/stdout
    dub run -q -b release --compiler=ldc2 -c headless -- --tests flat/walk structure/road --out /dev/stdout

    # the view and film scripts, run without rendering
    dub run -q -b release --compiler=ldc2 -c headless -- --views --out /dev/stdout
    dub run -q -b release --compiler=ldc2 -c headless -- --films --out /dev/stdout

    # a dropped tile repaints identically; CI runs repaint on city, backrooms, library, lattice, planet
    dub run -q -b release --compiler=ldc2 -c headless -- --worldgen structure city --check-repaint --out /dev/stdout
    # evicted structure state regenerates identically; CI runs this on lattice
    dub run -q -b release --compiler=ldc2 -c headless -- --worldgen structure lattice --check-forget --out /dev/stdout

    # hash of the terrain world; must not change across a refactor
    dub run -q -b release --compiler=ldc2 -c headless -- --world-digest --out /dev/stdout

    # render a view (scripts/views.d) offscreen to a PNG, which Read can then show
    dub run -q -b release --compiler=ldc2 -- --screenshot screenshots/name.png --out /dev/stdout city

    # build the web page, mined.html; needs lld and wasi-libc
    dub build -q -b release --compiler=ldc2 --arch=wasm32-unknown-wasi :web

    # web checks; drive quits Firefox after each run, so start it again for each one
    dub build -q -b release --compiler=ldc2 :webdrive
    firefox --headless --marionette --no-remote --profile .firefox-check
    obj/web/tool/drive obj/web/check.html "?mode=bench"    # modes: run, actions, tour, flight, world, bench
    obj/web/tool/drive                                     # plays mined.html with real input

`-- --help` lists more on both binaries: censuses, `--slice`, `--dump-structure`, `--bench-gen`, `--bench-mesh`,
`--bench-drive`, `--bench-nearby`, `--bench-hashmap` on headless; `--film`, `--drive`, `--bench-load [--profile]`,
`--record` on the game. `--world-digest`, `--dump-world`, the censuses and the `--bench-*` commands on headless always
use the terrain world and ignore `--worldgen`. Unit tests have no filter: everything in `source/unit/` runs. CI
(`.github/workflows/ci.yml`, LDC 1.36.0) runs the unit, behavior, view, film, repaint and forget checks and builds the
game. There is no linter or formatter.

## Hyperbolic space: how it has to be handled

Euclidean instincts break here. Most of these rules exist because the obvious approach is silently wrong.

### Model

- Hyperboloid model with curvature radius R = 1. `Vec4` is homogeneous with signature (+,+,+,-): `minkowski` is
  `xx + yy + zz - ww`. `Point` has `<p,p> = -1`, `w > 0`. `Normal` has `<n,n> = +1`, and `n` is positive beyond its plane.
- One distance has several forms, and code prefers the cheap one: `cosh d = -<p,q>`, `sinh d = <n,p>` for signed
  distance to a plane, `tanh d` is the Klein radius and the ray parameter (`Ray.at` is projective, so `>= 1` means never).
  All are monotone in d, so compare thresholds without converting: `coshf(a + b)`, never `coshf(a) + coshf(b)`.
- Reach tests are written `!(product > threshold)`, not `product <= threshold`, so NaN counts as in reach. Keep the form.
- `Motion` is a Lorentz matrix, column-major (`m.c[col][row]`). Its `inverse()` is the Minkowski transpose, which is
  cheap; do not use a general matrix inverse. It may be a reflection (`isMirroring`, determinant < 0).
- The Klein chart `(x,y,z)/w` keeps geodesics and planes straight, so the whole pipeline is linear: `cubeToNode` is
  projective, cell faces are flat, and `projection * camera_inverse * point` draws straight edges with no tessellation.
  `fog.frag` recovers true distance from depth with `atanh`. Klein displacements equal lengths only near the origin at
  body scale (see `UNITS.md`); `movedBy` is the one conversion.

### There are no global coordinates

- A position is `Position { NodeId node; Motion!float local; }`, normalized so the point stays inside its node
  (`normalized`, `ensureNormalized`). Anything far from its frame's origin loses float precision exponentially, since
  `w = cosh d`. Never accumulate a world position, and never key noise or effects on one.
- Crossing a dodecahedron face is a **reflection**, not a translation, and face labels are preserved: `neighbors[f]`
  leads to a node whose `neighbors[f]` leads back. Composition order is fixed:
  - point in the neighbor's coordinates: `side.mirror * local`
  - neighbor-to-frame: `transform * side.mirror`
  - frame-to-neighbor: `side.mirror * inverse`
  So chains of nodes alternate handedness. `view_parity` and `DrawTransform.reversed` in `cull.comp` undo the winding
  flip, and anything that culls or takes a cross product of world vectors must account for it.
- The body frame moves by right multiplication: `local * step`, then `orthonormalized()` to remove drift. Crossing a
  face multiplies on the left, so body-frame vectors (`velocity`, `up`, `groundNormal`) stay valid across nodes. Keep
  vectors in one frame per struct; a `float[3]` means nothing outside the frame it was taken in.
- Drawn transforms live in a floating "nearby frame" that rebases when the camera gets far from it (`followCamera`,
  `NearbyScratch.rebase`, `rederive`). `isOffHyperboloid` drops transforms that have drifted. Long chains of
  transforms are composed in `double` and cast down (`nodeToNode`). Effects must key on camera-relative position or be
  screen-space, or they pop at rebase.
- Values that need to reach far are carried along the graph, not stored globally. `Plane` is `{up, height}` relative
  to a node: `reflectAcross` and `carriedAlong(path)` move it, `snappedToFaces` cancels drift when it lands on a face,
  and `PlaneMeasure` uses `logCosh` so planes very far from a node do not overflow. `NodeState` is derived this way from
  parents, including the climate random process.

### The grid is not Z^3

- 20 cubes meet at a node center and five meet around each center-to-face-center line. No global integer lattice
  exists; a flat NxN plate of voxels is not reliably flat or square.
- Grid coordinates **reflect** at chunk borders, they do not increment. Across `Sign.minus` you enter the neighbor node
  at the same corner; across `Sign.plus` you stay in the node at `corner.across[axis]` with axes remapped by `AxisMap`.
  In both cases the boundary cell maps to a boundary cell (`acrossBorder`, `hopCell`). Always use these helpers, never
  `cell + 1`.
- Cells are not uniform in chart space. `ChunkLayout` spaces them geometrically (`gridToCube`, `cellRatio`), and
  `voxels.vert` holds the same formula. Never divide by `dimension`. Block edges vary and tilt against gravity, so no
  constant converts blocks to length; measure at a point (`BlockProbe`, `gridJacobian`, `UNITS.md` Local units).
- Cube coordinate 0 is at the dodecahedron corner on the face planes and 1 is at the node center.

### Ground, gravity and the surface

- Naming trap: the README and the code say "horosphere", but `Horosphere.plane` and `NodeState.surface` are `Plane`s:
  a spacelike normal, altitude `asinh(<n,p>)`. These are totally geodesic planes with intrinsic curvature -1, not true
  horospheres (lightlike normal, intrinsically flat, measured by a Busemann function). `demo/holonomy` confirms it: five
  right turns on the ground close a right-angled pentagon and turn the compass 90 degrees. Use plane formulas.
- Each plane is tiled by {5,4}: right-angled pentagons, the dodecahedron faces, with sides of one honeycomb edge (about
  1.06 R, 24 cells), four around a vertex. A "tile" is one pentagon.
- Surfaces at constant altitude are equidistants, which curve. A body moving along a geodesic rises off them at
  `s^2 tanh(h)`, which `flat/curve` checks.
- Curvature means area turns frames (`UNITS.md`, Curvature and holonomy). Replayed inputs do not close loops, and
  no orientation may be integrated open-loop: camera, body and compass re-level every frame.
- `gravityAt` blends the nearby planes and can point along an upright column. Gravity needs node state and horospheres
  to be known (`isGravityKnown`); code handles the case where they are not.
- Gravity is continuous by construction, so a node face or a plane leaving reach can never change it. Anything that adds a
  ground must fade it out before `GRAVITY_REACH` (`GROUND_REACH - NODE_RADIUS`); the straight-line tests in
  `unit/horospheres.d` and the round trips in `scripts/tests.d` measure this.
- A plane's negative side is a half-space that runs forever, so reach tests on non-upright planes are signed, and risen
  planes must face their ancestors (`isApart`). Their rock never contains the ground they rose from.
- Structures run along honeycomb edge lines: these are full geodesics, and the four nodes around each form a column with
  its own chart, `(x, y)` in `-dim .. dim-1` and `z` in cells along the line (`columnPoint`, `ColumnChunk`). Sites are
  frames at vertices, and turns are exact quarter turns, which is why `forward(1).right()` five times closes a pentagon.

### Exponential growth sets every budget

- Volume grows like e^(2r), so "just look a bit farther" is never cheap. Traversals have explicit reach, capacity or
  deadline. `NearbyScratch` only expands past `FULL_RADIUS` through nodes that may hold content (`NodeContent`,
  `mayHoldContent`), so the far view costs a thin band and not a ball. Radii and their costs are coupled: `loadRadius`
  follows `viewRadius`, and `radiusCut` backs off under fast travel.
- All per-frame work is budgeted in milliseconds and resumable (`STEP_BUDGET_MILLISECONDS`, `Pacing`, `ParallelJob`
  deadlines, `advance`, `continueKeeping`). Evictions and sweeps run incrementally. Do not add an unbounded per-frame loop.
- Hold nothing forever: unedited chunks drop and regenerate, idle tiles drop and repaint, idle nodes evict.
- The web build has one thread, so its batch sizes in `streaming.d`, `traversal.d` and `world.d` are tuned for that. Size them by deadline, not by count.

## Code structure

    source/base/        containers, allocator, parallel pool, units, hashing, crash reports, stdio (C stdio declared for wasm)
    source/geometry/    lorentz.d (model), honeycomb.d (faces, corners, mirrors, computed at compile time), cube.d, ray.d
    source/common/      headless world: no window or GPU
      graph.d             Graph: nodes, parents, ids, ownership of every store
      view.d              GraphView: thread-local overlay that lets workers read and extend the graph
      node.d chunks.d     Chunk word, Voxels, ChunkLayout, ChunkStore
      neighbors.d         cell and chunk adjacency across borders
      traversal.d         NearbyScratch: time-sliced BFS of nodes around the camera, with frame rebasing
      eviction.d          incremental unload of nodes, chunks and tiles
      raycast/ character/ ray casts; capsule controller (features collects, sweep moves, controller decides)
      worldgen/           generation (voxels), climate, plane, horospheres, structure (sites, lines),
                          blueprint (brushes), building (per-node stamped paint), strokes, store, spawn
    source/client/      engine around the world
      world.d game.d      LocalWorld (nearby, streaming, editing); Game (camera, character, step)
      streaming.d tasks.d arrivals.d   scan, plan, generate on workers, integrate on main
      meshing.d           voxels to packed faces
      structures.d tiles.d plugins.d   host side of the plugin API: main-thread and tile (worker) implementations
      script.d drive.d    test and scripted-input tooling
      graphics/           Vulkan renderer; voxels/ has cull, mesh upload, surface, textures (game binary only);
                          uniforms.d, frustum.d, matrices.d, voxels/textures.d have no Vulkan and are shared with web/
    source/shaders/     GLSL for both renderers; compiled to shaders/spv by glslc in preBuildCommands and embedded with import(), or expanded to GLSL ES at compile time by web/renderer.d
    source/bindings/    platform.c and kernel.c, read with ImportC for Vulkan, X11, futex
    source/scripts/     tests (behavior), views (screenshots), films, drives, walk and climb helpers
    source/unit/        one unittest module per engine module, imported by hand from source/unittests.d
    plugins/api/        the ABI: api.d, flags.d
    plugins/turtle/ box/ buildings/ connector/ blocks/ rooms/ horospheres/    sourceLibrary helpers shared by plugins
    plugins/*/plugin.d  each world, one dynamicLibrary sub-package
    web/                the game as one local page, single-threaded on WebGL2: main.d (exports, session), renderer.d (CPU culling, face texture),
                        glue.js (imports for wasm), play.js (the page), check.js (test and benchmark page), shell.html, imports.syms (the allowed JS imports)
    web/tool/           pack.d packs mined.html and obj/web/check.html; drive.d drives Firefox over Marionette, playing mined.html with real input or reporting a check page

Entry points: `source/main.d` (game), `web/main.d` (`:web`, wasm32 linked by `wasm-ld` against wasi-libc, plugins linked in, no threads), `source/headless.d` with `source/worldcheck.d` (`-c headless`, no `client/graphics`),
`source/unittests.d` (`dub test`, also no `client/script`, `drive`, `structures`, `tiles`, `scripts/`, so unit tests cannot
place plugin worlds). Dependencies run base, geometry, common, client, scripts, with `plugins.api` usable from common up.
Modules within a layer import each other freely, cycles included.

### Data flow

Nearby traversal finds nodes around the camera, and `Streamer` scans them for chunks in range. `ChunkParams.make` snapshots
what generation needs, using a `GraphView` so workers can run it, and a worker runs `generateVoxels`. `Integrator`
stores results in two parallel passes (store, then settle against neighbors), queues meshing, and may restore dropped
neighbors. Chunk life: `fresh`, `generating`, `populated`, and `dropped` (voxels released, regenerable). Edited chunks are
pinned and never dropped. A chunk proven uniform stores just its material; a chunk proven buried may defer materials (a
dirt stand-in) until it borders air (`resolveIfExposed`).

### Threading: Graph and GraphView

- The main thread owns `Graph`. Worldgen functions take `ref GraphView`, which works in two modes: `owner` set (main
  thread, mutates the graph) or `owner` null (worker overlay).
- In a worker, missing neighbors become **virtual nodes**: handles with bit 31 set (`VIRTUAL`). So a `uint node` in view
  code may not be a real slot. Go through view methods; never index `Graph` stores with it.
- A slice from `horospheresAt` dangles as soon as anything calls `ensureHorospheresAt`, which `measureOf` and `climateAt` do.
  A loop that calls out re-fetches it by index, as `cover` and `planCandidate` do.
- Workers record states, horospheres and rises in the view; `ThreadViews.finish` merges them on the main thread. Creating a
  horosphere needs the main thread: the view records it in `wanted`, `isBlocked` becomes true, the result is discarded
  (`forget`), and the work runs again on the main thread or a later round.
- `Chunk` is one `ulong` holding a 56-bit voxel pointer or fill plus flags. Only state and the queued flag have atomic
  accessors (`casState`, `loadState`, `claimQueued`). Everything else assumes a single writer in that phase.
- Slots are reused after eviction. Keep `NodeId` for anything that outlives a frame, or hold `graph.reference(slot)`.

### Determinism

Worldgen is a pure function of the node. `NodeId` is `hash(firstParent, face)`, where the first parent is the lowest-index
parent face. A node's parent faces are the faces that shorten its word from the root (`childParentFaces`, at most 3, all
mutually adjacent), and adjacent faces' mirrors commute (`appendReduced` cancels through them), so a node gets the same
id whichever path reaches it. Randomness comes from `id.spice()`, `SplitMix` and salts, never from visit order or
time. That is what lets chunks and tiles be dropped and rebuilt, and what `--world-digest`, `--check-repaint` and
`--check-forget` guard. Refactors must leave these unchanged. Changing worldgen changes the digest on purpose; say so.
Keep `FIBONACCI_MULTIPLIER` 64-bit, because world hashes depend on it; `TABLE_MULTIPLIER` is the one for hash tables.

### Plugins and structures

- `plugins/api/api.d` is the ABI, called through `Api` function pointers. `ENTRY` carries the version: any change to an API
  struct, enum or the `Api` table must bump it. `Material` lives there too. A new material also needs an entry in the keyed
  tables `MATERIAL_COLORS` (`common/material.d`) and `GRAIN` (`graphics/voxels/textures.d`); a missed entry silently
  defaults to zero.
- Plugins import only `plugins.*` and `core.stdc`, which is why `turtle.d` has its own `lowerOf`, `higherOf` and `clamped`. Do not merge
  those with `base.numbers`. To add a world: a sub-package in `dub.sdl`, an entry in the root `preGenerateCommands`, a
  `pragma(mangle, entryOf!__MODULE__)` function that registers names, and an entry in the web table in `client/plugins.d`.
  One library may register many worlds (`fixtures` does).
- Two host implementations stand behind `Api`: `main*` in `structures.d` and `tile*` in `tiles.d`. Add a call to both.
- Two ways to build. **Placed** structures run on the main thread in depth order (`place`, `PAINT_REACH`, `PLACE_SLACK`) and
  may claim sites. **Tiles** run on workers in any order and may be dropped and repainted, so they decide everything from
  `site.hash` or `api.random`, which is seeded per tile; they cannot place or claim. A paint may only touch nodes not yet
  built (a tile: structure not finished; a placed structure: within `PAINT_REACH` of its depth), so painting "behind" is
  refused.
- `HorosphereForm` sets what is behind a plane: `terrain` and `solid` fill forever, `bare` is empty. Tiles on a filled ground
  carve their own air, and connectors assume solid ground at both ends, with terrain flattened around their axis.
- Plugin errors are refusals, not crashes: `api.fail` and `refuse` store a message that surfaces as a `StructureProblem`.
- Painting becomes `Brush`es on canonical `LineSpec`s (`canonicalOf`), stamped per node by `Building`. Paint order is
  `BrushRank`, deterministic across tile arrival order.

### Shaders

One source serves Vulkan and WebGL2: `target.h` hides the differences behind macros and `GL_ES` selects the branch, `clip.h` and
`depth.h` hold the clip and reverse-Z differences. `cull.comp` is native only and `present.frag` is web only. A new header goes
in `SHADER_HEADERS` in `web/renderer.d`.

Layouts are duplicated by hand between D and GLSL and must change together: `CommonUniforms` and `common.h`, `LayoutPush` and
the `voxels.vert` push constants, `meshing.d` `Quad` and `face.h`, `ChunkLayout` spacing and `voxels.vert`, the push blocks and the
uniform calls in `web/glue.js`. `voxels.vert` hardcodes `glowing_materials[3]`, which matches `GLOW_WORDS` only up to 96 materials.
`.spv` files are generated.

## Style rules

Inferred from the code. They are consistent across the tree, so follow them even where a rule looks arbitrary.

Language and memory:
- betterC: no GC, classes, exceptions, associative arrays or druntime. `extern (C) int main`. Use `Array`, `HashMap`, `Slab`,
  `RunPool` and `Bits` from `base/`. Ownership is explicit: `release()` frees, and scratch buffers are reused across frames.
- Errors are values: `Maybe!T`, `ExitStatus`, `StartupError`, `StructureProblem`, or a null `const(char)*` message. Asserts stay
  on in release builds (`--enable-asserts`, bounds checks on), so use them for invariants that really hold.
- No comments anywhere, in D, GLSL or C. Types and names carry the meaning; that is why `UNITS.md` exists.
- Declarations state their type; `auto` is close to absent. Dimensional values use `base/units.d` kinds, with `.value` only at
  boundaries.

Control flow:
- No ternaries and no `continue`. `break` is rare. Every `if` has braces.
- Value-returning branches are an `if / else if / else` chain with every path returning, not guard clauses; early return
  appears mainly inside loops. Enums get `final switch`.
- A search is a `while` over an index that ends in a comparison:
  `while (index < n && !matches(index)) { index += 1; } return index < n;`
- `x += 1`, not `x++`.
- No bool parameters and no stored bool state: use a named two-value enum (`SkinRule`, `Pacing`, `Urgency`, `Cover`, `Footing`,
  `Readiness`). Pack sets of flags in `Flags!E`, or in bits as `Chunk` does. `isX` and `hasX` are functions deriving an answer
  from state, not fields. `Maybe.exists` is the exception.

Shape:
- Functions are small and mostly free functions whose first parameter is the subject, called with UFCS: `graph.hopCell(...)`,
  `corner.faces`, `side.mirror`, `v.scaled(k).plus(w)`. Getters drop the parentheses.
- Pass large values as `ref const`; pass small ones by value. Use slices in signatures. `Array` has no `opIndex`: index it with
  `array.ptr[i]`, or take `.slice()`.
- Constructors are `static make(...)`, `fromX(...)`, `ofX(...)`; "none" is `T.init`. Struct literals are positional.
- Struct fields run roughly largest to smallest, so small enums come last. Enums declare a base type, usually `: ubyte`.
- Constants: no magic numbers. Top of module, `enum float NAME = ...` with an explicit type, `immutable` for tables. Keyed tables
  use `Material.dirt: value`. Tie derived constants to their source (`GLOW_WORDS`, `RELIEF_BOUND`).
- Compile-time geometry where possible (`immutable Honeycomb HONEYCOMB = Honeycomb.make()`). Formulas over tables.

Names and layout:
- `PascalCase` types, `camelCase` functions and variables, `SCREAMING_SNAKE` constants, `snake_case` in GLSL.
- Full words, no abbreviations, no Hungarian, no unit in a name the type already states. Names say what a thing is in the
  domain: `lowerOf`, `higherOf`, `coshThreshold`, `tanhReach`, `MOST_THROWN`, `LEAST_CAPACITY`. A name holding a transform
  of a distance says which (`cosh`, `sinh`, `tanh`).
- First line is `module path.matching.file;`. Imports are selective, grouped `core.*` first and then project modules in
  order, names sorted with capitals first.
- 4 spaces, K&R braces, one statement per line. No line length limit: long signatures and calls stay on one line.

Tests:
- Test code stays out of engine modules. Unit tests are `unittest {}` blocks in `source/unit/<module>.d`; a new file must be
  imported in `source/unittests.d`. Test constants and tolerances are named enums at the top of the test module.
- Behavior tests are scripts driving a real `Game` by simulated keys: register in `TESTS` in `scripts/tests.d`, assert with
  `world.check(cond, "message with %.3f measured numbers", ...)`. Failure messages state what happened, in words.
- Prefer checking a derived physical prediction over a recorded value: see `flat/curve`, `demo/holonomy`.
- Benchmarks are in `worldcheck.d` and `--bench-load`. Reports go to `--out`.
