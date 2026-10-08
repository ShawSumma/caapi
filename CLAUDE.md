# mined - hyperbolic voxel engine

D + Vulkan voxel game in hyperbolic space (H^3). Client in `source/client`,
shared simulation code in `source/common`. Two entry points: `source/main.d`
(windowed client) and `source/headless.d` (scripts, dumps, benches).

## Code structure

- `source/main.d` - windowed client: X11 window, XInput2 raw mouse, input
  capture, frame loop; also `--screenshot` and `--bench-load` (offscreen).
- `source/headless.d` - script runner and `--dump-world`/`--world-digest`/
  `--bench-*` dispatch; `source/worldcheck.d` holds the dumps and benches.
- `source/unittests.d` - betterC unittest runner over imported modules.
- `source/bindings/` - ImportC shims: `lua.c`, `platform.c` (Xlib, XI2,
  Vulkan).
- `source/client/` - per-client state:
  - `game.d` - Game: world, character, camera, spawn, step, modes, input
    mapping.
  - `world.d` - LocalWorld: graph, streamer, double-buffered nearby node
    set, camera position, edits (`setVoxel`, ray picks).
  - `streaming.d` - Streamer: worker pool (generation requests, building
    requests and fork-join `runParallel` jobs), request scan, budgeted
    integration, chunk population and margin connection.
  - `meshing.d` - chunk surface extraction with ambient occlusion and
    see-through glass.
  - `camera.d` - Camera: orientation quaternion with a stored pitch,
    roll leveled to the view up every frame.
  - `lua.d` - Lua plumbing shared by both hosts (constants, safe state,
    snake_case enum names, methods, package path, traceback).
  - `structures.d` - the structure Lua API (StructureHost): runs the
    world's structure script into the graph's blueprint, then keeps its
    Lua state as the graph's `Grower` while placed structures wait in
    its depth-ordered queue; `placeStructure`/`restartGame` start a game
    on it, `growthProblem` reports a placement that failed later; it
    also runs the ground tiles (`site:tile`) as the graph needs them.
  - `script.d` - Lua API (ScriptHost) and the recorder; `config.d` - client
    config; `arguments.d` - command-line pieces shared by both entry
    points (flag values, `--worldgen`, StartupError); `png.d` - PNG writer
    for screenshots.
  - `graphics/` - Vulkan: `core.d` (instance, device), `base.d`
    (swapchain or offscreen target, render pass), `pipeline.d` (buffers,
    pipelines), `matrices.d` (flat 4x4 helpers), `renderer.d` (frame),
    `voxels/meshes.d` (face pool, drawable and node buffers, parallel mesh
    batch), `voxels/cull.d` (compute cull pipeline), `voxels/surface.d`
    (voxel pipeline, textures, common UBO), `fog.d`, `highlight.d`,
    `crosshair.d`, `frustum.d`.
- `source/common/` - simulation shared by client and headless:
  - geometry: `math.d` (hyperboloid types, scalar helpers), `vector3.d`
    (float[3] operations), `dodeca.d` (honeycomb tables), `coords.d`
    (chunk grid coordinates, axis permutations), `ray.d` (Ray and a
    point-plane solve), `units.d` (dimension-typed quantities, see
    Units).
  - world: `graph.d` (node graph, node and chunk slabs, change queue,
    per-node memoized state, line touches and building, the structure
    `Grower` hook),
    `node.d` (chunk and voxel storage), `margins.d`, `neighbors.d`
    (cross-chunk cell resolution), `traversal.d` (nearby BFS),
    `position.d`, `material.d`, `settings.d` (chunk dimension and
    `CharacterConfig`).
  - worldgen: `worldgen/generation.d` (Worldgen kinds, node state, chunk
    params, proofs, voxels, trees); structures (see Worldgen):
    `structure.d` (sites and their turtle moves; the canonical line of
    a site; the vertex and face a site stands on and their hashes; the
    ground face below a node and its ring; which lines touch a node,
    written ahead for bounded lines and propagated from its parents for
    endless ones; column coordinates and frames), `blueprint.d`
    (canonical lines with their brushes, materials, route, entrance and
    claims; `BlueprintBuilder` maps what a site draws onto its canonical
    line, writes the touches and refuses what a placed structure may not
    paint), `embedded.d` (the built-in structure scripts and modules,
    compiled in with `import()`), `building.d` (`BuildingPlan` copies
    what a node needs from the blueprint; `Building` stamps its voxels
    from it); `terraingen.d`, `plane.d`, `spawn.d`.
  - character (see Character controller): `character/features.d`
    (the exposed faces, edges and corners of solid cells around a body,
    in its local Klein frame; cell visitors for overlap checks and
    for what generation must provide), `character/sweep.d` (capsule
    sweep against those features), `character/controller.d`,
    `character/chart.d` (grid Jacobian, point in node from chunk
    coordinates); ray picks in `raycast/chunk.d`, `raycast/graph.d`.
  - containers and utilities: `array.d`, `hashmap.d`, `slab.d`,
    `allocator.d` (range allocator), `murmur.d`, `clock.d`.
- `structures/` - structure scripts (see Structure scripts): the
  built-in `tower.lua`, `crown.lua`, `road.lua`, `trail.lua` and
  `city.lua`, and the module `box.lua` (box tower parts,
  `require("box")`). `structures/buildings/` holds the city's
  buildings, one module per type (`brownstone.lua`, `tenement.lua`,
  `deco.lua`, `glass.lua`: palettes, story range and design) on the
  shared `kit.lua` (lots, tiers, facades, roofs, crowns, stairs, doors,
  routes), required as `buildings.<name>`.
- `source/shaders/` - GLSL, compiled to `spv/` by the pre-build step;
  `common.h` (common UBO), `draw.h` (structs shared by `cull.comp` and
  `voxels.vert`), `face.h` (packed face layout, matches `client/meshing.d`).
- `tests/` - behavior scripts: `tests/flat/` (level plane world),
  `tests/slope/` (tilted plane world), `tests/structure/` (structure
  world), `tests/api.lua`; `tests/lib/` shared Lua (`walk.lua` builds
  walls, steps and corners layer by layer, one material per layer;
  `climb.lua` follows a structure's route waypoints; structure files:
  `hut.lua`, `hamlet.lua` (a hut on every corner of a face), and the
  refused `broken.lua` and `wide.lua`);
  `tests/visual/` screenshot scenes.
  Physics is tested only in plane and structure worlds, never in terrain.
- `tools/gridvolume.py` - measures block-volume spread and block edge
  lengths for candidate chunk grid spacings, and the chunk volume.
- `UNITS.md` - the unit system: what is typed, the hyperbolic distance
  representations, and how to move the rest of the code onto it.
- `screenshots/` - gitignored; where offscreen renders go.

## Build, test, run

Always ldc2 through dub, always release: dmd debug builds are 5-10x slower
and useless for judging performance. Never invoke ldc2, cc, cmake or make
directly; dub is the only build command.

Everything is `-betterC` with `-checkaction=halt`: no GC, no Phobos, no
exceptions, no classes, no associative arrays. Memory is `malloc`/`free`
(`common/array.d`, `common/hashmap.d`), threads are pthreads, math is
`core.math` and `core.stdc.math`.

- `dub build -b release --compiler=ldc2 -c headless` -> `./mined-headless`.
  No X11, no Vulkan, no window. This is the build for all verification.
- `dub build -b release --compiler=ldc2` -> `./mined`, the windowed client.
  Never launch it windowed for verification. Rendering is verified
  offscreen: `./mined --screenshot <png> --out <report> <script.lua>`
  runs the script, lets worldgen cover the nearby set and meshing catch
  up, renders one frame with no window or input grab, and writes a PNG
  (read it to look at it). Scenes live in `tests/visual/`; PNGs go in
  `screenshots/`, never anywhere else.
- Unit tests: `dub test --compiler=ldc2`. The `unittest` configuration uses
  `source/unittests.d` as a betterC runner (`__traits(getUnitTests)` over
  every imported module) and leaves out Lua, whose headers ImportC rejects
  under `-unittest`, so `client/lua.d`, `script.d` and `structures.d`
  are not built there and worldgen unit tests write their blueprints in
  D. `structures/` is a string import path in every configuration.
- Behavior tests: `./mined-headless --out <report> tests` - a directory
  argument runs every `.lua` under it in sorted order, skipping `lib/`
  (required modules) and `visual/` (screenshot scenes); single scripts
  work too. Exit status 1 on any script error or failed assert; the
  report file holds the details.
- Nothing writes to stdout, and stderr carries only startup errors: a bad
  argument, a file or window that cannot be opened, a structure script
  that fails (its Lua message and traceback; a placed structure that
  fails while the client runs is reported when it exits, with status 1).
  Each is one line
  naming what was wrong, with exit status 2 for usage. Never fail
  silently. Headless output goes only to the `--out` file;
  `--dump-world`, `--world-digest` and `--bench-*` require it. Pass/fail
  is the exit status. `--out /dev/stdout` reads a report without creating
  a file.
- Dependencies live in `deps/`. C comes in through ImportC only - no cc, no
  make, no cmake, no build output outside dub's cache. Lua's individual
  `.c` files are `sourceFiles`. `lua` carries small ImportC patches:
  `dummynode_` uses a designated initializer, `lua_longjmp` and `BlockCnt`
  are defined in the headers that declared them, `lua_ident` is not
  declared in `lua.h`, and the VM uses switch dispatch
  (`LUA_USE_JUMPTABLE=0`, no computed goto). Lua's C API comes through
  `source/bindings/lua.c`; function-like and expression macros are not
  visible, so `client/script.d` defines the few constants it needs.
- The windowed client uses Xlib and Vulkan (`VK_KHR_xlib_surface`) through
  `source/bindings/platform.c` against `deps/vulkan-headers`. ImportC drops
  C `const` on pointer members and hides expression macros (X event masks
  are defined in `main.d`). The only pre-build step is `glslc`.
- Mouse look is XInput2 raw motion (unaccelerated device counts, no pointer
  warping); the pointer grab only hides the cursor and keeps clicks in the
  window. libXi's few declarations live in `platform.c` (constants come from
  the system `XI2.h`), and it links by soname (`:libXi.so.6`), so no
  libxi-dev is needed. `mouse_sensitivity` is radians per count.
- Never run git commands; version control is managed by hand.
- Shell: one plain command per call. No `&&`, pipes, redirects, filtering
  commands, or other shell constructs; read files whole, never partially.

Headless verification:

- `mined-headless --out <report> <script.lua or directory>...` - runs Lua
  scripts through the simulation, each in a fresh world. With
  `Game.isGeneratingOnDemand` (headless and `--screenshot`) nothing is
  streamed: each step synchronously generates only the chunks within
  `generationDistance` of the body (the physics region check's corners,
  or the pick reach), and a step that stalled on unloaded chunks is rerun
  after generating around where it stalled. Deterministic: a run is a
  pure function of the script. `--screenshot` settles the full nearby
  set only before rendering. Each script's `session:` line (steps, time,
  distance) and any script error land in the report.
- `./mined --record <file.lua>` records live play as a replayable Lua
  script (key changes, look deltas, events, and merged runs of identical
  steps as `world:wait(seconds, dt)`).
- `--worldgen terrain`, `--worldgen plane <tilt degrees>`, `--worldgen
  structure <name>` (both clients; `world:worldgen(kind[, tilt or name])`
  in a script). A kind takes a fixed number of arguments, parsed per kind
  with a `final switch`. A structure is a built-in name (`tower`,
  `crown`, `road`, `trail`, `city`, from `EMBEDDED_STRUCTURES`) or a path ending in `.lua`,
  relative to the working directory. `plane 0` fills exactly below the base surface plane. The base plane is
  lattice-aligned, so this is a genuinely flat floor with gravity
  perpendicular to it. Use it to isolate physics from terrain. A nonzero
  tilt gives a constant grade relative to gravity (gd(altitude) +
  tan(tilt) * horizontal distance = 0), not a tilted geodesic plane:
  in H^3 a geodesic plane tilted by t turns vertical within atanh(cos t)
  of its base line. The player spawns facing uphill. `structure` is the
  flat ground with exactly one structure; when the structure has an
  entrance the player spawns on the ground `SPAWN_DISTANCE` (1) out
  from its door, facing it. `terrain` carries the `road` structure.
- `--dump-structure` (needs `--worldgen structure <name>`) - each
  structure node in reach of the anchor (which grows placed structures
  that far): altitude and how many voxels it fills; then the
  blueprint's lines, brushes, route stops and claims and the edge
  length.
- `--dump-world [radius]` - deterministic world hash dump; byte-diff two
  runs' reports to prove worldgen unchanged. Deferred materials are
  resolved first; each chunk line carries a materials hash and an
  occupancy hash, so a shape-only change and a material-only change are
  told apart. `--world-digest [radius]` prints only the final
  order-independent digest line, which is enough to compare two builds.
- `--bench-gen | --bench-nearby | --bench-drive | --bench-mesh [radius]` -
  timings.

## Scripts (Lua 5.5)

Lua is the canonical language for driving and checking behavior. Tests are
authored, not recorded: they say what they do and `assert` what must hold.
The script owns time - nothing advances except through the world.

A script returns a function of the world; the API adds no globals and
everything hangs off that one object:

    return function(world)
      world:worldgen("plane")
      world:press(1, "fwd")
      assert(world:is_on_ground(), "still standing")
    end

All state (timestep, held keys, turn rate, step hook) lives on the world.
Modules take the world as a parameter (`walk.spawn(world)`, see
`tests/lib/walk.lua`). `require` searches the script's directory and each
of its ancestors, so `tests/flat/jump.lua` finds `lib.walk`. Methods check
their receiver, so `world.wait(1)` is an error - always call with `:`.

- Lengths are absolute units (curvature radius 1), times seconds, angles
  degrees. Positive yaw turns right and positive pitch looks down (mouse
  sense).
- Time: `wait(s[, dt])` (steps of dt, default the timestep), `step([dt])`
  (one step), `timestep([s])` (default 0.016), `time()`,
  `worldgen("terrain"|"plane"|"structure"[, tilt or name or path])`
  (before the first step; it creates a fresh world and respawns; a
  structure script that fails raises its message), `on_step(fn|nil)`
  (runs fn after each step to observe; it cannot advance time).
- Input: `hold(key...)`, `release(key...)`, `release_all()`,
  `press(s, key...)`, `look(yaw, pitch)` (immediate), `turn_rate([yaw/s,
  pitch/s])` (held look rate; returns the current one), `turn(yaw, pitch,
  s)`. Keys are the `Key` members in snake_case: fwd back left right up
  down yaw_left yaw_right pitch_up pitch_down. In walk mode up jumps on
  the step it is pressed (space in the client); holding it does not
  repeat, and down does nothing.
- Actions: `mode([walk|fly|noclip])` (fly to walk keeps the last fly
  velocity, so take one fly step with no keys before landing),
  `material([1..9])`, `break_block()`,
  `place_block()` (both return whether they changed a voxel),
  `enter_structure(h)` (structure world only: puts the player h
  straight up from the world site's vertex, on the `tower` axis),
  `enter_route()` (stands the player at the first stop of the world's
  structure route) and `route_waypoint(k)` (the k-th stop of the route:
  yaw and horizontal distance from the body to the center of that
  stop's floor, and the floor's rise above the feet; nil past the end,
  which moves out as placed structures grow. A tower's route stops
  seven times per story: the middle lane, the flight's lane, its three
  treads, the landing, and the middle lane again; the crown's leaves
  through the bridge door, crosses the arch and climbs the neighbor
  tower; the road's runs along its deck, the trail's stops once per
  segment, the city's walks in from the street and up the stairs).
- Observation: `target_material()` (snake_case name of the voxel in reach
  under the crosshair, or nil), `traveled()` (path length),
  `is_on_ground()`, `altitude()` (the body center's distance to the
  surface plane; standing on `plane 0` gives half height plus skin),
  `speed()`, `horizontal_speed()`,
  `vertical_speed()` (signed, up positive),
  `camera_vertical_acceleration()` (the bounce metric).
- `./mined --record` writes the same API.
- Only the base, package, coroutine, math, string, table and utf8 libraries
  are open, and `print`/`warn` are removed: scripts observe through
  `assert`, never by printing. A failed assert is a script error.
- The API lives in `client/script.d`. Lua names are snake_case; constants
  are ALL_CAPS. Enum names (keys, modes, worldgen kinds, materials) come
  from the D members by reflection (`ENUM_NAMES`, `LuaName`), never from
  hand-written name tables.

## Structure scripts (Lua)

A structure is a Lua function of a site, and a file holding one returns
it. A site is a turtle standing on a honeycomb vertex, facing along one
of its edges: everything a structure does is relative to the site it
was given, so a structure inside another is a call with another site,
and a structure placed further out is `site:place`:

    local hut = require("hut")

    return function(site)
      local corner = site
      for _ = 1, 5 do
        hut(corner)
        corner = corner:forward(1):right()
      end
    end

The engine runs the world's structure once, when the world is made,
with the anchor's first ground corner as the site (see Worldgen for the
rest); structures it places run later, as the world grows toward them.
The built-ins (`structures/*.lua`) are compiled into both binaries with
`import()` (`common/worldgen/embedded.d`); any other `.lua` path is
loaded from disk. `require` finds the built-in modules and structures
(`box`, `buildings.kit` and the building types, `tower`, `crown`,
`road`, `trail`, `city`) first, then files next to
the structure. Adding a built-in is a file in `structures/` plus a line
in `EMBEDDED_STRUCTURES` (`EMBEDDED_MODULES` for a module). The same
safe libraries as test scripts are open; errors carry a traceback.

- A site's axes are x (right), y (up) and z (forward, along its line).
  Coordinates are cells `(x, y, z)` in the site's column: z counts from
  the site's vertex (one edge is `site:edge_cells()` cells), x and y
  run perpendicular to the line. The column is the chunks around the
  line, `site:column()` (low, high: -dimension .. dimension - 1) cells
  either way in x and y; a box that leaves it is an error. Anything
  wider is built from more sites.
- Moving and turning give new sites; nothing changes the old one.
  `site:forward(edges)` walks along the line (negative walks back).
  Every angle in the honeycomb is right, so turns are quarter turns
  about the site's vertex: `left()` and `right()` about y,
  `pitch_up()` and `pitch_down()` about x, `roll_left()` and
  `roll_right()` about z (the `Turn` members). The world's site stands
  on the ground facing along the anchor's ground face, x into the face:
  `site:forward(1):right()` walks the face's pentagon,
  `site:pitch_up()` faces straight up a tower's axis with x unchanged,
  and `tower:forward(1):pitch_down()` stands level on the tower's top
  vertex.
- Drawing, applied in order, later over earlier: `site:paint(material,
  box[, rhythm])` and `site:fill(...)` (only into air, never over
  terrain). Materials are snake_case names, `"air"` carves. A box is
  `{ x = { low, high }, y = { low, high }, z = { low, high } }`,
  inclusive; a missing x or y is the whole column, a missing z the
  whole line (only the world's own structure may do that). A rhythm
  `{ every = n, from = phase, span = s }` keeps only cells whose z has
  (z - phase) mod n < s (`span` defaults to 1, `from` to 0).
- `site:stop(x, y, z)` appends a route stop for `route_waypoint` (a
  spot on a floor: the floor's top) in the order structures add them;
  `site:entrance(x, y, z)` is the door the player spawns facing,
  `SPAWN_DISTANCE` out along -x (the first entrance wins).
  `site:pick(n)` is a choice 1..n from one deterministic stream.
- Placing: `site:place(structure, ...)` queues `structure(site, ...)`
  to run when the world grows near the site, and returns false (placing
  nothing) when the site is more than `PLACE_SLACK` node levels behind
  the structure placing it; a placed structure may place more, so a
  structure can repeat or wander forever. Claims make rules that adapt:
  `site:claim([part])` claims the site's vertex (`"vertex"`, the
  default) or the face spanned by its forward and right edges
  (`"face"`: a ground turtle's city block) and returns whether it was
  free, `site:is_claimed([part])` asks. A placed structure paints only near
  its site (bounded z, and no node more than `PAINT_REACH` levels
  behind it); anything else is an error.
- The queue runs everything up to the deepest built node, which for
  anything that fills the ground is a whole disc around the root, so
  area-filling structures tile instead: `site:tile(fn, ...)` (the
  world's structure only, once) runs `fn(face, ...)` for every face of
  the ground plane, with the face's canonical site (`rootSite` of the
  sky node above it), just before any node it could paint is built:
  before a node gets its structure, the tiles of the eleven faces
  sharing a vertex with the face below it (`groundNodeOf`,
  `groundRing`) run. Tiles run in exploration order, so a tile cannot
  place or claim, and neighbors agree through `site:hash([part])`, a
  deterministic 64-bit hash of the site's vertex, face or edge from
  node ids (the same from every site on it); each tile's `pick` stream
  is seeded by its face. Where two tiles paint the same cells they must
  paint the same thing. A tile that paints an already built node is an
  error.
- `box.lua` holds box tower parts, each a function of an upright site
  (z up): `box.tower` (`shell`, `floors`, `windows`, `stairs`,
  `merlons`), `box.door`, `box.stair_route`, `box.palette`, `box.top`,
  and the constants (`HALF`, `STORY`, `DOOR`, ...). `tower.lua` is the
  box tower with a door and route, `crown.lua` builds its hall, five
  towers and arches around the face, `road.lua` paints the world's
  site along its whole length, and `trail.lua` is a winding gravel
  trail: each segment paves one edge, then places the next segment
  straight, left or right (a random order, the first whose far vertex
  is unclaimed and that is not behind), claiming that vertex, so the
  trail never crosses itself and ends only where all three are taken;
  every third segment places a hut on an unclaimed vertex beside it.
- `city.lua` is an endless city tiled over the ground plane. Every edge
  of the {5,4} tiling is a street unless its hash drops it
  (`DROPPED_STREET`); where that would leave a vertex with no street,
  its highest-hashing edge stays as a dead end, so every lot fronts a
  street. Blocks are irregular unions of pentagons and streets cross
  at right angles. Each street is painted once, by the face with the
  larger hash: a 4-cell basalt road, crosswalks, 2-cell raised concrete
  sidewalks on both sides that run through a vertex when no street
  crosses there, and street trees on some. Each vertex's lots are
  painted once, by its highest-hashing face: the four quadrants around
  it, cut into runs by its street edges, give a corner lot (one
  quadrant, 8 x 8 cells), a slab (two, 8 x 24), a wide L (three) or a
  lot wrapped around a dead end (four); a lot becomes a building
  (`KINDS` pick the types and cap the stories), a park, a plaza or a
  parking lot. A rare island face (`ISLAND`) keeps all its streets and
  carries one tower across its five quadrants. The root vertex keeps
  all its streets; its quadrant on the anchor face is the route
  building, a tenement whose route walks in from the street and
  climbs two stories, and the spawn stands on the street beside it.
- `buildings/kit.lua` builds a lot from its parts, a spec (type,
  stories, palette, front inset, alley gap, `route_stories`) and the
  type's design (setbacks, facade, storefront, roof material, a cap on
  every part, a crown on the largest). A part is a quadrant site whose
  four sides are each a street (sidewalk margin and wall), joined (no
  wall) or a lot boundary (wall, alley gap): the low sides lie on the
  vertex's edges, so joined low sides are in the same vertical column
  and stay one room all the way up. High sides join only across a
  pentagon (the island): below `dimension` cells the corner chunks of
  a face touch, above it the parts are in different nodes and a wedge
  of other chunks opens between them, so the island splits into five
  towers leaning apart as the vertical lines diverge. All parts of a
  building share one tier plan, every setback leaves a roofed terrace
  behind a parapet, and the top gets a roof and parapet. Every building
  with a front gets a door on that street and a stair core behind it
  (two lanes of three treads with a walkway between, stairwells cut
  through each floor, up to the top floor); setbacks never squeeze the
  core out. Types: `brownstone` (masonry, slate roof), `tenement`
  (storefront, tar roof, water tower), `deco` (masonry, two setbacks,
  spire), `glass` (curtain wall, spandrels, one setback, penthouse and
  antenna). Windows are glass, which is see-through.
  `tests/lib/showcase.lua` puts one of each type around an
  intersection for close inspection (`tests/visual/showcase*.lua`).

## Units

Lengths are absolute: 1 is the curvature radius R of the space
(sectional curvature -1/R^2). Hyperbolic space has its own length scale,
so this unit is a property of the geometry, not a convention; there is
no meter. Times are seconds, angles radians (degrees only at the Lua
boundary). UNITS.md is the full design.

- `common/units.d` types every dimensional value:
  `Quantity!(length, time, angle)` with `Ratio`, `Length`, `Time`,
  `Angle`, `Rate` (1/s), `Speed`, `Acceleration`, `AngularSpeed`.
  Products and quotients take their dimension from the operands
  (`Speed * Time` is a `Length`), and adding mismatched dimensions does
  not compile. Configs (`CharacterConfig`, `ClientConfig`), the
  controller's time step and parameters, and the game's time, distance
  and camera state are typed. Geometry kernels working in Klein or
  hyperboloid coordinates use plain floats and take `.value` at their
  boundary; worldgen and traversal radii are not typed yet (UNITS.md
  lists them).
- Blocks are a local unit. `Blocks` counts block heights, and a
  `LocalBlock` is one block measured at a point (its height along up,
  from the inverse grid Jacobian there); `heightOf` converts.
- A dodecahedral node cell is on the order of 1; a block's volume is
  ~1.2e-4 (mean edge ~0.05; with 12 cells a block edge is 0.035..0.077),
  and its shape varies (see Chunks below). The character controller works
  in Klein coordinates around the body (within ~0.3% of true distance at
  body scale) and moves the `Position` along the geodesic.
- tanh-parameterized distance: ray/sweep parameters are `tanh(distance)`.
  Values >= 1 mean unbounded. Convert with `atanh`/`tanh` at boundaries
  only.

Chunks additionally have grid coordinates (0..dimension), chunk
coordinates (0..1, what `chunkToNode` takes) and dual coordinates
(projective). `ChunkLayout` maps between them (`gridToChunk`,
`gridToDual`, `dualToGrid`, `cellCenter`); never divide by `dimension`.

## Hyperbolic space - representation

- Hyperboloid model, float, Minkowski product `mip` with signature
  (+,+,+,-). Points have mip(p,p) = -1, directions and plane normals
  mip(n,n) = +1. distance = acosh(-mip(a,b)); signed distance to a plane
  = asinh(mip(n,p)). Range tests compare `-mip > cosh(r)` and never call
  acosh; sphere-vs-plane tests compare against `sinh(r)`. Radii add in
  distance space, never in tanh or sinh space.
- `MIsometry.inverse` is the Minkowski transpose, so it's cheap but only
  correct for a true isometry. Float products drift off the group, so
  anything composed repeatedly (`Position.local`, the camera) is
  `renormalized()` each step.
- Tiling: order-4 dodecahedral honeycomb {5,3,4}. Nodes are right-angled
  dodecahedra, 12 sides and 20 vertices, 8 nodes around each vertex. Crossing
  a side applies that side's reflection, which is its own inverse.
  Reflections reverse orientation, so node transforms alternate parity hop
  by hop and half the visible world is mirrored. Anything involving winding,
  cross products or handedness must check parity (the determinant flip in
  `cull.comp` and `voxels.vert`).
- Positions are (node, local isometry) and never world coordinates.
  Hyperboloid coordinates grow like cosh(d), so float precision decays
  exponentially with distance from the frame origin. Every transform is
  rebuilt relative to the current node by a BFS over reflections, and
  nothing is accumulated from the root. The same growth is why `Plane`
  carries a separate exponent: a surface plane reflected through many nodes
  has normal coefficients ~e^d.
- Conventions for composing transforms: node changes left-multiply
  (`refl * local`), and motion and orientation in the body's own frame
  right-multiply (`local * step`). Velocity, up, and the collider axis are
  float[3] in the body frame, so a node hop leaves them untouched. Keep
  them there.
- Chunks: each node is split into 20 cubes, one per dodecahedron vertex,
  running from that vertex (grid 0) to the node center (grid `dimension`).
  Grid planes are planes of constant Klein (projective) coordinate in the
  vertex's dual frame, so voxel faces are geodesic planes; the same
  spacing is used on every axis, so planes line up across seams.
  The spacing is geometric (`ChunkLayout.make`), each cell
  cosh(R)^(-4/(3d)) the width of the one before. Block volumes are not
  equal: they vary up to 1.7x across a chunk, and blocks stretch up to
  ~2:1, tall near the base plane. Exactly equal volumes are impossible
  for a box grid of geodesic planes (the constraints are overdetermined;
  `tools/gridvolume.py`'s optimizer gets only to 1.69x). A
  unit test checks the spread and that the blocks sum to the node
  volume. Never assume a fixed voxel extent or shape.
- Chunk adjacency is asymmetric. A low face (coord 0) lies on a node side,
  and its neighbor is the same vertex in the adjacent node, mirrored with
  no axis permutation. A high face (coord `dimension`) is interior to the
  node, and its neighbor is the adjacent vertex's chunk in the same node
  with permuted axes. Always go through `chunkNeighborSlot` /
  `neighborAxisPermutation`; never hand-derive either.
- Rendering uses the Klein model. Applying a Euclidean projection to
  homogeneous hyperboloid coordinates keeps geodesics straight, so the
  normal rasterizer works, and all of H^3 fits inside zfar = 1 (the Klein
  ball). Depth is therefore not distance. Recover it with atanh of Klein
  length, as `fog.frag` does; fog closes at the render radius. Depth is
  reversed (near 1) and the projection flips y, so visible faces wind
  clockwise; the swapchain is sRGB and constant colors are converted
  from sRGB.
- Chunk meshes are built on the CPU (`client/meshing.d`) from the graph's
  change queue by the whole worker pool, the main thread included, as a
  `runParallel` job under a per-frame time budget; the graph is read-only
  while the job runs. Faces live in one growing device buffer managed by
  a range allocator. The CPU writes a drawable record (node, vertex, face
  range) and the listed nodes' transforms only when the nearby set is
  relisted or a mesh changes; `cull.comp` composes each chunk's transform,
  frustum-culls its bounding sphere and writes the indirect draws, so
  per-frame CPU cost does not scale with the number of drawables.
  Ambient occlusion reads cells beyond the face margins by hopping
  through slot-based chunk neighbors (`common/neighbors.d`), so a
  change to a chunk re-queues every chunk sharing a face, edge or corner
  with it. Glass is see-through (`isShownAgainst`): a solid cell's face
  is drawn against air or glass, never between two glass cells, and the
  glass texture is a clear pane with a one-texel frame that
  `voxels.frag` cuts out below half alpha; the frame's alpha is below
  one, which tells the shader to draw it on outward faces only, so a
  one-cell pane shows a single frame. Physics and picks still
  treat glass as solid.
- `Side.init == Side.a`. It isn't a free sentinel, so check for "no side"
  some other way. The invalid `Vertex` is 255.

## Hyperbolic space - what actually bites

- Volume grows like e^(2r). The nearby-node set at render radius 4.5 is
  ~33k nodes. Radius padding is never cheap (+0.05 radius ~ +10% nodes,
  +0.25 ~ +65%). Per-frame work must scale with what is visible or swept,
  never with the metric ball.
- Moving distance d replaces ~1 - e^(-2d) of the surrounding ball. There is
  no such thing as a small move; steady-state motion means constant churn of
  the working set, so rebuilds must be cheap and budgeted, not avoided.
- Holonomy: parallel transport around any loop rotates the frame. Never
  integrate orientation state and expect it to stay aligned; re-anchor to a
  world reference every frame. The body's up is the surface plane's up
  at the body (`Graph.upAt`), every substep. The camera is an
  orientation quaternion relative to the body's `Position`, a frame
  parallel-transported with the body; every frame its roll is leveled to
  that up and its pitch is reset to the stored `pitch`, so only yaw
  carries over.
- Down is not flat. Gravity follows equidistant surfaces of the surface
  plane; voxel faces are geodesic planes; the two agree nowhere except on
  the base plane itself. Normal worldgen therefore produces terrain that is
  corrugated 1-block staircases relative to gravity, and anything touching
  ground contact, stepping, or slopes must expect that. `--worldgen plane
  0` is the clean-room case.
- Tangent vectors live at a point. A normal computed at one point (an offset
  collider section, a contact) is wrong at another point until parallel
  transported - a few degrees of error at body scale, which is fatal for
  constraint solvers whose escape margins are ~1e-7.
- Chunk seams: adjacent chunks are different frames; nothing is coplanar
  across a seam by representation, only by geometry. Every chunk carries
  margin cells mirroring its neighbors' boundary voxels (`common/margins.d`);
  any cross-chunk voxel question must read margins, never assume.
- Collision and rendering both operate on the surface mesh: exposed faces
  only (solid cell, empty neighbor including margins), their bounded edges
  and corners. Faces that are flush in the grid are not coplanar in H^3
  (around a valence-5 edge five block tops form a slight peak), so every
  edge and corner of an exposed face is a collision feature; a sphere
  resting on such a peak touches only the corner. Internal lattice
  planes, infinite grid lines, and backfaces must never generate
  contacts.
- The graph is append-only: node slots and node pointers are stable
  (slabbed storage). Node ids derive from the parent path, so worldgen is
  deterministic; `--dump-world` is the proof. Chunks live in their own
  slab at slot * 20 + vertex (`Graph.chunkAt`): chunk params read the 8
  nodes around the chunk's vertex, which creates a shell of nodes ~4.5x
  the nearby set that never hold chunks, and their chunk pages are never
  touched.

## Character controller

Physics runs in true geometry, in absolute units, and is modeled on
Minecraft's movement without drag. Minecraft's speeds and accelerations
were converted once into absolute values (at the mean block edge, ~0.05)
and are not tied to blocks; anything that is said in blocks
(`stepHeight`) is a `Blocks` count measured locally (see Units). The body is a
`Position` (node and local isometry) with velocity, up and ground normal
in its own frame. Each substep `Features.collect` (`character/features.d`) visits
the nodes and chunks within `regionReach` of the body and turns every
exposed face of a solid cell (exposure read from chunk margins) into a
quad in the body's local frame, with its edges and corners; the substep's
motion is computed in that frame and applied to the `Position` along the
geodesic (`movedBy`).

`character/controller.d` is a kinematic controller with one primitive:
`Mover.slide` sweeps the capsule against those features
(`Sweep.fromCapsule`, `character/sweep.d`), clips the remaining
displacement and the velocity against every contact plane so far (single
plane, then the crease of two, else stop), and repeats up to
`MAX_CONTACT_PLANES`.

- Contacts: a feature is hit when radius plus `skin` would touch it
  within the move and the motion approaches it; motion stops one skin
  short and clipping restores the skin. Every contact clips along its
  normal. A slide's sweep skips features whose normal matches a plane it
  already clips against: the clipped motion satisfies that plane, so a
  re-hit is only rounding and would use up the slide's contacts (pressed
  against a wall, the settle never reached the floor). Where restoring
  the skin on all planes is infeasible (a body squeezed between opposed
  faces), the displacement clips without restoring it, as the velocity
  does, so it still slides along the gap.
- Collider: spheres along the axis, spaced so the chain stays within one
  skin of the true capsule. A face contact counts only where the touch
  point projects inside the quad; edges and corners cover the rest.
- Support: a contact supports when the motion is descending, it is on
  the lowest sphere, and its normal is inside the Coulomb friction cone
  (`normal . up >= minSupportCosine = 1 / sqrt(1 + footFriction^2)`).
  Where three grid axes are mutually perpendicular one of them is always
  within acos(1/sqrt(3)) = 54.7 degrees of up, so `footFriction` must
  exceed tan(54.7) = sqrt(2) for every block's most level face to hold;
  1.75 (a 60.3 degree cone) leaves margin for up varying across a face.
  At 1.5 blocks in grids tilted near node centers were not standable.
  Landing drops the vertical part of the rest of the move and of the
  velocity, as Minecraft does (a settle drops all of the move); there is
  no ledge rule and no slope limit beyond friction.
- Walking: on the ground the velocity approaches the input direction at
  `walkSpeed`, projected onto the ground plane (`alongGround`),
  exponentially at `walkResponse` (Minecraft's ground factor, 0.546 per
  1/20 s tick, is 12.1 /s); the step integrates the exponential exactly,
  so the result does not depend on the timestep. There is no gravity on
  the ground, so a slope slows motion along its fall line by its cosine.
  The walking slide keeps the ground plane as a constraint, then settles
  one skin; if that finds no support the body is unsupported.
- Stepping: `stepHeight` is one local block (`Blocks(1)`). Each walking
  substep probes the cell just ahead of the foot sphere (`BlockProbe`)
  and measures that block's height along up: the sum of its three
  edges' vertical components, from the inverse grid Jacobian, which is
  the riser it can form however the grid tilts. A walking slide
  obstructed by a non-supporting contact is retried raised by that
  height plus the skin, moved across by at least the radius plus skin
  (enough for the foot to land over the edge, independent of the
  substep's length) with the uncollided velocity, and settled back down.
  The step is kept only if it landed, ended higher than the plain slide
  by more than a skin, and got further along the move; otherwise the
  forced advance would slide the body around curved walls.
  `jumpHeight` (0.085) clears the tallest block edge with margin for the
  rounded bottom.
- Jump: on the step the key is pressed, if on the ground, the velocity
  becomes its ground part plus `jumpSpeed = sqrt(2 g jumpHeight)` along
  up.
- Unsupported (not touching ground): gravity acts, and input steers the
  horizontal velocity at `steering` (Minecraft's 0.02 blocks per tick
  squared). Steering never pushes the horizontal speed past the larger
  of `walkSpeed` and the speed already held, and without input momentum
  is kept. There is no drag. Clipping never adds speed. Taller ledges are
  climbed the Minecraft way: walk into one, jump, and holding forward
  carries the body onto it once it is above the edge.
- Gravity: `gravity` (1.6, Minecraft's 32 blocks/s^2) along minus up.
  Every substep up is the surface plane's up at the body (`Graph.upAt`),
  which is smooth; the capsule pivots about its lowest sphere when it
  turns. Velocity is carried along the geodesic (`local * step`
  parallel-transports it) while up is recomputed, so unsupported motion
  follows geodesics, which rise away from the surface plane: at speed s
  and altitude h a body falls s^2 tanh(h) slower than from rest
  (`tests/flat/curve.lua`). On long falls the same effect turns some of
  the fall into horizontal speed; landing keeps it and ground response
  sheds it.
- Block placement is refused where the voxel would overlap the character
  (`CellOverlap`).
- Steps of any length are split into substeps that each move at most one
  radius. A substep whose features are not loaded (a chunk in reach, or
  a neighbor whose margins it reads, unpopulated, or a node missing)
  zeroes the velocity and marks the step stalled (`Stepped.isStalled`);
  `RequiredChunks` lists what generation must provide.
- Spawn: `clearSpawnPosition` finds a point above the surface whose
  surroundings are proven void (a structure with an entrance stands the
  body in front of its door instead), then the body generates around
  itself and settles straight down until it lands.

## Worldgen

- A chunk is void when its lowest point is above the terrain ceiling:
  corner elevations plus the terrace bound plus the noise bound (Box-
  Muller over 24-bit uniforms is bounded). Plane distance is 1-Lipschitz
  and a chunk's farthest point is a corner, which is what
  `chunkGridCenterRadius` measures.
- A chunk proven solid is stored uniform when one material is proven
  (below the surface layer, one elevation band, climate range in one
  Voronoi cell), else stored solid with `hasDeferredMaterials`; the exact
  materials are generated, by the same function, when it is edited or a
  void cell appears in its margins. Never assume solid storage means one
  material.
- Trees are oak, birch and spruce (`TREE_SPECIES`), chosen by climate. A
  tree grows along the grid axis nearest up (`Plane.risingNeighbor`),
  needs ground below and empty cells at and above its base, and is
  placed only if its whole box fits inside its chunk: chunks are
  generated independently, so nothing may cross a chunk.
- A world has at most one structure (`Worldgen.structureName`: the
  chosen one in a structure world, `road` in terrain), relative to the
  anchor node (`anchorSlotOf`, a node standing on the surface plane
  with its down face `Side.a` on it). `Graph.make` only creates the
  anchor and an empty `Blueprint`; `placeWorldStructure`
  (`client/structures.d`) runs the structure's Lua script (see
  Structure scripts) into it before the player spawns. A blueprint is
  data: canonical lines, each with its brushes, the materials they
  use, a route, an optional entrance and the claimed vertices. Nothing
  in the engine knows a structure by name.
- Structures are built on honeycomb edge lines. Every line is where
  two honeycomb planes meet, and a plane carries one side label
  everywhere. A `SiteFrame` (the D side of a Lua site) is a node, a
  vertex of it, which planes are x and y (the line is z, along their
  meeting), the signs of the three axes against the node's inward
  normals, and the level of the site's origin from that vertex. Its
  moves are exact: walking along the line goes to the next vertex in
  the node or crosses the face perpendicular to the line, and a turn
  permutes the signed axes at the origin vertex, all creating nodes as
  needed. `rootedVertex` names a vertex by the node closest to the
  root among the 8 around it, which is what vertex claims key on and
  whose depth orders placement; `siteFace` names a face by the
  shallower of its two nodes and its side.
- The nodes on a line form a coset of a special subgroup of the
  reflection group, which is convex, so every one of them but the
  closest to the root has a parent on the line. `canonicalOf` descends
  from a site to that closest node; the line there, with its planes in
  side order, inward signs and level 0 at the lower vertex index, is
  the canonical `LineSpec`, and a `LineTransform` (signed swap of x and
  y, z sign and level offset) maps the site's cells onto it.
  `BlueprintBuilder` stores each brush in canonical cells, so sites
  placed differently on one line share it, and widens the line's edge
  range (`lowest`/`highest`, edges by their lower vertex's level) to the
  brush's z cells; an unbounded brush makes the line endless
  (`int.min`/`int.max`).
- Every node touching a line holds exactly one edge of it, the edge
  between those two planes, so a node stores per line a `LineTouch`
  (in `Graph.touches`): the level of that edge's lower vertex and which
  side of each plane the node is on. An endless line's touches
  propagate from a node's parents (`crossed`: crossing a plane flips
  its sign, crossing the side at either end of the edge moves one level
  along), starting from its canonical node, so it can run forever. A
  bounded line's touches are written ahead, as pending touches on the
  four nodes around each edge a brush covers (`walkedTouch`,
  `aroundEdge`), so a short line far out costs nothing elsewhere.
  `finalizeStructure` merges both when a node's structure is first
  needed, and a node whose touch is in its line's range is in the
  structure. No frames or float tolerances are involved. Unit tests
  check touches, site moves, the vertex keys, the paint limits and the
  canonical mapping against geometric frames.
- Placed structures are lazy but deterministic. Each waits in the
  host's queue under a key, the larger of its placer's key and its
  site's vertex depth, and the queue runs in key order, first in first
  out. Before a node at depth d gets its structure, `Graph.growBefore`
  runs every placement keyed up to d + `PAINT_REACH`; a placement
  paints only nodes at least its key minus `PAINT_REACH` deep, which
  are all still open. Running the queue is the same sequence however
  the world is explored, so claims and `pick` come out the same; only
  how far it has run differs. Rules that branch a lot grow
  exponentially in a placement's reach, as the space does.
- Around a line every chunk has one grid axis along it and two across
  it, so everything is counted in whole cells: `ColumnChunk.fromTouch`
  maps a cell to column coordinates (x, y, z), z counted from the
  line's level 0 and `edgeCells` (2 * dimension) cells per edge
  (vertex to edge midpoint to the next vertex). A `Brush` paints a
  `CellBox` in one line's column coordinates with a material (none
  carves), optionally only at z in a `Rhythm` (period, phase, span
  along the line), and optionally only into air. `Building` applies
  the brushes of the lines at each chunk in the order they were
  painted (`Brush.order`), later brushes over earlier ones. Frames are
  only for scripts and spawning: `siteToNode` composes the reflections
  from the site's node to the target node through their common
  ancestor, in double, because accumulating from the root drifted by a
  third of a cell at the top of a tower.
- The anchor's down face lies on the surface plane, so the edge leaving
  each vertex of that face is a geodesic perpendicular to the ground:
  a truly vertical line. Tower cell layers are geodesic planes
  perpendicular to it: floors are exactly flat, and relative to gravity
  a floor at altitude h rises toward its walls (sinh(altitude) =
  sinh(h) cosh(distance from the line)). Walls are grid planes, so a
  box is widest at each edge's midpoint.
- `tower` is one box on the first such line: 2 * `box.HALF` cells
  square, `EDGES` edges tall, on a `box.FOUNDATION` foundation. Its
  outer ring is the wall: trim at the corners and on
  every floor layer, a 2x3 door in the middle of the -x face, 2-wide
  1-tall windows (shorter than the body) one cell in from each corner
  pillar at layer 2 of each story (layer 0 is the floor), merlons above
  the top. Inside, a floor every `box.STORY` layers and one straight
  flight per story: three one-block treads in a two-cell lane, the lane
  alternating sides story by story, under a stairwell hole in the next
  floor that also spans the cell before the first tread. Without that
  cell the 3-cell headroom (cells shrink with height) left no room to
  step or jump onto the first tread under the ceiling.
- `crown` uses the five corners of the anchor's ground face (walked
  with `forward(1):right()`): its floor plan is that face, a
  right-angled pentagon. Each corner's upright site
  (`pitch_up():roll_right()`) has x along the side ahead and y along
  the side behind. A two-story hall fills the anchor's five corner
  chunks (a corner's inside quadrant, x and y both >= 0) with an open roof
  terrace at `HALL_ROOF`, windows, and a door in the middle of one
  side, which the spawn faces. On each corner a box tower (stairs as in
  `tower`, `EDGES` edges tall) rises; its inside quadrant is open to the
  hall below the roof, a door leads out onto the terrace, and bare
  balcony slabs (`FIRST_BALCONY_STORY` up, alternating outer faces)
  stand on its outer faces. Nothing has guardrails: falling off is
  allowed. Vertical geodesics diverge, so the
  five towers fan apart as they rise. One edge up, each tower's top
  vertex has two horizontal edges along the hall's sides; each pair
  that shares a side meets at the side's fifth vertex at a right angle
  (the side is a right-angled pentagon too), and a bridge line on each
  carries a bare 2-wide deck. Each deck is level at its tower, but a
  geodesic rises away from the equidistant surfaces, so the two decks
  form an arch: relative to gravity a deck at distance d along an edge
  from a vertical line at altitude h tilts by acos(cosh h / sqrt(1 +
  cosh^2 d sinh^2 h)), 45 degrees at the apex. A unit test checks that
  the two decks of an arch share their apex cell.
- `road` is the terrain world's road: one endless line, the world
  site's own, which is the edge of the anchor between `Side.a` (the
  ground) and `Side.b`, so it runs straight along the ground plane
  forever. A brick deck two cells
  thick sits on the ground with a white center stripe, air is carved
  above it to the chunk's reach (cutting through hills), and wooden
  posts and cross beams every `SUPPORT_SPACING` cells fill only air
  below it, so over valleys it is a trestle bridge.
- A node's building is memoized per node. In the client the streamer
  computes it on a worker (`Streamer.scheduleBuilding`) and holds that
  node's chunks back until it is integrated; headless and
  `--screenshot` generation build synchronously
  (`Graph.ensureBuildingAt`). Placed structures keep adding to the
  blueprint on the main thread, so a building request carries a
  `BuildingPlan` copied from it (the node's touches in range, their
  lines' brushes, the materials) and `Building.make` reads only that.
  A node with a structure is never proven clear, full or deferred.
- A node level is ~1.6 absolute (~30 blocks) tall. Seen from a node's center
  its face directions form an icosahedron: the faces around the down
  face sit 26.6 degrees below horizontal and those around the up face
  26.6 above. The 10 chunks at a node's middle height touch faces from
  both rings, so all three of their grid axes are ~63 degrees from
  vertical near the center, and every vertical route through a node
  crosses that band.
  Vertical geodesics diverge like cosh(altitude), so from the ground a
  constant-width tower's upper levels shrink toward a dome under the
  angle of parallelism, and anyone rising beside a tower drifts away
  from it.

## Performance rules

- Measure before changing, with the `--bench-*` commands; frame smoothness
  lives in the worst frame, not the average.
- No hash lookups in per-frame loops - use slots (`ChunkSlot`: graph slot
  plus vertex; the renderer indexes chunks by slot * 20 + vertex). No
  growing flat arrays for bulk data - the graph slab exists because one
  realloc memcpy of 60MB is a visible hitch. No stop-the-world growth
  either: the hash map rehashes incrementally.
- Budget any work that can arrive in bursts, by time, per frame: the
  nearby-set BFS (double buffered, published when complete), worldgen
  integration and requests (one budget; integration goes first), and
  meshing. Every loop under a budget checks it per item, including loops
  that mostly skip. Building computation runs on workers; an earlier
  tower computed on the main thread showed as ~200 ms worst frames in
  `--bench-load --worldgen structure tower`.
- `./mined --bench-load --out <report>` measures the client cold load at
  60 Hz pacing (frames until the nearby set, worldgen and meshing finish,
  frame/step/render average and worst) and then 5 s of noclip flight.
  Judge changes by its worst frames.
- Chunk generation is async on worker threads (cores minus two); the main
  thread builds params (including the memoized node structure) and
  integrates results. A chunk whose occupancy
  worldgen proves (`predictOccupancy`) has trivial voxels and is generated
  and populated inline; only unknown chunks go to the workers. Workers
  take an open `runParallel` job, then building requests, then
  generation requests. Unloaded world is impassable to the character
  (`Features.isLoaded`) - bodies must never occupy space that later
  materializes.
- A solid chunk stays solid (no dense storage) unless a neighbor's
  boundary differs from it in voidness: only voidness matters for a
  solid chunk's faces, collision and AO. Mesh-relevant changes go through
  `Graph.markChanged` (dense chunks only); the renderer meshes from that
  queue. AO treats an unloaded cell as occupied unless worldgen proved its
  chunk empty (`predictOccupancy` at request time), so a newly loaded
  chunk only notifies its edge and corner neighbors when it contradicts
  that prediction.

## Style

- ASCII only, everywhere: code, docs, and scripts.
- No comments at all, anywhere.
- 4-space indent, braces on the same line, every body braced.
- Wrapping: a construct is either entirely on one line or one element per
  line. Never wrap partially, never end a line with an operator, never put
  several list items on one line of a one-per-line list.
- Naming: types are PascalCase, constants (`enum` and module-level
  `immutable` values) are ALL_CAPS, everything else is camelCase, enum
  members included. Booleans and tests read as questions: `isFound`,
  `hasChanges()`, `isCellOccupied(...)`. File and directory names have no
  underscores; every module is named for what it holds, never `package.d`.
- Control flow: no ternaries, no `++`/`--`, no `for` (use `foreach` or
  `while`), no `return;`. Code must stay correct if every `return` were
  replaced by a `break` out of the outermost loop: a guard returns and its
  `else` returns too, and a search is a `while` loop advancing an index
  followed by `if`/`else` on whether it was found - never a `return`
  inside a loop followed by a fallback `return`.
- Conditions never mutate. A call that mutates and reports success has its
  result assigned to an `immutable` local, then tested with `if`/`else`.
  Success values may be returned; failure is never ignored. Don't extract
  a condition into a variable that is used once, and don't mark values
  `immutable` when nothing depends on it.
- Parameters: structs are passed by `ref` (`ref const` when read only),
  never by pointer; pointers are for stored references and C APIs. No
  `out` parameters except where a C API demands them: return a struct.
- Plain structs, minimal templates, no classes. An operation on a struct
  is its method, or a free function taking it by `ref` and called with
  UFCS (`graph.hopCell(...)`). No `private`; module boundaries are the
  visibility unit. Setup methods are `setup`, never `init`.
- Constructors are static methods named `make` or `fromX`
  (`ChunkLayout.make`, `Sweep.fromCapsule`), never free
  functions and never `this(...)`. Build values with struct literals
  rather than default-constructing and assigning fields.
- Struct fields are ordered by alignment, largest first, so structs carry
  no padding they don't need.
- Imports at the top of the module, always - never scoped inside functions
  or unittest blocks. core first, then project modules, sorted by module,
  each importing a named symbol list sorted in ASCII order.
- No module-level mutable state: no `__gshared`, no thread-local globals.
  State lives in structs owned by whoever uses it; state shared with worker
  threads lives in an object handed to them (see `GenQueue`).
- No `static this` and no `static immutable`. Lookup tables are built by a
  plain function evaluated with CTFE into module-level `immutable` (see
  `DodecaTables.make`). CTFE has a known aliasing bug with
  copy-then-mutate of static arrays - build fresh arrays element-wise.
- No unused functions, variables, or imports. Delete instrumentation after
  it answers its question.
- Constants get names and, if dimensional, a `common/units.d` type (or,
  inside a float geometry kernel, a name that says the unit). Bare magic
  numbers with unclear units are unacceptable.
- unittest blocks live next to the code they test. Behavior changes get a
  Lua script in `tests/` (or a bench) that checks them headlessly.
