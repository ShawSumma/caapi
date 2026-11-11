# Plan: from the owner's answers to a finished world

This file says what has to happen before the decisions recorded in `ideas.md` ("Decisions waiting") are fully built: the owner's answers in their own words, what each one is taken to mean, the work cut into packages, the order they depend on each other in, and how the packages are handed to subagents.

It is a working document. `ideas.md` holds wants and ideas, `CLAUDE.md` holds how the code is and how to work in it, and this file holds what is to be done. When a package is finished, its status here changes, the **Exists** lines in `ideas.md` are brought up to date, and anything durable it taught goes to `CLAUDE.md`.

Written 2026-11-11, at the end of the conversation that joined the built worlds to the default world.

How statements here are marked:

- **Read** means read in the code during that conversation.
- **Tested** means a test, a world check or a render showed it.
- **Reading** means an interpretation of something the owner said. It is the planner's, not the owner's.
- **Unread** means the file it concerns was not read when this was written, so the package has to read it first.

## Contents

1. [Where things stand](#1-where-things-stand)
2. [The owner's answers](#2-the-owners-answers)
3. [What the answers are taken to mean](#3-what-the-answers-are-taken-to-mean)
4. [Rules every package works under](#4-rules-every-package-works-under)
5. [The packages](#5-the-packages)
6. [Order and dependencies](#6-order-and-dependencies)
7. [Splitting the work across subagents](#7-splitting-the-work-across-subagents)
8. [Questions still open for the owner](#8-questions-still-open-for-the-owner)
9. [Status](#9-status)

## 1. Where things stand

Built and checked at the time of writing. Everything in this list was **Tested** on the final build unless it says otherwise.

- Seven worlds: `planet` (the default, the one `terrain` names), `city`, `backrooms`, `library`, `vaults`, `caves`, `lattice`. Single buildings and test rigs are debug structures (`registry.addDebug`, `--worldgen debug <name>`): `tower`, `crown`, `palace`, `arbor`, `babel`, `road`, `trail`, `underground` and the rigs in `plugins/fixtures`. Plugin ABI is 25.
- The default world holds the others as risen grounds, has caves under all of it, lattice groves on wild ground, and stands six landmarks around spawn.
- Caves: open sinkholes on wild ground, sealed caves from 1.9 edges down under city, backrooms and vaults, none under the library. A world gets caves by calling `build("underground")`.
- Ports and wells: `api.ports(odds)` rolls ports per ground vertex (3 in 100), `probePort` answers, every tile leaves the port's column open and the cave edge tile sinks a spiral stair two edges down to a cave head that is forced open. No port at a world's root vertex, at a risen ground's foot, or where a ground rises.
- Crust: `api.crust(ground, edges)`. Risen wild ground and vaults 3.4 edges, city and backrooms none. Below the crust nothing is generated, and the planet's edge tile hangs the lattice there (`lattice.hang`). `api.under` changes look and fog by depth.
- Package A, built and checked: the root wild ground's crust is a field between 5.6 edges and 2 (`api.thinCrust`; settings in `plugins/planet/settings.conf`). `probeCrust` answers the underside at a site; `api.underCrust` sets a look below the crust; the caves keep a chamber only half an edge or more inside the rock (`ROCK_MARGIN`); the lattice hangs wherever an end of a beam is in the open. Plugin ABI is 26. What it looks like: a roof about two edges thick, and under it great stepped masses of pale rock with lattice in the open between them; thin and thick places both lie right under spawn.
- Flat ground is soil over rock bands and veins.
- City districts (five), backrooms plans (pillars, pools, courts) and 18 biomes, library rooms (atrium, studies, lounge).
- Vaults rise with `bridge: none`: no connector to them or from them.

The checks that passed on that build: 103 behavior tests, the unit tests, the application, headless and `:web` builds, `content-check` (0 problems), `check-repaint` with `differing=0` on all seven worlds, `check-forget` on lattice, `views` (123) and `films` (9).

Known weak spots, none of them fixed:

- `world-digest` came out the same before and after the crust, the void and the wells were added. Fixed by N2: it now prints a second line, `deep`, for a column under spawn eight edges down, tiles included. Since package A the two lines read `digest populated=10140 materials 135fa9e2dc893a80983fd133d6ad301c occupancy 78676cc3384bc6057a5cc686700ed889` and `deep populated=856 materials e824508e4f1cc59d701a5f201d6d5178 occupancy bb3ed9d320159f549a78d96ee548fecf`, and package P left both as they were. It still does not reach a port.
- Under the root crust nothing catches a falling body but the lattice. **Tested** only as far as: a body let go 6.4 units under spawn fell 0.5 in a second and landed on a girder.
- Package A made generation near spawn slower: `bench-gen` and `bench-drive` both took about half as long again after it. The cause is read from the counts: within 2.5 units of spawn nearly four times as many chunks are generated cell by cell, because a chunk whose shield range crosses a threshold cannot be proven whole. The owner keeps the masses, so this cost stays; package P took back part of it (the parameters) and stopped the far underground from being generated at all from the surface.
- `structure/void`'s first law ("in the open and falls") would also hold for a body inside solid rock, since a body inside uniform rock falls. `structure/window` and `structure/shield` ask for solid cells and are the stronger statements.
- Probably, cave floors, ceilings and formations hang in the open where a chamber meets the flank of a rock mass (inferred by the scout of B from the code; the four renders of A did not look there). The repair is the first piece of B.
- A port is a bare hole with a limestone stair in every ground.
- In the backrooms the well's column is left open on every level (**Read**), but only the top level was looked at.
- `wiki.md` is a generated page and is behind the code.
- `live/fly` had come to use more than half of its 120 s limit. After package P it uses under a quarter.
- Lattice poles that straddle the underside are painted up into the rock as far as the vertex above (**Read** in `lattice.hang` and `beam`), so a joint may show in the floor of a deep cave chamber. Not looked at.

## 2. The owner's answers

In the owner's words. Where an answer was a choice among offered options, the option is given as it was offered.

### Standing wants

- "I don't want boring areas to exist."
- "There should be caves and rock and variety under anything that was just all dirt or something."
- The more abstract structures should not have bridges to them.
- On choosing between designs: "I think that for some of these doing both works as a form of variety".
- "where minecraft has things based on 2^n I like 3^n better, sizes of 1, 3, 27, 81 and so on". And on its reach: "It applies to all arbitrary numbers that are a count of things you can hold or need. So for crafting I'd go with 3 wood instead of 4 and then so on. It's not a hard rule, sometimes something else makes sense. Not for the world, it's an item-centric rule".
- On the backrooms: it "has different subtypes and various things", the way the Minecraft mods do it; it felt far too uniform.
- On the library: "think local american library but infinite. Big areas, small areas, rooms with things. Entrances that sometimes loop and sometimes don't."
- On what lies under the ground: some of it "should be sort of undergrowths above a void world like that of the lattice and whatever is next."
- On single-structure worlds: caves under them are "no by default but with an option for yes", and they "should transition into more debug than being presented as co-equal to a world, let alone a world that embeds others".

### The fourteen decisions

| # | Question | Built now | Answer |
| --- | --- | --- | --- |
| 1 | Under the root, does the void replace the deep or lie below it? | Full-depth crust, 5.6 edges | **Shields and windows**: clusters of faces roll a thick crust with the full geology or a thin one with the void near the surface. |
| 2 | What happens to a player who steps off into the void? | Nothing catches a body but the lattice | "The fall is real but we plan for a mechanism to get back. Like a respawn, with keepinventory-style things. Maybe 1/3 of items you have 3 or more of are lost." |
| 3 | How does a player get from the caves into the void? | No way through | **Through the caves**: the lowest chambers open through the crust's floor. |
| 4 | Is the way back up the way down? | Wells are stairs both ways and stop at the caves | "A network that almost doesn't feel so. I think the another way is good but not exactly one way out, but not too obvious either" |
| 5 | What decides where a port is? | A flat roll, 3 in 100 | **A feature of the place** (the city's works district, the backrooms' sump and cellar, a vault with a spire). |
| 6 | Where is the line between a world and a debug structure? | Endless places are worlds, single structures are debug | **As built.** |
| 7 | How is a no-bridge ground reached? | It is not | **The hidden stair** of mist stone. |
| 8 | What may rise from a no-bridge ground? | Grounds that are cut off as well | **As built.** |
| 9 | What decides which void world lies under a crust? | The ground above; one void world | **The ground above, depth, and the surface**, together. Not region. |
| 10 | Which void world comes after the lattice? | None | "More abstract things. Different ways of filling the lattice. Megaphobia structures and fractals. It's meant to be more nightmare than a place. Repeating patterns that break once in awhile. Island worlds that connect. A flat maze horosphere that is dangling from whatever's above it. Sparse islands" |
| 11 | What sets what lies under a built ground? | Depth alone | **The ground above** writes its own underground, and **sealed means kept**. |
| 12 | What makes a backrooms subtype a place? | Regions, by level | All four (regions with edges, rare rooms, levels, uses). "All of these are good, but don't close off. This is where variety really matters. Take inspiration from minecraft's multiple table worldgen" |
| 13 | What do the library's rooms hold? | Plain blocks | Notes, the catalog and working rooms. "Stock goes in the backrooms, tho maybe library-ish stock once and a while. More like a break room for library employees" |
| 14 | Where does normal play meet a debug structure? | Six stand at spawn; the menu lists none | A creative menu. "Essentially debug worlds are for seeing a structure out of context or in isolation. Normal play doesn't really see them. Think the concept of a scene or prefab in unity or godot". And on the six at spawn: "I think placing them is fine, but rather the goal is to turn them into real things that are not just for testing. Like, real places and objects" |

### Answers given after this plan was first written

Asked four of the questions in section 8:

- Where a fallen player wakes: "I think going back to the last thing they stood on before they entered the place would be good."
- On "megaphobia" and the maze sheet: "The fear of structures larger than you can comphrend. The flat maze should be closer to a rafter with no railings. Not walls as much as a minecraft-ish mineshaft."
- On "minecraft's multiple table worldgen": "Yes, but onlt a bit. You don't have to, and should not, do exactly that... just that's how I mean doing multiple strategies. You can't make it a tree, it's a space of parameters"
- On whether capacities fall under the threes rule: "The queue shouldn't have a size and should work like factorio. 24 compounds kept is also a bad/weird thing. Flowers stacking but being unidentified is a bit odd. They are basically a bundle of items, in a way."

And on who builds: the work is done by Opus 5.5 subagents, briefed and checked from the main session.

Asked five more once the scouts had reported:

- On the audit table: "I'm fine with your judgement. I like 81 as the limit. Minecraft has inventory problems. Hotbar should be 12 (maybe 13 with tilde). Not powers of 3 for thier own sake, but just when somerthing has no default"
- On the queue: "The queue should work as best you can. The ingrediants are taken immediately and you shouldn't be able to queue what you don't have. Very factorio"
- On bundles: "A bundle is that which you cannot make any distinction between. It just picks from it. The player should be aware of this, with some tooltip or UI drawing of the different flowers. Like you know which one you have but not what that means. It's a sort of abstract idea. I'd say be forgiving, when the player only has one of a thing, even if they don't know it."
- On the landmark table: "Give it a shot, if it's no good then we can remove it"
- On waking when the ground last stood on is gone: "If it's not there go to the block before it. If nothing is there go to world spawn"

### On speed, after the crust was built

"Btw the slowdowns are absolute failures. It was already slow. That is not good *at all*. The world gen is so slow, it's always overcommiting to work then just doing nothing. It's genuinely 10x to slow now as opposed to only being 5x before"

This outranks every package. See package P, which comes before all the others.

And then, on how: "I think work queues should be min-heaps of distance in a way. I want you to spend time optimizing things here. Think about data structures and remember that the goal is having fast generation, not just clever tricks. Like, do all the things that would make it fast. I'm fine with masses, it feels more geological to me."

So question 1 is answered: the rock masses stay, and the second build of package A is not built.

## 3. What the answers are taken to mean

Every paragraph here is a **Reading**. Where a reading could go two ways, section 8 asks.

**1, shields and windows.** The crust stops being one number per ground kind. Over some stretches of wild ground it is thick and holds the whole deep (the rock bands down to 4.5, iron below 2.6, the cave themes down to ember). Over others it is thin, about two edges, and the void is close. The thing that varies is the thickness of the root wild ground's crust. Risen grounds keep one thickness each unless that turns out to be dull. "Both, as variety" applies: thick and thin are both wanted, and the border between them is itself a place (the underside steps up or down there).

**2, the fall.** Falling is not softened: no catch, no rewind. What makes it bearable is what happens after: the player wakes somewhere safe with most of what they carried. The loss rule is the threes rule at work: of each kind of item held three or more of, a third is lost; kinds held one or two of are untouched. The game gets its first way for a trip to end, so it needs the least machinery that makes one honest: a condition that says "this body is lost", a place to wake, the loss, and a note that says what happened. "we plan for" reads as: this is wanted, and its details are not fixed.

**3 and 4, down and back.** The way into the void is the cave: where the crust is thin, the lowest chambers break through it. The way back is not the way down, and it is not one thing. There should be several kinds of link between the void and the ground (cave openings, stairs on some lattice poles, wells that go deeper than their cave, whatever a void world brings of its own), none of them signposted, so that coming home is finding a route through a network and not walking to the exit. "almost doesn't feel so" reads as: no map of it, no markers, no regular spacing a player could count on.

**5, ports.** A port stops being a roll and starts being something the ground does. Each built ground decides, from what it is at that spot, whether there is a way down, and dresses it as its own: a manhole or a works yard in the city, a sump or cellar stair in the backrooms, a broken floor under a spire in the vaults. A player who has seen two can find the third.

**6 and 8.** Nothing to build.

**7, the hidden stair.** The vaults stay without a visible bridge. What reaches them is the connector's hidden style: a stair of mist stone that is there only for a dosed body. This is the first use of that style in real play. Anything that rises from the vaults stays cut off (8), so it is reached the same way or not at all.

**9, which void.** Three rules at once. The ground above names what hangs under it (wild ground names the lattice). Void worlds are layers by depth, so under the first there is a second. And the void shows the underside of what stands above it: wells, footings, piers and roots come through and the void world ties onto them. Region was the one not chosen: the kind of void does not change by rolled cluster. (The thickness of the crust does, by 1.)

**10, what is next.** Not the four that were offered. The void is "more nightmare than a place": abstract, too large, patterned, and wrong in small ways. The list reads as a set of void worlds and of ways to vary one:

- other fillings of the lattice (denser, sparser, braced, broken);
- structures too large to take in ("megaphobia" is read as megalophobia, the fear of very large things);
- fractals;
- patterns that repeat and break once in a while;
- sparse islands, and island worlds that connect;
- a flat maze sheet dangling from whatever is above it.

**11, under built ground.** Both chosen answers hold. Each built ground writes what is under it (the city's is infrastructure, the backrooms' goes on down, the vaults' is crypts), and the sealed caves under them keep what open caves lose (air, hidden-family stones). Plain depth-only geology stays as what is between and below.

**12, backrooms.** All four at once, and no list of subtypes is ever final ("don't close off"). "minecraft's multiple table worldgen" is read as the way Minecraft picks a biome from several independent fields looked up in a table, and its structures from weighted pools of pieces: several tables that vary independently and combine, in place of one roll that picks one biome from one list. Section 8 asks whether that is the meaning.

**13, library.** Three things to find in its rooms: notes to read, the catalog of compounds, and working rooms with stations. Salvage is the backrooms' job; the library gets only a little stock of its own kind, in a staff break room.

**14, debug and landmarks.** A debug world is a scene: one structure, out of context, for looking at. It is offered in the world menu under creative rules and nowhere in normal play. The structures themselves are a different matter. They are prefabs: the tower, the crown, the palace, the arbor, Babel, the road and the trail are to become real places with a reason to be where they are and real things in them, and the debug scene of each stays as the way to look at it alone.

**Threes.** Item counts only. Where a number says how many of something a player holds or needs and nothing else fixes it, it is 1, 3, 9, 27 or 81. Not the world's sizes, and not a law.

## 4. Rules every package works under

These are in `CLAUDE.md` in full. The ones that have bitten:

- **Generation is a function of place.** Nodes and tiles are evicted and made again. Anything rolled comes from a hash of the node, face, edge or vertex, never from visiting order, time or a counter. `check-repaint` and `check-forget` catch violations, and every package that touches worldgen runs them on all seven worlds.
- **Tiles agree by hash or keep out.** Placed structures paint first and tile paints go over them in an order set by the tile's hash. Two tiles of different plugins that could paint the same cells must compute the same answer from hashes alone (`probeOwner`, `settled`, `probePort`), or one of them must leave the cells alone. A tile cannot place, claim or read claims.
- **Only the world's own structure shapes grounds.** `tile`, `tileEdges`, `horosphere`, `under`, `crust`, `ports`, `flatten`, `fog`, `look` are refused from tiles and from structures placed later. A structure placed later is also refused `openHorosphere`, `rooted`, `invertGravity`, `worldLook`, pens and endless paint. A tile is also refused `place`, `claim`, `probeClaimed`, `landmark`, `columnSite` and endless paint.
- **A tile paints only what is not yet finished.** A paint that reaches a node which is already finished is refused, and the refusal stops the world. In practice a face tile stays on the columns at its own face's five vertices, at any height or depth, and on the ground edges between them.
- **A stop pins its node.** A route stop or an entrance from a tile or a placed structure references a node for good. Anything that recurs lays none.
- **Shaping calls go by tag to the kinds that exist.** `crust` and its relatives set a number on every kind already registered with that tag, so they are called after the kinds are added. Nothing refuses the other order; it silently does nothing.
- **A new ABI number refuses every older save**, as does a new `SAVE_FORMAT`. The project changes formats and does not migrate.
- **The ABI number.** `ENTRY` in `plugins/api/api.d` goes up whenever the layout of `Api`, `Registry` or `Risen` changes, and new members go at the end. Two packages that both change the API must not be in flight together.
- **A new plugin** needs a subpackage and a `preGenerateCommands` line in `dub.sdl` and an entry in `WEB_ENTRIES` and `WEB_PLUGINS` in `source/client/plugins.d`. Shared code is a `sourceLibrary` with a `-mod` library beside it (see `caves`, `lattice`).
- **Laws are claims.** What a package makes true about the game is stated with `world.claim` or `world.link` in `source/scripts/tests.d`, with measures, and says no more than its condition checks. A view goes into `source/scripts/views.d` and is looked at with `./caapi --screenshot <png> <view>`; the PNG is deleted afterwards.
- **Verification** for a worldgen change: unit tests, all behavior tests, `content-check`, `world-digest` (must not change unless the package means it to), `check-repaint` on planet, city, backrooms, library, vaults, caves and lattice, `check-forget` on lattice, `views`, `films`, and the application and `:web` builds. Rebuild headless in release after `dub test`.
- **A slowdown is a failure, not a cost.** The owner's word for it. World generation was too slow before any of this work and the work made it worse. Every package measures generation before and after (the bench commands, and the `live/` tests' wall times), against a baseline taken the same way, with repeats, and hands back a tree that is no slower. If a feature cannot be had without a slowdown, the builder stops and reports instead of landing it.
- **Style.** D with `-betterC`, no comments, no ternaries, no `continue`, typed locals, `final switch` on enums, state as types. Content is data in `.decl`, `.content` and `settings.conf`, not constants in D, wherever a mod could want to change it.

## 5. The packages

### P. Speed first

**For.** World generation that keeps up with play. Nothing else in this plan is built until this is done, apart from the fall (C), which was already with a builder and brings a bottom below which tiles are not run.

**The owner's words.** "the slowdowns are absolute failures. It was already slow. ... The world gen is so slow, it's always overcommiting to work then just doing nothing. It's genuinely 10x to slow now as opposed to only being 5x before"

**Two problems.**

1. **The new one, which this work caused.** The scripted `live/` sessions all took longer than before any of this work, `live/fly` by half as much again. The owner's experience in play was worse than those ratios, so the sessions understate it; they never mesh or draw, and the application now generates, tiles and meshes lattice and broken rock under the ground where there was uniform rock that cost almost nothing. What was added: the cave tile run once per filled ground near each edge; groves; rock bands and veins under built ground; the void's lattice at any depth; ports and wells; and the crust field, which alone made `bench-gen` take half as long again and nearly four times as many chunks near spawn generate cell by cell.
2. **The old one.** It was already several times too slow, and the pattern the owner sees is that it commits to more than it can do and then does nothing.

**The bar.** First: every number above back to where it was before this work or better, with everything this work added still there. Then the old problem.

**The owner's direction.** Work queues are min-heaps keyed by distance: the nearest work is done first, and work for places left behind does not hold up work for where the player is. Time is to be spent here, on data structures and on doing less work, with fast generation as the goal and not tricks: everything that makes it fast, each thing measured. The masses stay, so the speed has to be found with them: a smoother shield (larger masses, fewer chunks that straddle the edge of one) is a tuning the owner's answer allows, and is tried and shown in renders if the measurements say the mixed chunks matter.

**How.** A scout is reading the whole streaming, tile, generation and meshing path for both problems and for a way to measure them. A builder then, in this order: a benchmark of a streamed session that reports where time and idle go, added to the harness in `source/worldcheck.d`; the fixes that undo the regression, one at a time, each measured; then the old problem. Candidates known before the scout reports, none of them measured:

- restore the chunk fast paths under the crust field (bound the thickness exactly from the chunk's corner values, or decide thick or thin once per node);
- tighten `isInBand`, which now lets nearly every node between two and 5.6 edges down hold content;
- do not generate, tile or mesh what cannot be seen: with the camera above the ground, what lies under an unbroken roof; with it below, what lies above;
- bound the lattice (the abyss from C);
- do not run the cave tile for a ground that can have no cave at that edge.

**Checked by.** Section 4 in full, both digest lines unchanged unless a fix is meant to change what is generated, and the benchmark numbers before and after, raw, three runs each.

**From the scout, read in the code. Nothing in it was measured; the sizes are its estimates.**

*How a frame streams.* `Game.step` calls `world.update` with a budget of 8 ms. In order: paint tiles ahead (up to 256 candidate nodes, up to four rounds of planning, then every task in one blocking job with no deadline, then each task applied on the main thread); rebuild or refresh the set of nearby nodes (everything within 4.5 units is expanded whatever it holds; beyond that only nodes that may hold content, out to the load reach, which is 7.57 units above ground and about 3.3 in the void's fog); drive the streamer (integrate arrivals, scan nodes, plan chunk parameters in one blocking job, submit generation and building requests to queues); evict. Workers are cores less two; they join any open job first, then take from the queues. Meshing is a 2 ms job per frame that every worker joins. The GPU culls against the frustum only: nothing is culled for being hidden or far.

*Where it commits to more than it can do and then idles.*

1. **Batches with no bound that the frame waits for.** Chunks within 3 units are all "urgent" and planned without a budget; a frame can plan thousands of parameters in one blocking job and then the queues hold seconds of work.
2. **Queues that never forget.** Requests are first in, first out, and are never cancelled when the camera moves, so the chunk under the body waits behind everything within 3 units, and work arrives for places already left.
3. **A main thread every stage passes through.** On it, serially: tiles that were not painted ahead (through `ensureStructureAt` in the scan), `planBuilding` for every building (which runs the whole tile visit of the node again on the main view), parameters for every chunk whose worker view was blocked, `resolveMaterials`, merging what the workers found, and applying every tile task. A node needs at least paint, building, parameters, generation, integration and mesh, each gated by the main thread on a different frame. With the frame paced to the display, the main thread sleeps, the queues drain, and the workers sleep until the next frame plans more. The headless sessions are not paced, which is why they hide it and why play feels worse than their numbers.
4. **Work redone after a blocked view.** A blocked chunk falls back to the main thread; a blocked tile candidate is planned again from scratch, up to four times.
5. **A batch waits for its slowest task.** A cave vertex carves 6912 cells with several tests each; a sky edge does almost nothing.
6. **Generate, drop, generate again.** The load reach is 7.57 units but dense chunks beyond 3.5 are dropped once meshed, and every fresh arrival restores (regenerates) its dropped neighbors. The shell between holds most of the volume.
7. **A cache flushed whole.** About every two seconds the sweep releases idle grounds and, if it released even one, clears the entire cache of what rises where.
8. **A reach that jumps.** The load reach follows the fog every frame, so going under half an edge shrinks it to about 3 and coming back up asks for the whole shell at once.

*What this work added.*

- With the camera on the ground, about 45 percent of the nodes that are always collected (the 4.5 ball) lie at or below the thin underside. That region used to be uniform rock: opaque, unmeshed, nearly free. It is now masses generated cell by cell and a lattice on every edge in the open, so nearly every deep node needs a building (which pays the main-thread `planBuilding`), loses the uniform fast path for all twenty of its chunks, and is meshed and drawn. None of it can be seen from above. This is taken to be the main source of the doubling.
- The bottom that C adds is twelve edges down, deeper than anything streamed from the surface. It does nothing for play above ground.
- The cave tile: each edge task runs once per filled ground near it, up to four times; each call opens pens, and for an owned end walks the chain of parents with a fresh memo, so shared chains are walked again by every task. `keeps` and `hang` now call `probeCrust`, which builds a climate around the point (eight node states, created if missing). Every edge in rock deeper than four cells pays two of them.
- The fast paths under the crust field were lost honestly: the bound from the chunk's corner values is already exact, and the ramp is as wide as one node step's noise, so most chunks between thin and thick really are mixed. Bounding better recovers little.
- `isInBand` widened only where relief is high; elsewhere the set of content nodes is about what it was.
- Rock bands and veins under flat ground make 8 percent of rock chunks dense; each is meshed in full for no faces and dropped and restored beyond 3.5.

*Fixes that undo the regression, by expected gain.*

- **R1. Do not make what cannot be seen.** Plan and mesh a chunk only if it is close (for collision and editing) or a face neighbor is made and has a cell on the shared face that does not block sight. Solid rock stops the flood; sinkholes, ports, wells and cave tubes let it through, which is why it stays correct. It never changes what is generated, only whether and when. Expected to save about half the nodes of the near ball above ground, with most of the lattice's cost. A depth gate would be simpler and is not provably correct.
- **R2. Decide thick or thin once per node,** or make the shield smoother. Brings cell-by-cell chunks back toward the old count. It changes the look and the `deep` digest line, so it is the owner's call and belongs with question 1.
- **R3. Cheaper exact paths:** hoist the climate's x and y interpolation out of the innermost cell loop (the floats are identical); in `lattice.hang` test the bottom before asking the crust; remember `probeCrust` per vertex within a task.
- **R4. Remember cave openness per worker,** not per tile call. It is a pure function.
- **R5. Do not run the node's tiles again on the main thread for every building,** only when one of its tiles was dropped.
- **R6. Tighten the shield's slack in `isInBand`.** Helps only in hills.
- **R7. Take a risen ground's plane from the reference the node already carries,** not by walking a path. The floats differ slightly, so the digest may move.

*Fixes for the old problem.*

- **O1. Priority and cancellation.** "Urgent" only for what is right at the body; far fewer requests in flight; a request popped for a place now out of reach is dropped back to fresh.
- **O2. Take the serial stages off the main thread:** blocked parameters retried on workers, material resolution as a request, building plans made on workers.
- **O3. Stop the drop-and-regenerate churn.**
- **O4. Do not mesh a dense chunk whose cells all block sight when its six neighbors do too.**
- **O5. Forget only the rising keys that changed.**
- **O6. Deadlines on the parameter and tile batches.**
- **O7. Tuning that is not exact:** the relief slack makes the content band eight units thick; a fog threshold of 1 in 32 in place of 1 in 256 would halve the far nodes at the cost of faint popping.
- **O8. A linear search inside a per-frame walk.** Small.

*How to measure.* `./caapi --bench-load --profile` exists and is the closest thing to play: it renders offscreen, flies six legs paced at 60 frames a second, and prints slow frames with their phases, how long the main thread waited, tiles painted ahead against tiles painted late, and faces by distance. Run it first. Then add `bench-stream` to `source/worldcheck.d`: a fresh streamed game on a fixed path at a paced 60 frames a second, with the meshing job run without a GPU, printing per run the phase times, worker idle time, fresh against restored arrivals, blocked views, tile counts, the depth of the queues, and faces meshed above against below the camera's ground. A few counters go into the streamer, the tile work, the integrator and the worker pool for it. Baselines are taken by running the old and new binaries interleaved, five or more each, and comparing medians and spread.

*What reading could not tell,* and so is measured first: how the main thread's frame divides among its serial stages, how long workers sleep, the share of nearby nodes below two edges, how many faces are drawn from under the ground, the ratio of restored to fresh chunks, how often views block.

**Measured and done by the main session (2026-11-11).** The owner asked for the speed work to be done directly, with work queues as min-heaps of distance and with data structures in mind. Everything below was measured with `./caapi --bench-load --profile` on the planet world from spawn, single runs unless it says otherwise; the bench now also prints, per distance shell, how many tiles painted nothing, how many are edge tiles and the nodes by content class, and at the end the nodes holding chunks by their nearest ground.

*What the measurements said.*

- The number of nodes tracked is set by the load reach, and it grows as e^(2r). At the old cutoff (fog leaves 1 in 256, 7.57 units) the bench never settled: it crashed growing the GPU face buffer with about two million nodes tracked. At 1 in 32 (6.73 units) it settled with about a million nodes and tens of gigabytes; at 1 in 8 (5.93 units, where a chunk is about 2 pixels and the fog leaves 12 percent) with well under half of that. The rule in `source/client/world.d` is now: load as far as the fog around the camera shows anything (1 in 256, `FOG_FAINT_THRESHOLD`, as before), but never farther than where the open sky's fog leaves 1 in 8 (`FOG_LOAD_THRESHOLD`, 5.93 units at the default render radius). Under a ground, where the fog is short and the reach cheap, nothing changed. In the open this is a tuning the owner can see: chunks appear at about 5.9 units, faintly.
- The main thread was the bottleneck and the workers idled: of thirty workers, about two were busy on average during a load. That is the "commits to work and then does nothing" the owner sees.
- Tiles: about sixteen live tile records for every node, nearly all of them edge tiles, and nearly three in four of those had painted nothing (sky and rock edges where the cave and lattice tile has nothing to do). Each still cost a record, two hash entries, an apply on the main thread, and later a sweep, a drop and a forget.
- The evictor's sweep for idle tiles looked at a thirtieth of all live tiles every frame with a hash lookup each: about half of the step budget during the load, more in flight.
- A fifth of all worker CPU went to `calmAt`: every node state walked a path to each of the world's thirteen flattened sites.
- In flight the set of nearby nodes could not be rebuilt as fast as the camera moved: a rebuild took a couple of seconds, and within 4 units of the camera well under half of the chunks were loaded at the worst moments.
- **The regression itself.** Counted by the ground nearest each node: all but about a fortieth of the faces drawn were below the root ground, with nearly all of the dense chunks and of the per-node buildings (which were most of the memory). The sealed underground (the masses and the lattice that package A put where uniform rock had been) was being generated, built, meshed and drawn out to six units from a camera standing on top of it. The test for "wholly underground" could not catch it: it allowed four units of slack (`RELIEF_SLACK`) for how far the terrain might vary across a node, so only nodes five units down counted.

*What was changed.*

- **Calm from a table.** `spreadCalm` (in `structure.d`) walks the nodes within reach of a site once, when the world flattens it, and stores each node's calm in `Blueprint.calms`; `calmAt` is one lookup. The arithmetic per node is the old one, so terrain is bit for bit the same (both digest lines unchanged).
- **A blank edge tile is one bit.** An edge tile that paints nothing sets a bit in its node's `NodeStructure.blankEdges` and leaves no record. Tile records are made when a tile's output is applied, not when it is queued.
- **A tile's life hangs off its node.** Live tiles are chained from the node whose face, vertex or edge they belong to (`NodeStructure.tiles`, `TileRecord.nextOnFace`). The evictor drops a node's idle tiles when its sweep finds the node outside the nearby set, and a node with live tiles is not evicted. Nothing sweeps all tiles any more.
- **Buried, exactly.** `probeBuried` (`horospheres.d`) says whether a node lies wholly below the surface of the root or of any risen ground near it, using the lowest relief among the 63 nodes that share a vertex with it (a chunk's relief is interpolated from exactly those), not a slack. It runs on the workers: in the tile planner, and in a parallel pass at the head of the streamer's scan. A buried node becomes `NodeContent.deep` and is never painted ahead. A camera above ground loads it only within 2.6 units (where the lattice's fog of 3.5 would leave 1 in 8): from above, the underground is seen only through holes and only that close. A camera that is itself under a ground loads it as far as that fog shows, as before.
- **A clear node is filled once.** `probeClear` says whether a node lies wholly above everything any ground near it can fill. If its structure also needs no building, its chunks are stored as air directly (`Streamer.fillAir`) with no parameters built. The bound is chosen so that it implies the per-chunk proof (`CLEAR_SLACK`), and a unit test checks both directions on terrain: clear nodes have twenty chunks predicted empty, buried nodes generate no air.
- **An edge tile's ceiling.** `api.edgeCeiling(cells)` (plugin ABI 28): the world says its edge tile paints nothing along an edge whose two ends are both higher than that over every ground the tile runs over. The engine then skips those edges without running the tile. The planet and the cave tile use the height above which the cave tile already did nothing.
- **Workers woken to the size of the job.** A parallel job of one item runs on the calling thread; larger jobs wake only as many sleeping workers as there are grains (Linux; macOS still wakes all).
- **Work heaps.** `base/heap.d` holds `WorkHeap`, a min-heap behind a futex lock. Chunk requests and building requests each sit in one, keyed by the hyperbolic cosine of their distance from the camera; a worker takes whichever heap's top is nearer. Every quarter unit the camera travels, and whenever the nearby set changes, the streamer re-keys both heaps and drops fresh-chunk and building requests that have fallen out of range, returning the chunk to fresh. The urgent and normal queues are gone.

- **A step budget that follows the frame.** `LocalWorld.paceBy(idle)` moves the step's budget between `LEAST_STEP_BUDGET` and `MOST_STEP_BUDGET` so that `IDLE_TARGET_MILLISECONDS` of each frame stays idle; the window loop feeds it the time spent waiting for the display (when the driver can wait for a present), the bench the time left before its 60 Hz pause. The nearby set is given at least half of what is left after painting ahead, where it used to get only what the streamer had not used the frame before. Scan windows and the nearby set's paint batches are smaller (`SCAN_WINDOW`, `PAINT_BATCH`), so a batch that starts just before the deadline overruns it by less, and a scan window with nothing pending in it starts no parallel pass at all.

*Tried and taken out.* A table of node states for nodes that are not in the graph, shared between the workers' views so that each is computed once: it cut worker time a little and cost the main thread a sixth of its time inserting into it. The main thread is the scarce one, so the workers go on recomputing.

*What it bought,* same world, same cutoff (the numbers were reported to the owner and are not kept here; run the bench for today's):

- The load from spawn settles about eight times sooner and in about a tenth of the memory.
- The faces drawn fell to about a thirtieth; the surface's own faces are the same ones as before.
- Live tile records and tiles run during a load fell to around a hundredth.
- The evict phase is a small fraction of what it was, and a rebuild of the nearby set in flight takes a fraction of a second.
- In flight a few frames in a hundred run late, where a third to a half did, and the visible chunks within 4 units are all but a handful loaded at any moment. "Visible" leaves out the underground that is left unloaded on purpose: about a quarter of the chunks within 4 units of a camera on the surface are buried more than 3 units away.
- The scripted `live/` sessions are all at or under their times from before this conversation's work, and `bench-gen`'s parameters and `bench-drive` are under their times from after package A. Its voxel time is unchanged: nothing in that path was touched, and six runs at the end spread over a few percent around the earlier readings.

*Still open.*

- Single frames still overrun by a few milliseconds: each slow frame the bench lists is one unbudgeted batch in the streamer or the nearby phase (a scan window's parallel pass, a tile batch, the keep pass of a rebuild).
- The workers still idle most of the time: the main thread is the only feeder. What it still does serially: applying painted tiles, finishing structure for nodes the painter did not reach, planning buildings, creating nodes.
- Horosphere discovery for nodes outside the graph is recomputed by every job (12 percent of worker time in the last profile).
- The exact relief span is recomputed on each scan of a node with fresh chunks, on a worker; it could be kept on the node.
- The load cutoff, the fog's reach under the ground (which sets how far the underground loads from above: 2.6 units) and the idle target are tunings the owner may want different.

Each package gives: what it is for, which answers it serves, what it reads first, a design, steps, what it states as laws, how it is checked, what it must not touch, and what is still undecided. Letters are names, not an order; section 6 has the order.

### A. A crust that varies (decision 1)

**For.** Wild ground with the full deep under it in some places and the void two edges down in others.

**Reads first.** `source/common/worldgen/horospheres.d` (`HorosphereKind.crust`, `Ground.crust`, `rootCrust`, `crustOf`, `isInBand`, `probeMayHoldContent`, `underAt`), `source/common/worldgen/generation.d` (`isBelowCrust`, `isWithinCrust`, `generateFlat`, `generateTerrain`, `generateTerrainVoxel`), `source/common/worldgen/climate.d`, `source/client/structures.d` (`crust`), `plugins/planet/plugin.d` (`ROOT_CRUST`, `RISEN_CRUST`, `crustUnder`), `plugins/caves/caves.d` (`Bed`), `plugins/lattice/lattice.d` (`hang`).

**How it is today (Read).** The crust is one number per ground kind: `HorosphereKind.crust` and `Horospheres.rootCrust`, copied into `Ground.crust` by `groundsOf`. Three places test a cell against it, all in the form `altitude > -(crust + UNDERSIDE_SWING * relief)` with the relief taken at the cell: `generateFlat`, `generateTerrainVoxel`, and the chunk tests `isBelowCrust` and `isWithinCrust` (with the chunk's highest and lowest relief). `isInBand` in `horospheres.d` decides whether a node may hold content at all, and has a second band around the underside. The planet passes fixed numbers (`ROOT_CRUST`, `RISEN_CRUST`) and its edge tile compares against them (`crustUnder`); `caves.Bed.bottom` and `lattice.hang` take fixed depths too. The look under the crust is an `Under` entry at a fixed depth.

**Design, first build: thickness as a field.** The swing of the underside already comes from a climate field read at the cell. Do the same for the thickness.

1. `climate.d`: a new slow `Process` (call it `SHIELD`, with `keep` near 1 so that a region is many cells across) and a `shield` member in `NodeClimate` and `Climate`, carried exactly as `strata` is: `fromParents`, `climate()`, `lerp`, `mean`, and the lowest and highest of `CubeClimate`. The literals of both structs are positional, and a new last member with a default does not break a literal that omits it, so every literal has to be found by reading, not by the compiler.
2. `horospheres.d`: a ground kind gets a second number, the thin crust, beside the thick one. One function, `crustAt(ground, climate)`, turns the shield value into a thickness between the two (`smoothRamp`, already in the file) and is the only place a thickness is computed. `isInBand` takes the node's shield with a slack, as it takes relief with `RELIEF_SLACK`.
3. `generation.d`: the three tests call `crustAt`; the chunk tests pass the chunk's extreme climates.
4. `plugins/api/api.d` (ABI goes up): `crust` takes the thick and the thin number, or a second call sets the thin one. `probeCrust(site)` answers the thickness in edges at a site, so tiles can ask. `StructureHost` answers for the root, `TileHost` for the ground the tile runs over (`host.horosphere`), both through `ensureClimate`.
5. Look and fog: an `Under` entry needs a way to say "below the crust" in place of a fixed depth, and `underAt` in `horospheres.d` then measures the crust at the camera with `loadedClimateAt`.
6. `plugins/planet`: thick and thin become settings (`settings.conf`), `crustUnder` goes, and the edge tile asks `probeCrust`.
7. `plugins/caves/caves.d`: `keeps` refuses a vertex that is not safely inside the crust at that place. `plugins/lattice/lattice.d`: `hang` paints a beam whose ends are both in the open.

**What that picture is, honestly.** The field lives in space, not on the ground: a cell reads it where the cell is. Far down, sideways lengths are stretched (45 times at 4.5 units), so the pattern of rock and open down there is as wide as the field's own reach and is not the shadow of a patch of surface. What comes out is a roof two edges thick everywhere, and under it, between two and 5.6 edges, great masses of rock with open void between them. That is closer to "island worlds that connect" than to shafts with walls. It gives package B its openings for free: caves end wherever a rock mass ends, on its underside and on its flanks.

**Design, second build if the first does not read as shields and windows: thickness by the ground above.** Look the thickness up at the ground node over the cell. `ensureGroundNode(view, slot, horosphere)` already walks from any node to its ground node and is how tiles find a node's ground faces. Cache the value per node and interpolate it over the eight nodes around a chunk as `CubeClimate` does. A window is then a true column that widens as it goes down. It costs a walk to the ground for every deep node, in thread views too.

**Steps.** Build the first design. Add three views that look sideways from 2.5, 3.5 and 4.5 units down and one that looks up from under a thin place. Show the renders to the owner (question 1 in section 8) before anything is built on top.

**Laws.** Within some number of edges of spawn there is a place where a body let go three edges down is in the open, and a place where a body let go there is in rock. The rock bands, veins and cave themes below 2.6 units still exist somewhere near spawn (so the deep geology was not lost).

**Checked by.** The full list in section 4. `world-digest` is expected to change only if it reaches below two edges; record whichever happens. Bench before and after: more nodes fall in `isInBand`.

**Must not touch.** A ground with one crust number must behave as it does now. A world that never calls `crust` must not pay for the field.

**Note for whoever reads the geometry.** A risen ground faces its parent: `risenPlaneOver` builds its plane with the normal pointing back along the rise. Its solid side is the far side, so its crust's underside faces outward, away from everything below, and what hangs "under" a risen ground hangs beyond it.

### B. Caves that open downward, and the ways back (decisions 3 and 4)

**For.** A way from the caves into the void, and several unmarked ways back.

**Depends on.** A, for `probeCrust`.

**How it is today (Read, `plugins/caves/caves.d` and `plugins/lattice/lattice.d`).** A cave network is a forest over honeycomb vertices. `parentOf` picks each vertex's way up, `keeps` decides whether a vertex has a chamber (its depth inside `Bed.top .. Bed.bottom`, and a roll per depth band), and `opennessOf` walks up the parents until it reaches a sinkhole, a well or an opened head. `Bed.bottom` is fixed: 5.2 edges under the root, 3 under a risen ground. A steep link is carved as a shaft with spiral treads, a gentle one as a passage. In the lattice, a vertical pole whose edge hash rolls under `stair-odds` (0.2) carries a spiral stair, and platforms sit where `probePlatform` says.

**Design.** Everything below is decided from vertex and edge hashes, so the cave tile and the lattice tile agree without talking.

1. The bed's bottom follows the crust. `keeps` asks `probeCrust` at the vertex and keeps it only while it is safely inside the rock there.
2. Three kinds of opening, each with its own odds in `plugins/caves/settings.conf`:
   - **Breach.** A chamber close enough to the underside simply shows the void, because the rock ends. No code beyond 1; the margin in `keeps` sets how often.
   - **Drain.** A kept vertex whose neighbor straight down is in the open gets, by the hash of that edge, a shaft through its floor to where the rock ends. Some drains carry treads (the existing shaft form) and some are bare chutes: one can be climbed, the other only fallen through.
   - **Mouth.** With the first design of A the rock has flanks. A passage from a kept vertex toward a neighbor that is in the open is carved, by hash, until the rock ends, and opens on the face of the rock mass.
3. Something to arrive on. Where a drain or a mouth ends, the lattice raises a platform. `lattice.d` cannot import the caves, so the planet, which compiles both, hands `lattice.beam` a predicate beside the root vertex it already takes (`Root`), and `probePlatform` asks it.
4. The ways back, none of them marked, each rolled on its own so that no one of them is the exit:
   - stair drains, up into a cave network and from there to a sinkhole or a well;
   - pole stairs that reach the underside and go on up through the rock as a well, ending in the nearest kept chamber above (`stairDown` already builds that stair, downward);
   - wells under grounds that have both wells and a crust (vaults today), going on past their cave to the underside;
   - whatever a void world brings of its own (G).
5. "almost doesn't feel so": no lights, no signs, no even spacing. The odds are tuned so that the nearest way back is usually not the way a player came down. The headless censuses (`./caapi-headless --help`) are the place for a count of links per cave vertex.

**Steps.** 1 and breach first, then drains, then mouths, then the lattice platforms, then pole stairs. Render after each.

**Laws.** There is a cave chamber near spawn from which a body dropped through the floor comes out under the crust. A body that follows a stair drain upward from the lattice ends in a cave. Scripts cannot call plugin code, so the forced sinkhole's network has to be one that holds a drain: the planet can search for it when the world is built, the way `caves.entryNear` already searches for a sinkhole with a branching cave, and lay route stops down it.

**Checked by.** Section 4, plus views of a breach, a drain from below and a mouth.

**Must not touch.** The `caves` world on its own (no crust: nothing changes there). The sealed beds' tops.

**Undecided.** How sparse the ways back are (section 8).

**From the scout, read in the code.** These correct the design above; where they differ, they win. Nothing here is built, and none of it starts before package P.

- **A probable fault in what package A left, inferred and not rendered.** The cave tile keeps a chamber by a test at its vertex only, but the underside can jump between two edges and 5.6 within a fraction of an edge sideways (the shield's thresholds are 0.1 apart from zero and a node step carries twice that in noise). A chamber's dome reaches 11 cells and its passages 10. Where one meets the flank of a rock mass, the tile paints its floor and ceiling skins, formations and treads into cells that generation left open: ice, cave grass, light panels and limestone hanging in the void. No margin can fix it, because the tile cannot know where generation puts the boundary cell by cell.
- **The fix is a third way to paint: only into what is solid.** One more member of `Cover` beside over and into air, one branch in `materialAt` in `building.d`, an `Api` member for it (ABI goes up) and a turtle method, and the carve code choosing it for floors, ceilings and formations. With it, breaches, drains and mouths all end exactly where the rock ends. This is the first piece of B and it stands on its own as a repair.
- **What "open" means.** Under wild ground a network is painted only if its chain of parents reaches a sinkhole: the forced one, or one in fifty surface vertices. So open networks are exactly the trees under sinkholes. Under sealed beds a network can be painted without being joined to the surface at all (an opened head).
- **`probeCrust` is not a column's bottom.** It answers the threshold between rock and open at the site's own point, and one column can go rock, open, rock several times between two and 5.6 edges. Only "is this vertex in rock" means something, and it can only be asked at vertices.
- **Breach.** Straight down, a chamber never shows the void today (its floor is at least twelve cells above its own threshold). Once skins cannot hang, a band is added: a vertex up to a quarter edge past its threshold is kept by a roll, so its floor is open while its dome still has a cap, on condition that its parent is kept in the ordinary way (or level links would chain galleries of floorless chambers).
- **Drain.** Only in networks that are already painted and only under open beds: a drain does not open a closed network (openness is walked upward only, and a network open only from below does not lead home). The vertex is kept in the ordinary way; its way down lies on its owner line (about one vertex in three; without that, the lower half of the shaft falls in a box nobody paints); the link is steep enough to be a shaft; the vertex below is in the open by the lattice's own test (which moves to `turtle.d` so both use one definition); and the edge's hash rolls under the drain's odds. A second roll makes it a stair or a bare chute. The shaft stops three cells short of the vertex below, so it stays off the platform there.
- **Mouth.** The same shape sideways: a passage along the owner line toward a neighbor in the open, cut three cells short. The lattice already hangs that edge in the same tile, so a girder runs out of the passage floor to the neighbor: a way to walk out. Whether a body can walk a girder two cells wide has never been tested.
- **Something to land on.** The planet passes the lattice no root today, and a bare function pointer cannot carry what the caves would need. So: flags per end, worked out by the planet's edge tile from a new function in the caves code, handed to the lattice, which raises a platform there and leaves off the lantern, tree or hut it would otherwise put up the pole (they would fill the chute). The same glue tells the lattice not to run a beam into an open chamber, which is also the cure for joints in the floors of deep chambers. It runs for every edge near the underside and has to be measured.
- **Ways back.** Stair drains. Pole stairs come free where a bare chute's edge also rolls a lattice stair. Deep wells under the vaults: a port's well that goes on down while it is in rock and hangs its last edge. Proposed odds: a half for drains, mouths and breaches, a third for deep wells.
- **They will be sparse whatever the odds.** The scout's estimate, on the back of an envelope: about 0.1 to 0.2 links within three steps of a landing, because only the two in a hundred trees under sinkholes are open at all. "Not exactly one way out" needs about ten times more open cave near the underside, and that is the owner's choice: more sinkholes, wells into the caves under wild ground too, or a new narrow opening. A census should be taken before choosing.
- **The forced route.** The planet does not lay the cave route today, only the caves world does, and the planet's route already starts with the road's and the landmarks' stops, so a script needs to follow a leg and not the whole route. Searching a sinkhole's tree for a drain when the world is built costs up to a second in the worst case at every start of the default world, and flattening the sinkhole moves the underside under it (calm scales relief, and the underside carries half the relief). Both have to be measured under the speed rule.
- **The pieces.** A census of open networks, flank cases and candidate openings near spawn, which needs no API change. The paint-into-solid repair. Landings, and the lattice kept out of open chambers, with the breach band. Drains. Mouths. The route and the two laws. Deep wells under the vaults. Pole stairs through solid rock, optional.

### C. The fall and the way back from it (decision 2)

**For.** A fall that is real, a respawn that keeps most of the inventory, and the loss rule in threes.

**How it is today (Read).** `gravityAt` in `horospheres.d`: with only the root ground in reach the pull is the root's "down" at full strength at any depth, so under the root crust a body falls until a block stops it. Nothing in `Game` ends a play: there is no health and no death. `Game.placeAtSpawn` puts the body at the blueprint's entrance, or at a found spawn, and settles it; `Game.startOver` empties everything a player has. `Game.beacons` holds the beacons the player placed. Notes are `NoteKind` values posted with `post`. **Unread:** `Game.step` itself, `source/common/inventory.d`, `source/client/hud.d` (where a note's words are), `source/client/save.d`.

**Design.**

1. **The world has a bottom.** A world names, per ground, the depth below which it builds nothing: `api.abyss(ground, edges)` (ABI goes up), stored beside the crust. Two things use it. Tiles are not run for nodes wholly below it, which gives the void the named reach that `CLAUDE.md` asks of anything that grows outward. And a body below it is lost. A depth is chosen over "has fallen for so many seconds" because a long fall would have to generate everything it passes.
2. **Lost.** In `Game.step`, in walk mode, when the body is below the abyss of the ground that has it (`nearestGround` and `heightAbove` already measure that), the play calls `wake`.
3. **Wake.** The body is put where it wakes, standing, with no speed; the thread is kept (it still leads to the edge that was fallen from); the body's chemistry is left as it is. Where, by the owner's answer: the last thing the body stood on before it entered the place. So the play remembers the last position at which the body was on the ground and not yet below a crust, and wakes there. Standing on something inside the void does not move that mark; standing in a cave does. If there is no mark yet, the world's entrance (`placeAtSpawn`).
4. **The loss.** For each kind of item, counted over all slots: three or more held, lose a third, rounded down; one or two held, lose nothing. 3 loses 1, 8 loses 2, 9 loses 3, 81 loses 27. Taken from the last slots first. A living stack's kind includes its genes, as `isSameKind` has it. Upgrades are not items and are kept. Compounds and doses are left alone unless the owner says otherwise. Creative rules lose nothing. This is one function on `Inventory`, with a unit test.
5. **Said.** A note that names what happened and how much was lost, and an `Event` for mods beside `Event.broke`.
6. **Saved.** The mark is one position and goes into the save, so that a play saved in the void still knows where it wakes.

**Laws.** A body that falls past the bottom of the world wakes at the world's entrance, standing. It keeps every kind it held one or two of and loses a third, rounded down, of each kind it held three or more of (the prediction is computed from the counts, not recorded). Under creative rules it loses nothing.

**The rig.** A debug structure in `plugins/fixtures`: wild ground with a crust one edge thick, no void world, an abyss three edges down. The test lets a body go under the crust.

**Checked by.** Section 4. The unit test in `source/unit/`. `live/` tests still inside their time.

**Must not touch.** Noclip and fly modes never wake. A world that names no abyss behaves as now.

**Settled by the owner since.**

- **Not one mark but a short trail of them.** "If it's not there go to the block before it. If nothing is there go to world spawn". The play keeps the last few places the body stood before it entered the void (nine, each at least a block from the one before), newest first. Waking tries the newest; if nothing is there to stand on, the one before it; and so on. If none holds, the world's spawn. Each mark holds its graph reference, and all of them are saved.
- **The loss counts by strain, and is forgiving.** "be forgiving, when the player only has one of a thing, even if they don't know it". A strain the player holds one or two of is untouched even when it sits in a bundle with many others. This is what the scout's function already does.

**From the scout, read in the code.** These correct and complete the design above; where they differ, they win.

- **The laws.** The body wakes where it last stood, not at the entrance. A second law covers a play with no mark yet: that one wakes at the entrance.
- **Lost.** The check goes in `Game.step` right after `traveled = traveled + stepped.traveled;` and before `layThread()`. The abyss is measured as the crust is: the raw distance from the ground's plane, with no relief and no gravity sign, so below means `altitude < -abyss`. A function `isBelowAbyss` beside `underAt` in `horospheres.d` takes `nearestGround` and compares; the step first makes sure the node's state and horospheres exist, as `ensureGravityAt` does. `Game.altitude` is the wrong number (root only, and signed by gravity).
- **A long fall today.** There is no top speed. The controller's substeps grow with speed. In on-demand supply every step generates the whole reach around the body and nothing is evicted, so a deep fall in a test is slow and keeps every node; in streamed supply the body stalls and its speed resets. Rigs keep the abyss shallow.
- **Skipping tiles below the abyss** belongs at the top of `visitTilesAt` in `tiles.d`, which serves both the cover path and the paint-ahead path. A node is skipped when the root's plane is farther above it than the root's abyss (with `NODE_RADIUS` of slack), the same holds for every non-upright ground near it, and no upright or sunken column is near (the library's stacks run down without end). This changes which nodes visit which tiles, so `check-repaint` decides whether it is right.
- **The mark.** Marked on a step when the mode is walk, `footing` is grounded, and the body is not below the underside of its nearest ground, by the same test generation uses (`altitude > -(crust + UNDERSIDE_SWING * relief)` with `loadedClimateAt`). Not marked while hidden blocks are revealed (`reveal.touchable`), since that ground is air once the dose fades. It is a `Maybe!Position` in `Game`. A `Position` names a node by id, and a node with no reference can be evicted, so the mark holds a graph reference the way beacons do (`reference` on the new node, `unreference` on the old) and is cleared in `rebuildWorld`.
- **Wake.** `closeScreen` first (it puts the `carried` stack back, so it is counted), clear `mining` and `eating`, then `placeAt(mark, Length(0))` and one bounded settle of the kind `settleToGround` does inside its loop. `settleToGround` itself loops until it lands and has no bound, so if the ground under the mark is gone (mined out, or hidden) it would fall and generate forever: when the bounded settle does not land, use `placeAtSpawn`. Then `world.settleFogColor()` and `updateView()`.
- **The loss.** `isSameKind` compares only the first strain of a living stack, so it is the wrong tool. `Stack.countLike` and `Inventory.countOfKind` count one kind (the item, plain or living, and one strain's genes, whatever the sorting). The function reads kinds from a copy of the inventory taken before anything is removed, takes `count / 3` of each kind from the last slots first, and returns the total. A stack of several strains is several kinds, so eight different unidentified flowers in one stack lose nothing: that is a question for the owner and it meets the bundle question in M.
- **Save.** `readGame` refuses any other `SAVE_FORMAT`, any other `ENTRY` and any other world, so the project changes the format and does not migrate. `SAVE_FORMAT` goes from 10 to 11, the mark is written as a face path from the root as beacons are, and `save/round-trip` gains a claim that a save keeps where the player wakes. Raising `ENTRY`, which every engine package does, already refuses every older save.
- **Said.** `describe` in `hud.d` is a `final switch` over `NoteKind`, so a new kind does not compile without its words. A new `Event` goes at the end of the enum in `plugins/api/content.d` and is fired after the loss.
- **The API.** `abyss` is appended to `Api`; `abyssOf` mirrors `crustOf`; the world's host copies `crust` (refused once growing, refused unless above zero, by tag for every kind already registered, so it must be called after the kinds exist, which nothing checks today). An abyss that is not below the crust should be refused. `HorosphereKind` is built positionally in `StructureHost.horosphere` and all through `source/unit/horospheres.d`.
- **The rig.** A debug structure `abyss` in `plugins/fixtures`: `crust` of one edge and `abyss` of three on the root, nothing else; a plain root is flat fill, which keeps the depths exact. The test stocks one, two, three, eight and 81 of five plain kinds and a living stack with two strains (four and two), walks a step to set the mark, noclips down past the crust, switches to walk, and steps until the wake note (`notedSince` exists in `tests.d`). A creative run loses nothing; a run with no mark wakes at spawn; a fly-mode run never wakes.
- **The planet** gets its abyss below the lattice, and `structure/void` must still pass.

### D. Ports that belong to their ground (decision 5)

**For.** A port decided by a feature of the place and dressed by its ground.

**How it is today (Read).** `probePort(view, site, over)` in `source/client/structures.d` rolls the vertex hash against one number for the whole world (`blueprint.portOdds`, set by `api.ports`), and refuses the world's root vertex, a risen ground's foot and any vertex where a ground rises. Who asks:

- `plugins/blocks/blocks.d`: `portGap` (streets stop short), `lotAt` (paves around the hole with `paveAroundPort` and plants), `probeIsland` (no island block at a port corner);
- `plugins/rooms/layout.d` and `rooms.d`: `QuarterKind.lobbyWithWell`, `hasWell`, `hasPort`, `lid`;
- `plugins/vaults/plugin.d`: `clearingAt` and `Clearing.port`;
- `plugins/caves/caves.d`: `probeWell`, `well`, `stairDown`;
- `source/scripts/walk.d`: `ensurePort`, for tests and views.

**Design. The ground decides, and everyone else asks the engine.**

1. `api.ports(odds)` gives way to a rule per ground kind: the world's structure registers, for a ground, a function that says whether a vertex is a port, with data, the way it registers a tile (ABI goes up). The engine keeps its three refusals and then calls the rule of the ground the asker is over. A rule is handed the asking host's `Api`, so it can read hashes on a worker thread like any tile.
2. A rule is a pure function of the vertex. It may not use `pick` or `random`, which belong to the tile that happens to be running. That has to be stated where rules are registered and, if it can be, refused.
3. The rules, each living with its ground's shared code and each driven by content:
   - **City** (`blocks`): every `blocks-district` gets a `ports` share. The vertex takes the district of one canonical face among its four (lowest face hash, as `probeOwner` does), and is a port when the vertex hash rolls under that share. `works` gets a high share, the others none or nearly none.
   - **Backrooms** (`rooms`): every `rooms-biome` gets a `well` share, high for `sump` and `cellar`. The vertex takes the lowest level's biome at its canonical face.
   - **Vaults**: a vertex is a port when its canonical face holds a spire (`Spire.shikhara`) and its hash rolls under a share in `plugins/vaults/settings.conf`.
   - **Anywhere**: the flat roll survives as one more rule, offered by the caves code, for worlds with no feature to hang a port on. "Both, as variety."
4. Dressing, by the ground's own tile around the hole: in the city a pit in a works yard with a kerb, railings and a frame over it; in the backrooms a walled stairwell with a doorway and a lit sign; in the vaults a broken ring of inlay with rubble. Under the hole, the well's lining and stair take materials named per ground in the caves content.
5. `walk.ensurePort` asks through the structure host of the running world, since a rule needs an `Api`.

**Steps.** Engine and API first, with the flat roll re-expressed as a rule so that every test still passes unchanged. Then one ground at a time: rule, dressing, view, render.

**Laws.** `structure/well` keeps holding. For each ground: a port exists among the vertices nearest the root, and what stands around it is that ground's dressing (the material looked at is the dressing's). A law that a port lies in the works district needs the district to be visible to a script; if nothing cheap offers that, a render stands in and no law is stated.

**Checked by.** Section 4, with `check-repaint` on city, backrooms, vaults and planet the ones that matter most.

**Must not touch.** The three refusals. The way a tile leaves the column open.

**Undecided.** Whether a thinning roll is wanted, or every such place has a port (section 8).

### E. The hidden stair to the vaults (decisions 7 and 8)

**For.** A way onto a ground with no bridge that only a dosed body can use.

**How it is today (Read, `plugins/connector/connector.d`, `connector.content`, `plugins/fixtures/plugin.d`).** `Style.hidden` exists: mist-stone floors, gallery and treads, a mist-light core (`connector:hidden`). No `connector-pair` gives it a share, so it only appears where a rig forces it (`hiddenstair`, a risen city). Every style, the hidden one too, lays plain concrete aprons at both doors (`doorway`, `materials.landing`). `connect` builds only when both grounds are `Bridge.built`. The upper ground's tile is what calls `connect`, at its foot; the vaults' `hall` never does. Tests `hidden/climb`, `hidden/reveal-inside` and `hidden/unrevealed` run on the rig.

**Design.**

1. Two separate facts about a ground, in `connector-ground`: how a stair comes up to it (`bridge`: `built`, `hidden` or `none`) and whether stairs leave it upward (a second field; the vaults say no, which is decision 8 as built). `connect` builds nothing if the lower ground lets nothing leave; forces `Style.hidden` if the upper ground's bridge is hidden; otherwise rolls as now.
2. The hidden style leaves no plain trace: its aprons take the hidden palette's floor. Whether the lower ground still clears a plaza or a lobby where a hidden stair rises is a choice; an empty plaza is a fair clue in the city and nothing should show on wild ground.
3. The vaults call `connect` at their foot. The foot test (`probeFoot` in `blocks.d`) moves to where both can use it, and one of the four quarters around the foot owns the call (lowest face hash). `plugins/vaults` gains the connector as a compiled-in dependency in `dub.sdl`.
4. The top of the stair. The connector's top floor in the hidden palette is mist stone, so to an undosed body in the vaults it is a hole in the floor with a long drop under it. That is consistent, and it makes the stair a one-way exit for the undosed. Look at it in a render before keeping it; the alternative is a plain vault floor with a mist-stone hatch.
5. A rig for it registered by the vaults plugin itself (the hall code is not shared code): vaults rising two edges over wild ground with a routed hidden stair.

**Laws.** Undosed, a body that follows the route does not leave the lower ground. With mist sight it follows the route up and stands on the vaults' floor. Nothing plain is painted at either door (the block under the lower door is the lower ground's own).

**Checked by.** Section 4, with the `hidden/` tests and `check-repaint` on vaults and planet.

**Must not touch.** The other four styles and their shares.

### Z. Shared ground for the engine packages

A, C, D and F each add to `Api` or `Registry`, and G3 adds a `SitePart`. They are built one after another, each raising `ENTRY` by one, each leaving every plugin rebuilt and every test green before the next starts. None of them is started while another is unfinished.

### F. Void worlds: the interface (decision 9)

**For.** More than one void world: named by the ground above, layered by depth, and showing what stands above.

**Depends on.** A for `probeCrust`, C for the abyss.

**How it is today (Read, `plugins/planet/plugin.d`, `plugins/lattice/lattice.d`, `source/client/tiles.d`).** One void world, wired by hand: the planet's edge tile calls `lattice.hang` for the root and for the grounds in `HOLLOW_TAGS`, and `lattice.deepen` adds the look. The lattice is shared code compiled into the planet. An edge tile runs once per filled ground near its edge. There are no face tiles in the void: face tiles belong to ground kinds.

**Design.**

1. **A void world is registered, like a rising kind.** `registry.addVoid(name, kind)`, where the kind holds a tile function for one edge, data, and a look and fog (ABI goes up). A void world is shared code in a plugin directory of its own with a `-mod` library beside it, as the lattice is. The lattice becomes the first one.
2. **The ground above names its voids.** In the content of the world that owns the grounds (a new `planet.decl` and `planet.content`): for a ground kind, a list of layers, each naming a void world and how thick it is in edges.
3. **Depth makes layers.** Under a ground the layers stack downward from the underside. The planet's edge tile works out how far below the underside the edge's lower end is (pen heights and `probeCrust`) and hands the edge to the void world of that layer. Layer boundaries are roughened by hash so that two worlds interleave where they meet. Below the last layer is the abyss.
4. **The surface shows through.** A void world can ask what comes through the crust over a vertex: a helper in `plugins/turtle/turtle.d` climbs the vertical edges from a void vertex to the ground vertex above it (the way `caves.probeWell` climbs two), and the facts there are hashes anyone can compute: a port, a sinkhole, a grove. Things that should hang through are extended by their own code where the crust is thin: grove footings, wells (package B), and whatever a later package adds. The void world ties onto them, for a start with a platform under each.
5. **Which edges are in the open** is decided once, in the planet, not in each void world.
6. The look under a ground changes per layer, through the "below the crust" form of `Under` from A.

**Laws.** Under the default world's wild ground the lattice is the first layer and a second world lies under it: a body let go a named distance below the underside lands on the second world's materials. A world with no layers has no void content.

**Checked by.** Section 4, and a bench: one more lookup per edge tile.

**Must not touch.** The `lattice` world on its own.

### G. Void worlds: the nightmare (decision 10)

**For.** The void worlds themselves. One sub-package per world, each a plugin directory of its own, all built on F.

**The brief every one of them shares.** It is "more nightmare than a place". Abstract, too large, patterned, wrong in small ways. No friendly marks. Decided by hash. Bounded work per edge. And enough to land on that a fall usually ends on something, since below the last layer a fall is the end of the trip.

**What an edge tile can do (Read).** It paints boxes within 24 cells square around a site's line (`columnOf`, `boxRefusal`), along that line as far as it likes, and it can move its site; what stops it is that it may not paint a node that is already finished. It can draw strokes (`TileHost.draw`), and it knows hashes of its vertices, its edge and the faces around it. It cannot place or claim.

**G1. Other fillings of the lattice.** `lattice.d` only. A weave, in content: how many edges are kept, whether there are diagonals, doubled beams, beams that stop half way, the odds of platforms and stairs. Which weave is used varies by cluster and by depth. Cheapest of all, and it comes first.

**G2. Patterns that break.** A filling with no randomness at all, the same motif on every edge by its direction, and then, at long odds (1 in 81), a motif turned, missing, doubled or replaced, with the breaks gathered in clusters so that a stretch is wrong together. It can be a weave of G1.

**G3. Structures too large to take in.** The owner's meaning: "The fear of structures larger than you can comphrend." So the test of a G3 structure is that no view of it shows its extent: it runs out of sight in every direction it has. Two ways to be that large:

- **Endless beams.** Every edge lies on a straight line of edges, and the engine already has a canonical key for that line (`canonicalOf` and `LineKey`, used by `TilePainter`). A hash of the line, offered to plugins as a new `SitePart` (ABI goes up), lets a void world thicken every edge of a chosen line to the full column: a girder 24 cells square that never ends, a few of them hollow with a corridor inside.
- **Hanging columns.** `api.sunken` already opens a column downward from a ground vertex (the library's stacks). A colossal pier or chain hung from wild ground through the crust is that form with a different tile.

**G4. Fractals.** A branching that repeats at every scale: a trunk that splits at each vertex into thinner limbs, the thickness set by how many steps out from the trunk a vertex is in a forest made of hashes. The caves already build such a forest (`parentOf`) and carve it; this paints it. A sponge in powers of three fits a column of 24 cells for one level only (three cubes of 8), which is why this is the fractal proposed.

**G5. Sparse islands, and islands that connect.** With the first design of A the deep is already islands of rock with caves and ore inside. Beyond that: small floating islands drawn with strokes at about 1 vertex in 27, a turf top and a tree, and a bridge along an edge when both its ends are islands. Larger islands that carry something (a hut, a garden, a station) wait for L.

**G6. The dangling maze.** A flat maze hanging below the crust from one point. The owner's picture of it: "closer to a rafter with no railings. Not walls as much as a minecraft-ish mineshaft." So it is not rooms and not the backrooms' maze level. It is a maze of narrow walkways: beams a cell or two wide with posts and braces, open on both sides, over the drop. The maze is in which walkways exist and which are missing, not in walls. It is flat in the sense the code gives "horosphere" (a plane along cell faces). Planes spread apart, so a plane opened a few edges below a ground vertex is nearest the crust at its foot and falls away from it everywhere else: it dangles.

- **Engine.** Today a plane rises above a ground vertex and faces back at its parent (`risenHorosphere`, `risenPlaneOver`). A hung sheet is the same construction through the ground, downward. That touches `risenHorosphere`, `probeRiseClear` and `probeClearOfAncestors`, `ensureAirSideNode`, `probeRisenSide` (which side a ground's tiles paint), and the limit of four grounds near a node (`MOST_GROUNDS`).
- This is the one sub-package with real engine risk. It starts with a design debate, not with code. The debate includes whether a maze of rafters needs a hung plane at all: walkways along the edges of one face-plane of the honeycomb might be picked by hash from an edge tile, if a plane can be given a canonical hash the way a line can.
- The tile, either way, is new shared code: walkways, posts, braces, gaps. It falls under the fall (C): a missed step is a real fall.

**Order within G.** G1 and G2, then G5, then G3, then G4, then G6.

**Each sub-package states** one law (what a body let go in its layer lands on), adds one view that is rendered and looked at, runs `check-repaint` on planet, and is benched.

### H. Under built ground (decision 11)

**For.** An underground that the ground above writes, and sealed caves that keep what open ones lose.

**Depends on.** D, because the ports are the ways down into it.

**How it is today (Read).** Under a built ground: soil, then the same rock bands and veins as anywhere, then sealed caves from 1.9 edges down (`SEALED_TOP`). What the grounds' own tiles paint below the surface is shallow: lots and ponds a cell or two down in the city, the levels of the backrooms about 25 cells down, the floor only in the vaults. Cave themes are content (`caves-theme`): `caves:glow` hangs `base:tide-stone`, `caves:ember` has `base:ember-stone`. **Unread:** `source/common/biology/air.d`, `plugins/buildings/`, `plugins/rooms/levels.d`.

**Design.** Four sub-packages in four different plugins, so they do not collide. Plain geology stays as what lies between and below them.

- **H1, the city.** Basements under buildings. A service tunnel under each street, with pipes and lamps, meeting at the crossings. Under the works district, cisterns and pump rooms, which is where the ports of D come out. All of it worked material: steel, concrete, glass. "Built worlds as ore."
- **H2, the backrooms.** The levels go on down: more entries in `rooms:materials.levels`, as far as `MOST_LEVELS` allows, then raising it. Content first, code only if the limit is in the way.
- **H3, the vaults.** Crypts: under some halls a lower chamber with niches, reached by a stair in the floor, in the hall's own palette.
- **H4, sealed means kept.** Two parts. A sealed bed takes its theme rules from a sealed variant of the theme where the content has one (more hanging stones of the hidden families, more light). And the air in a sealed cave is richer: the simplest carrier is the `Under` entry a world already registers per ground and depth, which could name gains for the three gases; a collector then reads them. That second part needs `air.d` read before it is designed.

**Laws.** A body let go under a city street lands in a tunnel (its floor is the tunnel's material). A collector in a sealed cave gathers faster than one on the ground above it, by the gain the content names (the prediction is computed). The backrooms have a level below the mazes.

**Checked by.** Section 4. A tile has no limit on depth; its limit is that it may not paint a node already finished, so H1 and H3 keep to the columns at their face's own vertices and the edges between them.

### I. Backrooms from several tables (decision 12)

**For.** Regions with edges, rare rooms, levels and uses at once, from tables a mod can add to.

**How it is today (Read, `plugins/rooms/layout.d`, `rooms.d`, `rooms.content`).** One roll per region and level picks a biome: `tileAt` takes `strongestNear(face)` and indexes the level's biome list with it. A biome is a row of materials and odds (`big`, `open`, `skylight`, `pillars`, `pool`, `court`, `nowhere`, ...). `planOf` then picks each quarter's plan: maze, lobby, rooms, solid, rings, chapel, or one of pillars, pool and court by the biome's odds. Three levels (offices, houses, mazes) hold 8, 5 and 5 biomes.

**Reading.** "minecraft's multiple table worldgen" was taken as two things Minecraft does: a biome is looked up in a table over several fields that vary independently, and a structure is assembled from weighted pools of pieces. The owner's correction: "Yes, but onlt a bit. You don't have to, and should not, do exactly that... just that's how I mean doing multiple strategies. You can't make it a tree, it's a space of parameters". So Minecraft is the hint and not the model. What is wanted is several strategies at work at once, and subtypes that live in a space of parameters, never in a tree of choices where one roll decides the next. The design below keeps to that and should stay small: where a table is not needed, there is none.

**Design.** Several tables, each of which a mod can add rows to, in place of one list.

1. **Fields.** A few hashed fields, each at its own scale and with its own salt: age (new to ruined, three rings wide), damp (dry to flooded, two rings), light (bright to dark, two rings), grandeur (cramped to vast, one ring). Level is the fifth. `strongestAround` and `strongestNear` give one and two rings; three rings needs a third helper in `turtle.d`, and its cost in hash probes per tile has to be measured.
2. **The subtype table.** Each `rooms-biome` says where it lives on each field, as a range. The tile takes the biome whose ranges hold the point, the nearest one if none does. A new biome is a new row with its ranges. Nothing is closed off.
3. **Plan pools.** A biome names a weighted pool of plans in place of its fixed odds, and a plan is a content node (a kind the code knows, with its numbers), so a pillar hall with another spacing is a row, not a patch.
4. **Rare rooms.** Set pieces rolled per face at long odds (1 in 27, 1 in 81), independent of the biome but allowed only in the biomes and levels they list. The chapel becomes the first.
5. **Uses.** A biome lists what is found in it, and `furnish` places it. This is where the stock goes that the owner sent to the backrooms from the library.
6. **Edges.** A wall line knows the face on each side (`linesOf`, `Line.beyond`). Where the two faces took different biomes, the line is built as a threshold: a change of trim, a frame, a step. A region then has an edge that can be found and followed.
7. **Sameness** holds inside a region, and most of all on the maze level.

**Steps.** Fields and the subtype table with today's 18 biomes given ranges that reproduce something close to today. Then pools. Then rare rooms. Then uses. Then edges. Each step leaves the backrooms playable.

**Laws.** Within a named number of faces of the root there are at least so many different plans. A threshold stands on a line between two regions. The maze level's biome does not change inside a region.

**Checked by.** Section 4, `check-repaint` on backrooms and planet, and a bench of the tile.

**Must not touch.** `plugins/blocks` uses `strongestAround` for districts; a change to the helpers must leave the city as it is.

**From the scout, read in the code.** These correct the design above; where they differ, they win. Nothing here is built, and none of it starts before package P.

- **Fields have to be salted before the maximum is taken.** `strongestAround` and `strongestNear` take the largest raw face hash, so fields that differ only by a salt applied afterwards would all share one set of region borders: one roll in disguise. Each field takes the largest of `mixed(faceHash, itsSalt)` over the ball, and its value is a re-hash of the face that won. The level is not a field: it is the floor, and each level has its own list.
- **Cost.** A tile makes about 171 hash probes today, 36 of them in `strongestNear`. Gathering the ball's faces once and taking every field from that costs no more than today for fields up to two rings wide. Thresholds between regions need every neighbor's fields, so the gather grows by a ring: about 241 probes if each face is fetched once, about 351 the recursive way. A three-ring field together with thresholds is 306 to 1296. Under the speed rule that has to be measured, and the three-ring field is left out unless it is free.
- **What a space of parameters is here.** There are no coordinates to feed noise. A field is a function of a face's neighborhood: a salted maximum over a ball of so many rings. Each face is then a point in a cube of field values, a biome is a box in that cube, and a biome's area in the world is the overlap of several independently cut sets of regions, which no single roll can make. Depth is the one real coordinate.
- **The table needs no parser change.** The palette already does it (`warmth-above`, `warmth-below`, absent meaning no bound). A biome gets an above and a below per field and a weight. The pick is the box nearest the point (zero inside), ties broken by a weighted roll on a hash that is constant over the overlap, so no face is ever left without a biome. `MOST_BIOMES` is 8 and the offices already list 8, so it is raised; today's pick is the hash modulo the count, so adding any biome reshuffles every region, which the table ends.
- **First ranges**, which give today's shares if the fields are uniform and independent. Grandeur and darkness one ring wide, age and wetness two.

  | Biome | Grandeur | Wetness | Age | Darkness |
  | --- | --- | --- | --- | --- |
  | office | below .5 | below .5 | below .5 | any |
  | stained | below .5 | below .5 | .5 and up | any |
  | tiled | below .5 | .5 and up | below .5 | any |
  | sodden | below .5 | .5 and up | .5 and up | any |
  | open-hall | .5 and up | below .5 | any | below .5 |
  | atrium | .5 and up | .5 and up | any | below .5 |
  | red-room | .5 and up | any | below .5 | .5 and up |
  | archive | .5 and up | any | .5 and up | .5 and up |
  | parlor | below .4 | any | below .5 | any |
  | attic | below .4 | any | .5 and up | any |
  | study | .4 and up | any | any | .67 and up |
  | gallery | .4 and up | below .5 | any | below .67 |
  | conservatory | .4 and up | .5 and up | any | below .67 |
  | bunker | any | below .5 | below .4 | any |
  | cellar | any | .5 and up | below .4 | any |
  | sump | any | .67 and up | .4 and up | any |
  | hedge | any | below .67 | .4 and up | below .5 |
  | catacomb | any | below .67 | .4 and up | .5 and up |

- **Plans.** The plan is rolled in two stages today (the level's odds for rings and chapel, then the biome's odds for pillars, pool and court), and four plans are forced by the situation and cannot be pooled: maze, lobby, the rooms around a stair, and solid. A weight on an edge can be written in content today, but the plugin binding reads only the edge's target, so a small addition to `plugins/api/binding.d` is needed (no ABI change). Cheap new plans with the painting code there is: pillars at other spacings, a colonnade, a long gallery, a sunken floor, a raised dais, a flooded room.
- **Rare rooms.** `roll` in `turtle.d` returns hundredths, so 1 in 81 cannot be said with it. The chapel is chosen per quarter today, offices only, where no hall crosses. As a table each row is rolled on its own from the face hash, so no row's roll depends on another's. Set pieces the code can build now: the chapel, a drowned room, a hall of pillars, a garden hall under the sky.
- **Uses.** The backrooms' shell already is salvage: its walls and floors are cloth and masonry, its lights are lamps. So stock means concentrations of what is scarce there: lamps, steel (which needs an iron pickaxe, so it is a late find), bales and pallets. Boxes, shelves and damp patches become rows of the same table.
- **Edges.** A line along a face's edge is already two walls back to back, each side painting its own. A threshold is each side framing its half in its own trim at the door slots the line's hash gives. Both sides agree because the biome is a pure function of hashes; anything taken from the tile's own random numbers would make the halves disagree. An inner line can never be a threshold, and on the offices a hall edge has no wall at all.
- **Regions are mostly border.** A face and its two rings are 21 faces, 15 of them in the outer ring, so "sameness inside a region" is a small inside.
- **The laws as first worded cannot be checked,** since scripts cannot call plugin code. They become censuses of materials, or use a rig: the root face forced to a point of the cube, the way `ForcedStair` forces a stair.
- **Tests that can flip with the mix.** `checkBackroomsAround` accepts only certain floors and ceilings; an atrium's plank floor is not among them, so a spawn face that becomes an atrium fails two tests. The pool and court views need water and oak within reach.
- **The pieces.** Fields and the table, with a function that says which biome a face has (package D's backrooms port rule wants it). Plan pools. Rare rooms. Uses. Edges, last and measured. None of it changes the API, the ABI number or the save format.

### J. The library's rooms (decision 13)

**For.** Notes, working rooms, a staff break room, and the catalog.

**Unread.** `plugins/library/plugin.d`, `library.decl`, `library.content`, and `Game.interact`. What is known: the room kinds `atrium`, `studies` and `lounge` with their odds in `settings.conf`, and from `game.d` that a station works when the block at the place the player opened it is still that station's block and is within reach (`isNearStation`), which says nothing about who put the block there.

**J1. Working rooms.** Study rooms and lounges get stations: the tile paints the station's block (bench, press, lab, workbench, collector) by the room's hash. The package first confirms that a station painted by worldgen opens and works like a placed one.

**J2. The break room.** A rare room kind for the staff: a little stock of the library's own sort (cloth, glass, a kettle's worth of water, steel lockers). Everything else to salvage stays out of the library.

**J3. Notes.** A block that can be read.

- Engine: a role for the readable block, a content kind for a note (its text, and the insight it gives), and a third trigger beside `Trigger.broke` and `Trigger.worked` so that using the block teaches the insight and posts the text. Which note a block holds is the hash of its place among the notes its room kind allows.
- Content: the notes themselves. They are rumors, in the sense of `ideas.md` ("Rumors before facts"): where tide shows, what ember needs, which plant must exist. Someone has to write them, and the owner reads them before they go in (section 8).

**J4. The catalog.** Every compound has a shelf, the walk to it spells its shape, and a reading room shows what the shelf's compound would do to the reader. This is design work before it is code: an addressing scheme from a path through the honeycomb to a molecule and back (`source/common/biology/molecule.d`, **Unread**), short enough that a shelf is some thirty steps from a door, as `ideas.md` works out. It gets a design debate of its own and is built last.

**Laws.** A press in a study room presses. Reading a note teaches its insight once and posts its text. The catalog's laws come out of its design.

**Checked by.** Section 4, `check-repaint` on library and planet.

**From the scout, read in the code.** These correct the paragraphs above; where they differ, they win. Nothing here is built, and none of it starts before package P.

- **The library as it is.** A slab of four stories (floors at -12, -6, 0 and 6 cells), each face's five corners painted as quarters. A face's kind comes from its hash: gallery, hall, stair, atrium, studies or lounge. Studies split a quarter into four carrels per story with a desk each; `loop-odds` (0.4) decides whether all four doors are open, so the carrels form a loop, or one is shut and they form a chain. The stacks are sunken columns under some vertices, endless downward. Everything structural comes from hashes; the color of each book and the gallery's second stack come from the tile's own random numbers, so a new `pick` before them shifts every later book color.
- **Stations.** The stations are workbench, furnace, anvil, press and lab. The bench is not a station but a role (`engine:bench`) and it works when painted. A station painted by worldgen works exactly like a placed one: `interact` remembers the cell, and `isNearStation` only asks that the block there is still the station and within reach. A painted collector does not work (it needs the record of having been placed), so it is left out. Creative rules skip the station check, so the law runs under survival.
- **Where they go.** In a carrel, replacing one cell of the desk, decided per story and per carrel by a hash (content paints repeat over the four stories by a rhythm today, so a station needs its own box). Proposed: a press in one carrel in nine, a lab in one in 27, a bench at a table end in some halls, a workbench in the staff room. `roll` in `turtle.d` resolves only hundredths, so one in 81 cannot be said with it.
- **A concern.** A painted station can be broken and carried off. The press needs no tool, and a lab found this way skips the recipe for one. The owner said stations are to be used where they stand; keeping them there needs engine work.
- **The library is already a salvage mine.** Its books include cloth, its lamps are light panels, its partitions are plaster, its tables are oak. So the staff room's own stock is what is new to it: steel lockers, a sink with water, wallpaper, ceiling tile.
- **Notes.** A role is the wrong carrier (a role is exactly one material and must be filled by the base mod) and no new trigger is needed. Proposed: a content kind for a rumor (its text, the materials it is found in, the insight it teaches if any); any material some rumor names is readable, and it has to be a material only the library paints; which rumor a block holds is a hash of its place among the rumors for that material; reading sets a mark in a new set in `Game`, teaches the insight once, and posts a short note. A note on the hud is one line of about 57 characters for five seconds, so the text itself goes in the journal, which wraps and scrolls. The set is saved, so `SAVE_FORMAT` goes up. The word "note" is taken in the code by the hud's messages; "rumor" is free.
- **Nine draft rumors, for the owner to read.** The first seven can be checked in the game today; the last two point at work that is not built and are not shipped until it is.
  1. "Walk five equal lengths, turning right after each, and you stand where you began, facing the way you set out. Only the compass disagrees, by a quarter turn."
  2. "The panels that light these rooms are mostly glass. A furnace would give it back."
  3. "Many of the books here are bound in cloth, and cloth chars in a furnace like wood."
  4. "The fern of wet ground opens something in the eye. The thornbush of dry sand sits in the same lock and does not turn it."
  5. "Copper keeps to marble and slate; iron to the dark rocks further down; sulfur to the pale layered stone near the top."
  6. "Seeds crossed where the air is thick with ash come out stranger, and stranger still with sulfur in the pocket."
  7. "Ore smelted alone gives back less metal than ore worked with charcoal."
  8. "By the lake beds there are stones that show only to an eye coming down from a dose." (waits on tide)
  9. "In the deepest caves there are stones that show only when two things are felt at once." (waits on ember)
- **The catalog.** There are 2 x 9^27 compounds, about 1.16e26. A shelf thirty steps from a door needs nine choices a step (28 steps exactly); a walk through the library's rooms has four doors forward and would take at least 44. Three ways: a tree of rooms with nine exits each, one fragment a room (a new structure, since the library's faces do not form a tree); a walk that is recorded as the thread is, with marks on doorways (cheap, but a compound is then not a place); or a card-catalog desk whose screen sets the 27 cells and shows the effect (no walk). The screen that shows what a compound does to the player's receptors exists for an aimed plant and could be reused; nothing draws a molecule's shape. The scout would build the desk first. The owner decides whether every compound must be a place, whether reading needs the assay kit, and whether a compound's 24 rotations share a shelf.
- **The pieces.** Presses and labs in carrels, with a law that a press found there presses. A bench in reading halls. The staff room. The rumor engine (it touches `game.d`, `hud.d`, `screens.d`, `save.d` and `crafting.d`, the same files as C and M, so it comes after them). The rumors in the library. The catalog's debate.

### K. Debug scenes in the creative menu (decision 14)

**For.** A debug list in the world menu under creative rules.

**How it is today (Read).** `worldCount` and `worldNameAt` in `source/client/plugins.d` count and name "terrain" and then the worlds; `worldgenAt` and `steppedWorld` in `source/client/structures.d` turn an index into a `Worldgen`; `Game.worlds` is a `WorldMenu` (`saved`, `picked`, `current`, `deleting`, `saving`) driven by `UiKind.pickWorld`, `askDelete`, `playWorld` and `deleteWorld`. `sheetsFor(rules)` in `game.d` is the existing pattern for something creative rules add. `StructureHost.build` finds a name among worlds and debug structures alike. The menu is drawn in `source/client/screens.d`. **Unread:** `screens.d`, `web/play.js`.

**Design.** Under creative rules the menu shows a second list after the worlds, the scenes, one per debug structure (`allDebugNames`). A pick is a typed thing (a world or a scene, and its number), not an index that runs across both lists. A scene is never saved. Under survival rules the menu is what it is now.

**Laws.** Under survival rules the menu lists the worlds and nothing else. Under creative rules it also lists every debug structure, and picking one starts it.

**Checked by.** The `ui/` tests, the application and `:web` builds, and a render of the menu (`menu` is a view already).

**Must not touch.** `--worldgen debug`, which stays.

### L. Landmarks that are real (decision 14, second answer)

**For.** The tower, crown, palace, arbor, Babel, road and trail as places and objects with a reason to be where they are.

**How it is today.** The planet stands each registered landmark once, on four arms around spawn, flattens its site and keeps groves and sinkholes off it (**Read**, `landmarks` in `plugins/planet/plugin.d`). Six structures register as landmarks (arbor, babel, crown, palace, tower, trail; from earlier in the conversation, to be confirmed by reading). The arbor and Babel also rise as kinds. The road is built through spawn. `api.build` runs a structure in place and is in the tile API too, where `place`, `claim` and `flatten` are refused (**Read**). The trail grows as the world grows, by placing its own continuation (**Unread**). `ideas.md` gives each of them a lesson ("Each world teaches one rule").

**Reading.** Each structure becomes a place that turns up in the world more than once, by a rule a player can learn, and holds things a player can use. Its debug scene stays as the way to look at it alone. Standing them at spawn is fine and is not the goal.

**L0. Design first.** Two things have to be settled before any structure is touched, and both go to the owner.

1. **The table.** What each structure becomes, where it stands, what it holds. A first proposal, every row of it open:

   | Structure | Becomes | Stands where | Holds |
   | --- | --- | --- | --- |
   | tower | a watchtower | on high ground | a deck to look from (from height the ground is a small disc), a place for a beacon |
   | crown | a ring of towers joined by bridges | where grounds crowd | the loop that leaves the ground, a hall with stations |
   | palace | a great house | at the middle of a green city district, or on low wild ground | rooms with stock and notes |
   | arbor, babel | what they are: giant trees and towers that rise as grounds | as rising kinds do | decks worth building on |
   | road | a straight highway | along chosen straight lines of the honeycomb | piers, and huts as hand-off posts |
   | trail | a winding path | from a sinkhole to the nearest grove or landmark | huts and cairns |
   | hamlet (a rig today) | a village of huts | low wild ground | huts with stations |

2. **How a structure recurs.** Two ways exist and both have a wall in front of them.
   - A face tile builds it where a hash says, as the planet's tile builds groves. A tile cannot flatten, and flat sites are today a list the world's structure fills once at the start (`flatten`, and `calmAt` reads the list for every node). So either structures stand on footings and take the ground as it is, or flat sites become a rule of place that any node can evaluate.
   - The world's structure places it as the graph grows, as the trail extends itself. A structure placed later cannot flatten either.
   This is a design debate for a fresh subagent with the two options and the constraint that generation is a function of place.

**L1 and on.** One sub-package per structure, after L0, each with its rule, its contents, a view, and a law that it is met within some number of edges of spawn.

**From the scout, read in the code.** These correct the paragraphs above; where they differ, they win.

- **The structures as they are.**
  - *Tower:* one column at a vertex, ten cells square, three edges tall, floors every four cells with a stair each, a door, merlons. Assumes flat ground.
  - *Crown:* on the five vertices of one face: a two-edge tower and a two-story hall at each, and a deck two cells wide along each of the face's five edges one edge up, with no rails. Assumes flat ground.
  - *Palace:* the site's face and every face touching it, eleven faces, each quadrant a half-sunken hall with pillars, lamps, outer walls with windows, grand stairs down, and a basin with a jet at the middle. Needs flat ground badly.
  - *Arbor and Babel:* upright kinds whose tiles run per segment, endless upward, taking the ground as it is. They already recur across the default world as rising kinds, each at 0.0015 per ground vertex (`rise-odds` 0.015 times a share of 0.1). `ideas.md` is wrong to say they are only reachable by a flag.
  - *Road:* an endless paint along one line of ground edges, twelve cells wide, cut and fill against the plane, with a pier eight edges deep at every vertex placed one after another forever. It only works through the root: endless paint is allowed only while the world is placed, and a pier whose next site is behind the growth fails the whole world.
  - *Trail:* claims the vertex at each end of an edge, paves gravel four wide at the plane's height (so off its flattened start it is buried under hills and floats over valleys; inferred, not rendered), a hut on one edge in three, and extends itself by `place`. Twelve segments as a landmark, endless as a scene.
  - *Hamlet:* five timber huts on the five vertices of a face. Assumes flat ground.
- **What a tile may touch.** There is no limit on depth and none on how far a turtle moves. The limit is that a tile may not paint a node that is already finished (`probeLineAhead`), and the refusal stops the world. In practice a face tile is safe on the columns at its own face's five vertices, at any height or depth, and on the ground edges between them, which is exactly what a grove paints. The tower, the crown and the hamlet fit that. The palace does not: its outer vertices are out of reach.
- **Two traps.** A `stop` laid by a tile or by a placed structure references its node forever, and every one of these structures lays stops, so the recurring copies must lay none. And `api.build` from a tile cannot run any of them: it finds only worlds and debug structures, never landmarks, and each debug function calls something a tile is refused.
- **Linking.** The planet cannot call the tower's or the crown's code, which live in other libraries. Either their bodies move into shared code compiled into the planet (the box code already is shared), or the registry gains tile-safe prefabs (ABI goes up).
- **Flat sites.** Two flatteners exist. The list (`flatten`, read by `calmAt` for every new node state) is why only the world's structure may flatten: calm is baked into a node's state when the state is made, so a flat added later would give old and remade nodes different relief. The other is already a rule of place: `reliefShareAmong` and `flatLinesNear` flatten relief around the column of every planar risen ground, found through the horosphere references nodes carry. Flat sites by rule should ride on that (a kind that flattens, with its own radius), not on `calmAt`.
- **Footings.** The alternative needs one read-only call, the height of the ground along the vertical at a vertex (`ensureGroundAlong`, which upright columns already use), and a second for a node's relief and climate would make "on high ground" computable. Today a face tile on terrain cannot learn the terrain's height at all.
- **Growing with the world** is not a way to scatter things. The queue is global by depth, not by nearness: every trail and road grows whenever the player goes deeper anywhere, creating nodes and pinning memory in directions nobody visits. And tiles cannot read claims, so groves, sinkholes and ports can land on the trail past its start, on its huts and on the road outside the spawn ring (inferred, not rendered). What recurs has to be decided by a hash that every tile can evaluate.
- **The scout's table**, replacing the first proposal:

  | Structure | Becomes | Stands where | How often | Holds |
  | --- | --- | --- | --- | --- |
  | tower | a watchtower | at a vertex higher than its neighbors and above a threshold; never on a port or where a ground rises | about 1 hilltop in 3 | stairs, a deck, a place for a beacon |
  | crown | a ring of towers with bridges | unsure: a face that wins a roll of about 1 in 81, or where rising grounds crowd (which risks meeting connectors) | | a hall with stations; the loop that leaves the ground |
  | hamlet | a village | a face lower than its neighbors, or where trails meet | about 1 cluster in 27 | huts with stations and stock |
  | arbor, babel | as now | as now | as now | decks and floors with stations or notes on some |
  | road | a highway | every line of ground edges whose line hash wins a roll; it never bends | unsure | piers down to the crust, a post hut every few edges |
  | trail | a path between places | each trail vertex points by hash to a neighbor, ending at a hamlet or a tower | unsure; a debate first | gravel on the ground, cairns at forks |
  | palace | a great house | unsure: a set piece of the city's own tile, or shrunk to one face on low wild ground, or the copy at spawn only | | rooms with stock and notes |

- **The owner on the table:** "Give it a shot, if it's no good then we can remove it". So the unsure rows are built as the scout proposed them, each small enough to take out again: the crown on a face that wins a roll of about 1 in 81; the road on lines that win a roll; the palace shrunk to one face on low wild ground; the trail after its debate.
- **The scout's recommendation.** A mix. Arbor and Babel stay rising kinds and only gain contents. Tower, hamlet and crown are built by face tiles from a hash, on footings. The road is built per edge from a hash of its line. The trail and the palace each get a debate first. Placing with growth is not used for recurrence at all. The six at spawn stay.
- **The pieces.**
  1. Engine, one ABI step: the ground's height at a vertex, a node's climate, a hash of an edge's line. (The line hash is also what G3 needs.)
  2. Shared code that holds the predicates for which face or vertex holds what, compiled into the planet and the caves, so that groves, sinkholes, wells and ports keep off structures.
  3. The tower's and the hut's bodies as tile-safe shared code with no stops; the debug scenes call the same code.
  4. The watchtower, with a view and a law that one stands within some edges of spawn.
  5. The hamlet. 6. The crown. 7. Road lines in the planet's edge tile. 8. Contents for arbor and Babel, after J1. 9. The trail's debate. 10. The palace's debate.
- **Possible faults seen on the way, not confirmed by a render:** a port opening inside the tower, crown or palace at spawn (ports are kept off the root vertex, a foot and a rising vertex, not off landmarks); groves, sinkholes and ports over the trail, its huts and the road.

**Depends on.** J1 and J3 for things to put in them (stations, notes), M for counts, and containers, which do not exist yet and are not planned here.

### M. Threes in what is held and needed (the item rule)

**For.** Item counts that lean to powers of three.

**The rule.** The owner's: "all arbitrary numbers that are a count of things you can hold or need", "not a hard rule", "Not for the world".

**Known so far (Read, `source/client/game.d`, and by the scout in `inventory.d`, `crafting.d`, `screens.d`, `save.d` and `plugins/base/base.content`).** Four extract make a dose (`RAW_PER_DOSE`). A ripe plant yields one to three (`MOST_EXTRA_YIELD` is 2), which already fits. The crafting queue holds 16 (`MOST_CRAFTS`) and 24 compounds are kept (`MOST_COMPOUNDS`). The hotbar has twelve slots (`HOTBAR_SLOTS`, keys 1 to 9, 0, minus and equal), the pack three rows of twelve, 48 slots in all; a stack holds 64 (`STACK_LIMIT`) and a living stack up to eight strains (`MOST_STRAINS`). All recipes are data in `plugins/base/base.content`; the press ratio and the yields are constants in D. The queue, the inventory, the compound list, the bench, the press and the world menu are drawn in `source/client/screens.d`, not `hud.d`. The inventory is saved as one raw block, so any change to its layout raises `SAVE_FORMAT`.

**Steps.**

1. **Audit.** One table of every count of things held or needed: each recipe's inputs and yield, the press ratio, stack and slot limits, the queue, what a harvest gives. For each: the number now, a proposed number, and the reason to change it or leave it.
2. **The owner signs the table.** Capacities such as the queue and the stack limit are the doubtful rows.
3. **Apply.** Recipes are content and change there. Constants change in the code. Tests that work from the numbers (`flat/crafting`, `gene/synthesis`, `gene/harvest`, `plant/`) mostly derive them and should follow; those that state a number are corrected.
4. **Numbers in `ideas.md`** that were worked out from the old values (the press and garden arithmetic under "Steady states") are worked out again.

**Not in it.** Chunk and edge sizes, the port's width, treads per turn, anything that is the world's.

**Three things the owner added, which are not about threes and belong with items.**

- **The queue has no size and works like Factorio's.** Today `MOST_CRAFTS` is 16 and a full queue refuses (`NoteKind.queueFull`). Wanted: no limit; a recipe queued when its ingredients are missing queues what makes them (it does already, through `planRecipe`); many of one thing queue as one entry with a count; cancelling gives back what was taken. What "like Factorio" adds beyond dropping the limit is for a scout to list against the code.
- **Keeping 24 compounds is wrong.** `slotFor` in `game.d` drops the oldest compound when a 25th arrives. A compound a player made should not vanish because of a count. What bounds the list instead, if anything, is undecided.
- **Unidentified flowers that stack are odd.** A living stack holds runs of different genes (`strains`, `Sorting.unsorted`), so a stack of unknown flowers is really several different things that look alike. The owner: "They are basically a bundle of items, in a way." Reading: show and treat it as a bundle, a thing that holds different items, not as a count of one item. This needs `source/common/inventory.d` read and a small design before anything is changed.

**Laws.** For the threes: none new; the existing ones must still hold with the new numbers. For the queue: more recipes can be queued than the old limit, and each finishes.

**Settled by the owner since.** The table below was left to the planner's judgement, with these fixed points, and the rule restated: a power of three only where a number has no default of its own.

- **A stack holds 81.**
- **The hotbar stays at twelve.** A thirteenth slot on the tilde key is a maybe, and is not built unless asked for. The pack stays three rows of twelve.
- **The recipes, as judged.** Every row of the table is applied as proposed, with these choices on the doubtful ones: the workbench takes nine planks (three wood); the stone, copper and iron pickaxes keep two planks for the handle, which has a default of its own; smelting takes three ore; the lab takes three and three; the masonry furnace takes nine; charring and pulping cloth take three.
- **The queue is Factorio's.** Ingredients leave the inventory when a thing is queued, and a thing that cannot be paid for cannot be queued. Missing intermediates are paid for and queued ahead, as now. So the present law that a lab reaction waits for its reagent goes: without the reagent it is not queued. Work still waits for its station. Cancelling gives everything back. The queue is saved if that is not costly; until it is, a save refunds every entry.
- **A bundle is what cannot be told apart.** It is not a holder to take things out of: an action picks from it. What changes is that the player can see it: the cell and its tooltip draw the different flowers in the bundle, so the player knows there are several and which is which by look, and not what any of them means. Nothing underneath changes, so `MOST_STRAINS` stays and the save is untouched by this.

**The audit.** From the scout. "In" is what a recipe takes, "out" what it gives. Rounding was done in powers of three: 2 and 4 go to 3, 6 and 8 go to 9. Rows marked (?) are the doubtful ones. Nothing here is applied.

| Where | Now | Proposed | Note |
| --- | --- | --- | --- |
| `STACK_LIMIT` | 64 | 81 (?) | 27 is the other choice |
| `HOTBAR_SLOTS` | 12 | 9 | drops the keys 0, minus and equal |
| pack rows | 3 of 12 | 3 of 9 | pack 27 and hotbar 9, 36 slots in all |
| `MOST_STRAINS` | 8 | 9 (?) | depends on the bundle |
| `MOST_CRAFTS` | 16 | removed | the owner's answer |
| `MOST_COMPOUNDS` | 24 | removed | the owner's answer |
| `RAW_PER_DOSE` | 4 | 3 | better as a field of the pressing in content |
| harvest yield, extract per pressing, parents per cross | 1 to 3, 1, 2 | leave | already fit, or not arbitrary |
| planks | 1 wood gives 4 | gives 3 | the owner's example |
| make-workbench (?) | 6 planks | 9, or 3 | "3 wood" reads either way |
| make-wooden-pickaxe | 3 planks | leave | |
| make-stone-pickaxe (?) | 2 planks, 3 stones | 3 and 3 | |
| make-furnace | 8 stones | 9 | |
| make-press, make-bench | 4 planks and 2 of another | 3 and 3 | |
| make-anvil | 4 stones, 3 copper bars | 3 and 3 | |
| make-inhaler | 2 glass, 1 plank | 3 and 1 | |
| smelt-glass | 2 sands | 3 | |
| smelt-copper, smelt-iron (?) | 2 ore | 3 | bars cost half again as much ore |
| make-copper-pickaxe, make-iron-pickaxe (?) | 2 planks, 3 bars | 3 and 3 | |
| make-collector, make-assay-kit | 2 glass, 2 copper bars | 3 and 3 | |
| make-lab (?) | 4 iron bars, 4 glass | 3 and 3 | cheaper than now; 9 and 3 is the other choice |
| make-beacon, make-syringe, make-cleaver | 1 and 1 | leave | |
| make-oxidizer, char-wood, strip-lamp, melt-steel | 1 gives 2 | gives 3 | |
| make-conjugant | 2 leaves give 2 | 3 give 3 | |
| make-polar-graft, make-bulky-graft, fire-brick, crush-rubble, melt-ice, strange-charge, strange-bulk | 2 | 3 | |
| make-charged-graft, cool-lava, crush-masonry, lamp-beacon, melt-fine-soil | 1 or 3 | leave | |
| reduce-iron, reduce-copper | 2 ore and 1 charcoal give 2 | 3 and 1 give 3 | charring then triples the bars |
| quench-glass | 2 sands and 1 water give 2 | 3 and 1 give 3 | quenching then triples the glass |
| sift-sand, sift-clay | 4 soil | 3 | |
| masonry-furnace (?) | 6 masonry | 9, or 3 | cheaper than the stone furnace today |
| char-cloth, pulp-cloth (?) | 2 cloth | 3, or 1 | |
| steel-anvil | 4 stones, 1 steel | 3 and 1 | |

What follows if it is signed: `flat/crafting` and `flat/learning` state recipe numbers outright and change; `gene/unsorted` states the present stack model; the other tests derive their numbers. In `ideas.md` the press and garden arithmetic under "Steady states", "four extract into a dose", "a queue of at most 16 steps" and "double a yield" go stale.

**The queue, from the scout.** Today: `craft` plans a recipe against a projected stock, queuing what makes the missing ingredients (known recipes only, four deep), one entry per batch; work skips forward to the first entry whose station is at hand; ingredients are taken when an entry starts, not when it is queued; cancelling a started entry refunds it; the queue is not saved (started entries are refunded into the save, pending ones dropped); the screen draws one row and silently leaves out what does not fit. Against Factorio's hand queue, as the scout remembers it and not from a source, the gaps are:

1. the limit itself;
2. one entry per batch, where Factorio shows one entry with a count;
3. no way to queue several at once (one, a few, all that can be made);
4. ingredients taken at start, where Factorio takes them when queuing. This is a real fork: taking at start is what lets a lab reaction wait for its reagent, which is a law the tests state. The scout recommends keeping it;
5. entries are not linked, so cancelling the planks leaves the workbench waiting forever;
6. a refund that does not fit is lost without a word (an existing fault);
7. a finished product with no room is lost, with a note;
8. the queue is not saved.

**Compounds, from the scout.** No array is sized by the 24. The 25th distinct compound silently deletes the oldest with its extract and doses, unselects the chosen one, makes plants that produce it read as unidentified again, and leaves any queued work on it waiting forever; `save.d` refuses a save with more than 24. Recommended: drop the cap and nothing else, and list the compounds that hold something first.

**Living stacks, from the scout.** A `Stack` holds up to eight runs of (genes, count). Harvests arrive unsorted and pour into any unsorted stack of that item, which is where "unidentified flowers stack" comes from. A strain is identified when the player has an assay kit or already holds its compound, and then leaves for a sorted stack of its own. Every action quietly uses the first run. Three designs were offered: label it (draw the mix as a bundle, change nothing underneath); split it (never mix); open it (a holder the player takes strains out of). The owner's answer is the first: a band or mark per strain colored from its genes (`letterColor` exists for that), the name saying it is a bundle and of how many, the tooltip listing the runs with their gene strips.

**The pieces, in an order that keeps the tests passing.**

1. The recipes in `base.content`, with `flat/crafting` and `flat/learning` reading their counts from the recipes.
2. The press ratio, moved into content if that is cheap, and the "Steady states" arithmetic redone.
3. The compound cap removed, with a law that 27 distinct compounds are all still held.
4. The queue's core: no limit, ingredients taken when queued, nothing queued that cannot be paid for, counts on entries, queuing several, a screen that wraps. A law that 27 batches queue and all finish, and a law that a recipe whose ingredients are missing is refused. The law about a reaction waiting for its reagent is restated.
5. The stack limit of 81, with `SAVE_FORMAT`.
6. Cancelling: linked entries, and refunds that say when they do not fit.
7. Bundles drawn as bundles.
8. Saving the queue.

### N. Keeping the record straight

**For.** `wiki.md` rebuilt, a digest that sees the deep, and the three documents kept true.

- **N1.** `./caapi-headless wiki --out wiki.md` after any package that adds laws. `ideas.md` names `wiki.md` as its source for what exists.
- **N2.** `world-digest` did not move when the crust, the void and the wells went in. Give it a second sample below the ground, or a second line, so that A, B and F are guarded. **Unread:** `source/headless.d`, `source/worldcheck.d`.
- **N3.** Two things read in code and never looked at: lattice joints in the floors of the deepest chambers, and the backrooms well below the top level. A view each.
- **N4.** After every package: its status in section 9, the **Exists** lines and "Decisions waiting" in `ideas.md`, and whatever `CLAUDE.md` needs.

## 6. Order and dependencies

What needs what:

| Package | Needs first | Why |
| --- | --- | --- |
| A | N2 | so that the change is guarded by a digest that sees it |
| B | A | asks `probeCrust` |
| C | A (order only) | both change the API; one at a time |
| D | C (order only) | the same |
| E | nothing | |
| F | A, C | layers hang from the underside and end at the abyss |
| G1, G2, G4 | F | they are void worlds |
| G3 | F, and its own `SitePart` | |
| G5 | F, A | the islands of rock come from A |
| G6 | F, a design debate | engine risk |
| H1 to H4 | D | the ports lead into it |
| I | nothing | |
| J1, J2, J3 | nothing | |
| J4 | a design debate | |
| K | nothing | |
| L | L0 and the owner, then J1, J3, M | |
| M | the owner's signature on the audit | |
| N1, N4 | every package | |

The engine queue is strict: A, then C, then D, then F, then G3, one at a time (package Z).

A sequence for one builder, chosen so that whatever the owner has to look at or sign comes early and never blocks the next step:

1. N2, the digest that sees below ground.
2. A, first design. Renders go to the owner (question 1). Work goes on while they look.
3. M step 1, the audit table, to the owner (question 8). L0, the landmark table and the recurrence debate, to the owner (question 7). These are reading and writing, not building.
4. E, the hidden stair.
5. C, the fall.
6. B, down and back (once question 1 is answered, since it leans on what A became).
7. D, ports.
8. K, the creative menu.
9. F, the void interface.
10. G1, G2.
11. M, applied.
12. I, the backrooms tables.
13. H4, H2, then H1 and H3.
14. G5, J1, J2, J3.
15. G3, G4.
16. L, structure by structure.
17. G6 and J4, the two that start with a debate.

N1 and N4 follow every step.

## 7. Splitting the work across subagents

### What limits the split

- **One tree, one builder.** Every build of the root package rebuilds all plugins into `lib/` and writes `obj/` and the binaries. Two agents building in the same tree overwrite each other. So at most one agent that builds, tests or renders is running at any time.
- **No worktrees from here.** The owner uses git; the agents do not touch it. An agent in a git worktree would need its work merged back with git.
- **An agent knows only its brief.** It did not see this conversation. It can read `plan.md`, `ideas.md` and both `CLAUDE.md` files, and the brief must tell it to.
- **A report is not a fact.** What an agent says it did is checked by the session that asked.

### Three kinds of agent

- **Scout.** Reads only. Several can run at once, also while a builder is building. A scout takes one package, reads its "reads first" and **Unread** lists whole, and writes back: what the code really does where this file guessed, the exact functions to change, and anything in the design that cannot work. Its findings go into the package's section here before a builder is briefed.
- **Builder.** Exactly one at a time. Takes one package, or one sub-package, small enough to finish with a green build: A alone, C alone, one ground of D, one void world of G, one step of I. It builds and tests as it goes and hands back a tree that passes section 4.
- **Debater.** Reads only, fresh, for a choice between designs. It gets the goal, the options and the constraints, and no lean. The debates this plan already knows of: A's first design against its second (after the renders), flat sites by rule against footings (L0), the hung sheet (G6), the catalog's addressing (J4), the shape of the backrooms tables (I).

The session that briefs them is the integrator. After each builder it reads the files that changed, runs the whole of section 4 itself, renders and looks at the new views, updates `ideas.md`, `CLAUDE.md` and section 9 here, and only then briefs the next. For packages that change the engine (A, C, D, F, G3, G6) it can also hand the changed files, without its own conclusions, to a fresh agent for a second reading.

### What actually runs side by side

- Scouts for the next two or three packages, while one builder works.
- Debaters, at any time.
- Writing that is not yet in the tree: the note texts of J3, the ranges of the 18 biomes for I, the weaves of G1, the audit table of M, the landmark table of L0. These are drafted into this file or handed back as text, and a builder puts them in the tree later.

If the owner makes copies of the tree, one per lane, builders can run side by side on lanes that share no files, and the owner merges:

| Lane | Packages | Files it owns |
| --- | --- | --- |
| engine | N2, A, B, C (engine part), D (engine part), F, G3, G6, H4 | `source/common/worldgen/`, `source/client/structures.d`, `tiles.d`, `plugins/api/`, `plugins/planet/`, `plugins/caves/` (B also adds one predicate to `plugins/lattice/lattice.d`, which is the voids lane's file) |
| voids | G1, G2, G4, G5 | `plugins/lattice/` and the new void directories |
| rooms | I, H2 | `plugins/rooms/`, `plugins/backrooms/` |
| city | H1, D (city part) | `plugins/blocks/`, `plugins/buildings/`, `plugins/city/` |
| vaults | E, H3, D (vaults part) | `plugins/vaults/`, `plugins/connector/` |
| library | J | `plugins/library/` |
| play | C (game part), K, M | `source/client/game.d`, `hud.d`, `plugins.d`, `source/common/inventory.d`, `plugins/base/` |

Every lane also adds rows to `source/scripts/tests.d` and `views.d`, a `dub.sdl` line when it adds a plugin, and entries in `WEB_ENTRIES` and `WEB_PLUGINS`. Those few shared files are where merges will meet, and the ABI number is the engine lane's alone.

### A brief, in full

A builder's brief has these parts, in this order, and nothing that depends on having been in this conversation.

1. **The goal** in two sentences, and the owner's words it serves, quoted from section 2.
2. **Read first:** `CLAUDE.md` in the repository, the package's section in `plan.md`, sections 3 and 4 of `plan.md`, and the files on the package's list, whole.
3. **How to work here**, because none of it is inherited: no git and no reading of `.git`; one command per shell call, no pipes, no chaining, absolute paths; read files with the read tool and whole; no searching tools, navigate from `CLAUDE.md`'s code structure and let the compiler list uses; no temporary files, and delete any screenshot written; D without comments, ternaries, `continue` or `auto`; tests and views go in the project as real rows; build commands exactly as `CLAUDE.md` gives them, with `--compiler=ldc2`.
4. **The design** from the package, with what a scout found.
5. **Done when:** the laws named in the package hold as claims, the new views exist and were rendered and looked at, and every check in section 4 passes, with `world-digest` either unchanged or changed for a stated reason.
6. **Do not touch:** the package's list, and anything outside its files. If the work needs an API change the package does not name, stop and report.
7. **Hand back:** the files changed and why; the laws added, with the line each test printed; the output lines of every check run; what was left undone; what was assumed; questions for the owner. Verified and inferred kept apart.

A scout's brief is parts 1 and 2, then: "change nothing; report where `plan.md` is wrong about the code, the functions a builder will change, and what in the design cannot work as written."

A debater's brief is the goal, the options, the constraints (section 4), the files to read, and: "choose one and say what would change your mind."

### Sizes

A builder's piece is one that ends in a green tree in one sitting. As a guide: one engine concept (a field, an API call and its two hosts), or one plugin's worth of worldgen with its content, tests and view. A, D, F, G, H, I, J and L are each several pieces; the sub-packages and steps written in section 5 are the cuts.

## 8. Questions still open for the owner

1. **A, after the renders.** Answered: masses. "I'm fine with masses, it feels more geological to me."
2. **C, the fall.** Answered in part: the player wakes on the last thing they stood on before entering the place. Still open: do compounds and doses count as items for the loss? Is the third rounded down (8 loses 2)? Is creative exempt? The plan assumes no, yes and yes.
3. **B, the ways back.** How sparse? The plan tunes for "usually not the way you came", but an order of magnitude would help: one way back in sight of most landings, or a real search?
4. **D, ports.** Does every works block, sump and spired vault have a port, or only some of them?
5. **E, the hidden stair.** From inside the vaults an undosed player would see a hole in the floor where the stair's mist-stone top is, and could drop down it. Keep that as the undosed way out, or close it with a hatch?
6. **G.** Answered: structures larger than can be comprehended, and a maze of rafters with no railings, like a mineshaft, not walls. Taken as flat in the code's sense; say so if a true horosphere, off the honeycomb, was meant.
7. **L, landmarks.** The table in L0: what each structure becomes, where it stands and what it holds. And whether structures may stand on rough ground on footings, or need flat sites wherever they are.
8. **M, threes.** The audit table, when it exists. Answered for capacities: the queue gets no size, and the cap of 24 compounds goes. Open: what a bundle of unidentified flowers is in the hand and in the inventory.
9. **I, backrooms.** Answered: a hint, not a model; a space of parameters, not a tree.
10. **J3, notes.** Who writes them? The plan assumes drafts from `ideas.md` that the owner reads before they go in.
11. **M, the audit.** Answered: left to judgement, a stack of 81, a hotbar of twelve, threes only where a number has no default. The choices made are under package M.
12. **M, the queue.** Answered: ingredients are taken when a thing is queued, and what cannot be paid for cannot be queued.
13. **M, bundles.** Answered: a bundle is what cannot be told apart; actions pick from it; the player is shown the different flowers in it; and the fall is forgiving of a strain held once or twice.
14. **C, the mark.** Answered: the place before it, and before that, and the world's spawn if nothing holds.
15. **L, landmarks.** Answered: build the table as proposed and take out what is no good.

## 9. Status

Work was being done by Opus 5.5 subagents: one builder at a time, scouts beside it, the main session briefing them and checking what they hand back by running section 4 itself. The last builder was stopped, and a new agent is launched only when the owner asks for one. Package P was done by the main session directly. The plugin ABI is 28.

| Package | State |
| --- | --- |
| P. Speed first | done by the main session, at the owner's request, as far as the "Still open" list in the package: the load from spawn settles about eight times sooner in about a tenth of the memory, and flight keeps the visible world loaded with a few late frames in a hundred. What is open is tuning and the serial stages left on the main thread |
| A. A crust that varies | built and checked; the owner keeps the masses, so the second build is not built. Its cost is package P's to remove |
| B. Caves that open downward, ways back | scouted; findings are in the package, including a probable fault left by A (cave skins hanging in the open at rock flanks); held until P is done |
| C. The fall and the way back | the builder was stopped before it reported. Its work is in the tree and its tests pass (`falls/`, `save/round-trip`), the bottom under a ground included (`api.abyss`); nobody has reviewed it or looked at it in play |
| D. Ports that belong to their ground | not started |
| E. The hidden stair to the vaults | not started |
| F. Void worlds: the interface | not started |
| G. Void worlds: the nightmare | not started |
| H. Under built ground | not started |
| I. Backrooms from several tables | scouted; findings and a first table of ranges are in the package; held until P is done |
| J. The library's rooms | scouted; findings and nine draft rumors are in the package; held until P is done |
| K. Debug scenes in the creative menu | not started |
| L. Landmarks that are real | scouted and answered; ready to build piece by piece, the engine piece first |
| M. Threes in what is held and needed | scouted and answered; ready to build piece by piece |
| N. Keeping the record straight | N2 done and checked (the `deep` digest line). N1, N3, N4 ongoing |
