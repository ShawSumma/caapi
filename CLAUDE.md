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
  - `streaming.d` - Streamer: worker pool (generation requests and
    fork-join `runParallel` jobs), request scan, budgeted integration,
    chunk population and margin connection.
  - `meshing.d` - chunk surface extraction with ambient occlusion.
  - `camera.d` - Camera: orientation quaternion, pitch, eye smoothing.
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
    (chunk grid coordinates, axis permutations), `ray.d` (rays and contact
    terms).
  - world: `graph.d` (node graph, node and chunk slabs, change queue),
    `node.d` (chunk and voxel storage), `margins.d`, `neighbors.d`
    (cross-chunk cell resolution), `traversal.d` (nearby BFS),
    `position.d`, `material.d`, `settings.d` (SimMeters to SimConfig).
  - worldgen: `worldgen/generation.d` (Worldgen kinds, node state, chunk
    params, proofs, voxels, trees), `tower.d` (tower L-system, per-node
    structure), `building.d` (a node's building voxels: prisms, walls,
    floors, windows, door, stair search), `terraingen.d`, `plane.d`,
    `spawn.d`.
  - collision: `collision/chunk.d`, `collision/graph.d` (shape casts,
    region checks), `character/controller.d`, `character/sweep.d`,
    `character/frame.d` (up and body modes: the block under the feet
    gives gravity, view up and body size); ray picks in
    `raycast/chunk.d`, `raycast/graph.d`.
  - containers and utilities: `array.d`, `hashmap.d`, `slab.d`,
    `allocator.d` (range allocator), `murmur.d`, `clock.d`.
- `source/shaders/` - GLSL, compiled to `spv/` by the pre-build step;
  `common.h` (common UBO), `draw.h` (structs shared by `cull.comp` and
  `voxels.vert`), `face.h` (packed face layout, matches `client/meshing.d`).
- `tests/` - behavior scripts: `tests/flat/` (level plane world),
  `tests/slope/` (tilted plane world), `tests/structure/` (structure
  world), `tests/modes/` (up and body modes), `tests/api.lua`;
  `tests/lib/` shared Lua (`walk.lua` builds walls and corners layer by
  layer, one material per layer; `climb.lua` follows the base's stair
  route); `tests/visual/` screenshot scenes. Physics is tested only in
  plane and structure worlds, never in terrain.
- `tools/gridvolume.py` - measures block-volume spread and block edge
  lengths in meters for candidate chunk grid spacings, and the chunk
  volume.
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
  under `-unittest`.
- Behavior tests: `dub run -b release --compiler=ldc2 -c headless -- --out
  <report> tests/<dir>/<name>.lua...` - exit status 1 on any script error
  or failed assert; the report file holds the details.
- Nothing writes to stdout, and stderr carries only startup errors: a bad
  argument, a file or window that cannot be opened. Each is one line
  naming what was wrong, with exit status 2 for usage. Never fail
  silently. Headless output goes only to the `--out` file;
  `--dump-world`, `--world-digest` and `--bench-*` require it. Pass/fail
  is the exit status. `--out /dev/stdout` reads a report without creating
  a file.
- Dependencies live in `deps/`. C comes in through ImportC only - no cc, no
  make, no cmake, no build output outside dub's cache. Lua's individual
  `.c` files are `sourceFiles`. `deps/lua` carries small ImportC patches:
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

- `mined-headless --out <report> <script.lua>...` - runs Lua scripts
  through the full simulation, each in a fresh world. Deterministic: chunk
  generation is settled every step, so a run is a pure function of the
  script. Each script's `session:` line (steps, time, distance in meters)
  and any script error land in the report.
- `./mined --record <file.lua>` records live play as a replayable Lua
  script (key changes, look deltas, events, and merged runs of identical
  steps as `world:wait(seconds, dt)`).
- `--worldgen terrain`, `--worldgen plane <tilt degrees>`, `--worldgen
  structure <name>` (both clients; `world:worldgen(kind[, tilt or name])`
  in a script). A kind takes a fixed number of arguments, parsed per kind
  with a `final switch`; structure names come from `StructureKind`
  (`tower`). `plane 0` fills exactly below the base surface plane. The base plane is
  lattice-aligned, so this is a genuinely flat floor with gravity
  perpendicular to it. Use it to isolate physics from terrain. A nonzero
  tilt gives a constant grade relative to gravity (gd(altitude) +
  tan(tilt) * horizontal distance = 0), not a tilted geodesic plane:
  in H^3 a geodesic plane tilted by t turns vertical within atanh(cos t)
  of its base line. The player spawns facing uphill. `structure` is the
  flat ground with exactly one structure one node from spawn; the player
  spawns facing it.
- `--dump-structure` (needs `--worldgen structure <name>`) - the tower as
  its node tree: symbol, counters, altitude, face masks, which up faces
  the stairs connected, how many cells the stair searches reached, the
  route length, and how many voxels each node fills. Use it to see a structure's shape without
  rendering.
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

- Quantities are meters, seconds, and degrees (like `*Meters` config).
  Positive yaw turns right and positive pitch looks down (mouse sense).
- Time: `wait(s[, dt])` (steps of dt, default the timestep), `step([dt])`
  (one step), `timestep([s])` (default 0.016), `time()`,
  `worldgen("terrain"|"plane"|"structure"[, tilt or name])` and
  `grid(["volume"|"uniform"])` (both before the first step; they create a
  fresh world and respawn), `on_step(fn|nil)` (runs
  fn after each step to observe; it cannot advance time).
- Input: `hold(key...)`, `release(key...)`, `release_all()`,
  `press(s, key...)`, `look(yaw, pitch)` (immediate), `turn_rate([yaw/s,
  pitch/s])` (held look rate; returns the current one), `turn(yaw, pitch,
  s)`. Keys are the `Key` members in snake_case: fwd back left right up
  down yaw_left yaw_right pitch_up pitch_down. In walk mode up jumps and
  down sprints (space and shift in the client).
- Actions: `mode([walk|fly|noclip])` (fly to walk keeps the last fly
  velocity, so take one fly step with no keys before landing),
  `up([world|grid|camera])` and `body([fixed|stretched])` (see Modes
  below; each returns the current mode), `material([1..9])`,
  `break_block()`,
  `place_block()` (both return whether they changed a voxel),
  `enter_structure(m)` (structure world only: puts the player on the
  tower's axis m meters above the ground - the only reliable way to get
  near a tower's upper floors, see below), `enter_stairs()` and
  `stair_waypoint(k)` (the base's stair route: yaw, horizontal distance
  and rise to its k-th cell, or nil past the end).
- Observation: `target_material()` (snake_case name of the voxel in reach
  under the crosshair, or nil), `traveled()` (path length),
  `is_on_ground()`, `altitude()`
  (body center above the base surface plane; half height plus the contact
  skin standing on flat worldgen), `speed()`, `horizontal_speed()`,
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

## Units

Three unit systems coexist. Confusing them costs days.

1. Absolute units: curvature radius = 1. All math in `common/math.d`,
   collision, traversal, and every stored position/distance. A dodecahedral
   node cell is on the order of 1; a voxel's volume is ~1.2e-4 (edge
   ~0.05), but its shape varies (see Chunks below).
2. Meters: human-scale config. All `*Meters` config values (`SimMeters`,
   `CharacterMeters`: speeds, sizes, reach) are meters and seconds;
   `voxelSize` is the cube root of a block's volume in meters
   (`NODE_VOLUME / 20 / dimension^3`). `SimConfig.fromMeters` converts to
   absolute via `metersToAbsolute` exactly once. Never convert anywhere
   else and never hand-estimate the factor - compute it or read it from
   `SimConfig`.
3. tanh-parameterized distance: ray/sweep parameters are `tanh(distance)`.
   Values >= 1 mean unbounded. Convert with `atanh`/`tanh` at boundaries only.

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
  `GridSpacing` (part of `Worldgen`, G in the client, `world:grid`)
  picks the spacing: `volume` (default) is geometric, each cell
  cosh(R)^(-4/(3d)) the width of the one before, which keeps block volumes
  within 1.7x across a chunk (exactly equal is impossible for box grids)
  but stretches blocks up to ~2:1, tall near the base plane; `uniform` is
  even in Klein coordinates, ~8x volume spread, blocks flat near the base
  plane. A unit test checks the spread and that the blocks sum to the
  node volume. Never assume a fixed voxel extent or shape.
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
  with it.
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
  world reference every frame. "Up" comes from the world
  (`relativeUp` -> `NodeState.surface`), the camera keeps a yaw-only
  up-aligned quaternion plus a scalar pitch, which cannot accumulate roll.
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
  and corners. Internal lattice planes, infinite grid lines, and backfaces
  must never generate contacts; needing a special case to suppress one is
  the sign of colliding against the wrong geometry.
- The graph is append-only: node slots and node pointers are stable
  (slabbed storage). Node ids derive from the parent path, so worldgen is
  deterministic; `--dump-world` is the proof. Chunks live in their own
  slab at slot * 20 + vertex (`Graph.chunkAt`): chunk params read the 8
  nodes around the chunk's vertex, which creates a shell of nodes ~4.5x
  the nearby set that never hold chunks, and their chunk pages are never
  touched.

## Character controller

`common/character/controller.d` is a kinematic controller with one
primitive: `Mover.slide` sweeps the capsule (`Sweep.fromCapsule`,
`common/character/sweep.d`), clips the remaining displacement and the
velocity against every contact plane so far (single plane, then the crease
of two, else stop), and repeats. Everything else is built from it.

The only tolerance is `contactSkin` (meters): bodies rest one skin from
every surface. Nothing else in collision or response has an epsilon; the
remaining constants are an iteration bound and a parallel-plane
conditioning guard.

- Contacts (`common/ray.d`, `common/collision/chunk.d`): a feature is hit
  when radius plus skin would touch it within the move, and only while the
  motion approaches it, so tangent motion never produces contacts. Motion
  stops one skin short, and the hit reports its gap against the true
  radius; clipping restores the skin, which also depenetrates. Detecting
  at the true radius let bodies drift into the skin band unnoticed and
  get pushed back out on the next approach - a one-frame oscillation in
  inside corners (`tests/flat/corner.lua`). Inside the band a contact
  also needs the move to reduce the separation as computed in float:
  motion clipped exactly onto a plane is tangent up to rounding, and
  counting that rounding as an approach re-hits the same plane until the
  contact budget runs out (a settle that never lands).
- Collider: spheres along the axis, spaced so the chain stays within one
  skin of the true capsule. Faces own their contact point half-open (exact
  partition within a chunk); edges and corners are tested where convex or
  on the chunk boundary, which closes the float crack between chunks'
  frames.
- Support: a contact supports when it is on the lowest sphere's lower half
  and either its normal is walkable (`maxGroundSlope`) or a walkable face
  meets the feature - a footprint rule, so a ledge rim under the foot
  holds you. The walkable normal matters at chunk boundaries: there the
  concave edge where a riser meets the tread below is tested as the
  riser block's feature, whose faces are all steep. A supporting contact
  while descending absorbs the downward motion.
- Velocity: on the ground it approaches the input target at
  `groundAcceleration` with no gravity; in the air gravity and drag apply
  and input only steers toward the target. Clipping never adds speed.
- Walking slides keep the ground plane as a constraint; walkable contacts
  clip along up while walking or descending, others along their normal.
- Ground move: slide; if a wall blocked it and the wall's block has empty
  space above it (`stepBlockHeight`: exactly one block tall along the
  grid axis nearest up), try a step: slide up 1.5 block heights (capped
  at `stepHeight`), slide across the step's motion plus the one skin the
  wall held us off, settle onto support. If that did not rise half a
  block (a wall leaning back keeps its lip ahead of its base), retry
  reaching one character radius across. Keep the step if it progressed
  further; then settle down `stepHeight` to follow stairs, or become
  airborne. Settling is a downward probe: once it lands, whatever is left
  of its motion is dropped, so a settle that slid along steep walls never
  turns into a horizontal move.
- Block placement is refused where the voxel would overlap the character
  (`isCapsuleOverlappingVoxel`), so geometry never appears inside a body.
- Steps of any length: a step is split into substeps that each move at
  most one character radius (from a bound on the speed the step can
  reach), and the populated-region check covers one substep. There is no
  timestep clamp.
- Spawn: climb the perpendicular from the root to the surface plane until
  every chunk the body could touch is proven void by the worldgen's own
  bound (`ChunkParams.isProvenClear`), generate the chunks below
  synchronously, and settle onto the ground. The player starts standing,
  in walk mode.
- Vertical quantities that must survive node crossings (eye smoothing,
  the bounce metric) are altitudes, the distance to the one global
  surface plane, never node-local coordinates. `CharacterState.runStep`
  returns the path length it moved.
- Modes (`character/frame.d`, U and B in the client, `world:up` and
  `world:body`): `BodyFrame` is rebuilt every substep from the block at
  half the body's half height below its center. Up modes: `world`
  (gravity and view from the surface plane), `grid` (both along that
  block's face normal nearest world up, so the player stands flat on
  blocks), `camera` (world gravity, block-aligned view). Body modes:
  `fixed` (`CharacterMeters`) and `stretched` (half height, eye and step
  height scale with the block's height, radius with its width, each over
  the mean block edge, so the body is always the same number of blocks).
  When the half height changes, the center moves along up so the feet
  stay put. Grid gravity follows the grid's tilt, so a hill's steepness
  in grid terms differs from its world grade wherever the grid leans.

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
  needs ground below and air above its base, and is placed only if its
  whole box fits inside its chunk: chunks are generated independently,
  so nothing may cross a chunk.
- Towers are an L-system on the honeycomb (`worldgen/tower.d`). A tower
  node has a down face; its up faces are the opposite face (straight)
  and the five faces ringing it, which in H^3 lead to six genuinely
  different "ups". The base grows a straight trunk, the last trunk node
  forks into the straight face plus some ring faces, branches can fork
  again, and a branch that stops grows a spire. Each node's part comes
  from the lower neighbor that claims it (`NodeStructure.fromNode`,
  memoized per node like `NodeState`), so it is order-independent. A
  node only grows into neighbors that are higher and below
  `MAX_TOWER_ALTITUDE`, which also bounds the downward claim search.
- Buildings (`worldgen/building.d`) are whole blocks. For each face a
  node's tower uses, a prism: in the five chunks around that face's
  center-to-node-center edge, the cells whose two other coordinates are
  within `PRISM_WIDTH` of the node center; plus a core of such cells in
  all 20 chunks. Mirrored chunks across a face make a prism continue
  into the neighbor. Walls are building cells with a 6-neighbor outside
  the building (across chunks through the axis permutations). Stories
  are block layers, `STORY_LAYERS` apart along a prism's own axis (the
  core uses each cell's rising axis): layer 0 is floor, windows are 1x1
  holes in layer 2, off chunk seams. Everything is counted in blocks.
- Stairs are breadth-first searches over the node's interior cells using
  each cell's own rising direction, with flat or one-block-up moves. A
  move needs headroom over the cell it leaves: at least
  `CEILING_BLOCKS` (3) blocks, the fixed body's height plus the rise in
  meters, and `BODY_BLOCKS` plus one block per block of rise, so both
  body modes fit. A step's support may not lie in any earlier step's
  headroom along its path, nor an earlier step's support in its own.
  One search runs per up face, in turn, from the door (base) or the
  down-face portal; each sees what earlier routes stamped (a support
  cannot be air, headroom cannot be solid). A found route stamps its
  headroom air, its supports solid, fill under them down to a floor
  layer, and air beside its headroom with a supported tread on each
  side, so a body wider than one block (the fixed body is ~1.2 blocks
  wide where blocks are narrow) fits. Both nodes at a face compute the
  same portal crossing, mirrored, so stairs continue between nodes. The
  shortest route crosses a node's middle-height band near the center,
  where the band is thinnest (see the node level note below). The
  base's first route is kept (`Building.route`) for `enter_stairs` and
  `stair_waypoint`. A move may rise up to `stepHeight` in altitude, so
  where a one-block climb adds grid tilt a step rises 1.5-2 m. A node
  with a structure is never proven clear, full or deferred.
- A node level is ~1.6 absolute (~30 m) tall. Seen from a node's center
  its face directions form an icosahedron: the faces around the down
  face sit 26.6 degrees below horizontal and those around the up face
  26.6 above. The 10 chunks at a node's middle height touch faces from
  both rings, so all three of their grid axes are ~63 degrees from
  vertical near the center: their block faces are steeper than
  walkable, and every vertical route through a node crosses that band.
  Vertical geodesics diverge like cosh(altitude), so from the ground a
  tower's upper levels squeeze
  under the angle of parallelism, and anyone rising beside a tower drifts
  away from it. Seeing a fork means being near the axis at its altitude
  (`enter_structure`, or noclip along the tower).

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
  that mostly skip. With `isSettlingWorldgenEachFrame` everything runs
  unbudgeted, so headless runs stay a pure function of the script.
- `./mined --bench-load --out <report>` measures the client cold load at
  60 Hz pacing (frames until the nearby set, worldgen and meshing finish,
  frame/step/render average and worst) and then 5 s of noclip flight.
  Judge changes by its worst frames.
- Chunk generation is async on worker threads (cores minus two); the main
  thread builds params (including the memoized node structure) and
  integrates results. A chunk whose occupancy
  worldgen proves (`predictOccupancy`) has trivial voxels and is generated
  and populated inline; only unknown chunks go to the workers. Workers
  take an open `runParallel` job before generation requests. Unloaded
  world is impassable to the character (`isRegionPopulated`) - bodies must
  never occupy space that later materializes.
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
- Constants get names and, if dimensional, their unit must be obvious from
  the name, the type, or the `*Meters` config convention. Bare magic
  numbers with unclear units are unacceptable.
- unittest blocks live next to the code they test. Behavior changes get a
  Lua script in `tests/` (or a bench) that checks them headlessly.
