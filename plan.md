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
- Crust: `api.crust(ground, edges)`. Root wild ground 5.6 edges, risen wild ground and vaults 3.4 edges, city and backrooms none. Below the crust nothing is generated, and the planet's edge tile hangs the lattice there (`lattice.hang`). `api.under` changes look and fog by depth.
- Flat ground is soil over rock bands and veins.
- City districts (five), backrooms plans (pillars, pools, courts) and 18 biomes, library rooms (atrium, studies, lounge).
- Vaults rise with `bridge: none`: no connector to them or from them.

The checks that passed on that build: 103 behavior tests, the unit tests, the application, headless and `:web` builds, `content-check` (0 problems), `check-repaint` with `differing=0` on all seven worlds, `check-forget` on lattice, `views` (123) and `films` (9).

Known weak spots, none of them fixed:

- `world-digest` came out the same before and after the crust, the void and the wells were added. It does not look deep enough to guard them.
- Under the root crust nothing catches a falling body but the lattice. **Tested** only as far as: a body let go 6.4 units under spawn fell 0.5 in a second and landed on a girder.
- A port is a bare hole with a limestone stair in every ground.
- In the backrooms the well's column is left open on every level (**Read**), but only the top level was looked at.
- `wiki.md` is a generated page and is behind the code.
- `live/fly` ran 66 to 68 s of its 120 s limit in single runs. Not a benchmark, but the margin is thinner than it was.
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
- **Only the world's own structure shapes grounds.** `tile`, `tileEdges`, `horosphere`, `under`, `crust`, `ports`, `flatten`, `fog`, `look` are refused from tiles and from structures placed later.
- **The ABI number.** `ENTRY` in `plugins/api/api.d` goes up whenever the layout of `Api`, `Registry` or `Risen` changes, and new members go at the end. Two packages that both change the API must not be in flight together.
- **A new plugin** needs a subpackage and a `preGenerateCommands` line in `dub.sdl` and an entry in `WEB_ENTRIES` and `WEB_PLUGINS` in `source/client/plugins.d`. Shared code is a `sourceLibrary` with a `-mod` library beside it (see `caves`, `lattice`).
- **Laws are claims.** What a package makes true about the game is stated with `world.claim` or `world.link` in `source/scripts/tests.d`, with measures, and says no more than its condition checks. A view goes into `source/scripts/views.d` and is looked at with `./caapi --screenshot <png> <view>`; the PNG is deleted afterwards.
- **Verification** for a worldgen change: unit tests, all behavior tests, `content-check`, `world-digest` (must not change unless the package means it to), `check-repaint` on planet, city, backrooms, library, vaults, caves and lattice, `check-forget` on lattice, `views`, `films`, and the application and `:web` builds. Rebuild headless in release after `dub test`.
- **Load.** The void made deep nodes hold content. A package that adds content below the crust or more tile work measures it with the bench commands (`./caapi-headless --help` lists `bench-*`), against a baseline taken the same way, with repeats.
- **Style.** D with `-betterC`, no comments, no ternaries, no `continue`, typed locals, `final switch` on enums, state as types. Content is data in `.decl`, `.content` and `settings.conf`, not constants in D, wherever a mod could want to change it.

## 5. The packages

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

### C. The fall and the way back from it (decision 2)

**For.** A fall that is real, a respawn that keeps most of the inventory, and the loss rule in threes.

**How it is today (Read).** `gravityAt` in `horospheres.d`: with only the root ground in reach the pull is the root's "down" at full strength at any depth, so under the root crust a body falls until a block stops it. Nothing in `Game` ends a play: there is no health and no death. `Game.placeAtSpawn` puts the body at the blueprint's entrance, or at a found spawn, and settles it; `Game.startOver` empties everything a player has. `Game.beacons` holds the beacons the player placed. Notes are `NoteKind` values posted with `post`. **Unread:** `Game.step` itself, `source/common/inventory.d`, `source/client/hud.d` (where a note's words are), `source/client/save.d`.

**Design.**

1. **The world has a bottom.** A world names, per ground, the depth below which it builds nothing: `api.abyss(ground, edges)` (ABI goes up), stored beside the crust. Two things use it. Tiles are not run for nodes wholly below it, which gives the void the named reach that `CLAUDE.md` asks of anything that grows outward. And a body below it is lost. A depth is chosen over "has fallen for so many seconds" because a long fall would have to generate everything it passes.
2. **Lost.** In `Game.step`, in walk mode, when the body is below the abyss of the ground that has it (`nearestGround` and `heightAbove` already measure that), the play calls `wake`.
3. **Wake.** The body is put where it wakes, standing, with no speed; the thread is kept (it still leads to the edge that was fallen from); the body's chemistry is left as it is. Where: the newest beacon still standing, else the world's entrance (`placeAtSpawn`). Section 8 asks.
4. **The loss.** For each kind of item, counted over all slots: three or more held, lose a third, rounded down; one or two held, lose nothing. 3 loses 1, 8 loses 2, 9 loses 3, 81 loses 27. Taken from the last slots first. A living stack's kind includes its genes, as `isSameKind` has it. Upgrades are not items and are kept. Compounds and doses are left alone unless the owner says otherwise. Creative rules lose nothing. This is one function on `Inventory`, with a unit test.
5. **Said.** A note that names what happened and how much was lost, and an `Event` for mods beside `Event.broke`.
6. **Saved.** Nothing new, as long as the waking place is worked out from beacons and the entrance.

**Laws.** A body that falls past the bottom of the world wakes at the world's entrance, standing. It keeps every kind it held one or two of and loses a third, rounded down, of each kind it held three or more of (the prediction is computed from the counts, not recorded). Under creative rules it loses nothing.

**The rig.** A debug structure in `plugins/fixtures`: wild ground with a crust one edge thick, no void world, an abyss three edges down. The test lets a body go under the crust.

**Checked by.** Section 4. The unit test in `source/unit/`. `live/` tests still inside their time.

**Must not touch.** Noclip and fly modes never wake. A world that names no abyss behaves as now.

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

**What an edge tile can do (Read).** It paints boxes in the column of its edge, which is 24 cells square and 24 long (`columnOf`, `boxRefusal`), it can draw strokes (`TileHost.draw`), and it knows hashes of its vertices, its edge and the faces around it. It cannot place or claim.

**G1. Other fillings of the lattice.** `lattice.d` only. A weave, in content: how many edges are kept, whether there are diagonals, doubled beams, beams that stop half way, the odds of platforms and stairs. Which weave is used varies by cluster and by depth. Cheapest of all, and it comes first.

**G2. Patterns that break.** A filling with no randomness at all, the same motif on every edge by its direction, and then, at long odds (1 in 81), a motif turned, missing, doubled or replaced, with the breaks gathered in clusters so that a stretch is wrong together. It can be a weave of G1.

**G3. Structures too large to take in.** "megaphobia" is read as megalophobia. Two ways to be large:

- **Endless beams.** Every edge lies on a straight line of edges, and the engine already has a canonical key for that line (`canonicalOf` and `LineKey`, used by `TilePainter`). A hash of the line, offered to plugins as a new `SitePart` (ABI goes up), lets a void world thicken every edge of a chosen line to the full column: a girder 24 cells square that never ends, a few of them hollow with a corridor inside.
- **Hanging columns.** `api.sunken` already opens a column downward from a ground vertex (the library's stacks). A colossal pier or chain hung from wild ground through the crust is that form with a different tile.

**G4. Fractals.** A branching that repeats at every scale: a trunk that splits at each vertex into thinner limbs, the thickness set by how many steps out from the trunk a vertex is in a forest made of hashes. The caves already build such a forest (`parentOf`) and carve it; this paints it. A sponge in powers of three fits a column of 24 cells for one level only (three cubes of 8), which is why this is the fractal proposed.

**G5. Sparse islands, and islands that connect.** With the first design of A the deep is already islands of rock with caves and ore inside. Beyond that: small floating islands drawn with strokes at about 1 vertex in 27, a turf top and a tree, and a bridge along an edge when both its ends are islands. Larger islands that carry something (a hut, a garden, a station) wait for L.

**G6. The dangling maze sheet.** Read as a flat sheet, in the sense the code gives "horosphere" (a plane along cell faces), with a maze on it, hanging below the crust from one point. Planes spread apart, so a sheet opened a few edges below a ground vertex is nearest the crust at its foot and falls away from it everywhere else: it dangles. The maze is the backrooms' maze level (`rooms:mazes`) on its own.

- **Engine.** Today a plane rises above a ground vertex and faces back at its parent (`risenHorosphere`, `risenPlaneOver`). A hung sheet is the same construction through the ground, downward. That touches `risenHorosphere`, `probeRiseClear` and `probeClearOfAncestors`, `ensureAirSideNode`, `probeRisenSide` (which side a ground's tiles paint), and the limit of four grounds near a node (`MOST_GROUNDS`).
- This is the one sub-package with real engine risk. It starts with a design debate, not with code.
- If the owner meant a true horosphere, flat inside and not along cell faces, it is a different and much larger piece of work (section 8).

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

**Checked by.** Section 4. How far below its face a tile may paint is limited (`probeLineAhead` in `blueprint.d`, **Unread**), so H1 and H3 find that limit first.

### I. Backrooms from several tables (decision 12)

**For.** Regions with edges, rare rooms, levels and uses at once, from tables a mod can add to.

**How it is today (Read, `plugins/rooms/layout.d`, `rooms.d`, `rooms.content`).** One roll per region and level picks a biome: `tileAt` takes `strongestNear(face)` and indexes the level's biome list with it. A biome is a row of materials and odds (`big`, `open`, `skylight`, `pillars`, `pool`, `court`, `nowhere`, ...). `planOf` then picks each quarter's plan: maze, lobby, rooms, solid, rings, chapel, or one of pillars, pool and court by the biome's odds. Three levels (offices, houses, mazes) hold 8, 5 and 5 biomes.

**Reading.** "minecraft's multiple table worldgen" is taken as two things Minecraft does: a biome is looked up in a table over several fields that vary independently, and a structure is assembled from weighted pools of pieces. Section 8 asks.

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

### K. Debug scenes in the creative menu (decision 14)

**For.** A debug list in the world menu under creative rules.

**How it is today (Read).** `worldCount` and `worldNameAt` in `source/client/plugins.d` count and name "terrain" and then the worlds; `worldgenAt` and `steppedWorld` in `source/client/structures.d` turn an index into a `Worldgen`; `Game.worlds` is a `WorldMenu` (`saved`, `picked`, `current`, `deleting`, `saving`) driven by `UiKind.pickWorld`, `askDelete`, `playWorld` and `deleteWorld`. `sheetsFor(rules)` in `game.d` is the existing pattern for something creative rules add. `StructureHost.build` finds a name among worlds and debug structures alike. **Unread:** `source/client/hud.d` (how the menu is drawn), `source/client/save.d`, `web/play.js`.

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

**Depends on.** J1 and J3 for things to put in them (stations, notes), M for counts, and containers, which do not exist yet and are not planned here.

### M. Threes in what is held and needed (the item rule)

**For.** Item counts that lean to powers of three.

**The rule.** The owner's: "all arbitrary numbers that are a count of things you can hold or need", "not a hard rule", "Not for the world".

**Known so far (Read, `source/client/game.d`).** Four extract make a dose (`RAW_PER_DOSE`). A ripe plant yields one to three (`MOST_EXTRA_YIELD` is 2), which already fits. The crafting queue holds 16 (`MOST_CRAFTS`) and 24 compounds are kept (`MOST_COMPOUNDS`). The hotbar has nine slots. **Unread:** `source/common/inventory.d` (`STACK_LIMIT`, `SLOT_COUNT`), the recipes in the base mod's content, `source/common/crafting.d`.

**Steps.**

1. **Audit.** One table of every count of things held or needed: each recipe's inputs and yield, the press ratio, stack and slot limits, the queue, what a harvest gives. For each: the number now, a proposed number, and the reason to change it or leave it.
2. **The owner signs the table.** Capacities such as the queue and the stack limit are the doubtful rows.
3. **Apply.** Recipes are content and change there. Constants change in the code. Tests that work from the numbers (`flat/crafting`, `gene/synthesis`, `gene/harvest`, `plant/`) mostly derive them and should follow; those that state a number are corrected.
4. **Numbers in `ideas.md`** that were worked out from the old values (the press and garden arithmetic under "Steady states") are worked out again.

**Not in it.** Chunk and edge sizes, the port's width, treads per turn, anything that is the world's.

**Laws.** None new; the existing ones must still hold with the new numbers.

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

1. **A, after the renders.** Shafts or masses? The first design gives a two-edge roof with great islands of rock under it and void between. The second gives true windows: columns of void that widen as they go down, with walls. Which is "shields and windows"?
2. **C, the fall.** Where does the player wake: at their newest beacon, at the world's entrance, somewhere else? Do compounds and doses count as items for the loss? Is the third rounded down (8 loses 2)? Is creative exempt?
3. **B, the ways back.** How sparse? The plan tunes for "usually not the way you came", but an order of magnitude would help: one way back in sight of most landings, or a real search?
4. **D, ports.** Does every works block, sump and spired vault have a port, or only some of them?
5. **E, the hidden stair.** From inside the vaults an undosed player would see a hole in the floor where the stair's mist-stone top is, and could drop down it. Keep that as the undosed way out, or close it with a hatch?
6. **G.** Is "megaphobia" the fear of very large things? Is the "flat maze horosphere" a sheet in the sense the code uses (a plane along cell faces, hung below the crust), or a true horosphere, flat inside and off the honeycomb?
7. **L, landmarks.** The table in L0: what each structure becomes, where it stands and what it holds. And whether structures may stand on rough ground on footings, or need flat sites wherever they are.
8. **M, threes.** The audit table, when it exists. In particular: do capacities (the crafting queue of 16, the stack limit, the 24 compounds kept) fall under the rule, or only recipes and yields?
9. **I, backrooms.** Is "minecraft's multiple table worldgen" the multi-field biome table and the weighted pools of pieces, or something else?
10. **J3, notes.** Who writes them? The plan assumes drafts from `ideas.md` that the owner reads before they go in.

## 9. Status

| Package | State |
| --- | --- |
| A. A crust that varies | not started |
| B. Caves that open downward, ways back | not started |
| C. The fall and the way back | not started |
| D. Ports that belong to their ground | not started |
| E. The hidden stair to the vaults | not started |
| F. Void worlds: the interface | not started |
| G. Void worlds: the nightmare | not started |
| H. Under built ground | not started |
| I. Backrooms from several tables | not started |
| J. The library's rooms | not started |
| K. Debug scenes in the creative menu | not started |
| L. Landmarks that are real | not started |
| M. Threes in what is held and needed | not started |
| N. Keeping the record straight | not started |
