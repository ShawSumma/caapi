# Gameplay plan

Status: Stage 1 is built (1e as a hidden connector style, without the floating hidden kind), text is built, Stage 2 is built (2a to 2h), Stage 3 is built (3a to 3e; saves are native only), and Stages 4 and 5 are built in reduced form (see the concerns). Stage 2's exit, whether a player can explain a dose from the readout, is for people to judge. Post-processing and everything under Later are not built. This file lists the ideas from the design conversation with a verdict, then proposes how to build them on this engine and in what order.

The thread running through it: perception is a parameter you can tune, and one simplified biology runs the player, the plants and the creatures. Gene engineering is what the game is about.

Basis: the engine facts below come from reading the tree, not from building or running anything. Files read: `material.d`, `node.d`, `neighbors.d`, `chunks.d`, `graph.d`, `position.d`, `settings.d`, `eviction.d`, `generation.d`, `climate.d`, `horospheres.d`, `features.d`, `controller.d`, `raycast/*`, `game.d`, `world.d`, `arrivals.d`, `tasks.d`, `meshing.d`, `hud.d`, `config.d`, `script.d`, `main.d` (first half), `renderer.d`, `base.d`, `surface.d`, `uniforms.d`, `frustum.d`, `textures.d`, `voxels.vert`, `voxels.frag`, `fog.frag`, `face.h`, `common.h`, `clip.h`, `depth.h`, `cull.comp`, `web/renderer.d`, `web/glue.js`, `plugins/api/api.d`, `plugins/api/flags.d`, `connector.d`, `horospheres/horospheres.d`, `planet`, `fixtures`, `scripts/climb.d`. Not read: `sweep.d`, `streaming.d`, `traversal.d`, `structure.d`, `blueprint.d`, `building.d`, `store.d`, `structures.d`, `tiles.d`, `drive.d`, `cocoa.d`, `web/main.d`, `web/play.js`, `scripts/tests.d`, and most plugins. Anything said about those is marked as inferred. The tree changes, so recheck a fact before building on it.

Verdicts say what to do with an idea, not that it works: KEEP, CHANGE (keep the goal, use a different mechanism), LATER, DOUBT, CUT. Sources: (you) the user, (Claude) Claude's suggestions in the conversation, (new) added by this plan.

## Decisions

- Text: yes, clear and well rendered. A fairly readable font, typewriter-like but close to sans-serif, from a real font file in the tree. Candidate: IBM Plex Mono (OFL-1.1, github.com/IBM/plex); its look is to be judged once rendered.
- Plants: wherever they make sense, not only in `planet`.
- Worlds: different locations within one world are too similar to each other, and each world is too much like the others. Not yet turned into steps.
- Clones are duplicates of the player.
- Audio: no library. Synthesis is written in the project and goes out through the platform's own audio interface.

## What the engine has and lacks

Has:

- `CharacterConfig` (`common/settings.d`) is a plain struct passed by `ref const` into `CharacterState.runStep` every step (`game.d` `runCharacter`). `Mover` copies it. So a per-step effective config is one function, and several bodies can step against the same graph.
- `NodeClimate.fromParents` steps a random process along the graph: it averages up to three parents and adds `spread * noiseOf(spice ^ salt)` (`climate.d` `stepped`). `loadedClimateAt` samples it at runtime.
- Worldgen is a pure function of the node. `NodeId` is `childId(firstParent, face)`, the same whichever path reaches the node (`graph.d` `addChild`).
- `lookAt` (`horospheres.d`) finds the nearest non-upright ground at a position, and `lookOfGround` returns its kind's `Look`. A kind is registered by a plugin with a form, tag, tile and `Look`.
- `Thrown` is a free-moving object. `Marker` draws a cube at any `Motion`. `RouteWaypoint` points at a route stop. `Hud` draws rects, lines and circles in pixels.
- `scripts/climb.d` `route` walks a structure's route stops and checks the climb, so a route test needs only a structure that calls `stop`.
- `--screenshot` prints the face count of the frame (`main.d` `renderSettled`), which measures meshing cost.
- `CommonUniforms` is built by one D function, `commonUniforms` (`uniforms.d`), used by both renderers. Its frustum planes drive both the native GPU cull (`cull.comp`) and the web CPU cull (`web/renderer.d` `isInFrustum`). Projection, field of view, fog and culling change in one place.
- The web renderer already draws into offscreen textures (`geometryFramebuffer` with color, glow and depth textures; `overlayFramebuffer`) and copies to the canvas with `present.frag` (`glue.js` `web_gl_finish`).

Lacks:

- No inventory: `breakBlock` destroys the block and `placeBlock` draws from the fixed 9-item `MATERIAL_PALETTE`.
- No per-block data: a voxel is one `Material` byte.
- No simulation tick. `Game.step` runs on a variable `dt` capped at `MAX_STEP_SECONDS`. Water is solid: collision tests `!= Material.none`.
- No saves.
- No text. `Hud` has no font, and status goes in the window title (`statusLine`).
- No clones, creatures or audio.
- No use input: the right button only places.

## Engine facts that shape the ideas

1. Hiding a material is not just a discard. The mesher emits a face only where `isShownAgainst` says the neighbor is see-through (`meshing.d` `facingAt`). A hidden block that is simply discarded leaves a hole where the visible block beside it has no face. Hidden materials must count as see-through, like glass, and must suppress faces against their own family, as glass does.
2. Ambient occlusion counts any non-air cell: `ChunkCells.isOccupied` (`meshing.d`) and `isCellOccupied` (`neighbors.d`). Hidden materials would leave dark smudges unless excluded there.
3. Deferred materials would show through a hidden block. A buried chunk stores a dirt stand-in until `isBorderingVoid` finds a neighbor cell that is exactly `Material.none` (`showsVoidAcross`), and only then resolves its real materials. A see-through hidden block beside one would show the stand-in. `showsVoidAcross` must test `isSeeThrough`, not `== none`. Glass has the same exposure today; whether glass ever borders a deferred chunk was not checked.
4. Collision and picking each test `!= Material.none`: `ChunkCellsNear.isSolid` (twice, via `materialNear`) and `hasExposedFace` (`features.d`), `GridWalk.isFilled` plus the empty-chunk shortcut in `castThroughChunk` (`raycast/chunk.d`), and `SolidProbe` (`game.d`). The filter belongs to a body, not the graph.
5. `Frustum.projection` leaves `columns[15] = 0`, so `clip.w = -z`. Setting it to `c` gives `clip.w = -z + c*w`, a pinhole at Klein `z = c` behind the true eye. That is not a new projection: straight lines in the Klein chart are geodesics, so the pinhole sees what a camera moved back by `atanh(c)` sees, with a wider field of view (1b). `onDisk` (the HUD disk) uses the Poincare map, a different projection.
6. There are no global coordinates. Nearby transforms rebase (`followCamera`), so noise keyed on world position pops. Effects key on camera-relative position or screen space.
7. The grid is not Z^3 (CLAUDE.md, `UNITS.md`). A flat 5x5 plate of world voxels is not reliably flat or square. Anything that needs a precise grid is not made of world voxels.
8. Input replay does not close a loop: holonomy turns the frame by enclosed area, and `dt` varies.
9. The loaded region follows one camera. `dropFarChunks` releases dense unedited chunks past `DROP_RADIUS` (`eviction.d`), and an unloaded chunk makes `Features` report `unloaded`, so `runStep` stalls.
10. `loadRadius()` is derived from `viewRadius()`, which includes the world's fog (`world.d`). Perception may shrink the drawn fog only through the fog uniform, never through `viewRadius`, or the world unloads with it.
11. Edited chunks are pinned forever. `isPinnedChunk` holds edited chunks, `isPinned` holds their node, and `isEvictable` requires `liveChildren == 0`, so every ancestor up to the root stays loaded too.
12. Materials are append-only. `Material` is a ubyte enum in the plugin API with 65 values. Appending keeps existing values, so the digest and old edits stay valid; inserting renumbers. Material masks are `MATERIAL_WORDS` (3) words in D, while `voxels.vert`, `common.h` and `glue.js` hardcode the same count, so they agree only up to 96 materials (81 are used). The keyed tables `MATERIAL_COLORS` and `GRAIN` silently default a missed entry to zero.
13. Faces pack material in bits 0-7, texture window in 16-23 and occlusion in 24-31, so 8-15 are free (`meshing.d` `Quad.fromVoxel`). `face.h` reads the material with `0xFFFF`, which must shrink to `0xFF` before bits 8-15 carry anything. `Chunk` uses flag bits 56-62, so bit 63 is free (`node.d`).
14. Any API struct, enum or `Api` table change bumps `ENTRY` (now `mined_plugin_14`). Adding a horosphere kind to a world reshuffles `rolled` and changes that world. Ore and plant passes change the terrain digest, so saved edits need a worldgen version.
15. Native voxel push constants are `LayoutPush`, 24 bytes. The web common uniform buffer is a fixed `COMMON_BUFFER_BYTES = 512` in `glue.js`, and `CommonUniforms` is about 290 bytes. A per-material color table (up to 96 vec4, 1.5 KB) fits in neither and needs its own uniform buffer on both sides.
16. Adjacent nodes differ in depth by one, since a reflection changes word length by exactly one, so one is a parent of the other. That parent need not be the first parent. Inheriting along first parents only can put two neighbors on lineages that split near the root, which is why `NodeClimate` averages all parents.
17. `Flags!E` (`plugins/api/flags.d`) asserts `E.max < 32`, so it cannot hold a set of materials. A material set is words in the layout `glowingMaterials` (`uniforms.d`) uses.

## The ideas

### Perception state

- (Claude) One struct recomputed each step, read by renderer, world, physics, clones and audio. KEEP. In `common/`, so headless tests can use it.
- (Claude) Drugs raise and lower channels instead of switching effects, so combinations compose. KEEP.
- (Claude) Audio reads it. LATER.

### Pharmacology

- (Claude) Fictional receptors and molecules with serious structure. KEEP. Game data is invented: no real compound names, doses or routes.
- (Claude) Receptor families mapped straight to channels. CHANGE. Families push through the signaling layers below instead.
- (Claude) Subtypes and selectivity. KEEP, from pocket shapes.
- (Claude) Ligand profile of affinity, efficacy, kinetics, route, metabolites. CHANGE. Derived from the molecule's structure, never authored per compound. Routes: inhaled, injected, ingested (ingested passes the liver enzymes first).
- (Claude) Occupancy by mass action gives ceilings and competition, and so antidotes. KEEP.
- (Claude) One target hit by a short-lived creature peptide and a fast plant molecule. KEEP, from kinetics plus route.
- (Claude) Anti-targets as the cost of dirty compounds. KEEP.
- (Claude) Tolerance per receptor and cross-tolerance. KEEP, as the adaptation variable below.
- (Claude) Repeated states unlock traits. CUT as an unlock list; the adaptation variable moves the setpoint instead, and genes stay the route to permanent change.
- (you, Claude) Permanent upgrades through gene engineering, receptor engineering as the endgame. KEEP.

### One biology

- (Claude) Genomes of short genes for receptor subunits, enzymes, transporters, photoreceptors; one model for player, plants and creatures. KEEP. Transporters later.
- (Claude) Splice a plant enzyme into yourself; put a receptor gene in a plant as a living assay; make your own compounds. KEEP, late.
- (you) Things generally voxel-sized. KEEP, with fact 7 as the limit. Plants, ores, machines and sessile creatures are one block each. Molecules and genes are drawn as small hologram grids, not built from world blocks.
- (Claude) Molecules as tiny voxel structures, pockets as voxel shapes, binding as complementarity. KEEP. A 3x3x3 grid of 8 fragment kinds plus empty is 27 cells at 4 bits, 108 bits, so a `ulong[2]` like `NodeId`.
- (new) Efficacy from the same shape rule: trigger cells per transducer and a brake cell. Touching triggers is agonism, filling the pocket while touching none is antagonism, touching the brake is inverse agonism, touching a few triggers is partial agonism.
- (Claude) Genes as strips of colored cells to read, cut, splice. KEEP. One letter changes one pocket cell.

### Receptors

- (you) Receptors push, with heteromers and metabolism; simplified, serious, consistent.
- (Claude) Subunits assemble from an expression pool into homomers and heteromers by mass action. KEEP.
- (new) Each subunit carries a half-pocket and a receptor joins two halves. Homomer pockets are then symmetric under inversion through the center and heteromers are not.
- (Claude) Messengers that inhibit and excite each other and push channels through thresholds. KEEP. Needs a readout from the start and a fixed tick.
- (Claude) One adaptation variable per channel gives tolerance, cross-tolerance and rebound. KEEP.
- (Claude) 6 families, 4 transducers, 5 messengers, 12 enzymes. CHANGE. Start at 3, 2, 3 and 4.

### Metabolism

- (Claude) One set of operations everywhere: cleave, attach, oxidize, cyclize, conjugate. KEEP. Cap chain depth and active species per body (16).
- (Claude) Prodrugs, active metabolites, enzyme-blocking interactions. KEEP, from the same operations.
- (Claude) Editing your own enzymes changes which operations your body applies to every compound. KEEP.

### Resources

- (you, Claude) Ores as one source among many. KEEP. A pass keyed to `rockBand`, rolled per chunk first so uniform chunks stay uniform, skipped in `MaterialPass.deferring`.
- (you, Claude) Air from biomes, collected by condensers. KEEP. A pure function of the nearest ground's kind and the climate at a point, found the way `lookAt` finds a `Look`.
- (Claude) Fog color derived from the gas mix. KEEP. An API change; every authored fog color becomes a mix.
- (Claude) Gases only perceivable in altered states. KEEP, through the color rotation.
- (Claude) Soil and water leaching from the strata. LATER.
- (Claude) Creature peptides. LATER. Sessile one-block organisms first.

### Plants and breeding

- (you, Claude) Plants with alkaloids and a breeding system like the player's. KEEP.
- (Claude) Genome of a few biosynthesis enzymes plus traits; product from the enzyme chain. KEEP.
- (Claude) Environment shifts expression, from the climate fields. KEEP.
- (Claude) Crossing and mutation, with mutagenic gases and minerals. KEEP.
- (new) Wild genomes vary along the node graph. Per fact 16, each gene inherits from one of the node's parents chosen by hash, not always the first parent.
- (new) Wild plants need no stored data: genome is a pure function of node and cell.
- (new) Growth is lazy: store planted time and derive the stage.

### Perception-gated content

- (Claude) Hidden materials with a channel threshold and a bitmask. CHANGE per facts 1 to 4: hidden faces collapse in the vertex shader next to the glow mask, with a small family of hidden materials.
- (Claude) Hidden layers and connectors, such as a stair you can only climb while dosed. KEEP, as a `HorosphereForm.bare` kind whose tile paints only hidden materials, plus a hidden connector style.
- (new) Gravity stays unfiltered. `gravityAt` blends grounds by geometry, not material, so a hidden layer still pulls.
- (Claude) Different families reveal different worlds. KEEP. One hidden family per reveal channel.
- (Claude) Hidden glyphs, beings, geometry-made architecture. KEEP. Beings could be `Thrown` without gravity, drawn with `Marker` only when revealed.

### Five-dimensional color

- (you, Claude) 5D color with a perception rotation: grain-only textures, a per-material 5D color, and a CPU-computed table of `P * R * c` each frame. KEEP.
- (new) Rotations act on the 4D complement of the gray axis (6 planes), so gray stays gray. A color whose chroma exceeds its gray level can still rotate a channel negative, so the table soft-limits chroma per material.
- (Claude) Hidden-by-color: materials equal in three channels that separate when rotated. KEEP.
- (Claude) Plants advertising in hidden channels. KEEP by species; per strain needs face bits 8-15 (fact 13).
- (Claude) Photoreceptor genes raise projection dimension. CHANGE. Each row of P is an opsin gene with a 5D sensitivity. Drugs move R for a while, genes move P for good.
- (new) Enclosed area turns the color rotation as it turns the compass. DOUBT; an experiment.

### Shaders

- (Claude) Offscreen image, post passes, composite. KEEP. Native needs a render-pass restructure; web already renders offscreen.
- (Claude) Laplacian pyramid with band gains. KEEP.
- (Claude) Feedback and trails, no reprojection at first. KEEP.
- (Claude) Vertex warp. CHANGE per fact 6: camera-relative, and zero on the view axis so aiming stays true.
- (Claude) Fog reach. KEEP, for shrinking only (fact 10).
- (Claude) Field of view. KEEP. `HALF_VERTICAL_FOV` becomes a per-frame value.
- (Claude) Projection change. CHANGE per fact 5, to one number.
- (Claude) Hue, saturation, glow into bloom. Hue is replaced by the color rotation. Bloom KEEP, after post.
- (Claude) True FFT. LATER.
- (Claude) Eulerian temporal magnification. DOUBT. Camera motion would swamp it.
- (new) Comfort: bound temporal gain and warp, with a config cap.

### Chemistry

- (Claude) Bench with scaffold and fragments on a grid, in the world. CHANGE per fact 7: the bench is one block and its grid is drawn, not built from world voxels.
- (Claude) Hold a molecule to a pocket and see clashes. KEEP.
- (Claude) Assays and structure-activity rules as the research tree. KEEP. Pockets stay hidden and are inferred.
- (Claude) Synthesis as a factory. LATER. Plants supply most molecules first.
- (Claude) Instruments: assay, spectrometer, messenger readout. KEEP. The body readout comes before the systems it shows.
- (new) Instruments are curves, bars and spectra, labeled with text.

### Clones

Clones are duplicates of the player.

- (Claude) Clones automate the factory. LATER.
- (Claude) Limits on how many and how long, set by perception. KEEP.
- (Claude) A clone keeps the perception it was made with. KEEP.

### Creatures

- (Claude) Creatures on the same biology, making peptides. LATER. Sessile first; walkers could reuse `CharacterState`.

### Added by this plan

- (new) Saves, as an edit overlay keyed by chunk id plus anchors stored as face paths.
- (new) Beacons, for finding the way back in hyperbolic space.
- (new) Items and a use key.
- (new) Per-block records, kept in the same overlay as edits.

## How to build it

Everything here is an untested proposal. Stage 1 rests on reading the code it changes. Later stages get less detail the further out they are, and each gets worked out against the tree when it comes up.

### Rules for every stage

- Web parity. Every renderer change lands in both renderers in the same step. Shared: `commonUniforms`, the shaders (a new header goes in `SHADER_HEADERS`), meshing and the HUD. Separate: Vulkan setup (`surface.d`, `renderer.d`, `base.d`) against `web/renderer.d` and `glue.js` (uniform names in `PROGRAM_UNIFORMS`, buffer sizes, key codes in `KEY_CODES`). Each new key binding also needs X11, Cocoa, `DriveKey` and web codes.
- ABI. Materials, `Tag`, `Style` and other enums are append-only. Every API change bumps `ENTRY`, once per step that changes it.
- Determinism. Steps that do not mean to change worldgen run `world-digest`, `check-repaint` and `check-forget` before and after. Steps that do say so and bump `WORLDGEN_VERSION`.
- Units. New dimensional values use `base/units.d` kinds. Concentrations, occupancy and channel levels are `Ratio`.
- Tests. Biology is unit tested in `source/unit/` against derived predictions. Gameplay is behavior tested in `scripts/tests.d`. Visuals are checked by `--screenshot` views and read back.
- Fixed tick. Biology and anything simulated advance in whole steps of a constant `Time` from an accumulator in `Game.step`, never by the frame's `dt`.

### Stage 1: feel test

Goal: a stair that exists only in one perception state, colors that rotate, a camera that bends. A debug key cycles fixed presets.

1a. `Perception`. New `common/perception.d`:

- `enum Channel : ubyte`: walk speed, gravity, jump height, field of view, fog, eye offset, warp, the six color rotation angles, one reveal channel per hidden family. Each channel is added in the step that first reads it.
- `struct Perception { Ratio[CHANNEL_COUNT] level; }`. In 1d it gains `MaterialSet shown` and `MaterialSet solid`; `MaterialSet` is words in the `glowingMaterials` layout (fact 17), with the word count moved from `uniforms.d` to `common/material.d`.
- `CharacterConfig effectiveFor(ref const CharacterConfig base, ref const Perception)` scales `walkSpeed`, `gravity` and `jumpHeight` only. Body dimensions never change mid-step, or the capsule wakes up inside walls.
- `ViewEffects viewOf(ref const Perception)`: half vertical FOV, fog share, and later eye offset, warp and rotation angles.
- `Game` holds `Perception perception` and steps with `effectiveFor(character, perception)`. `Script` gets `perceive(preset)`, and `ScriptRecorder` records it like `recordMode`.

1b. View effects. Each checked by a `views.d` screenshot.

- Field of view: `commonUniforms` takes `ViewEffects` and uses its FOV instead of `HALF_VERTICAL_FOV`. `main.d` imports `HALF_VERTICAL_FOV`; follow the compiler.
- Fog: `fogReach(world.viewRadius()) * effects.fogShare` in `commonUniforms`, nothing else (fact 10).
- Eye offset: the drawn camera moves back along its view axis, in `commonUniforms` only, so streaming, picking and the body still use the true eye. A Euclidean pinhole at Klein `z = c` (fact 5) draws the same picture: its rays are the straight chart lines through that point, which are the geodesics through it, so it is the camera moved back by `atanh(c)` with the tangent of the field of view scaled by `1 / sqrt(1 - c^2)`. Moving the camera needs no projection, plane, depth or fog change.
- Warp: new header `warp.h` with one function applied to the camera-space point before `projection`, in `voxels.vert`, `highlight.vert` and `marker.vert`. Zero on the view axis. `CommonUniforms` and `common.h` gain its strength and time.

1c. Color table.

- Each material gets a 5D color. Channels 1 to 3 come from `MATERIAL_COLORS`, linearized. Channels 4 and 5 come from a new keyed table defaulting to the material's gray level.
- Per frame on the CPU: `R` is six Givens rotations in the complement of the gray axis; `P` is 3x5 with non-negative rows summing to 1. `P = [I3 | 0]` and `R = I` reproduce today's colors.
- Upload: a new uniform buffer of `vec4[MATERIAL_COUNT]` on both sides (fact 15). `voxels.vert` reads it and passes a flat tint.
- Textures stay as they are. A texel is close to `linear(base) * g(grain)`, so a per-material, per-channel tint `turned / base` paints the same grain on the turned color, and the picture is unchanged at zero turn.
- Fog color goes through the same `P * R`.

1d. Hidden materials. Lands as one change.

- Append hidden materials to `Material`, bump `ENTRY`, add `MATERIAL_COLORS`, `GRAIN` and 5D entries. Past 96 materials, derive the shader and `glue.js` word counts from `GLOW_WORDS` first (fact 12).
- `material.d`: `isSeeThrough` includes hidden materials, `isShownAgainst` suppresses faces against the same family, `hiddenFamilyOf(Material)` returns a `Maybe`.
- Occlusion (fact 2), deferred materials (fact 3) and collision and picking (fact 4) as listed there. `CharacterConfig` gains the body's `solid` set so the existing `ref const` parameter carries it. `castCenterRay` uses the player's set, so you can neither aim at nor break what you cannot see.
- `placeBlock` refuses a cell holding any material, hidden or not.
- `Thrown` takes the thrower's set at throw time.
- Shader: the voxel push constants gain a hidden mask next to `glowing`; `voxels.vert` collapses hidden faces. Web: the same array through `web_gl_voxels` and `PROGRAM_UNIFORMS`.
- A family becoming shown joins `solid` only once the capsule overlaps none of its cells (`CellOverlap`). Shown uses hysteresis so it does not flicker at the threshold.

1e. Hidden world.

- Connector: append `Style.hidden`, `Tag.hidden` and a palette of hidden materials, with zero odds in every existing `PAIRS` row so existing worlds roll the same styles.
- A fixtures world, `hiddenstair`: a routed hidden connector up to a `HorosphereForm.bare` kind whose tile paints only hidden materials. In `fixtures`, so no other world's `rolled` changes.
- Behavior tests: `hidden/climb` (revealed, `climb.route` succeeds), `hidden/unrevealed` (the same start gains no altitude), `hidden/reveal-inside` (revealing while inside a hidden cell does not embed the body).
- Views of `hiddenstair` shown and not shown. The `--screenshot` face counts measure what hidden materials cost.

Gate: is walking up a stair that exists in one state, with the colors rotating and the eye moved back, good? If not, rethink before biology. If it feels thin, try post-processing first.

### Post-processing

Depends only on 1b.

- Web: post passes go between the fog pass and `present` in `web_gl_finish`. Crosshair and HUD move after post.
- Native: both subpasses write straight into the swapchain image today (`base.d` `createRenderPass`), with depth and glow `STORE_OP_DONT_CARE`. Geometry and fog would render into a sampled offscreen image, post passes run on fullscreen triangles, and a composite pass draws to the swapchain with the crosshair and HUD.
- Effects: trails, pyramid with band gains, bloom from glow. Each driven by `ViewEffects` and capped by a comfort setting.

### Text

Needed by the body readout and everything after it. A font file in the tree, chosen with the user. Glyphs rasterized from its outlines into an atlas, drawn by `Hud` as textured quads in both renderers.

### Stage 2: biology core

Pure `common/` code in `source/common/biology/`, one unit test module per file. Steps 2a to 2g share no files with Stage 1, so they need not wait for the gate. First set: 3 families, 2 transducers, 3 messengers, 4 enzymes.

2a. Molecule. `Fragment : ubyte`: empty plus 8 kinds from 3 binary properties. `Molecule` packs 27 cells at 4 bits in `ulong[2]`, hashed like `NodeId`. The 24 rotations of the cube computed at compile time.

2b. Pocket and binding. A pocket is 27 cells: wall, open (wants a property pattern), trigger for a transducer, or brake. A pose scores matched properties minus clashes; the best of 24 poses gives affinity and an efficacy vector. Cached by both hashes. A half-pocket is 13 cells (an outer layer plus 4 of the middle ring) and the center cell is shared.

2c. Kinetics. Per body: gut and blood, at most 16 species. Elimination rate derived from properties. First-order, integrated exactly per fixed tick.

2d. Occupancy. `occupancy_i = (C_i / K_i) / (1 + sum_j C_j / K_j)`. Unit tests against what the formula predicts: half occupancy at `C = K`; a competitor at B shifts the half-occupancy concentration by `1 + B / K_B`; concentration halves in `ln 2 / rate`.

2e. Signaling. Transducer activation from occupancy times efficacy. Messengers follow `dm/dt = rate * (W a + U sigma(m) - m)`. Channel raw values are `V m`; each channel has an adaptation that relaxes to the raw value slowly, and the output is raw minus adaptation. A unit test checks the rebound after a long dose ends.

2f. Metabolism. Enzymes are genes encoding one operation and a 2x2x2 recognition motif. Cleave empties a cell, attach fills an empty neighbor, oxidize flips the polar bit, conjugate marks for fast clearance.

2g. Genome. One `Genome` type: a short list of genes, each a kind and a string of letters, with expression levels.

2h. Body readout. Needs text and the fixed tick.
  - The fixed tick lands here: an accumulator in `Game.step`; the character and `Thrown` stay on `dt`.
  - `Hud` panels: bars for channels, a trace per messenger, occupancy per receptor, labeled.
  - A headless tool in `worldcheck.d` prints dose-response and time-course tables.
  - The preset key becomes a dose key for a few fixed molecules, and channels map to `Perception`.

Exit: someone dosed with two molecules can explain from the readout what happened. Judged by people.

### Stage 3: game substrate

3a. Edit overlay (fact 11). Edits live in a store keyed by chunk id, applied when a chunk is generated or its materials resolve. Edited chunks then drop and regenerate like any other, and the pinning in `isPinnedChunk`, `dropFarChunks` and `unloadNode` goes. Verify: edit, walk past eviction, walk back; the edit is there and memory returns to baseline. Touches no file Stages 1 and 2 touch, so it can move earlier.

3b. Items and use. An inventory in `Game`; breaking adds, placing consumes. A use key. `MATERIAL_PALETTE` and its script and recorder calls move to the inventory.

3c. Block records in the overlay: kind, time, small payload.

3d. Saves: the overlay, anchors as face paths from the root plus a local `Motion`, inventory, biology state, `ENTRY` and `WORLDGEN_VERSION`. A mismatched save refuses to load with a clear message.

3e. Beacons: a block record plus an anchor, and a HUD needle toward it. Whether `pathBetween` (`structure.d`, not read) already finds the path is to be checked.

### Stage 4: sources

Air from ground kind and climate; wild genomes on `NodeState` inherited per fact 16; wild plants where they make sense; ores; collector and soil machines with lazy time; spectrometer and assay instruments. Plants and ores change the digest on purpose.

### Stage 5: genes

Gene strips at a bench, breeding with mutation from gases and minerals, lazy growth refreshed by a budgeted sweep, climate shifting expression, and editing the player's own receptors, enzymes and opsins.

### Later

Designing molecules at the bench, clones, creatures, more hidden worlds, splicing between species, per-strain colors, audio, FFT. Not worked out.

## Order

```
1a perception -> 1b view effects -> 1c color -> 1d hidden materials -> 1e hidden world -> gate
1b -> post-processing (any time after 1b)
2a..2g biology (any time)
gate + 2a..2g + text -> 2h readout -> 3a overlay -> 3b items -> 3c records -> 3d saves -> 3e beacons
2 + 3c -> 4 sources -> 5 genes -> later
```

- Biology before substrate: the substrate is ordinary engineering, and the biology is what is unknown.
- Overlay before saves: saves serialize the overlay, and the overlay fixes the pinning on its own.
- Genes before the bench: plants make molecules through enzyme chains, so breeding reaches chemistry without a synthesis system.

## Concerns from building

Noted while building, to go through phase by phase.

- Preset values (`client/game.d` `PRESETS`) and the signaling weights (`DRIVE`, `CROSSTALK`, `READOUT`) are first guesses, not tuned.
- Hidden blocks are always meshed, so they always cost faces; both `hiddenstair` renders report the same face count.
- 1e is reduced: a hidden connector style in `hiddenstair`, without the floating hidden pentagon floors of a `bare` hidden kind.
- The `hiddenstair` and `terrainbehind` views use poor vantages; good ones need someone to play the worlds.
- Text has only been looked at in the 640x360 screenshot, and not on the web page.
- `check-forget` on lattice was not run after the connector change; `check-repaint` on city was (0 differing).
- More than 96 materials needs the hardcoded counts in `voxels.vert`, `common.h` and `glue.js` raised.
- The eye offset moves only the drawn camera, so with a large offset the camera can sit inside terrain behind the body and see the backs of faces.
- Biology tuning: affinity is `exp((REFERENCE_SCORE - score) * BINDING_SCALE)` with a reference of 30; a perfect complement of a starter pocket half-saturates near 0.01 and no other starter receptor binds it. The fixed doses are complements of the starter homomers, so they are cleanly selective, which makes the first experience simpler than the system is.
- The lift messenger is driven by both transducers and by the mist messenger, so any agonist also raises lift (gravity down, jump up). That coupling is a weight choice in `signaling.d`.
- `biology-tables` (headless) prints dose-response and time-course tables; use it for tuning.
- The messenger trace fills over live frames, so a screenshot shows it empty.
- The fixed tick is inside `Organism.advance` (`BIOLOGY_TICK`), not a general accumulator in `Game.step`; the character and `Thrown` still use `dt`.
- Opsin and trait genes are not built; `GeneKind` gains them when something reads them (5e).
- Edits are sparse per-cell lists with a linear search per edit; the plan's switch to a dense copy past a threshold is not built. The edit store is never pruned, which is what saves are for.
- `live/edit-kept` checks the stored cell after eviction, not by aiming: flying out and back with the camera re-levelling every frame does not retrace the path, so the same ray misses.
- The plan's "memory returned to baseline" check after eviction is not built.
- Nodes near the root are ancestors of everything live, so they are never evicted; edits there were never at risk.
- Starting inventory is the old palette with 999 of each, plus beacons in slot 9; there is no source of new blocks other than breaking.
- Saves are native only (`--save <file>`, loaded at start and written on quit); the web page has no storage import. Switching worlds with `[`/`]` mid-session drops the previous world's edits, and a save written after switching belongs to the last world.
- Beacons hold a reference on their node, which keeps the node and all its ancestors loaded for the session.
- `WORLDGEN_VERSION` lives in `client/save.d`; it is 3 after ores and plants.
- 4a is reduced: air is derived from the node's climate (`common/biology/air.d`: mire, frost, ash), not authored per ground kind through `RisingKind`, and fog color does not follow the air yet.
- 4b stores four 64-bit gene seeds per node (`WildGenes` in `NodeState`) instead of a `Genome`; a plant's product is expanded from them on demand. `wild-census` (headless) shows drift rising to all four genes by depth about 20; its first-2000-per-depth sample is biased, so depths 6 to 12 dip.
- 4c plants are one block per form (fern, flower, thornbush, moss), chosen by climate, only on terrain-filled grounds. They are opaque full blocks.
- Random wild products mostly bind none of the starter receptors, so most plants are inert to the player; finding binders is rare. Whether that is the intended difficulty is open.
- 4d ores are blobs painted by a per-chunk roll; the effect on `dense_chunks` in `--bench-load` was not measured.
- 4e is the collector only; the soil machine is not built. 4f is the plant scan (spectrum bars and an assay plot per receptor) on the use key, plus eating on F.
- Stage 5 is a loop of seeds: breaking a plant keeps a seed of its genes (newest 32); placing a plant uses the newest seed of that form and records it with its planting time (`RecordKind.planted`); the product exists once `GROWN_SECONDS` has passed, so growth is derived, never ticked. At a bench, E crosses the two newest seeds (ash in the air and a spent sulfur raise mutation) and F splices the newest seed's first enzyme gene into the player's genome. Eating scales the dose by how well the plant's form suits the climate (5d).
- 5e covers enzymes only: receptor subunits and opsins cannot be edited, because opsins (rows of `P`) do not exist yet.
- The bench panel grows with every spliced gene and runs into the compass; the HUD has no layout beyond fixed corners.
- Seeds are a list on `Game`, not inventory items; the hotbar shows plant counts but not which seeds they carry.
- The terrain digest changed on purpose with ores and plants (materials `40ba150db85a2b3fb6046cccf5436ddd`, occupancy `0a70cf01f29d633ca04c5df967d33354`).

## Risks

- Legibility. Four layers between a dose and what you see can read as random. Every layer gets a readout, and tuning is judged by whether a player can explain what happened.
- Hidden-material face count. Hidden materials always emit faces. Measure with screenshot face counts once the hidden world exists.
- Comfort. Warp, trails and eye offset can make people ill. Caps exist from the first step that adds each.
- Web budget. One thread; post passes and the color table cost fill rate there. Measure with `drive check bench`.
