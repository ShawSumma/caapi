# Units

The code has no comments, so a number's type has to say what it is. A
bare `float reach` could be a length, the tanh of a length, or a cosh
threshold, and mixing those up is a real class of bugs here. Hyperbolic
space makes it worse than usual: one distance shows up as d, cosh d,
sinh d and tanh d; a grid cell has no fixed size; and a vector only
means something at the point and in the frame where it was taken. This
document defines the unit system, the parts that exist today
(`source/common/units.d`), and how to move the rest of the code onto
it.

## Base units

- **Length**: the absolute unit. 1 is the curvature radius R of the
  space (sectional curvature -1/R^2). Euclidean space has no preferred
  length: scale everything up and nothing changes. Hyperbolic space has
  one, its absolute unit of length. A circle of radius r has
  circumference 2 pi R sinh(r/R), so lengths small and large compared
  with R behave differently. That makes R a property of the geometry,
  not a choice like the meter. There is no meter.
- **Time**: the second.
- **Angle**: the radian. Angles are dimensionless, but they are a kind
  of their own, so a turn rate cannot be confused with a frequency and
  degrees exist only at text boundaries (Lua, recorded scripts).

Everything else is built from these. Integer counts (cells, steps,
nodes, story layers) are not quantities; they stay integers.

## Quantity

```d
struct Quantity(int lengthPower, int timePower, int anglePower) {
    float value;
}
```

`value` is in R^length * s^time * rad^angle. The named kinds:

| type           | length | time | angle | examples                               |
|----------------|--------|------|-------|----------------------------------------|
| `Ratio`        | 0      | 0    | 0     | `footFriction`, `Rate * Time`          |
| `Length`       | 1      | 0    | 0     | `radius`, `jumpHeight`, `altitude`     |
| `Time`         | 0      | 1    | 0     | `dt`, `Game.time`                      |
| `Angle`        | 0      | 0    | 1     | yaw, pitch, `mouseTurnPerCount`        |
| `Rate`         | 0      | -1   | 0     | `walkResponse`                         |
| `Speed`        | 1      | -1   | 0     | `walkSpeed`, `jumpSpeed`               |
| `Acceleration` | 1      | -2   | 0     | `gravity`, `steering`                  |
| `AngularSpeed` | 0      | -1   | 1     | `keyTurnRate`, Lua `turn_rate`         |
| `Area`         | 2      | 0    | 0     | planned: block faces, disk areas       |
| `Volume`       | 3      | 0    | 0     | planned: `NODE_VOLUME`, block volume   |
| `Curvature`    | -2     | 0    | 1     | planned: the space's -1 rad per R^2    |

Kinds are added to `units.d` when the first code uses them, not before.

Operations:

- `+`, `-` and comparisons between the same kind only. `Length + Time`
  does not compile.
- `*` and `/` between kinds add or subtract the exponents:
  `Speed * Time` is a `Length`, `Length / Time` is a `Speed`, and
  `Rate * Time` is a `Ratio`.
- `*` and `/` by a plain `float` scale a quantity without changing its
  kind (`radius * 2.0f`).
- There is no implicit conversion to `float`. `.value` is the only way
  out, and it belongs at a boundary (below).

## Rules

1. A dimensional value is declared with its kind: fields, parameters,
   returns and constants (`enum Time DEFAULT_TIMESTEP = Time(0.016f)`).
2. Names do not repeat what the type says: `gravity: Acceleration`,
   `radius: Length`, `keyTurnRate: AngularSpeed`, not
   `gravityAcceleration` or `turnSpeedRadiansPerSecond`.
3. `.value` appears only at a boundary: a C or Lua API, a vector kernel
   working in chart coordinates (below), or a transcendental function.
4. `exp`, `log` and the like take a `Ratio`: decay over a step is
   `expf(-(rate * dt).value)`, never `expf(-rate.value * dt.value)`.
   Hyperbolic functions take a `Length`, implicitly divided by R (see
   Distance representations).
5. Adding anything other than a plain `Length` to a distance is a type
   error by construction (see below). Radii add in distance space.

## Boundaries

- **Lua**: scripts see plain numbers: lengths in R, times in seconds,
  angles in degrees. `client/script.d` converts at the edge
  (`degreesArgument`, `degreesOf`, `Time(...)`, `Length(...)`).
- **Config files**: plain numbers in the same units; `client/config.d`
  wraps them on load. `mouse_sensitivity` is radians per count.
- **Clock and C APIs**: `clock_gettime` and friends return plain numbers;
  wrap them where they enter.
- **GPU**: shaders get floats. UBO fields say their unit in their name.
- **Chart kernels**: features, sweep and clipping work on `float[3]` in
  the body's Klein chart (see Movement). They take `.value` from the
  typed parameters when the capsule or mover is built, and nowhere else.

## Hyperbolic space

Most types and functions named in this section are not in `units.d`
yet; Status lists what exists and the order to add the rest.

### Distance representations

In the hyperboloid model a distance d shows up through the Minkowski
product and the projective charts, and the code rarely calls acosh:

| representation | value      | where it comes from                        |
|----------------|------------|--------------------------------------------|
| `Length`       | d          | geodesic distance, the only one that adds  |
| `CoshDistance` | cosh d     | `-mip(a, b)` for points a, b               |
| `SinhDistance` | sinh d     | `mip(n, p)`: signed distance to a plane    |
| `TanhDistance` | tanh d     | Klein radius, ray parameters (>= 1: none)  |

Each one is a strictly monotone function of d, so comparisons are valid
without converting: a range test is `CoshDistance.between(a, b) >
threshold`. None of them supports `+`: there is no meaningful
`cosh(a) + cosh(b)`. To pad a radius, add the `Length`s and convert
once:

```d
CoshDistance threshold = CoshDistance.fromLength(reach + CHUNK_BOUNDING_SPHERE_RADIUS);
```

Converting back (`length()`) costs an acosh, asinh or atanh and happens
only when a true distance is needed.

### Lengths enter functions as d / R

Formulas in H^3 are transcendental in d / R: a disk's area is
4 pi R^2 sinh^2(r / 2R) and a ball's volume is pi R^3 (sinh(2r/R) - 2r/R).
With R = 1 the arithmetic is the same, but the kind still matters. The
result of a disk area is an `Area` even though no `Length * Length`
happened. These belong in `units.d` as constructors on the result kind:

```d
Volume ball = Volume.ofBall(RENDER_RADIUS);
Ratio nodes = ball / NODE_VOLUME;
```

This is where "volume grows like e^(2r)" becomes something you can
compute and check, not just a remembered rule.

### Curvature and holonomy

Gauss-Bonnet ties area to rotation: carrying a frame around a loop that
encloses area A turns it by A / R^2 radians. As a quantity, the space's
curvature is -1 radian per R^2, a `Curvature` (length -2, angle 1):

```d
Angle drift = enclosed * CURVATURE;
```

That is why nothing orientation-related may be integrated over time.
The camera and body re-level every frame (see CLAUDE.md).

The same idea covers paths. An equidistant curve at altitude h bends
toward the surface plane by tanh(h) radians per R. A geodesic does not
bend, so a body moving at speed s along one rises away from the
equidistant surface with acceleration s^2 tanh(h). That is the
"falling curves back up" effect `tests/flat/curve.lua` measures. Here
the radian cancels the way it does in arc length (s = r theta), so the
conversion is explicit:

```d
Acceleration lift = speed * speed * equidistantBend(altitude).perRadian();
```

`perRadian()` turns an `Angle`-carrying kind into the same kind without
the angle, and it is the only way to drop one.

### Vectors live at a point, in a frame

A `float[3]` velocity is a `Speed` vector in the body frame. It means
nothing in another frame until it is carried there by an isometry. The
body frame moves with the body by `local * step`, which
parallel-transports it along the geodesic step. The plan is
`Vector!Speed` (and `Vector!Length` for displacements): `dot` gives the
product kind, `magnitude` gives the component kind, and `scaled` takes a
quantity. A struct holds vectors from one frame only. `CharacterState`
is the model: velocity, up and ground normal are all in the body frame.

### Charts are not lengths

- **Klein coordinates** (`LocalFrame.klein`, features, sweep) form a
  chart: a dimensionless point in the unit ball. Near the origin a Klein
  displacement of magnitude k is a geodesic of length atanh(k), which is
  what `movedBy` applies. The controller treats Klein displacements as
  lengths at body scale (within 0.3%). That approximation is a boundary:
  a `Klein` type for chart vectors, with `movedBy` the one conversion to
  `Length`, makes it visible.
- **Grid coordinates** are cells, a chart like the others (see Local
  units for what a block measures).
- **Chunk and dual coordinates** (0..1, projective) are further charts;
  `ChunkLayout` converts between them. Never divide by `dimension`.

### Local units: blocks

A block is a unit, but only locally. Block edges run 0.035..0.077 R and
shapes up to 2:1, and the grid tilts against gravity by different
amounts in different places, so no constant converts blocks to
`Length`. Writing one down (a "mean block of 0.05") is exactly the kind
of hardcoded meter this system exists to prevent. What does exist is
the conversion at a point: the grid Jacobian there (cells per R,
`chart.gridJacobian`) and its inverse (R per cell).

So blocks have two types:

- `Blocks` counts block heights: a dimensionless amount that only means
  something once measured somewhere (`stepHeight = Blocks(1)`).
- `LocalBlock` is one measured block: its `height` along up at a given
  point, as a `Length`. `heightOf(Blocks)` converts a count there.

A block's height along up is the sum of its three edges' vertical
components (inverse Jacobian columns dotted with up). That is the
tallest riser a block can form however the grid is tilted; where a grid
axis points straight up it is just the edge length. `BlockProbe`
(`character/features.d`) measures it at a point by finding the chunk
that contains the point. The controller probes the cell just ahead of
the feet, so "step up one block" means one block of whatever is
actually in front of you:

```d
Length rise = probe.block.heightOf(character.stepHeight) + character.skin;
```

The same pattern fits any quantity that is naturally said in blocks: a
`Blocks` count in the config, a `LocalBlock` measured where it applies,
and `heightOf` (or a future `widthOf` along a direction) at that point.
Counting cells in voxel loops (chunk dimension, grid indices) is counting
and stays integer.

### Positions and instants are affine

A point in H^3 is not a vector. `Position` (node and isometry) can be
moved by an isometry or a geodesic step, and two positions give a
distance, but positions do not add. The same holds for time: an instant
on the clock is not a duration. Instants need `double` (a float holding
monotonic milliseconds drops below 1 ms resolution after about 4.7 hours
of uptime), so they get their own `Instant` kind: `Instant - Instant` is
a `Time`, and `Instant + Time` is an `Instant`. Frame budgets are
`Time`.

## Movement

The controller (`common/character/controller.d`) is the first fully
typed path, and it shows the pattern:

- The `CharacterConfig` parameters are kinds: `walkSpeed: Speed`,
  `walkResponse: Rate`, `steering` and `gravity: Acceleration`,
  `jumpHeight`, `radius`, `height` and `skin: Length`,
  `footFriction: Ratio`, and `stepHeight: Blocks`, a local unit that
  becomes a `Length` only where it is measured.
- `runStep` takes a `Time`; substeps are `Time`; the bound on how far a
  substep may move is `(speed * step / radius).value`, a `Ratio`.
- Ground response integrates exactly: `decay = expf(-(walkResponse *
  dt).value)`, and the lag's displacement is `(1 - decay) /
  walkResponse`, a `Ratio / Rate`, that is a `Time`.
- `jumpSpeed` is `sqrt(2 * gravity * jumpHeight)`: the product is a
  `Quantity!(2, -2, 0)` (speed squared), and the square root is a
  boundary because roots are not in the system. Taking it explicitly is
  the honest version.
- The chart kernels (sweep, clipping) receive `.value` of `radius`,
  `halfHeight` and `skin` once, when the `Capsule` and `Mover` are made.
- Structures (`worldgen/structure.d`, `blueprint.d`) are the other side
  of the rule. They are built of whole blocks, so blueprint brushes,
  line edge ranges and the structure scripts' dimensions (`box.HALF`,
  `box.STORY`, the road's `HALF`) are cell or edge counts, and
  `PAINT_REACH` and `PLACE_SLACK` count node levels; all stay
  integers. Column coordinates are a chart like grid coordinates, and
  `columnPoint` is the one conversion from them to a point. The few true
  distances (`edgeLength`, `SPAWN_DISTANCE`) are `Length`s.

## Status

Typed now:

- `common/units.d`: `Quantity`, `Ratio`, `Length`, `Time`, `Angle`,
  `Rate`, `Speed`, `Acceleration`, `AngularSpeed`, and the local
  `Blocks` and `LocalBlock`.
- `common/settings.d`: `CharacterConfig`.
- `common/character/controller.d`: the step, its parameters,
  `regionReach`, `Stepped.traveled`, `Mover.settle`, the step rise.
- `common/character/features.d`: the reach of `collect` and
  `visitCells`; `BlockProbe`.
- `common/worldgen/structure.d`: the edge length and the spawn distance
  (structures are counted in cells and edges).
- `client/config.d`: `ClientConfig`.
- `client/game.d`: time, traveled distance, altitude, camera vertical
  motion, route waypoints, look input, spawn and placement lifts.
- `client/camera.d`: eye offset, pitch, turns.
- `client/script.d` and `main.d`: timesteps, turn rates, look deltas.
- `client/graphics/frustum.d` and `renderer.d`: the field of view.

Not typed yet, in the order to do them:

1. Distance representations. Add `CoshDistance` and `TanhDistance` to
   `units.d`, first used in `traversal.d` (`coshThreshold`, the
   `nodeThreshold` parameters) and `features.visitCells`. Then
   `streaming.isOutOfRange`, `spawn.collectChunksNear`, `raycast/*`
   (`tanhDistance` parameters, `MAX_TANH_DISTANCE`),
   `LocalWorld.tanhReach`, and `SinhDistance` in `plane.d`.
2. Radii and heights as `Length`: `BOUNDING_SPHERE_RADIUS` and
   `CHUNK_BOUNDING_SPHERE_RADIUS` (`dodeca.d`), `RENDER_RADIUS` and
   `NEARBY_PADDING` (`world.d`), `STRUCTURE_SEARCH_RADIUS` (`game.d`),
   the default radii in `headless.d`, `faceDistance` (`dodeca.d`),
   `Plane.distanceTo` and node altitudes.
3. `Area` and `Volume`: `NODE_VOLUME`, `kleinBoxVolume`, the
   block-volume test in `node.d`, with `Volume.ofBall` for nearby-set
   estimates.
4. Clock: `Instant` (double) in `clock.d`; frame and worldgen budgets as
   `Time`.
5. Vectors: `Vector!Speed` for `CharacterState.velocity`, a `Klein`
   chart type for features and sweep, `movedBy` as the conversion.
6. Grid: `GridJacobian` in `chart.d` (cells per R) and its inverse,
   used by `BlockProbe`, `features.cellRange` and `plane.gridUpAt`;
   `LocalBlock` built from it, and a `widthOf` along a direction once
   something is said in block widths.
7. Terrain elevation. Worldgen elevations are in elevation units, R
   times `TERRAIN_SMOOTHNESS`. Give that unit a name and a conversion
   instead of dividing inline.
8. `Curvature`, `perRadian` and the hyperbolic constructors, when the
   first formula needs them (nearby-set sizing, holonomy checks).

For each step: change the declaration's type and build. The compiler
then lists every use; fix each one at its boundary or push the type
further. Keep the suite (`./mined-headless --out <report> tests`) and
`--world-digest` unchanged across a step. Units change types, never
values.
