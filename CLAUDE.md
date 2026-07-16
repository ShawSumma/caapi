# mined — hyperbolic voxel engine

D + Vulkan voxel game in hyperbolic space (H³). Client in `source/client`,
shared simulation code in `source/common`, entry point `source/main.d`.

## Build, test, run

- Build: `dub build -b release --compiler=ldc2` — always ldc2, always release.
  dmd debug builds are 5–10× slower and useless for judging performance.
- Tests: `dub test --compiler=ldc2`
- Never run git commands; version control is managed by hand.

Headless verification (preferred over launching the window):

- `./mined --replay tests/<name>.actions --headless` — replays recorded input
  through the full simulation with no GPU work. Deterministic. The
  `session: traveled=` line at exit is the traversal odometer; the per-second
  status line carries `vacc=` (worst vertical camera acceleration — the
  bounce metric) and `traveled=`.
- `./mined --record <file>` records live play to the same format.
- `./mined --flat` — debug worldgen: fills exactly below the base surface
  plane. The base plane is lattice-aligned, so this is a genuinely flat floor
  with gravity perpendicular to it. Use it to isolate physics from terrain.
- `./mined --dump-world <radius>` — deterministic world hash dump; byte-diff
  two runs to prove worldgen unchanged.
- `./mined --bench-gen | --bench-nearby | --bench-drive` — headless timings.

## Units

Three unit systems coexist. Confusing them costs days.

1. Absolute units: curvature radius = 1. All math in `common/math.d`,
   collision, traversal, and every stored position/distance. A dodecahedral
   node cell is on the order of 1; a voxel is ~0.05.
2. Meters: human-scale config. All `*Raw` config values (speeds, sizes,
   reach) are meters and seconds; `voxelSize` sets meters per voxel.
   `SimConfig.fromRaw` converts to absolute via `metersToAbsolute` exactly
   once. Never convert anywhere else and never hand-estimate the factor —
   compute it or read it from `SimConfig`.
3. tanh-parameterized distance: ray/sweep parameters are `tanh(distance)`.
   Values ≥ 1 mean unbounded. Convert with `atanh`/`tanh` at boundaries only.

Chunks additionally have grid coordinates (0..dimension ints) and dual
coordinates (projective, `ChunkLayout.dualToGridFactor` maps between them).

## Hyperbolic space — what actually bites

- Volume grows like e^(2r). The nearby-node set at render radius 4.5 is
  ~33k nodes. Radius padding is never cheap (+0.05 radius ≈ +10% nodes,
  +0.25 ≈ +65%). Per-frame work must scale with what is visible or swept,
  never with the metric ball.
- Moving distance d replaces ~1 − e^(−2d) of the surrounding ball. There is
  no such thing as a small move; steady-state motion means constant churn of
  the working set, so rebuilds must be cheap and budgeted, not avoided.
- Holonomy: parallel transport around any loop rotates the frame. Never
  integrate orientation state and expect it to stay aligned; re-anchor to a
  world reference every frame. "Up" comes from the world
  (`getRelativeUp` → `NodeState.surface`), the camera keeps a yaw-only
  up-aligned quaternion plus a scalar pitch, which cannot accumulate roll.
- Down is not flat. Gravity follows equidistant surfaces of the surface
  plane; voxel faces are geodesic planes; the two agree nowhere except on
  the base plane itself. Normal worldgen therefore produces terrain that is
  corrugated 1-block staircases relative to gravity, and anything touching
  ground contact, stepping, or slopes must expect that. `--flat` is the
  clean-room case.
- Tangent vectors live at a point. A normal computed at one point (an offset
  collider section, a contact) is wrong at another point until parallel
  transported — a few degrees of error at body scale, which is fatal for
  constraint solvers whose escape margins are ~1e-7.
- Chunk seams: adjacent chunks are different frames; nothing is coplanar
  across a seam by representation, only by geometry. Every chunk carries
  margin cells mirroring its neighbors' boundary voxels (`common/margins.d`)
  — any cross-chunk voxel question must read margins, never assume.
- Collision and rendering both operate on the surface mesh: exposed faces
  only (solid cell, empty neighbor including margins), their bounded edges
  and corners. Internal lattice planes, infinite grid lines, and backfaces
  must never generate contacts; needing a special case to suppress one is
  the sign of colliding against the wrong geometry.
- The graph is append-only: node slots and node pointers are stable
  (slabbed storage). Node ids derive from the parent path, so worldgen is
  deterministic; `--dump-world` is the proof.

## Performance rules

- Measure before changing; the stage log prints per-second avg/max for each
  frame phase plus GC pauses. Frame smoothness lives in the max column.
- No hash lookups in per-frame loops — use slots. No growing flat arrays for
  bulk data — the graph slab exists because one realloc memcpy of 60MB is a
  visible hitch. Budget any work that can arrive in bursts (worldgen scan
  cursor, request budget, node-creation budget per rebuild).
- Chunk generation is async on worker threads; the render thread only builds
  params and integrates results. Unloaded world is impassable to the
  character (`regionPopulated`) — bodies must never occupy space that later
  materializes.

## Style

- 4-space indent, braces on the same line, every body braced.
- Explicit types, plain structs and free functions, minimal templates. No
  classes — reference semantics come from a pointer to a struct (see
  `GenQueue`). No `private`; module boundaries are the visibility unit.
- Imports at the top of the module, always — never scoped inside functions
  or unittest blocks. std first, then project modules, each importing a
  named symbol list.
- No module-level mutable state: no `__gshared`, no thread-local globals.
  State lives in structs owned by whoever uses it; state shared with worker
  threads lives in an object handed to them (see `GenQueue`).
- No `static this`. Lookup tables are built by a plain function evaluated
  with CTFE into `immutable` (see `dodeca.d`). CTFE has a known aliasing bug
  with copy-then-mutate of static arrays — build fresh arrays element-wise.
- Subpackage entry points are `package.d`, never `mod_.d` or similar.
- Comments are rare. One short comment for a non-obvious invariant is fine;
  paragraph-length narration, restating what code does, or leaving TEMP
  diagnostics in place is not. Delete instrumentation after it answers its
  question.
- Constants get names and, if dimensional, their unit must be obvious from
  the name, the type, or the `*Raw` config convention. Bare magic numbers
  with unclear units are unacceptable.
- unittest blocks live next to the code they test. Behavior changes get a
  replay or bench that can check them headlessly.
