# Gameplay plan

Status: ideas stage. Nothing here is built. This lists every idea from the design conversation, says whether I
think it works on this engine, and gives a rough order.

The thread running through it: perception is a parameter you can tune, and one simplified biology runs the
player, the plants and the creatures. The user wants gene engineering to be what the game is about.

Basis: I read the code by hand but did not build or run anything. Another agent is editing the tree, so symbols
are named instead of line numbers. `source/main.d` currently disagrees with `client/game.d` and
`graphics/renderer.d` (for example `game.isGeneratingOnDemand` against `Game.supply`, `renderer.isCapturing`
against `captureMarks`), so it looks mid-change. Not read: `sweep.d`, `streaming.d`, `blueprint.d`, `building.d`,
`scripts/*`, and most plugins. Claims that something is absent come from the files I read and the file names.

Verdicts: WORKS, CHANGE (good idea, the suggested mechanism needs to differ), LATER (good, not early), DOUBT, CUT.
Source: (you) the user's own message, (paste) Claude's suggestions in the conversation, (new) added by this plan.

## What the engine has and lacks

Has, and useful:

- `CharacterConfig` is a plain runtime struct passed by const ref into `CharacterState.runStep`, which takes
  `ref const Graph`. So a per-tick "effective config" for speed, gravity, jump and reach is one function, and
  several bodies can step against the same graph.
- `NodeClimate` is a smooth random process inherited from parents (heat, wetness, strata, ruggedness), and
  `loadedClimateAt` samples it at runtime.
- Worldgen is a pure function of node id, so unedited chunks can be dropped and regenerated. Edited chunks are
  pinned (`isPinnedChunk`) and stay in memory.
- `Look` gives each horosphere kind a fog color, and `lookAt` finds the one at a position. `addKinds`, `Connection`
  and `PAIRS` add layers and connectors from a plugin.
- `Thrown` is a working free-moving object. `Marker` draws a cube at any `Motion`. `RouteWaypoint` points at a site.
  `Hud` draws rects, lines and circles.
- `--screenshot`, `--film` and the world checks can verify visuals and reachability headlessly. `GpuTimer` and
  `--bench-load` (which reports `dense_chunks`) can measure cost.

Lacks, and every idea below needs some of it:

- No inventory: `breakBlock` destroys the block and `placeBlock` draws from a fixed 9-item `MATERIAL_PALETTE`.
- No per-block data: a voxel is one `Material` byte. No machines, no block entities.
- No simulation tick for the world. No health, stamina, damage or death. Water is solid (`isSolid` is `!= none`).
- No saves. Permanent upgrades mean nothing without them.
- No text. `Hud` has no font, and status goes in the window title.
- No clones, creatures, or audio. The paste talks about clones as if they exist; they are not in the tree.
- No "use" input: the right button only places.

## Engine facts that change the ideas

1. Hiding a material is not just a discard. The mesher emits a face only where `isShownAgainst` says the neighbor is
   see-through. If a hidden block is simply discarded in the shader, the visible block beside it has no face there
   and you see a hole. Hidden materials must count as see-through for meshing, like glass, and must suppress faces
   against their own family, as glass does. Ambient occlusion also counts them (`isOccupied`, `isCellOccupied`), which
   would leave dark smudges, so they need to be excluded there too.
2. Filtering collision touches every `!= Material.none`: `ChunkCellsNear.isSolid` (features.d), `GridWalk.isFilled`
   (raycast/chunk.d), `SolidProbe` (game.d), and `showsVoidAcross`. The mask must belong to a body, not to the graph,
   because a clone can be in a different state from the player. Pass it into `Features.collect` and `rayCast`.
3. A radial Klein-to-Poincare blend changes nothing on screen. Klein is (x,y,z)/w and Poincare is (x,y,z)/(1+w),
   both centered on the eye, and the perspective divide x/z cancels the difference. Only depth changes. What does
   work is moving the eye off center: clip.w = -z + c*w. This is `columns[15]` in `Frustum.projection`. It stays
   linear, so faces stay straight and nothing needs tessellating. c = 0 is the true view, and c near 1 is the
   stereographic view the HUD disk already uses (`onDisk`). `Frustum.planes` and the depth reconstruction in
   `fog.frag` both assume c = 0 and need the same term. Derived algebraically, not run.
4. There are no global coordinates. Nearby transforms rebase (`followCamera`, `publish`), so noise keyed on world
   position pops when the frame changes. Effects must key on camera-relative position or be screen-space. The same
   issue applies to reprojection for temporal effects.
5. The grid is not Z^3. Twenty cubes meet at a node center and five meet around each center-to-face-center line, so
   every chunk has three edges where five columns of cells meet instead of four. On top of that, blocks measure
   0.035..0.077 R, shapes run up to 2:1, and the grid tilts against gravity (UNITS.md). A flat 5x5 plate of world
   voxels is not reliably flat or square. Anything that needs a precise grid should not be made of world voxels.
6. Input replay will not close a loop. Walking around a loop rotates the frame by enclosed area (UNITS.md, Curvature
   and holonomy), and the frame step is variable. A recorded input loop drifts every cycle.
7. The loaded region follows one camera. `dropFarChunks` releases dense unedited chunks past `DROP_RADIUS` (3.5 R,
   about 15 seconds of walking), and `Features.visitChunk` then reports unloaded, so `runStep` stalls. A clone
   farther away than that stops. Volume grows like e^(2r), so keeping several regions loaded gets expensive quickly.
8. Seeing farther is expensive. `loadRadius` follows `viewRadius`, capped by `renderRadius`, and the default 8 is
   already the cap. Perception can shrink the view cheaply; growing it costs exponential loading.
9. Materials are limited. `Material` is a ubyte (256 at most) and there are 65 now. `voxels.vert` hardcodes
   `glowing_materials[3]`, while `GLOW_WORDS` is computed in surface.d, so they disagree past 96 materials. `Material`
   lives in the plugin API, so new materials touch `api.d`, and the keyed tables `MATERIAL_COLORS` and `GRAIN` would
   silently default a missed entry to zero. Strains and molecules cannot be materials; they need side data.
10. Faces have 8 spare bits. `face.h` masks the material with 0xFFFF but only 8 bits are used. That is room for a
    per-face tint later, for example a strain color. `Chunk` also has one spare flag bit (bit 63).
11. Any API struct change must bump `ENTRY`. Adding a horosphere kind reshuffles `rolled`, which changes the world
    and `--world-digest` (`digest.txt` holds a digest). Ore and plant passes change it as well. Expected, but it
    means worldgen changes invalidate saved edits, so saves need a version.

## The ideas

### Perception state

- (paste) One struct recomputed each tick, read by renderer, world, physics, clones, audio. WORKS. Do this first.
  Put it in `common/`, so headless tests can use it. `CharacterConfig` shows the pattern for physics.
- (paste) Drugs raise and lower channels instead of switching effects, so combinations compose. WORKS. This is what
  makes the combination space the game.
- (paste) Audio reads it. LATER. There is no audio in the tree, so this needs a dependency decision.

### Pharmacology

- (paste) Fictional receptors and molecules with serious structure. WORKS. Keep game data invented: no real compound
  names, doses or routes. The dynorphin and salvinorin example is a design reference only.
- (paste) Receptor families mapped to channels: reveal matter, distort space and gravity, stretch time and memory,
  dissolve the body, pain and stamina. CHANGE. As a direct map it is the "simple map" the user rejected. Families
  should push through the signaling layers below.
- (paste) Subtypes and selectivity. WORKS. Follows from pocket shapes.
- (paste) Ligand profile of affinity vector, efficacy class, kinetics, route, metabolites. CHANGE. Do not author
  these per compound; derive them from the molecule's structure, as below. Authored numbers would turn it back into a
  lookup table. Keep routes as a small enum: inhaled, injected, ingested (ingested passes the liver enzymes first).
- (paste) Hill occupancy gives ceilings, antidotes, competition, synergy. WORKS. A few lines of math; verify with
  unit tests.
- (paste) One target hit by a short-lived creature peptide and a fast plant molecule. WORKS. Follows from
  kinetics plus route.
- (paste) Anti-targets as the cost of dirty compounds, with clean analogues as the goal. WORKS. It turns binding into
  a multi-objective puzzle. The specific costs (max health, stamina crashes) depend on an open question below.
- (paste) Tolerance per receptor and cross-tolerance. WORKS, but as the adaptation variable below, not its own system.
- (paste) Integration: repeated states unlock traits. CUT as an unlock list. A slow adaptation variable that moves the
  setpoint gives the same feel with no second system, and it keeps genes as the main route to permanence.
- (you, paste) Permanent upgrades through gene engineering, and receptor engineering as the endgame. WORKS. This is
  the point of the game, and the reason saves come early.

### One biology

- (paste) Genomes of short gene sequences, encoding receptor subunits, enzymes, transporters, photoreceptors; same model
  for player, plants, creatures. WORKS. Best idea in the set: one thing to learn. Keep transporters for later.
- (paste) Splice a plant enzyme into yourself; put a receptor gene in a plant as a living assay; eventually make your
  own compounds. WORKS once the model is shared, and costs little beyond the bench. Late content.
- (you) Things generally voxel-sized. WORKS, with fact 5 as the limit. Plants, ores, machines and sessile creatures are
  each one block. No multi-block machines and no entity models. Reading: molecules and genes are shown as small voxel
  grids, not built out of world blocks.
- (paste) Molecules as tiny voxel structures, with pockets as voxel shapes and binding as complementarity. WORKS and it
  is compact. A 3x3x3 grid of 8 fragment kinds plus empty is 108 bits, which fits a `ulong[2]` like `NodeId` and hashes
  the same way. Compute affinity once per molecule and receptor and cache it, so the tick is only arithmetic.
- (new) Derive efficacy from the same shape rule. Each pocket has binding cells plus one trigger cell per transducer and
  a brake cell. Touching a trigger engages that transducer, so biased agonism is which triggers are touched. Filling
  the pocket and touching none is an antagonist. Touching the brake is an inverse agonist. Touching a few is partial.
  All four efficacy classes then come from one visible rule.
- (paste) Genes as strips of colored voxels to read, cut, splice. WORKS. Decoding must be systematic: one letter changes
  one pocket cell, so mutations are small and learnable. Random decoding would make breeding noise.

### Receptors that push

- (you) Receptors push, with heteromers and metabolism; simplified, serious, consistent. All of the below follows this.
- (paste) Subunits assemble from an expression pool into homomers and heteromers. WORKS. Keep mass action: AB forms in
  proportion to a*b.
- (new) Make a heteromer's pocket literal: each subunit carries a half-pocket and a receptor joins two halves. Then "not
  the average of its parts" has a visible cause, and a surprise can be understood after the fact.
- (paste) Three or four transducers. WORKS.
- (paste) Messengers that inhibit and excite each other, pushing channels with thresholds. WORKS, with the highest
  legibility risk of anything here. Needs a readout from day one. Integrate on a fixed tick (see Build notes).
- (paste) One adaptation variable per channel gives tolerance, cross-tolerance and rebound. WORKS. Elegant and cheap.
- (paste) Counts of 6 families, 4 transducers, 5 messengers, 12 enzymes. CHANGE. Start smaller at 3, 2, 3 and 4, and
  grow only after the first set is fun.

### Metabolism

- (paste) One vocabulary everywhere: cleave, attach, oxidize, cyclize, conjugate. WORKS. Same operations for machines,
  liver and plant biosynthesis. Cap chain depth and active species per body (say 16) to stop combinatorial growth.
- (paste) Prodrugs, active metabolites, enzyme-blocking interactions. WORKS. These come for free from the vocabulary.
- (paste) Engineering your own enzymes changes how every compound behaves in you. WORKS. Probably the most interesting
  upgrade class, because it changes everything you already own.

### Resources

- (you, paste) Ores are one source among many. WORKS. Ore pass goes in after terrain, keyed to `rockBand`. Roll per chunk
  first so uniform chunks stay uniform, skip it during `MaterialPass.deferring`, and watch `dense_chunks`.
- (you, paste) Air from biomes: each biome and layer has a gas mixture, and condensers collect it. WORKS, and it is nearly
  free. Atmosphere can be a pure function of horosphere kind and climate at a point, so a collector needs only a read.
- (paste) Fog color derived from the gas mix, so you can read air by looking. WORKS. `Look.fog` is sRGB and authored, so
  this is an API change. The wild look has no fog color now (`Tint.sky`) and falls back to `SKY_SRGB`.
- (paste) Gases only perceivable in altered states. WORKS, small. Follows from the above and the reveal mask.
- (paste) Soil and water leaching and sifting from the existing strata. WORKS, low priority. A machine reading the block's
  `Material`. Water being solid is fine for this.
- (paste) Creature peptides. LATER. Depends on creatures. Start with sessile, one-block secreting organisms, which need
  no AI and fit voxel-sized.

### Plants and breeding

- (you, paste) Plants with alkaloids and a simple breeding system like what the player does. WORKS. Core content.
- (paste) Genome of a few biosynthesis enzymes plus traits; product comes from the enzyme chain. WORKS.
- (paste) Environment shifts expression, giving terroir. WORKS. The climate fields already exist.
- (paste) Crossing and mutation, with mutagenic gases and minerals from certain layers. WORKS. Ties resources to breeding.
- (new) Wild genomes evolve along the node graph. Step a genome through `NodeState.fromParents` the way `NodeClimate` is
  stepped: inherit from parents, mutate by node spice. Nearby plants are then close relatives and strains diverge outward.
  Hyperbolic space is already tree-like, so the world's geometry becomes a phylogeny and exploring becomes collecting
  across a family tree. This is the strongest fit between idea and engine in this document.
- (new) Wild plants need no stored data: genome is a pure function of node and cell. Only planted or bred ones get a side
  table entry. This suits exponential space and chunk regeneration.
- (new) Growth is lazy: store planted time and derive the stage when looked at. No random ticks, which would not scale.

### Perception-gated content

- (paste) Hidden materials with a channel threshold and a second bitmask. CHANGE per facts 1 and 2. Keep the bitmask, but
  collapse hidden faces in the vertex shader, where the glow mask is already read. That needs no fragment discard and
  no re-mesh when your state changes. Use a small family of veil materials rather than a flag on all materials.
- (paste) Hidden layers and connectors, such as a stair you can only climb while dosed. WORKS as `HorosphereForm.bare`
  kinds whose tiles paint only veil materials. Do not use terrain form, since that paints ordinary materials. A connector
  is a `Palette` of veil materials and new `PAIRS` rows. Route-based world checks can test the climb with a state set.
- (new) Leave gravity unfiltered at first. `gravityAt` still blends in a hidden layer, so high up you feel pulled toward
  something you cannot see. It is free, and it is a better first hint than any visual.
- (paste) Different families reveal different worlds. WORKS. One veil family per reveal channel.
- (paste) Hidden glyphs, beings, geometry-made architecture. WORKS. Geodesic beings are cheap: `Thrown` without gravity
  already moves along a geodesic, drawn with `Marker`, drawn only when revealed.

### Five-dimensional color

- (you, paste) 5D color with a perception rotation. WORKS, and it is cheaper than suggested. Do not add channels to the
  textures. Make the texture grain only, and hold a per-material color table. Each frame compute P * R * c on the CPU for
  each material and upload a table of 3-vectors; the fragment shader does table[material] * grain. No per-pixel matrix and
  no second texture array. Rotate the fog color by the same matrix. Grain is currently applied in encoded sRGB in
  `fillFirstMip`, so the look shifts slightly, and the current colors need re-checking by screenshot.
- (new) Hold the gray axis fixed, so rotations act on the 4D chroma space (6 planes, not 10). Neutrals stay neutral,
  brightness is preserved, and nothing clips to black. A free rotation of non-negative colors goes negative and clips.
- (paste) Hidden-by-color: materials equal in three channels that separate when rotated. WORKS. Gentler than invisibility.
- (paste) Plants advertising in hidden channels. WORKS by species, using material colors. Per-strain needs the spare face
  bits from fact 10, so later.
- (paste) Photoreceptor genes raise projection dimension (see four channels, then five). CHANGE. A display always ends in
  three. Instead make each of the three rows of P a gene: an opsin with a 5D sensitivity. Editing it permanently changes
  what you can distinguish. Drugs move R for a while and genes move P for good, using the same math and the same biology.
- (new) Optional: enclosed area turns the color rotation, as it turns the compass. Walking a loop changes your colors,
  which would be a literal link between curvature and perception. Cheap experiment, may be too subtle.

### Shaders

- (paste) Offscreen image, post passes, final composite. WORKS and contained, mostly in `base.d` and `renderer.d`. Fog,
  crosshair and HUD all share subpass 1 now, so the HUD must move after post or it gets warped. Swapchain images have no
  storage usage, so the composite is a fragment pass. Depth and glow use `STORE_OP_DONT_CARE` and would need storing.
  The screenshot path shares the render pass, so effects can be checked headlessly.
- (paste) Laplacian pyramid with band gains. WORKS. Probably the signature look. Fragment passes reuse
  `fullscreen.vert` and avoid any storage-image format question; compute also works, with `cull` as a model.
- (paste) Feedback and trails. WORKS, very cheap. Start without reprojection, since drift is the look.
- (paste) Vertex warp in `voxels.vert`. CHANGE per fact 4. Key it on camera-relative position and time. World-position
  noise would pop on rebase.
- (paste) Fog reach. WORKS for shrinking; see fact 8. Keep `loadRadius` unchanged while the fog shrinks.
- (paste) Field of view. WORKS, trivial. `HALF_VERTICAL_FOV` is an enum but it is used per frame.
- (paste) Projection change. CHANGE per fact 3, to one number. This may be the best cost-to-effect item here, and no
  Euclidean game can do it. Try it in the first stage.
- (paste) Hue, saturation, glow into bloom. Hue is replaced by the color rotation. Bloom WORKS after the offscreen change.
- (paste) True FFT. LATER, and possibly never. The pyramid may be enough; decide after seeing it.
- (paste) Eulerian temporal magnification. DOUBT. It assumes a nearly static view, and camera motion is the largest signal
  in a first-person game, so it needs reprojection across rebases. Try last, or apply only when standing still.
- (new) Comfort: bound temporal gain and warp, and add a config cap. Flicker and swimming can cause nausea or worse.

### Physical chemistry

- (paste) Bench with a scaffold and fragment blocks on a grid, Psi-like, in the world. CHANGE per fact 5. Keep it physical,
  but the bench is one block and the grid belongs to it: a floating voxel hologram drawn with `Marker` cubes, edited by
  aiming at it. 27 cubes at one push-constant draw each is fine. World voxels would break on five-way lines.
- (paste) Hold a molecule to a pocket and see clashes. WORKS with the hologram, and it is the best teaching tool here.
- (paste) Assay machines and structure-activity rules as the research tree. WORKS. Pockets stay hidden and are inferred from
  assays, which keeps it a puzzle; if pockets were readable, it would be solved once and over. Mastermind is the risk
  and also the fun. Anti-targets and heteromers keep the answers from being final.
- (paste) Synthesis as a factory: attach, cyclize, cleave, purify. LATER. Start with single-operation machines by hand,
  and let plants supply most molecules. Factory depth only matters once clones exist.
- (paste) Instruments: assay bench, spectrometer, messenger readout. WORKS and required. Without them the depth is
  invisible. The body readout should exist before the systems it shows.
- (new) No text at first. `Hud` has no font, and the user's rules forbid font tables from memory. Instruments can be curves,
  bars and spectra, and a molecule's name can be a glyph drawn from its structure. That suits the alien tone. Debug
  numbers go to the title bar and reports.

### Clones

The conversation assumes these exist; I infer they are recorded loops that replay. Not in the tree.

- (paste) Clones automate the factory. LATER. Depends on nearly everything else, but it is the game's main late mechanic.
- (paste) Limits on how many you can wind and how long a loop is, set by perception. WORKS.
- (paste) A clone keeps the state it was recorded in, so harvesting a hidden layer means recording while altered. WORKS, and
  is cheap: store a `Perception` snapshot with the recording, with no pharmacology sim per clone. Ties two systems together.
- (new) Record `Position` keyframes plus action events, not inputs, per fact 6. Snap back to the start at the end of each
  loop, like a wound toy. An action whose precondition fails is skipped, and the instrument shows it.
- (new) When a clone is out of loaded range (fact 7), do not load around it. Measure one real loop's inputs and outputs, then
  credit that as a rate while you are away. Exponential space makes keeping regions loaded the wrong answer. Do not build
  on `client/script.d`; that is test tooling and clones are game code. Benchmark before committing to a clone count.

### Creatures

- (paste) Creatures on the same biology, making peptides. LATER. Sessile ones first; walkers can use `CharacterState` with
  scripted input.

### Added by this plan

- (new) Saves. Worldgen is pure, so a save is only edited chunks, side tables, and body state. Node ids are hashes
  (`childId`), so store the face path from the root; the parent links of pinned nodes make it available. I infer that
  regeneration is order-independent because the digest tooling implies it, but that needs checking.
- (new) Beacons. Getting home is the real distance problem in hyperbolic space, since paths diverge fast and there is no global
  direction. A base you can never find again kills farming. `RouteWaypoint` and the compass are most of the way there.
- (new) Items and a use key. Pickup on break, a hotbar drawn from material colors, keep walk, fly and noclip as debug toggles.
- (new) Side table keyed by chunk and cell for block data. Placing anything marks the chunk edited, which already pins it.

## Rough order

Each stage should be playable or testable alone. The gate after stage 1 is the most important point in the plan.

Stage 1: feel test, no chemistry. Debug keys set hardcoded perception states.
  - `Perception` struct, effective `CharacterConfig`, reveal mask per body.
  - Veil materials through mesher, vertex shader, collision and raycast (facts 1 and 2).
  - Color table and rotation; FOV; projection offset; camera-relative warp; fog shrink.
  - One bare veil layer with a veil connector, plus world checks for the climb.
  Gate: is walking up a stair that only exists in one state, with the world rotating in color, actually good? If not,
  rethink before building the biology. Cheap to throw away.

Stage 2: post chain. Can run alongside stage 1 or slip.
  - Offscreen target, composite, HUD moved after post. Pyramid, trails, bloom. Measure with `GpuTimer`.

Stage 3: game substrate.
  - Items, use key, side table, text-free HUD panels, beacons, saves with a version.

Stage 4: biology core, headless first, unit tested in `source/unit/`.
  - Molecule, pocket, cached affinity, kinetics, occupancy, transducers, messengers, adaptation, metabolism.
  - Body readout instrument. Replaces the debug doses from stage 1. A headless check that prints curves for tuning.

Stage 5: sources and reading them.
  - Wild plants on the node graph, atmosphere and collectors, ores, soil machine.
  - Spectrometer and assay, so that what plants make is legible before breeding starts.

Stage 6: genes, which is the heart of the game.
  - Gene strips, breeding, mutagens, terroir, lazy growth.
  - Self-editing: receptor subunits, enzymes, opsins (the P matrix). This is the first complete version of the game.

Stage 7: designing molecules.
  - Bench hologram, clash view, single-operation machines. Analogues, anti-target tradeoffs.

Stage 8: automation.
  - Clones with snapshot perception and away-rate credit. Factory machines, longer synthesis chains.

Stage 9: whenever, if still wanted.
  - Creatures, more veil worlds, splicing plant genes into yourself and back, making your own compounds,
    hidden-channel strains, audio, FFT, Eulerian.

Why genes before the bench: the user wants the game to be about gene engineering, and plants already produce molecules through
enzyme chains, so breeding reaches chemistry without a synthesis system. The bench then adds precision rather than being
the only way in.

Smallest version that is still the idea: stages 1, 3, 4, 5 and 6. No clones, creatures, FFT or audio.

## Risks

- Legibility. A four-layer signaling network can easily read as random. Every layer needs an in-world view, and the first
  tuning pass should be judged by whether a player can explain what just happened.
- Scope. This is a lot of systems. The one-biology rule is what makes it feasible, since each addition reuses the same
  data, and anything needing its own special model should be questioned.
- Solved puzzles. If an optimal molecule stays optimal, chemistry ends. Tolerance, cross-tolerance and self-editing are what
  keep moving the target, so those are not optional polish.
- Hidden-material face count. Veil materials always emit faces. Check with `--bench-load` once a veil layer exists.

## Open questions for the user

1. Clones: what were they in the part of the conversation I did not see? Recorded loops is my inference.
2. What is at stake? No damage or death exists, and "lowers max health" needs one. I lean toward costs staying in the same
   currency, meaning lost channels, weakened movement, and blackouts that cost time, with no health bar and no combat at first.
3. Audio needs a new dependency, which I have not chosen. Not needed before stage 9.
4. Text: are text-free instruments fine, or do you want a font? If so, it has to come from a real source file.
5. Worldgen: should the wild-plant phylogeny apply in every plugin world, or only `planet`?
