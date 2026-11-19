# Abstraction candidates

What this is: things in the engine, the plugin API and the plugins that are done badly today and could become systems, ranked by how much they would buy against what they cost. Every "now" below names code that was read for this document. Where a claim rests on something not read, it says so ("guess").

Read for this: `plugins/api/api.d`, `plugins/api/binding.d`, `plugins/turtle/turtle.d`, `plugins/carve/carve.d`, the plugins `planet`, `caves`, `lattice`, `skies`, `vaults`, `backrooms`, `city`, `library`, `blocks`, `rooms` (`layout.d`, `levels.d`, `rooms.d`), `connector`, `horospheres` (`horospheres.d`, `tree.d`), `palace/palace.d`, `box`, `buildings/building.d`, `buildings/types.d`, `tower`, `crown`, `road`, `trail`, `arbor`, `babel`, `fixtures`, and on the engine side `source/client/tiles.d` and `source/client/structures.d`. Not read: `source/common/worldgen/*` (blueprint, structure, strokes, store, horospheres), the other building styles, `base/forms.d`, `skies`/`vaults`/`caves` content files beyond the settings named below.

Ranking key: value = how many plugins get simpler or can do something new; cost = engine work plus migration; "ABI" = whether `Api`, `Registry`, `Risen` or `RisingKind` change, which raises the number in `ENTRY`; "digest" = whether `world-digest` would move (a change of which hash decides something changes the world even when the code is equivalent).

## 1. One edge-lie query instead of ten copies of "near, far, which end is up"

Now. Almost every edge tile starts by opening a pen at both ends of its edge and comparing heights:

- `planet/plugin.d`: `shelterAlong`, `roadAlong`, `trailAlong`, `uprightAt`, `voids` each compute `start.openPen().height()` and `start.openPen().forward(edge).height()` and then classify against `SHELTER_SLACK` (level, rising by an edge, falling by an edge). `uprightAt` is the full classifier with four outcomes; the other three re-derive parts of it inline, and `isLevel` exists but `shelterAlong`, `roadAlong` and `trailAlong` spell the same test out by hand.
- `caves/caves.d`: `drain` and `well` do the same with `VERTICAL_SLACK` and then pick the top end (`start.forward(1).pitchUp().pitchUp()` when `far > near`); `paintEnd` opens a pen at each end again; `isInOpen` is "below the crust by a margin".
- `lattice/lattice.d`: `hang`, `drift`, `branch`, `colossus` each recompute near, far and `bottom = -abyss * edge`, and `probeOpen` is `isInOpen` again with another margin (`HANG_CLEAR` against `DRAIN_CLEAR`).
- "Which axis of this frame is up": `planet.upOf` (and inlined twice more in `roadAlong` and `paintTrail`), `lattice.riseOf`/`verticalOf`, `carve.upOf`, `caves.downOf`.

Why bad. The same physical question has five slack constants and three ways to orient the answer, and the copies disagree in small ways (planet's level band is `SHELTER_SLACK = 0.5` cells, caves' vertical test is `VERTICAL_SLACK = 0.5`, lattice has none). It is also the hottest code in the planet: `planet.underground` runs per edge per ground, and through `caves.tile`, `voids` (which calls four lattice functions) and the four homestead/road/trail/standing passes it asks for the same two pen heights roughly ten times per edge, each through `apiPenHeight` -> `ensurePen` -> `ensurePlaneIn` on a worker (counted from the code, not measured).

System. An `EdgeLie` value computed once per edge: height of each end in cells, crust depth at each end (`probeCrust`), relief at each end (`probeRelief`), a `Lie` enum (`level`, `rising`, `falling`, `slanted`, `buried`, `aloft`) with one named slack, and frames `upper`, `lower`, `uphill`, `downhill` already turned the right way. Stage one is plugin-side: `lieOf(Turtle edge)` in `turtle.d` (or a new `plugins/ground` helper), and every copy above calls it once and passes it down. Stage two is engine-side: the tile host fills it before calling the edge tile and hands it over in `Risen` (or a new `const(EdgeLie)*` parameter), so it is computed once per edge task, not once per plugin per ground.

Plugins then: write "a hut where the edge rises out of level ground" as `lie.lie == Lie.rising && lie.lowerIsLevel`, with no pen arithmetic; new decorations along edges cost one `if`.

Built since, in part: `Lie` and `lieOf(Turtle edge)` in `turtle.d` give an edge's two end heights from one call, and the caves (`well`, `wellMouth`, `drain`) and the lattice (`shelves`, `asteroids`, `bookVoid`) take a `Lie` and pass it down. On 2026-11-18 the lattice's void passes followed (`hang`, `drift`, `branch`, `colossus` take the `Lie` the planet's edge tile already holds, and `branch` and `colossus` ask `probeOpenEdge` where they spelled it out), so under the planet's crust an edge opens its two pens once; the planet's digest lines, the `deep` one included, and lattice `check-forget` are as they were. Not built: the classifier (`level`, `rising`, ... with one slack), the crust and relief at each end, the turned frames, and stage two.

Cost and risk. Stage one is a few hours and is behavior-preserving only if the slacks are kept per caller, so do it as a pure refactor first and unify the slacks later (that second step moves the digest). Stage two is an ABI change (`Risen` grows or `Tile` gets a parameter). No save change.

## 2. Engine-defined ownership of shared features

Now. Every rule of the form "two tiles could paint this, exactly one must" is hand-rolled, and the rolls do not agree with each other:

- `turtle.ownerAround`: lowest face hash of the four faces around a vertex. Used by `connector.probeOwnsFoot`, `blocks.portAt`, `vaults.portAt`, `layout.portAt`, `layout.quarter` (well door).
- `blocks.probeOwner`: highest face hash of the same four faces (strict `<` against the other three). Used to decide which quarter lays a city block's lots.
- `blocks.tileAt`: the face with the higher hash of the two on an edge paints the street.
- `turtle.settled`: lowest face hash rolling around an edge (used for the cave well shaft); `caves.helixOf` repeats the same minimum by hand plus a neighbor choice.
- `carve.triadAt` / `isOwnedBy`: lowest edge hash of the six ways picks which end of an edge paints a cave scene.
- `lattice.probeDesignated`: own line hash below the crossing line's hash.
- `rooms.quarter`: `Owns` from "my vertex hash is above the neighbor vertex".
- `planet.isDoorCorner`: lowest vertex hash around a face.
- `caves/plugin.d facedVertex` (a test rig) had its own loop for `ownerAround` until this pass.

Why bad. The invariant "exactly one tile paints a shared thing" is the most important rule tiles have and the engine neither states nor checks it; each plugin proves it informally. Two conventions (lowest vs highest of the same four faces) for the same question invite a plugin that mixes them and paints twice or never. Every one of these spends 4 to 6 `probeHash` calls through the host.

System. `api.probeOwns(site, SitePart part) -> bool`: the engine answers whether the face or edge the site is on owns the given shared feature (an edge between two faces, a vertex among four faces, a line). The engine already canonicalizes sites (`canonicalOf`, `SiteLine`, `LineKey` in `tiles.d`), so the answer can come from the canonical frame instead of a hash comparison, which is cheaper and the same everywhere. `ownerAround`, `settled`, `probeOwner`, `isDoorCorner` become calls to it.

Plugins then: never write an ownership roll; a new building plugin cannot get it wrong.

Looked at again on 2026-11-18. Plugin-side the convention already has one home: `turtle.ownerAround` (lowest face hash of the four around a vertex) serves the connector's foot, the city's, vaults' and backrooms' port rules and the wells. The one rule of the same question written the other way is `blocks.probeOwner` (highest of the four, for which quarter lays a city block's lots); moving it onto `ownerAround` would reshuffle every city block's lots, which changes the city's world for a naming cleanup, so it is left and named here. An engine `probeOwns` would add an ABI member for something the shared plugin code already answers the same way everywhere else.

Built (2026-11-18, at the owner's word to build all the ABI items; plugin ABI 37): `api.probeOwns(site, part)`, at the end of `Api`, answered by both hosts from one function (`apiOwns` and `isLeastAround` in `structures.d`). For a vertex it says whether the site's face has the lowest face hash of the four faces turned right around the vertex, and for an edge whether it has the lowest of the four rolled around the edge: exactly the rules of `turtle.ownerAround` and `turtle.settled`, ties going to the asking face as they do there, so moving a caller onto it moves nothing. A face or a line is refused with a message. `Turtle.probeOwns` wraps it, and the connector's foot (`probeOwnsFoot`) asks it in place of comparing `ownerAround`'s hash with its own; the planet's digest lines did not move and the 92 structure tests and `api` pass. `ownerAround` and `settled` stay where a caller needs the owner's frame and not only the answer (the port rules, the wells, the caves' shaft), and `blocks.probeOwner` keeps its highest-hash rule for the city's lots, as said above.

Cost and risk. Small engine function; ABI change (new `Api` member at the end). Migrating a plugin to it changes which face wins, so it moves the digest of that world; keep plugin-specific rolls where the output must not move, migrate the rest.

## 3. Feature tiles: let the engine run a tile once per vertex, per edge line, per foot

Now. The engine has face (ground) tiles, edge tiles and upright segment tiles (`visitTilesAt` in `tiles.d`). Anything that belongs to a vertex is done by a face tile that elects one of its quarters (item 2) and then works in a frame it turned into place:

- The connector at a risen ground's foot: identical boilerplate in `horospheres.wildTile`, `horospheres.backroomsTile`, `skies.foot`, `library.tile`, `vaults.hall` (`if (risen.hasRisen && probeOwnsFoot(face, risen)) connect(Turtle(api, risen.foot), risen, TAG, how)`), and a different variant in `blocks.lotsAt` that connects from `quarters[0]` instead of `risen.foot`, so the city's connector is built in a frame turned by which quarter won while every other ground's is built in the foot's frame (whether this is intended was not checked; it matters because `connector.bridge` derives the tower and its doors from the frame it is given).
- Ports: each port-carrying tile tests `probePort` per corner and leaves a hole (`blocks.portGap`, `vaults.clearingAt`, `layout.quarter`, `caves.well`), and the cave tile separately sinks a stair under it.
- Homesteads, crowns and palaces in `planet` are vertex things found from a vertical edge (`standingAt` turns four quarters around it, `shelterAlong` uses the up edge).
- Cave mouths (`caves.probeSunk`) are vertex things computed from edge tiles at both ends.

Why bad. Every vertex feature costs an election, a frame dance (`rollLeft().pitchDown()`, `pitchUp().rollRight()`), and the rule "the foot connector is painted after the ground's own cells" holds only because each tile calls `connect` last.

System. `api.tileVertices(tile, data, size)` and per-kind foot tiles: the engine visits each ground vertex once (keyed like edges, with its own `TileKey` feature range; `edgeKey` and `segmentKey` in `tiles.d` show the encoding) and hands the tile one canonical upright frame and a small `VertexInfo` (port or not, rising tag, foot or not, root or not, relief). The connector becomes the foot tile of every built ground, run by the engine after that ground's face tiles (tile order is already by hash; a feature range that sorts after faces gives "after"). `RisingKind` carries the bridge instead of every tile function.

Plugins then: a plugin adds "a well at every port of my ground" or "a shrine at one vertex in 30" as one function; the connector cannot be forgotten by a new ground kind; skies, library and vaults lose their `foot` code.

Built plugin-side (2026-11-18): `connector.connectFoot(face, risen, tag, how)` is the one place the foot rule is written (a risen ground, the face that `probeOwnsFoot` elects, the connector built in the foot's frame), and the wild, backrooms, terraces, garden, trellis, library and vault tiles each call it last, as they called the three lines it replaces. The city still connects from `blocks.risenRootAt`, in the frame of the quarter that won, and is left as it is because moving it would move the city's connectors. Then the engine's foot tiles (2026-11-18, plugin ABI 39). A kind is given a foot tile with `api.foot(tag, tile, data, size)` (refused from tiles and placed structures, and refused twice for one ground) or with the new `foot`, `footData` and `footSize` at the end of `RisingKind`; the engine runs it in the face tile's own task, right after the face tile, when that face owns the risen ground's foot vertex (`runFoot` and `isFootOwner` in `tiles.d`, the lowest face hash of the four around the vertex, as `probeOwnsFoot` did). It needs no key range of its own, because it rides on the face task, and that is also what keeps the paint order exactly as it was: the connector is still the last thing the owning face paints. A kind with a foot counts as tiled even with no face tile, so wild ground has no face tile any more (171 fewer tile records within 2.5 units of spawn, the same brushes). The connector's foot tile is `connector.footTile`; the wild, backrooms, terraces, garden, trellis, library and vault grounds register it and their tiles lost their connector call and, for the library and the vaults, the `Connection` data that existed only for it (the skies' `Root.how` too). The planet's digest lines are as they were, `check-repaint` is clean on planet, vaults and library, 169 tests pass. The city keeps building its connector from its lots (`blocks.risenRootAt`, in the frame of the quarter that won), because moving it would move its connectors. Not built: vertex tiles in general ("a shrine at one vertex in 30"), which would need the key range and the planning of their own; ports still have every tile leave the hole itself.

Built since (2026-11-19, plugin ABI 40): vertex tiles in general, without the key range. A world registers one with `api.tileVertices(tile, data, size)` (at the end of `Api`; refused from tiles and placed structures and refused twice). It runs the way a foot tile does: inside each root ground face task, right after the face tile and the foot. It runs once for each of the face's five corners whose face has the lowest face hash of the four around that vertex (`runVertices` in `tiles.d`, `isLeastAround`, the rule `probeOwns` states). So every ground vertex is run exactly once, by the same face whatever order tiles run in, and after that face's own paint. Riding on face tasks needs no new key, planning or blank bits, and a root ground with only a vertex tile still counts as tiled. The tile gets the corner's site, lying in the face, so `pitchUp()` is up, as in a face tile. Law: `structure/vertexmarks`, on a rig in the caves plugin whose vertex tile stands a four cell limestone column at each vertex: bare ground near spawn holds no limestone, the rig 20 cells in 5 whole columns. The view `vertexmarks` shows the columns standing at the ground's vertices. The footprint census counts a vertex tile's brushes against its own vertex with the face slack, and every world holds. The planet's digest lines did not move: no world registers a vertex tile yet. Not done: the per-vertex info the design above lists (port, rising tag, relief); a vertex tile asks for them through `probePort`, `probeRising` and `probeRelief`, as any tile can.

Cost and risk. Medium: a new visit in `visitTilesAt`, a new key range, planning and blank-bit handling like edges have (`blankEdges`). ABI change. Moving the connector into a foot tile changes paint order and may move the digest where a connector and a face tile overlap. Saves: guess that saves do not store tiles (they store `graph.edits`), so no save change; not checked.

## 4. Paint contracts the engine checks instead of conventions

Now. Rules tiles must follow that nothing checks: a face tile paints only within its own quarters; an edge tile paints only along its own edge's line; a pen starts near what it draws; what the down edge paints below a vertex must be the same from either side. What is checked (`TilePainter.paint` in `tiles.d`): painting behind already-built ground (`probeLineAhead`, refused as "paints ground that is already built"), painting past the ground's reach (`TileReach`), unbounded boxes, boxes leaving the column (`boxRefusal` in `structures.d`).

Why bad. A violation shows up as a non-deterministic seam (`check-repaint` and `check-forget` catch some, after the fact, and only on the worlds they are run on) instead of a refusal that names the tile.

System. Each tile kind declares a footprint when it is registered (`Footprint.quarters`, `Footprint.line(halfWidth)`, `Footprint.reach(cells)`), and `TilePainter.paint` checks every brush's canonical `LineKey` against the lines that footprint allows, refusing with a message in the existing style. Pen strokes check the distance of the stroke start from the tile's site against a declared reach. For the down-edge symmetry rule the stronger fix is structural: hand the edge tile a frame whose "down" end is canonical (the engine already canonicalizes lines), so a tile cannot paint asymmetrically by accident.

Plugins then: get told at the first paint which rule they broke; writing a new world stops needing knowledge of these rules.

Looked at on 2026-11-18 and not built: the simplest contract, that an edge tile paints only along its own edge's line, is false by design for the most important edge tile. The caves paint a chamber's scene in the frames of the ways out of the vertex the tile owns (`slabAt(frame, own)`, `along(frame, way)`), which are other lines. So the check needs the footprints declared per tile first, as above, and the caves' footprint is "the six lines out of an owned vertex", not "my line".

Measured on 2026-11-18, while starting the build the owner asked for: a count over the planet's live tiles of how many face steps each brush run's line is rooted from the tile's own node gave 56535 runs in the tile's node, 21393 one step away, 2007 two and 383 farther. It was taken out again, because it cannot tell a broken contract from a lawful line: a line is keyed by a canonical node somewhere along it (`canonicalOf`), so a connector, a gallery or a well running through the tile's own vertex can be rooted several nodes away and still be exactly where the tile ought to paint. The same holds for the design above, which compares `LineKey`s: a footprint has to be stated as "lines through these vertices", and the check needs the line's geometry (does the line pass through one of the tile's vertices, and within what span of levels), not where its key is rooted. That geometric test is the real first step of this item, and it is not built.

Built on 2026-11-19: the geometric test and the census. While `footprintCensus` (in `tiles.d`) is `Census.counting`, the tile host notes the vertex hashes of a task's own vertices: a face tile's five corners, an edge tile's two ends, and, while a foot tile runs, its foot vertex. Every brush a first pass paints is then asked whether a vertex on its own line, at a level within the span of edges it covers (widened by a slack in levels), is one of those (`isThroughCorner`). The counts gather on the main thread after each pass (`footprintTotal`). The census is off unless a test turns it on, so the planet's digest lines did not move. The laws `structure/footprint` and nine siblings, one per world (planet, city, backrooms, library, vaults, caves, lattice, terraces, garden, trellis), run it near where the world starts.

What the census found:
- **Edge tiles keep the contract exactly.** The caves' six lines out of a vertex all pass through it.
- **Foot tiles need the whole rise.** The connector paints the vertical line under its foot down to the lower ground, so a foot's slack is `risen.edges`. Without it, the planet's 23 connector brushes counted as strays.
- **Face tiles need a slack of 8 levels (`CORNER_LINE_LEVELS`).** With none, the city had 439 strays of 7365 brushes and the backrooms 201 of 16936. With 4 levels, the city still had 69 and the backrooms none. With 8 levels both have none. Wells, stairs and the city's own connectors run down and up the lines through a face's corners.
- **The planet:** 13545 brushes, none stray.

So the contract is now stated and tested: every tile paints only on lines through its own vertices, within a known span of levels. The refusal is not built. As a runtime check it costs a vertex hash per level per brush on every brush ever painted, against a census that already holds on every world. That is the trade this document says to measure before paying, and the laws catch a new violation first. The slack of 8 is measured, not derived. A face tile's real reach is its ground's rise and its wells' depth, which the engine could hand the census in place of the constant.

Cost and risk. The check is cheap per brush (one key compare against at most a handful). Existing plugins may violate it in ways the digest never showed; run it behind a debug flag first, fix the plugins, then make it a refusal. ABI change only for the declaration.

## 5. Several edge tiles per world, composed by the engine

Now. A world has exactly one edge tile (`StructureHost.tileEdges` refuses a second). `planet.underground` therefore multiplexes by hand: `caves.tile` unless the ground is the library, then `voids`, then, only on the root ground, shelter, road, trail and standing. Other worlds get caves by `build("underground")`, which registers caves' edge tile and, as a side effect, the world's port odds (`caves.underlie` calls `api.ports`). `api.edgeCeiling` is per world, so the planet's ceiling (`caves.SURFACE_BAND`) is shared by every pass it multiplexes.

System. `tileEdges` appends; each entry has its own data, ceiling, and a ground filter (tags, forms, root only). The engine runs the entries of one edge in registration order within the same task, so they share the blank-edge bit and the task cost.

Plugins then: caves, lattice voids and homesteads each register themselves; a mod adds an edge pass to a world it did not write.

Built, in its plain form (2026-11-18): `TileCalls.edges` is a list and `StructureHost.tileEdges` appends where it refused a second call, so `Api` and the ABI are unchanged. An edge task runs every entry in registration order, each over the root ground and then the filled grounds near the edge, sharing the task, its random stream and its blank-edge bit. With one entry per world, as every world has today, the work is the same: the digests of the planet, caves, lattice and city and lattice `check-forget` came out as before. Law: `structure/twoedges`, on a rig in the caves plugin with two edge tiles that each mark the edges near spawn with their own stone. Not built: a ceiling and a ground filter per entry (`edgeCeiling` is still one for the world, the lowest it may be set for all of its edge tiles), and splitting the planet's multiplexer (`underground`) into separate entries, which would move its random stream and so its digest.

Cost and risk. Small engine change in `TileCalls` and `TileHost.run`/`runOverGrounds`; the ceiling test (`isOverCeiling`) becomes the lowest of the entries' ceilings, with each entry skipped individually above its own. ABI change. No digest change if planet registers its passes in today's order.

## 6. Grounds declared in content, not in world code

Now. `planet.sink` sets crust, thin crust, abyss, under-looks, under-crust looks and ports per ground tag from its tuning, with the tag lists `BUILT_TAGS` and `HOLLOW_TAGS` in code; `caves.darken` and `lattice.deepen` wrap one call each; connector grounds (`connector:materials` `grounds`, with `level`, `bridge`, `dress`, `relief`) are already content; `tileReach` is set in code by three plugins and again in `RisingKind`.

System. A `ground` content kind keyed by tag holding crust, thin crust, abyss, under look/depth/fog, under-crust look/fog, tile reach, port odds and the connector fields. The engine reads it at world start. The `Api` calls `crust`, `thinCrust`, `abyss`, `under`, `underCrust`, `tileReach` go away, or stay only for the world's root ground.

Plugins then: a mod retunes or adds a ground's depth, fog and connector without code; worlds stop hard-coding which tags are built.

Cost and risk. Medium (schema in an engine module, a `build*` pass). ABI change (removed members). No digest change if the numbers are moved as they are.

Built plugin-side (2026-11-18), with no engine or ABI change: which of the default world's grounds are built and which are hollow is content now, not the code lists `BUILT_TAGS` and `HOLLOW_TAGS`. `planet:grounds` lists `planet-ground` nodes, each naming a tag, the darkness under it (`open`, the depth wild ground goes dark at, or `sealed`) and whether it takes a risen ground's crust and bottom (`crust: risen`); `sink` makes the same calls in the same order from them. A mod adds or retunes a ground the default world knows by adding or overriding a node. The planet's digest lines are as before, and the tests of the depths under city, backrooms and vaults (`sealedair`, the cave stacks, `vaultwell`, the voids, `falls/planet`) pass. The depths themselves are still the planet's settings (`risen-crust`, `risen-abyss`, `library-crust`, ...), and the engine-side version, where any world declares its grounds in content and the `Api` calls go, is not built.

## 7. One hash-and-roll vocabulary

Now. Two families: `turtle.mixed`/`roll` (one multiply and shift; `roll` is `mixed % 100 / 100`, so only 100 steps) and `carve.hashed`/`unitOf`/`between` (a finalizer, 2^24 steps). caves and vaults use `unitOf`; planet, lattice, skies, library, blocks, rooms and palace use `roll`. Every odds in the planet, lattice, library and blocks `settings.conf` that goes through `roll` is a multiple of 0.01, so nothing there is wrong today (odds held in `.content` files, such as the lattice weaves, were not checked), but an odds of 0.005 would silently become 0. Weighted choices are written five ways: cumulative `if` chains (`library.kindOf`, `library.wallOf`, `vaults.wallOf`, `skies.terraceOf`, `lattice.decorate`, where `tree-odds: 0.7` and `hut-odds: 0.9` are cumulative thresholds despite their names), integer shares (`connector.styleOf`), and `Weighted` lists from content (`layout.openPlan`, `layout.biomeIn`).

System. One module (`turtle` or a new `plugins/dice`) with `unitAt(hash, salt)`, `chance(hash, salt, odds)` and `pickWeighted(hash, salt, list)`, and tables expressed as `List!(Weighted!T, n)` in content so mods can add a kind of room or wall.

Built in part (2026-11-18): both families live in `turtle.d` now: `mixed` and `roll` (hundredths), and `hashed`, `unitOf` and `between` (2^24 steps), moved unchanged out of `carve.d`, whose noise and lattice hashes and whose users (`caves.d`, the vaults) import them from there; the caves', vaults' and planet's digests did not move. New code should roll with `unitOf`; `roll` stays for the call sites that have it, since moving one moves its world. Not built: `pickWeighted` and the weighted tables in content.

Cost and risk. Small code; any switch from `roll` to a finer roll moves the digest of that world, so migrate world by world with the digest change accepted, or keep `roll` for existing call sites and use the new one for new code. No ABI change.

## 8. Registered building forms, cave themes and room plans

Now. `buildings.types.build` switches over a closed `Form` enum of eight styles; `caves.Theme` has five depth bands with thresholds in code (`FROST_DEPTH` ...) and formation recipes in a `final switch` (`addFormations`); `skies.Form`, `library.Kind`, `rooms.Plan` are the same shape. Tree shapes already show the alternative: `registry.addForm` plus a content `shape` naming it.

System. `registry.addBuilding(name, fn)` with `Traits` naming the builder; cave themes as content (depth band, rules node, a list of formation recipes `hang`/`stand`/`chandelier`/`beam` with counts and sizes), leaving only the four formation primitives in code.

Plugins then: a mod adds a building style or a cave band without touching `buildings` or `caves`.

Cost and risk. Building forms: small, ABI change (`Registry`). Cave themes: medium, and the recipe data must reproduce the current salts exactly or the digest moves.

Since: cave themes are content (2026-11-18): `caves-theme` names its formations (`icicles`, `dripstone`, `chandelier`, `beams`, `columns`, `pillars`, `roots`) and its dome, a `caves-stack` lists themes by depth per ground, and the formation code stays as the primitives; the old themes' digests came out the same. Building forms looked at again and left: `types.build` is an eight-way switch in one module of a source library that every plugin using buildings compiles in, so within the plugins it is already one place to add a style. A registry only pays for a style that comes from another plugin, and then the engine has to carry `Lots`, `Spec` and `Traits`, which are the buildings library's types and not the API's; that is not worth an ABI change until a mod wants it.

## 9. Typed tile data instead of `const(void)*` casts

Now. Every tile and port rule casts its data (`*cast(const(Root)*) data`, `*cast(const(Connection)*) data`); `vaults.connectionOf` handles null data, `horospheres.connectionOf` does not, and both exist.

System. A template in `plugins/api` that registers `void fn(Turtle face, ref const Risen risen, ref const T data)` and passes `T.sizeof` itself, with `T.init` when no data was given.

Cost: small, plugin-side only, no ABI or digest change.

Built in part. `typedTile!(paint, T)` in `plugins/api/api.d` wraps `void paint(const(Api)* api, Site face, ref const Risen risen, ref const T data)` as a `Tile`, unpacking the data with `dataOf!T` (so no data gives `T.init`). The tiles of `skies`, `vaults`, the shared `lawn` in `turtle.d` (used by `babel` and `arbor`), `horospheres` (wild, city, backrooms, tree), `library` (its face tile; `shaft` takes no data), `blocks.tile`, `layout.tile` and their callers in `city`, `backrooms` and `fixtures` take typed data now; none of them casts. The digests of the planet, city, backrooms, library, vaults and garden came out as before, and the full behavior suite passed. Still raw: the edge tiles `caves.tile` and `lattice.edge` and the planet's edge tile, which hands its own data down to both. The caves' tile is raw for a reason: it passes its data on as a pointer that may be null (`Bed.ofGround(cast(const(Root)*) data, risen)`), and null means "no root", as in `entryUnder`, which builds its bed with `Bed.ofSurface(null)`. `dataOf` would turn a missing root into a default `Root`, which is not the same thing, so this one waits for `Bed` to take a `Maybe!Root`.

## 10. Per-task memo of site queries in the tile host

Now. `probeHash`, `probeRelief`, `probeCrust`, `probePort`, `probeRising` and pen heights are recomputed per call; the trail search (`planet.probeMouthBehind`, recursive over `groundWaysOf` with `parentOf` at each step, three levels) asks for the same vertex hashes and pens many times per edge (the count is from the code; not measured).

System. A small cache in `TileHost` keyed by `(SiteFrame, part)` cleared per task. Invisible to plugins; no ABI change. Must be measured per the project's benchmark rules before keeping.

Built in part (2026-11-18): `probeCrust` and `probeRelief` are kept per task in `TileHost` (`SiteMemo`, keyed by the site and the ground the tile runs over, cleared when a task starts), since each builds the climate of several nodes. Planet `bench-gen` parameters, three runs each in the same hour: 1617 to 1665 ms with its lookups off, 1594 to 1599 ms with them. The planet's, caves', library's and city's digests are the same with and without it, lattice `check-forget` and vaults `check-repaint` are clean, and the full suite passes. Not memoized: `probeHash` (cheap), `probePort` (a port rule may read hashes the memo could not key) and pen heights (a pen's frame is not a site).

## 11. Smaller duplications worth folding into the shared kits

- `lattice.Axis`/`along`/`riseOf` against `carve.Way`/`along`/`upOf`: two encodings of the six directions of a vertex.
- `Found { none, some }` was declared in `caves.d`, `lattice.d` and `planet/plugin.d`. Done: it is declared once in `turtle.d` and the three import it (the planet had read the caves' copy as `caves.Found` as well as its own); `rooms.d` has an unrelated struct named `Found` and does not import the enum.
- Angle constants `GOLDEN_ANGLE`, `FULL_TURN`, `QUARTER_TURN`, `HALF_TURN` in `connector.d`, `carve.d`, `horospheres/tree.d`. Done: all three take them from `turtle.d`; `carve.d` was the last with copies of its own.
- Hash sets: `turtle.Hashes`, `palace.FaceHashes`, `caves.Memo`. Looked at and left: `turtle.Hashes` holds 1024 (8 KB, for the caves' searches), the palace's footprint holds 16 beside a parallel array of the faces themselves, so one type would put the large table in every footprint; they differ for a reason.
- The ring of faces around a face: `planet.Clear.keepAround` and `palace.footprintOf` walk the same neighborhood; `layout.neighborhoodOf` walks a different one.
- `buildings.building.middle` (int, `floorDiv(low + high, 2)`) and `turtle.middle` (float, `(low + high + 1) / 2`) share a name and mean different centers.
- `rooms.rollChance(Frame, double odds)` and `Turtle.rollChance(uint percent)` shared a name and differed in units. Done: the turtle's is `rollPercent` now; its six callers in `blocks.d` all pass percents, and the city's and the planet's digests did not move.
- `caves.resolveCaves` filled `Tuning` field by field because `settingsOf` could not bind arrays and three keys did not match their fields. Done: `settingsOf` reads a static array field element by element through `settingAt` (`readSetting` in `binding.d`), the fields are named after their keys (`tubeRadii`, `domeSizes`, `drainStairOdds`), and `resolveCaves` is one call; the planet's, caves' and vaults' digests did not move.
- `buildings.building.middle` and `turtle.middle`: still both named `middle`; five modules of the buildings and rooms import the buildings one, so the rename was left for when those files are being changed anyway.
- Tile randomness: `api.pick` in a tile draws from one `SplitMix` seeded by the tile key, and `runOverGrounds` keeps drawing from the same stream across grounds, so adding a single `pick` early in a tile reshuffles everything after it, including the output over later grounds. Hash-keyed draws (`pickAt(site, part, salt)`) would make edits local.
- Port rules all begin with `ownerAround(Turtle(api, vertex))`; the engine could hand the rule the owner face frame directly (it already grounds the site in `groundedSite`).

## Fixes for files that were busy

These were noted in files another worker was changing. Checked against the tree on 2026-11-18:

- `plugins/planet/plugin.d`: done. `roadAlong` is gone, `paintTrail` and `groundWaysOf` take the up axis from one `skywardOf`, and `shelterAlong`, `trailAlong` and `uprightAt` all call `isLevel`. `Clear.keepAround` (the face and the three faces through each of its corners) and `palace.footprintOf` were not compared cell for cell, so they are left.
- `plugins/connector/connector.d`: done. Core imports come first, `ring` is one function with `EVERY_HEIGHT` as its default, and `probeOwnsFoot` hashes each corner once.
- `plugins/horospheres/horospheres.d`: done. Imports are in module path order and `connectionOf` is gone (typed tiles, item 9). The foot-connect block is now `connector.connectFoot`, called by the wild and backrooms tiles here and by the skies, the library and the vaults; that is item 3's plugin-side half.
- `plugins/palace/palace.d`: `FaceHashes` against `turtle.Hashes` was looked at and left; see item 11.
- `source/client/tiles.d`: done. The imports and the spacing were already right; the three walks of a face path are one `slotAlong` over a `Graph` or a `GraphView`, and `portCallOf` answers `MaybeIndex!PortCall`.
- `source/common/worldgen/strokes.d`: not read.

## Not changed but worth a look outside this list

- `app/scripts/tests.d`: done. The import lines are in module path order, and the selective names of `plugins.pharmacology.panels` and `plugins.pharmacology.player` are in ASCII order.
- `plugins/buildings/building.d strips`: traced, cannot underflow. Its faces come from `walls`: `faceOf` of a footprint that `setbacks` keeps at least `CORE_ROOM` wide, or pieces from `uncovered`, which adds a piece only when `mine.low < theirs.low` or `mine.high > theirs.high`. So every face has `first <= last`, and the loop adds at least one strip.
