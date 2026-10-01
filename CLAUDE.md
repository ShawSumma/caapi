# mined - hyperbolic voxel engine

D + Vulkan voxel game in hyperbolic space (H^3). Client in `source/client`,
shared simulation code in `source/common`. Two entry points: `source/main.d`
(windowed client) and `source/headless.d` (scripts, dumps, benches).

## Build, test, run

Always ldc2 through dub, always release: dmd debug builds are 5-10x slower
and useless for judging performance. Never invoke ldc2, cc, cmake or make
directly; dub is the only build command.

Everything is `-betterC` with `-checkaction=halt`: no GC, no Phobos, no
exceptions, no classes, no associative arrays. Memory is `malloc`/`free`
(`common/array.d`, `common/hash_map.d`), threads are pthreads, math is
`core.math` and `core.stdc.math`.

- `dub build -b release --compiler=ldc2 -c headless` -> `./mined-headless`.
  No X11, no Vulkan, no window. This is the build for all verification.
- `dub build -b release --compiler=ldc2` -> `./mined`, the windowed client.
  Never launch it windowed for verification. Rendering is verified
  offscreen: `./mined --screenshot <png> --out <report> <script.lua>`
  runs the script, lets worldgen cover the nearby set and meshing catch
  up, renders one frame with no window or input grab, and writes a PNG
  (read it to look at it). Scenes live in `tests/visual/`.
- Unit tests: `dub test --compiler=ldc2`. The `unittest` configuration uses
  `source/unittests.d` as a betterC runner (`__traits(getUnitTests)` over
  every imported module) and leaves out Lua, whose headers ImportC rejects
  under `-unittest`.
- Behavior tests: `dub run -b release --compiler=ldc2 -c headless -- --out
  <report> tests/<name>.lua...` - exit status 1 on any failed check or
  script error; the report file holds the details.
- Nothing ever writes to stdout or stderr. Headless output goes only to the
  `--out` file; `--dump-world` and `--bench-*` require it. Pass/fail is the
  exit status.
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
  generation is settled every frame, so a run is a pure function of the
  script. Each script's `session:` line and every `FAIL` land in the report,
  in meters.
- `./mined --record <file.lua>` records live play as a replayable Lua
  script (key changes, look deltas, events, and merged runs of identical
  frames).
- `--flat` (or `worldgen("flat")` in a script) - debug worldgen: fills
  exactly below the base surface plane. The base plane is lattice-aligned,
  so this is a genuinely flat floor with gravity perpendicular to it. Use it
  to isolate physics from terrain.
- `--dump-world [radius]` - deterministic world hash dump; byte-diff two
  runs' reports to prove worldgen unchanged. Deferred materials are
  resolved first; each chunk line carries a materials hash and an
  occupancy hash, and the last line digests each column, so a shape-only
  change and a material-only change are told apart.
- `--bench-gen | --bench-nearby | --bench-drive | --bench-mesh [radius]` -
  timings.

## Scripts (Lua 5.5)

Lua is the canonical language for driving and checking behavior. Tests are
authored, not recorded: they say what they do and `check` what must hold.
The script owns time - nothing advances except through the world.

The API adds no globals. A script is a chunk called with the world as its
only argument, and everything hangs off that object:

    local world = ...
    local player = world.player

All state (timestep, held keys, turn rate, frame hook) lives on the world
and its player. Modules take the world as a parameter (`walk.spawn(world)`,
see `tests/lib/walk.lua`). Methods check their receiver, so `world.wait(1)`
is an error - always call with `:`.

- Quantities are meters, seconds, and degrees (like `*Raw` config).
  Positive yaw turns right and positive pitch looks down (mouse sense).
- `world`: `frames(n[, dt])` (dt defaults to the timestep), `wait(s)`,
  `timestep([s])` (default 0.016), `time()`, `worldgen("flat"|"terrain")`
  (before the first frame; it creates a fresh world and respawns),
  `every_frame(fn|nil)` (runs fn after each frame
  to observe; it cannot advance time), `check(cond, msg)` (writes a `FAIL`
  line to the report and counts a failure).
- `player` input: `hold(key...)`, `release(key...)`, `release_all()`,
  `press(s, key...)`, `look(yaw, pitch)` (immediate), `turn_rate([yaw/s,
  pitch/s])` (held look rate; returns the current one), `turn(yaw, pitch,
  s)`. Keys: fwd back left right up (alias jump) down yaw_left yaw_right
  pitch_up pitch_down.
- `player` actions: `mode([walk|fly|noclip])`, `material([1..9])`,
  `break_block()`, `place_block()`.
- `player` observation: `traveled()` (path length), `on_ground()`,
  `altitude()` (body center above the base surface plane; half height plus
  the contact skin, 0.91, standing on flat worldgen), `speed()`, `horizontal_speed()`, `vertical_speed()`
  (signed, up positive), `camera_vertical_acceleration()` (the bounce
  metric).
- `./mined --record` writes the same API: `player:hold`, `player:look`,
  `world:frames(n, dt)`, `player:mode`, and so on.
- Only the base, package, coroutine, math, string, table and utf8 libraries
  are open, and `print`/`warn` are removed: scripts observe through
  `check`, never by printing. `tests/script_api.lua` enforces the global
  set.
- API in `client/script.d`, Lua-side conveniences in `import/prelude.lua`
  (called with the world and the script directory).

## Units

Three unit systems coexist. Confusing them costs days.

1. Absolute units: curvature radius = 1. All math in `common/math.d`,
   collision, traversal, and every stored position/distance. A dodecahedral
   node cell is on the order of 1; a voxel averages ~0.05 but varies
   ~2x in edge length within a chunk (see Chunks below).
2. Meters: human-scale config. All `*Raw` config values (speeds, sizes,
   reach) are meters and seconds; `voxelSize` sets meters per voxel.
   `simConfigFromRaw` converts to absolute via `metersToAbsolute` exactly
   once. Never convert anywhere else and never hand-estimate the factor -
   compute it or read it from `SimConfig`.
3. tanh-parameterized distance: ray/sweep parameters are `tanh(distance)`.
   Values >= 1 mean unbounded. Convert with `atanh`/`tanh` at boundaries only.

Chunks additionally have grid coordinates (0..dimension ints) and dual
coordinates (projective, `ChunkLayout.dualToGridFactor` maps between them).

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
  `voxels.vert`).
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
  The grid is uniform in Klein (projective) coordinates of the vertex's dual
  frame. That keeps voxel faces geodesic planes, but voxels are not
  congruent: edges are ~2x longer and volume ~8x larger at the node-center
  corner than at the vertex corner. `voxelSize` calibrates the mid-line
  average, so never assume a fixed voxel extent in absolute units.
- Chunk adjacency is asymmetric. A low face (coord 0) lies on a node side,
  and its neighbor is the same vertex in the adjacent node, mirrored with
  no axis permutation. A high face (coord `dimension`) is interior to the
  node, and its neighbor is the adjacent vertex's chunk in the same node
  with permuted axes. Always go through `getChunkNeighbor` /
  `neighborAxisPermutation`; never hand-derive either.
- Rendering uses the Klein model. Applying a Euclidean projection to
  homogeneous hyperboloid coordinates keeps geodesics straight, so the
  normal rasterizer works, and all of H^3 fits inside zfar = 1 (the Klein
  ball). Depth is therefore not distance. Recover it with atanh of Klein
  length, as `fog.frag` does; fog closes at the render radius. Depth is
  reversed (near 1) and the projection flips y, so visible faces wind
  clockwise; the swapchain is sRGB and constant colors are converted
  from sRGB.
- Chunk meshes are built on the CPU (`client/meshing.d`) under a per
  frame time budget, nearest first, and kept while the chunk is in the
  nearby set. Faces live in one growing device buffer managed by a range
  allocator; the CPU writes indirect draws and per-chunk transforms.
  Ambient occlusion reads cells beyond the face margins by hopping
  through slot-based chunk neighbors (`common/chunk_neighbors.d`), so a
  change to a chunk bumps the generation of every chunk sharing a face,
  edge or corner with it.
- `Side.init == Side.A`. It isn't a free sentinel, so check for "no side"
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
  (`getRelativeUp` -> `NodeState.surface`), the camera keeps a yaw-only
  up-aligned quaternion plus a scalar pitch, which cannot accumulate roll.
- Down is not flat. Gravity follows equidistant surfaces of the surface
  plane; voxel faces are geodesic planes; the two agree nowhere except on
  the base plane itself. Normal worldgen therefore produces terrain that is
  corrugated 1-block staircases relative to gravity, and anything touching
  ground contact, stepping, or slopes must expect that. `--flat` is the
  clean-room case.
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
  deterministic; `--dump-world` is the proof.

## Character controller

`common/character_controller/controller.d` is a kinematic controller with
one primitive: `slide` sweeps the capsule, clips the remaining displacement
and the velocity against every contact plane so far (single plane, then the
crease of two, else stop), and repeats. Everything else is built from it.

The only tolerance is `contactSkin` (meters): bodies rest one skin from
every surface. Nothing else in collision or response has an epsilon; the
remaining constants are an iteration bound and a parallel-plane
conditioning guard.

- Contacts (`collision_math`, `chunk_collision`): a feature is hit when
  the true radius would touch it within the move, and only while the
  motion approaches it, so tangent motion never produces contacts. Motion
  stops one skin short, and the hit reports its gap; clipping restores the
  skin, which also depenetrates.
- Collider: spheres along the axis, spaced so the chain stays within one
  skin of the true capsule. Faces own their contact point half-open (exact
  partition within a chunk); edges and corners are tested where convex or
  on the chunk boundary, which closes the float crack between chunks'
  frames.
- Support: a contact supports when it is on the lowest sphere's lower half
  and a walkable (`maxGroundSlope`) face meets the feature - a footprint
  rule, so a ledge rim under the foot holds you. A supporting contact while
  descending absorbs the downward motion.
- Velocity: on the ground it approaches the input target at
  `groundAcceleration` with no gravity; in the air gravity and drag apply
  and input only steers toward the target. Clipping never adds speed.
- Walking slides keep the ground plane as a constraint; walkable contacts
  clip along up while walking or descending, others along their normal.
- Ground move: slide; if a wall blocked it, try a step (slide up
  `stepHeight`, slide across the frame's motion plus the one skin the wall
  held us off, settle onto support) and keep it if it progressed further;
  then settle down `stepHeight` to follow stairs, or become airborne.
- Block placement is refused where the voxel would overlap the character
  (`capsuleOverlapsVoxel`), so geometry never appears inside a body.
- Frames of any length: the step is split into substeps that each move at
  most one character radius (from a bound on the speed the frame can
  reach), and the populated-region check covers one substep. There is no
  frame time clamp.
- Spawn: climb the perpendicular from the root to the surface plane until
  every chunk the body could touch is proven void by the worldgen's own
  bound (`chunkProvenClear`), generate the chunks below synchronously,
  and settle onto the ground. The player starts standing, in walk mode.
- Vertical quantities that must survive node crossings (eye smoothing,
  the bounce metric) are altitudes, the distance to the one global
  surface plane, never node-local coordinates. `runCharacterStep` returns
  the path length it moved.

## Worldgen

- A chunk is void when its lowest point is above the terrain ceiling:
  corner elevations plus the terrace bound plus the noise bound (Box-
  Muller over 24-bit uniforms is bounded). Plane distance is 1-Lipschitz
  and a chunk's farthest point is a corner, which is what
  `chunkGridCenterRadius` measures.
- A chunk proven solid is stored uniform when one material is proven
  (below the surface layer, one elevation band, climate range in one
  Voronoi cell), else stored solid with `materialsDeferred`; the exact
  materials are generated, by the same function, when it is edited or a
  void cell appears in its margins. Never assume solid storage means one
  material.

## Performance rules

- Measure before changing, with the `--bench-*` commands; frame smoothness
  lives in the worst frame, not the average.
- No hash lookups in per-frame loops - use slots (the renderer maps chunks
  to GPU slots by graph slot * 20 + vertex). No growing flat arrays for
  bulk data - the graph slab exists because one realloc memcpy of 60MB is a
  visible hitch. Budget any work that can arrive in bursts (worldgen scan
  cursor, request budget, node-creation budget per rebuild).
- Chunk generation is async on worker threads; the render thread only builds
  params and integrates results. Unloaded world is impassable to the
  character (`regionPopulated`) - bodies must never occupy space that later
  materializes.

## Style

- ASCII only, everywhere: code, docs, and scripts.
- No comments at all, anywhere.
- 4-space indent, braces on the same line, every body braced.
- Wrapping: a construct is either entirely on one line or one element per
  line. Never wrap partially, never end a line with an operator, never put
  several list items on one line of a one-per-line list.
- Control flow: no ternaries, no `++`/`--`, no `for` (use `foreach` or
  `while`), no `return;`, and never an early `return` in place of `else` -
  alternatives are `if`/`else` chains and each function has one `return`.
- No `ref` or `out` parameters: return a struct, or pass a pointer to the
  struct being operated on.
- Don't extract a condition into a variable that is used once.
- Explicit types, plain structs and free functions, minimal templates. No
  classes - reference semantics come from a pointer to a struct (see
  `GenQueue`). No `private`; module boundaries are the visibility unit.
  Setup methods are `setup`, never `init`.
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
  `dodeca.d`). CTFE has a known aliasing bug with copy-then-mutate of static
  arrays - build fresh arrays element-wise.
- Never `package.d`; every module is named for what it holds.
- No unused functions, variables, or imports. Delete instrumentation after
  it answers its question.
- Constants get names and, if dimensional, their unit must be obvious from
  the name, the type, or the `*Raw` config convention. Bare magic numbers
  with unclear units are unacceptable.
- unittest blocks live next to the code they test. Behavior changes get a
  Lua script in `tests/` (or a bench) that checks them headlessly.
