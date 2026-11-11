# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

caapi is a voxel game engine set in hyperbolic 3-space, written in D with `-betterC` and built with dub and LDC. One engine has three front ends: `caapi` (Vulkan window: X11 with XInput2 on Linux, Cocoa on macOS), `caapi-headless` (behavior tests, benchmarks, dumps; no graphics) and a browser build (wasm and WebGL packed into the single page `caapi.html`). Worlds and game content come from plugins under `plugins/`.

## Commands

The dflags in `dub.sdl` are LDC-only. A dub that defaults to dmd fails on them, so pass `--compiler=ldc2`.

```
dub build -q -b release --compiler=ldc2                                     # ./caapi (needs glslc, Vulkan, X11, libXi)
dub test -q --compiler=ldc2                                                 # builds and runs ./caapi-unittest
dub run -q -b release --compiler=ldc2 -c headless -- tests                  # builds ./caapi-headless and runs every behavior test
dub run -q -b release --compiler=ldc2 -c headless -- tests flat/walk gene/  # the arguments are name prefixes: one test and one group
dub build -q -b release --compiler=ldc2 :web                                # caapi.html and obj/web/check.html (needs lld, and wasi-libc under /usr/lib/wasm32-wasi)

./caapi-headless claims gravity flat/                       # run tests and print every check of a law with what was measured; arguments are topics or test name prefixes
./caapi-headless wiki --out <file>                          # the laws as one Markdown page: a map of the systems, then a linked section for each; all, or by topic or prefix
./caapi-headless views                                      # run the screenshot scripts without rendering; films does the same for the films
./caapi-headless content-check                              # place every world, check every item can be reached and has uses
./caapi-headless world-digest                               # hash the terrain world
./caapi-headless --worldgen structure city check-repaint    # a dropped tile repaints identically
./caapi-headless --worldgen structure lattice check-forget  # evicted structure state regenerates identically
./caapi-headless --worldgen debug tower check-repaint       # a debug structure goes after the word debug
./caapi-headless --help                                     # the rest: dumps, censuses, bench-*, biology-tables, content-graph
./caapi --help                                              # --worldgen, --creative, --screenshot <png> <view>, --film, --drive, --record
```

- A change to the engine is checked by the unit tests, the behavior tests, `views`, `films`, `content-check`, `check-repaint` on every world (planet, city, backrooms, library, vaults, caves, lattice), and `check-forget` on lattice. A change that is not meant to alter worldgen must leave the `world-digest` line as it was.
- The headless and unittest configurations leave out `source/client/graphics/`, and nothing but `:web` compiles `web/`. A rename is only checked once the application and `:web` build as well.
- There are two kinds of tests. Unit tests (`source/unit/`) run through `dub test`: all of them, no filter, silent on success, and a failed assert traps and prints a backtrace. Behavior tests (`source/scripts/tests.d`) are scripted play sessions run by `caapi-headless tests`, so rebuild the headless configuration first; `dub test` does not. Each prints `== name` and a `session:` line, the run ends with `N passed, M failed`, and a test that runs past 120 s ends the whole run with a backtrace.
- Every build of the root package, `dub test` included, first rebuilds all plugins into `lib/` in that build's type. `caapi` and `caapi-headless` load `lib/*.so` from their own directory at startup, so they run whatever plugins the last build left there.
- `--worldgen` takes `terrain`, `plane <tilt in degrees>`, `structure <world>` or `debug <structure>`; an unknown name lists the valid ones, and a debug structure given to `structure` is refused with where it goes.
- `./caapi --screenshot <png> <view>` runs the view script, writes the PNG to the path given and exits, so a view can be looked at without playing. `views` only runs the scripts; a view that passes there can still face a wall.
- `caapi` reads `caapi.cfg` from the working directory and saves to `saves/<world>-<mode>.save`. User content overrides go in `settings.conf` beside the executable, keyed by mod name.
- The `:webdrive` subpackage builds `obj/web/tool/drive`, which drives the pages in a Firefox started with `--marionette` (`drive play`, `drive check <mode>`), run from the repository root. Its screenshots go to `.firefox-check/`.
- There is no linter or formatter configuration. CI (`.github/workflows/pages.yml`) only builds `:web` in release and publishes `caapi.html` to GitHub Pages; it runs no tests.
- `export.py` concatenates the sources into `export.txt`.

## Code structure

- `dub.sdl`: the root package with three configurations (`application`, `headless`, `unittest`) and a subpackage per plugin, plus `web`, `wasm`, `webpack` and `webdrive`. Which source files each configuration leaves out is decided here: graphics and platform code are absent from headless and unittest, and `source/unit/` only builds in unittest.
- `source/base/`: what the engine uses in place of druntime and Phobos. `Array`, `HashMap`, `Slab`, `Maybe`/`MaybeIndex`, `Flags`, typed quantities (`units.d`), hashing (`murmur.d`), random numbers (`splitmix.d`), the worker pool (`parallel.d`), crash and hang backtraces (`crash.d`).
- `source/geometry/`: hyperbolic math in the Lorentz model (`lorentz.d`: `Point`, `Motion`, `Normal`) and the honeycomb's tables, computed at compile time (`honeycomb.d`).
- `source/common/`: the engine, free of windowing and rendering.
  - Space: `graph.d` (`Graph`), `view.d` (`GraphView`), `node.d` (chunks, voxels, `ChunkLayout`), `position.d`, `neighbors.d`, `traversal.d`, `raycast/`, `edits.d`, `eviction.d`.
  - `worldgen/`: `generation.d` (a chunk's voxels), `climate.d`, `horospheres.d` (grounds and gravity), and the structure pipeline in `structure.d`, `blueprint.d`, `building.d`, `strokes.d`, `store.d`.
  - `content/`: the content graph, its three parsers, mod ordering and the load pipeline (`load.d`).
  - Tables built from content, each beside its `.decl` schema: `material.d`, `items.d`, `crafting.d`, `perception.d`, `look.d`, `worldgen/palette.d`, `biology/`.
  - `character/`: the character controller and its collision sweep.
- `source/client/`: `game.d` (`Game`, the whole session), `world.d` (`LocalWorld`), `streaming.d`, `tasks.d` and `arrivals.d` (background generation), `meshing.d`, `plugins.d` (finding and loading plugins, and the lists of worlds, debug structures, rising kinds and landmarks they register), `structures.d` and `tiles.d` (the host side of the plugin `Api`), `script.d` (`Script`), `save.d`, `hud.d`, `input.d`, `bindings.d`, `config.d`, `arguments.d`, and `graphics/` (the Vulkan renderer).
- `source/main.d`, `source/headless.d` with `worldcheck.d`, `source/unittests.d`: the three entry points.
- `source/scripts/`: tables of named scripts. `tests.d` (`TESTS`), `views.d` (`VIEWS`), `films.d` (`FILMS`), `drives.d` (`DRIVES`), with shared helpers in `walk.d` and `climb.d`. `claims.d` holds what the tests state about the game: `Topic`, `claim`, `link`, the ledger of a run and the writers behind `claims` and `wiki`.
- `source/unit/`: unit tests, one module per module tested.
- `source/shaders/`: GLSL shared by Vulkan and WebGL. `spv/` is written by glslc during the application build.
- `source/bindings/`: C files that pull Vulkan, X11 and Linux system headers into D.
- `plugins/api/`: the interface between engine and plugins. `api.d` (`Api`, `Registry`, `Site`, `Material`), `content.d` (`Content`, `Manifest`, `Play`), `binding.d` (content to D structs), `flags.d`.
- `plugins/turtle/`, `plugins/carve/`: helpers compiled into the plugins that use them. `Turtle` wraps `Api` and a `Site`, and `turtle.d` holds what tiles of different plugins have to agree on: `PORT`, `settled`, `strongestAround`, `strongestNear`, `Hashes`.
- `plugins/box`, `buildings`, `connector`, `blocks`, `rooms`, `horospheres`: building code other plugins share, each also a mod with content. `plugins/caves`, `lattice`: worlds whose code (`caves.d`, `lattice.d`) the default world also compiles in, with the world and the mod in `plugin.d`. `plugins/base`: the base content mod. `plugins/planet` is the default world, the one `terrain` names; `city`, `backrooms`, `library` and `vaults` are the other world plugins. `tower`, `crown`, `palace`, `arbor`, `babel`, `road`, `trail` and `fixtures` (the rigs the tests and views name) register debug structures.
- `web/`: `main.d` (the wasm exports, `web_*`), `renderer.d` (WebGL renderer), `glue.js` (the JS side: GL, input, storage; implements the imports listed in `imports.syms`), `play.js` and `check.js` (what drives the game page and the check page), `shell.html`, `tool/pack.d` (inlines the wasm and scripts into the pages), `tool/drive.d`.

## Architecture

### Space

Space is tiled by right-angled dodecahedra (12 faces, 20 corners). Each cell is a node of `Graph`, and each node is cut into 20 cube chunks, one per corner, of `CHUNK_DIMENSION`^3 voxels. A `Position` is a `NodeId` plus a `Motion` inside that node; crossing a face mirrors the motion into the neighbor (`Graph.normalized`).

The graph is endless and built lazily. A `NodeId` is a hash chained from a parent's id and the face crossed, starting at `ROOT_NODE`, so the same node gets the same id however it is reached. Live nodes sit in numbered slots that are reused after eviction: `NodeId` and `ChunkId` name things durably, slot numbers and `ChunkSlot` only while the node is loaded.

### Working in hyperbolic space

- Lengths are in units of the curvature radius. The model is the hyperboloid: `Vec4.minkowski` has signature (+,+,+,-), a `Point` has `<p,p> = -1` and a `Normal` has `<n,n> = +1`.
- Distances come out of products as hyperbolic functions: `cosh d = -<p,q>` between two points (`Point.coshDistance`) and `sinh d = <n,p>` from a plane (`PlaneMeasure.sinhDistanceTo`). Where only a comparison is needed, the code compares the products and skips the inverse function (`Thread.rewoundTo`, `isRayApart`).
- `tanh d` is a radius in the Klein chart. The character controller's displacements are Klein vectors in the body's frame: `movedBy` moves the body by `atanh` of their length.
- A `Motion` is a Lorentz matrix stored column-major (`m.c[col][row]`). `inverse()` is the Minkowski transpose, so it is only right for a matrix that still is one: a frame is moved by multiplying on the right and then `orthonormalized()`. A motion can be a reflection (`isMirroring`), and crossing a face is one.
- There are no global coordinates. A place is a node and a motion inside it, and anything remembered across nodes is carried through the faces between them (`Plane.carriedAlong`, `HorosphereRef.across`). Carrying around a loop turns things: `demo/holonomy` walks five equal legs with a right turn after each and ends where it began, facing the way it first faced, after a turn and a quarter.
- What the code calls a horosphere is a geodesic plane. `Plane` holds a unit normal as `up` and `height`, and `distanceTo` is the signed distance from it. The surface at a fixed height above a plane is not a plane and it curves: `flat/curve` checks that a body moving at speed `v` at height `h` falls slower by `v^2 tanh(h)`.
- Far from a plane `cosh` overflows, so `PlaneMeasure` carries the logarithm of its scale (`logCosh`) and changes formula past `LARGEST_DIRECT_SCALE`.
- Space grows exponentially with distance (`demo/growth` checks that the cells within reach more than double with each step), so whatever reaches outward has a named reach or a budget.
- A chunk's grid is not a piece of Z^3. Cells are spaced geometrically (`ChunkLayout.gridToCube`, `cellRatio`), so convert with `gridToCube` and `cubeToGrid`, never by dividing by the dimension. Stepping off a chunk does not continue the coordinate either: past the low end of an axis lies the same corner's chunk in the node across that face, mirrored, and past the high end lies another corner's chunk in the same node with its axes permuted (`AxisMap`). Go through `hopCell`, `acrossBorder` or `materialNear`.

### Generation and threads

Nodes and chunks are evicted and made again, so everything generated has to be a function of node identity, the worldgen and the content, never of visiting order or time. Randomness comes from `SplitMix` seeded by the node's `spice()`. The headless commands `world-digest`, `check-repaint` and `check-forget` exist to catch violations. What the player changes is kept apart in `graph.edits`.

Only the main thread changes the `Graph`. `graph.view` is the owning `GraphView` and creates nodes and state in place. Workers get `graph.threadViews[worker]`, which reads the graph, invents virtual nodes for what is missing and keeps what it discovers to itself; `ThreadViews.finish` merges that back on the main thread. A worker whose view ends up `isBlocked` drops its result and the work is tried again later. Worldgen code is written against `GraphView` so it runs both ways.

A chunk is generated in two parts: `ChunkParams.make` gathers what it depends on (structure, grounds, climate), then `generateVoxels` computes from the params alone. `ChunkSupply.streamed` does this in the background under a per-frame budget (`Streamer`); `ChunkSupply.onDemand` does it synchronously, which is what the headless tests use until a script calls `live()`.

Under any ground the fill is soil over the climate's rock bands with ore veins, the same under a built ground as under terrain (`underAt` in `climate.d`). A ground with a crust ends there: below it nothing is generated but what tiles paint, and its underside swings with relief (`UNDERSIDE_SWING`). The chunk fast paths (`isClearOf`, `isFullOf`, the uniform and deferred fills) each ask `isBelowCrust` or `isWithinCrust`, so a new fast path has to as well.

### Plugins and structures

A plugin exports one entry function, named by `ENTRY` in `plugins/api/api.d`. The number in that name is the plugin ABI version: a library without exactly that symbol is skipped. Whatever changes the layout of `Api`, `Registry` or `Risen` raises that number, and new `Api` and `Registry` members go at the end. The entry gets a `Registry` and uses it to declare its mod `Manifest` and to add worlds, debug structures, rising kinds and landmarks. Natively each plugin is a shared library found in `lib/` beside the executable. The wasm build links them all in statically, from the hand-kept lists `WEB_ENTRIES` and `WEB_PLUGINS` in `source/client/plugins.d`. A new plugin therefore needs a subpackage and a `preGenerateCommands` line in `dub.sdl`, and an entry in both lists.

Shared building code (`box`, `buildings`, ...) is a `sourceLibrary` compiled into every plugin that depends on it, next to a `<name>-mod` library holding only `plugin.d` and the mod's content. Each dependent plugin gets its own copy of that code's `__gshared` state and has to fill it by calling the library's `resolve*` from its own `Manifest.resolve` (see `plugins/tower/plugin.d`).

A world (`registry.add`) is a place to play in: the world menu and `--worldgen structure` list worlds and nothing else. A debug structure (`registry.addDebug`) is one building, a piece other structures build, or a test rig; only `--worldgen debug`, the scripts (`Script.structure` takes either) and `api.build` reach it. `content-check` places both. Caves under a world are such a piece: a world that wants them calls `build("underground")`, which the `caves` plugin registers.

A world is a `Structure` function called once with an `Api` (a table of function pointers) and a `Site`, a frame on the honeycomb that it moves with `forward` and `turn`. It paints boxes of cells, queues further structures with `place`, and registers tile callbacks and horosphere kinds. `StructureHost` in `source/client/structures.d` implements the `Api` for world and placed structures, recording into the graph's `Blueprint`; queued structures run as the graph grows deeper, and a node's `Building` is derived from the blueprint before its chunks generate. `source/client/tiles.d` implements the same `Api` for tile callbacks, which run in no fixed order and so may not `place`. Several calls are only allowed from the world's own structure. A refused call becomes a `StructureProblem` that stops the world from starting.

Tiles are the unit everything endless is made of, and three facts about them decide how plugins share a place:

- A face tile belongs to a ground kind. The one edge tile of a world runs once for the root ground and once more for each filled ground near its edge, with `Risen` (`tag`, `form`, `hasRisen`) saying which, so one callback serves the caves under every ground (`runOverGrounds` in `tiles.d`).
- Placed structures paint first, and tile paints go over them in an order set by the tile's hash. Two tiles that could paint the same cells therefore decide from hashes alone who paints (`probeOwner`, `settled`), or keep out of each other's cells.
- A port is how they keep out. `api.ports(odds)` rolls ports per ground vertex and `probePort` asks; a tile leaves the `PORT` cells each way around a port open from its floor down, and the cave tile sinks a stair well there. `probePort` says no at the world's root vertex, at the foot of a risen ground and where a ground rises, because routes, entrances and connectors stand there.

The world's own structure also says what lies under its grounds, per ground: `KindTag.init` names the root ground and a tag names every risen ground of that kind. `api.under` changes the look and fog below a depth, `api.crust` gives the ground a bottom, both in edges. A `connector-ground` with `bridge: none` (vaults) gets no connector, and neither does anything rising from it.

### Content

Everything a mod defines is data in one content graph (`source/common/content/`), assembled at startup from three texts each mod embeds with `import()`:

- `<mod>.decl` is the schema: `kind`, `extend` and `type` declarations, fields with ranges and defaults, edges with a cardinality (`one`, `optional`, `many`, `some`, `n..m`). The engine's own schemas are the `.decl` files in `source/common/`.
- `<mod>.content` is the data: `kind mod:name { key: value  edge -> target }`, with `?->` for optional edges, and `remove` and `unlink` to change what earlier mods defined.
- `settings.conf` is the mod's tunables as `key: value`; nesting and lists flatten to dotted keys.

`loadContent` (`load.d`) runs in a fixed order: engine declarations, then each mod in dependency order, then `freeze` (check against the declarations, drop what does not fit and whatever depended on it, fill defaults), then the engine's `build*` passes that turn the graph into runtime tables, then each mod's `resolve`. A mod whose dependencies are not met, or whose `resolve` reports a problem, is refused along with its worlds. Content problems go to stderr as `content from '<mod>': ...` and refusals as `<plugin file>: ...`.

Names are `mod:kebab-name`. `plugins/api/binding.d` fills D structs from content by reflection, mapping camelCase fields to kebab-case keys (`content.bound!T(name)`, `content.settingsOf!T(mod)`). A `Material` is the ordinal of a `material` node in a `ubyte`, with `engine:air` as 0, so there are at most 256. Engine features that need a specific block or item (`engine:beacon`, `engine:bench`, ...) are roles that a mod fills with a `fills` edge.

### Game, scripts and front ends

`Game` holds one player's whole session and `Game.step(FrameInput, dt)` advances it. `main.d`, `web/main.d` and the scripts all drive that one function; the front ends add input, rendering, saving and the HUD around it.

A script is a D function `void name(ref Script world)` listed by name in a table in `source/scripts/`. `Script` (`source/client/script.d`) is its API: pick a worldgen, hold keys, `wait`, `look`, then `world.check(condition, format, ...)`. Tests, screenshot views and films are all scripts; `caapi --record <file>` writes a played session out as a script body. To add a behavior test, write the function in `tests.d` and add a `NamedScript("group/name", &fn)` row to `TESTS`. A script that needs a place the world rolled asks the engine for it and goes there with `game.placeAt`: `walk.ensurePort`, `walk.ensureLastFlat`, `firstOf` in `views.d`.

A check that states what the game does is written as a claim: `world.claim(Topic.x, "The law, as one full sentence.", condition, Measure.of("label", value), ...)`, or `world.link(Topic.from, Topic.onto, ...)` when one system acts on another. A claim fails its test the way `check` does, and every check is also kept with its measures, pass or fail. Nothing else is registered anywhere: `claims` prints the checks of a run, and `wiki` writes them as one Markdown page that is a graph. The topics are its nodes, each a section, and every `link` is an edge, listed in both sections with a link to the other. The page opens with a map (a Mermaid flowchart and a table), puts the measures of each law in a table with one row per check, and ends with the topics and tests that state nothing. All of it is computed from the run. An argument that is neither a topic nor the start of a test name is refused with the list of topics, and naming a topic runs every test, because only a run shows which tests state laws about it. A new `Topic` needs a title in `titleOf` or the build fails; the title may hold only letters and spaces, because the section link is made from it. A law may say no more than its condition checks, because the page presents it as verified.

Unit tests are `unittest` blocks in `source/unit/<module>.d`. `source/unittests.d` runs them by walking its own renamed imports, so a new module needs an `import unitName = unit.name;` line there or its tests never run. Only the `base` mod's content is loaded for them.

The Vulkan and WebGL renderers share the GLSL in `source/shaders/`. The application build compiles it to SPIR-V with glslc (one `preBuildCommands` line per shader in `dub.sdl`); `web/renderer.d` rewrites the same sources at compile time, swapping the `#version` line and expanding `#include` from its `SHADER_HEADERS` list.

## Style

These rules are taken from the code. Where a file differs from them, the file is what needs fixing.

### Language and layout

- betterC: no GC, classes, exceptions or Phobos. The C library comes through `core.stdc`, containers from `source/base/`, and whatever owns memory has a `release()` that its owner calls.
- The D sources carry no comments. Names and messages do that work.
- The first line is `module path.matching.file;`. Imports are selective, one line per module, with the names in ASCII order (capitals first). The `core.*` lines come first, then the rest in order of module path.
- 4 spaces, K&R braces, every `if` braced, one statement per line. A statement is not wrapped to fit a line length; only table literals span lines.
- No ternaries, no `continue`, no `auto`, no `++` or `--` (`x += 1`).
- Every local states its type. Only `foreach` variables are inferred.

### Control flow

- A loop ends through its condition, or by returning the function's answer. `break` only closes a `final switch` case.
- A search is `while (index < n && !matches(index)) { index += 1; }` followed by a comparison of `index` with `n`.
- A function that returns a value is an `if / else if / else` chain in which every arm returns.
- An enum is consumed by `final switch`.
- A guard is written negated, as in `!(dt.value > 0)`, so that NaN lands on the refusing side. That only works on the float: `Quantity.opCmp` answers 0 for NaN, so on a typed quantity `<=` and `>=` are true for NaN and `<` and `>` are false.

### Types

- State is typed. A two-way choice is a `: ubyte` enum (`Footing`, `SkinRule`, `Readiness`), never a bool parameter or a bool field; `Maybe.exists` is the one stored bool. A set of marks is `Flags!E`, `Bits` or `IdSet`. `Maybe!T` and `MaybeIndex!T` stand where sentinels would. An id is a one-field struct (`Station`, `Material`, `HorosphereId`), not a bare integer.
- A quantity with a dimension is a `base/units.d` type (`Length`, `Time`, `Speed`, `Rate`, `Ratio`, `Angle`) when it is a constant, a field or a parameter in character, biology, crafting or game code, and `.value` appears only where the number enters plain math. Vectors are `Vec3!float`. Worldgen geometry (`climate.d`, `horospheres.d`, `plane.d`) and the test scripts compute in bare floats.
- A small bounded set is a fixed array with a count, and its capacity is a named constant (`Body`, `Genome`, `PlaneSet`, `Grounds`).
- Constructors are `static make`, `of`, `ofX` or `fromX`, and "none" is `T.init`. Struct literals are positional, so adding or moving a field means checking every literal of that struct. Sparse structs (`Note`, `UiAction`) are filled with `{field: value}`.
- Large values are passed `ref const`, and a method that does not change its struct is `const`.

### Names

- `PascalCase` types, `camelCase` functions and fields, `UPPER_SNAKE` constants. Words are written out wherever a name is visible outside a function. Locals may be short (`dt`, `rng`, `k`).
- A tunable number is a named `enum` constant that states its type. It sits near the top of its module or, in the test scripts, just above the test that uses it. Tables are `immutable`.
- A bound is named `MOST_` or `LEAST_`, and the helpers are `lowerOf`, `higherOf` and `clamped`. The words max and min are not used.
- A hash salt is a hex constant named `*_SALT`.
- Function names follow a grammar:
  - `xOf`, `xAt`, `xNamed` and `xFor` are lookups.
  - A past participle (`rotated`, `clamped`, `crossed`, `leveled`) returns a changed copy, and `withX` returns a copy with one part set.
  - `isX`, `hasX` and `canX` are predicates that change nothing.
  - `ensureX` may create nodes or compute and store state on demand. A plain lookup such as `stateAt` asserts that the thing already exists.
  - `probeX` is a yes or no question that is allowed to compute or create state to answer.
  - `declareX` loads a schema, `buildX` turns content into runtime tables, and `release` frees.

### Numbers

- Stepping is exact in the step size. `advance(step)` uses the closed form (`Body.advance`, `Signaling.advance`, `groundMove`), so one long step and many short ones agree, and tests check that (`flat/timestep`, `unit/kinetics.d`).
- What can be computed at compile time is (`rotationTable`, `halfPoints`, `channelNames`), and a `static assert` ties together tables that must agree.
- A count of things a player holds or needs (a recipe's inputs, a yield, what a fall costs) leans to a power of three where the number is otherwise arbitrary: three wood, not four. It is a lean and not a law, and it is about items, never the world's sizes.

### Errors

- What a user or a mod can get wrong is reported as a value with a full-sentence message (`StartupError`, `StructureProblem`, content problems through `graph.report`, `Script.check`). The message is written where it is reported.
- A player action that can be refused returns bool and posts a `Note`.
- Asserts are for invariants, and they halt.
- Text is formatted printf-style. A slice goes in as `%.*s` with `cast(int) s.length, s.ptr`.

### Tests

- Test code stays out of the engine modules: unit tests in `source/unit/`, behavior tests in `source/scripts/`.
- `world.check(condition, format, ...)` prints its message only when the check fails, after `script error: `, and a passing run prints nothing about it. The newer checks say what went wrong and give the measured numbers; a good number of older ones state the expectation instead ("spawned walking").
- Where the model predicts a number, the test derives the prediction and checks against it instead of a recorded value: `flat/curve` (`v^2 tanh(h)`), `demo/holonomy` (a quarter turn), `unit/kinetics.d` (the half-life from the clearance rate).
