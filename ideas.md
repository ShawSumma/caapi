# Ideas

A place to gather ideas for fleshing out caapi's systems. Nothing here is decided. Ideas are grouped by what they build on, and each says which existing code or content it grows from, so it stays tied to the game as it is.

Sources: the rebuilt `wiki.md` (the systems as they are, and what no test states yet), two rounds of review in the conversation that started this file (quoted where used), and reading on the games and real practices that are linked through the text and gathered in the [inspiration index](#inspiration-index).

Each section uses the same labels:

- **Exists** is what the game does today, from `wiki.md`.
- **Numbers** are worked out from the game's own settings. The arithmetic was run. None of it has been tested in the game.
- **Ideas** are proposals.
- **Borrowed** is something another game or a real practice already worked out, with a link.
- **Open** is a question someone has to answer.

New in this version: blueprints (a recording played once), what the geometry gives for free, sections for climate, plants, compounds and the body, what the factory is for, a journal that works like the wiki, candidate content, cheap experiments, and the index of inspirations.

Since then the built worlds were joined to the default world, and the ground got caves under all of it and an underside. That is written up in [Worlds](#worlds-one-default-world-that-holds-the-others), and the **Exists** lines it touches (Down, Up) were brought up to date from the code and its tests, which are ahead of `wiki.md`. The choices that work left open are listed in [Decisions waiting](#decisions-waiting), with their options and the owner's answers.

## Contents

- [What we want](#what-we-want)
- [Tests for an idea](#tests-for-an-idea)
- [What already works this way](#what-already-works-this-way)
- [What the space gives for free](#what-the-space-gives-for-free)
- [Directions instead of tiers](#directions-instead-of-tiers): [Down](#down-geology), [Up](#up-gravity-and-grounds), [In](#in-perception-and-hidden-families), [Out](#out-distance-and-the-way-back)
- [Worlds: one default world that holds the others](#worlds-one-default-world-that-holds-the-others)
- [The living chain](#the-living-chain): [climate and air](#climate-and-air-every-place-has-a-use), [plants](#plants-and-breeding), [compounds](#compounds-one-chemistry-for-everything), [the body](#the-body-your-genome-is-the-tech-tree)
- [Crafting and learning](#crafting-and-learning)
- [Automation: the player is the machine](#automation-the-player-is-the-machine)
- [Making it discoverable](#making-it-discoverable)
- [A lonely world that fills with you](#a-lonely-world-that-fills-with-you)
- [Width: what each subsystem trades](#width-what-each-subsystem-trades)
- [Candidate content](#candidate-content)
- [Cheap experiments](#cheap-experiments)
- [Inspiration index](#inspiration-index)
- [Decisions waiting](#decisions-waiting)
- [Open questions](#open-questions)

## What we want

- **Depth and width.** Factorio-like depth: understanding a system is where the work starts. Starbound-like width: several coherent tiers. Not the incoherent breadth of modded Minecraft, where every mod brings its own ladder and you need a wiki to cross it.
- **Specialized subsystems rather than one ladder.** Each subsystem has its own logic and its own reasons to go deeper. The interesting content is where they cross.
- **Emergent and discoverable.** Outer Wilds: the world is complete from the start, and progress is mostly knowledge. You change what you understand, or what you are, and something that was always there becomes reachable.
- **A lonely world that fills with you.** Alive only as much as you make it. In the Minecraft sense, your builds and gardens are the life. In the Last Clockwinder sense, the machines are you: recorded copies of yourself doing the work.
- **Automation is a big part of the plan.**
- **You never redo a thing.** Like Factorio's blueprints: once you have built or done something by hand, it can be done again without you. Everything in the world was still done by your hands, once.
- **No boring areas.** From the owner: "I don't want boring areas to exist." That holds downward too: no ground is dirt all the way down.
- **Both, as variety.** From the owner, on choosing between two designs for a place: "for some of these doing both works as a form of variety". A choice between ways to fill the world is often not a choice.
- **Threes where Minecraft has twos.** From the owner: "where minecraft has things based on 2^n I like 3^n better, sizes of 1, 3, 27, 81 and so on". Asked how far it reaches: "It applies to all arbitrary numbers that are a count of things you can hold or need. So for crafting I'd go with 3 wood instead of 4 and then so on. It's not a hard rule, sometimes something else makes sense. Not for the world, it's an item-centric rule".

## Tests for an idea

Seven questions to hold an idea against. They have names so the rest of the file can point at them.

1. **Physical and local.** Can a player watch every link happen, at a place?
2. **Takes and gives.** From the review: "does each system both take something from another system and give something to one?"
3. **A rule, not a list.** Could a player who knows the rule predict this recipe, this plant or this effect before seeing it?
4. **Knowledge first.** Could a player who already knew everything do this at once? If not, the gate should be something they built or something they are, never a counter.
5. **Yours.** Does it stay still unless the player set it moving?
6. **Worked out from the clock.** Can its state be computed from a start time while nobody is watching?
7. **Comfortable.** Does the part a player needs still work with the comfort setting at its gentlest?

## What already works this way

The game's best thread runs from climate to plants, compounds, the body, perception and movement. A cold climate grows moss, moss's compound dulls you, your genes decide what a plant makes, your receptors decide what that does to you, and a mist signal reveals a stair that was always there. Every link is physical and local, so nobody needs a wiki to believe it. That chain is the model for everything else.

From the review: "mist stairs in particular are pure Outer Wilds: the world was complete all along, and you had to change yourself to see it."

Two kinds of depth, and the pharmacology already has both:

- **Knowledge.** Learning that a compound fills a brake is a discovery. Once you understand it, it is solved.
- **Mastery.** Designing a molecule that raises lift without sway, clears fast and survives your own enzymes is engineering. Tolerance and rebound make it a timing problem as well. This is the half that keeps the game going after the mysteries run out.

## What the space gives for free

Hyperbolic space does design work with no new mechanic. These are facts about the geometry, with numbers from caapi's own settings: cell edge 1.061, walk speed 0.225, gravity 1.6. Each one is a reason for something further down.

One assumption runs through this file: a ground runs along cell faces, so it is tiled by right-angled pentagons. The five-leg walk in `demo/holonomy` has legs of 1.061, which is the side of that pentagon, so it looks that way. The honeycomb the wiki describes is the [order-4 dodecahedral honeycomb](https://en.wikipedia.org/wiki/Order-4_dodecahedral_honeycomb).

### Room is free, closeness is scarce

**Numbers**

- On open ground, about 176 tiles lie within a 20-second walk of any point.
- Two workshops 20 seconds out, a right angle apart, are 37 seconds from each other directly and 40 by way of the middle. In flat space it would be 28.
- A direction that is 1 degree off misses by 0.18 at 3 units, by 1.3 at 5 units (more than a tile), and by 192 at 10 units. In flat space the miss at 10 units is 0.17.

What follows:

- **A base is a tree.** Everything can be near the hub, and almost nothing is near anything else. Ring roads are pointless. Packing, which is Factorio's puzzle, mostly goes away. Distance and timing take its place.
- **Nobody can be told where a thing is. They have to be led.** A bearing only works if it is read again at every step, which is what the beacon readout does.

**Borrowed**

- The [hyperbolic browser](https://www.chi1995.chistatic.hosting.acm.org/proceedings/papers/jl_bdy.htm) (Lamping, Rao and Pirolli, 1995) lays a tree out on the hyperbolic plane, because that plane has room for a thing that grows exponentially, and shows it in a disc you drag to refocus. An Escher print inspired it. caapi is that picture from the inside. The authors also found that things tend to get rotated as the focus moves, which is holonomy turning up in a user interface.
- [HyperRogue](https://roguetemple.com/z/hyper) builds quests on this: you do not get back to a place unless you retrace your steps, and [its challenges](https://en.wikipedia.org/wiki/HyperRogue) would be trivial in flat space.
- [Hypermine](https://github.com/Ralith/hypermine), another hyperbolic voxel game, says in its [first release notes](https://github.com/Ralith/hypermine/releases/tag/v0.1.0) that anything built far from spawn without a breadcrumb trail is almost certainly lost for good.

### Height and depth multiply room

**Exists.** From the wiki: "The surface at a fixed height above a plane is not itself a plane, it curves away."

**Numbers.** A level surface at distance h from a ground is longer than the ground by cosh(h) in every sideways direction (the [length of an equidistant curve](<https://en.wikipedia.org/wiki/Hypercycle_(geometry)>)).

| Height above or depth below a ground | Sideways lengths | Areas |
| --- | --- | --- |
| 0.4 (where rock begins) | x 1.08 | x 1.2 |
| 1.2 (where copper begins) | x 1.8 | x 3.3 |
| 2.05 (a risen ground) | x 3.9 | x 16 |
| 2.6 (where iron begins) | x 6.8 | x 46 |
| 3.18 (a tower three edges high) | x 12 | x 145 |
| 4.5 (the bottom rock band) | x 45 | x 2,000 |
| 5.3 (the bottom of the caves) | x 100 | x 10,000 |
| 5.94 (the underside of the default world's ground) | x 190 | x 36,000 |

What follows:

- **Towers lean apart.** Two towers one edge apart at the base are 2.9 edges apart at the height of a risen ground and 4.9 edges apart three edges up.
- **The deep is enormous.** At iron depth, the rock under one ground tile has 46 times the tile's area. In the bottom band it has about 2,000 times.
- **Go up to go across.** Two shafts sunk side by side are far apart at the bottom.

**Borrowed.** HyperRogue's Ivory Tower is this fact as a level: [two ladders that start close end far apart](https://zenorogue.itch.io/hyperrogue/devlog/63392/hyperrogue-110-released). Its Free Fall land is a fall beside an endless tower where the space widens as you drift out.

### A level throw can stay up

**Exists.** A law the tests check: "A body launched level at speed v at height h over flat ground falls slower than one dropped from rest: after a time t its downward speed is less by v^2 tanh(h) t."

**Numbers.** Gravity is 1.6, so a body holds its height when v^2 tanh(h) reaches 1.6. That takes a speed of 1.86 at height 0.5, 1.45 at height 1, 1.29 at height 2, and never less than 1.265. A thrown block leaves at 1.4 forward. If thrown blocks obey the same law, a level throw from above about 1.15 does not come down, and from higher it climbs. Walking takes off about 3 percent of gravity at most.

This is the nearest thing caapi has to orbit, and nobody designed it. See [sling lines](#up-gravity-and-grounds).

### Loops turn things by their area

**Exists.** The five-leg walk closes, and the compass comes back a quarter turn off.

**Numbers**

- On a ground, a thing carried around a loop comes back turned by the area the loop encloses, in radians. A tile's area is half of pi: a quarter turn.
- So the compass measures land. Walk the boundary of a field and the compass has turned a quarter for every tile's worth inside.
- Off the ground, loops along cell edges give quarter turns about three axes at right angles. Together those make exactly 24 orientations, the same 24 the wiki counts for a molecule in a pocket.
- A loop that does not go around whole faces leaves a thing skew.

**Borrowed.** The south-pointing chariot was a geared cart whose pointer kept its direction while the cart turned. Santander showed in 1992 that such a pointer is carried the way geometry carries a direction along a path, and offered the cart as a device for seeing curvature ([summary and follow-up](https://arxiv.org/pdf/0906.0288)). caapi's compass is one.

### Light and sound do not carry

**Numbers.** A point source spreads over a sphere of area 4 pi sinh^2(r), where flat space has 4 pi r^2. Compared with flat space it is 3 times dimmer at 2 units, 11 times at 3, and 220 times at 5.

If light and sound follow the geometry:

- A lit, busy base is an island. You come home by walking into the sound.
- A beacon cannot be a lighthouse. It has to be tracked, as it is now, or relayed.

**Borrowed.** Hypermine's [wiki](https://github.com/Ralith/hypermine/wiki) lists the dispersal of energy among the consequences its design has to face, next to navigation.

### From above, a whole ground is a small disc

**Numbers.** From height h, every line of sight that will ever meet the ground lies within an angle of 2 atan(e^-h) from straight down (the [angle of parallelism](https://mathworld.wolfram.com/AngleofParallelism.html)). That is 62 degrees from half a unit up, 40 from 1 unit, 15 from a risen ground, and under 5 from a tower three edges high.

So from a risen ground the whole endless ground below is a disc you could cover with a hand. It looks like a planet. A view from height is already a map, and a narrow field of view, which is a perception channel, is a telescope. The engine only draws nearby cells, so a real version needs a drawn chart (see [Out](#out-distance-and-the-way-back)).

## Directions instead of tiers

The crafting ladder (wood, stone, copper, iron) is the least "caapi" part. It is fine as scaffolding, but it is the one tier system that does not come out of the world's own logic. The world has better tiers hiding in it, as directions rather than levels. Each direction is a specialized subsystem with its own tiers, and the content lives where two directions cross.

### Down: geology

**Exists.** Rock bands by depth, shifted by strata. Ores form only in certain rocks, which puts sulfur at about 0.4 to 1.2 down, copper at 1.2 to 2.6 and iron below 2.6. A vein is a ball of radius 2 voxels, in 8 percent of chunks. Pickaxe tiers gate the harder stones and ores, and a block that needs a better tool "does not crack however long you hold". The caves change theme with depth: frost, dripstone, gypsum, crystal, then basalt columns (the ember theme). Lava, snow and ice are blocks.

The caves are no longer a world apart. They lie under the default world: sinkholes open them on wild ground, and under the city, the backrooms and the vaults they are sealed and reached by wells. Built ground is soil over the same rock bands and veins as wild ground, where it used to be dirt all the way down. The ground also ends. Under the default world's wild ground the rock stops 5.6 edges down (5.94 units), a little below the deepest cave, and a lattice hangs in the open below it. The details are in [Worlds](#worlds-one-default-world-that-holds-the-others).

**Numbers.** The deep is big (table above). The copper band has 3 to 46 times a tile's area under each tile, and the iron bands have more. Sideways travel down there is 7 times longer at 2.6 and 45 times longer at 4.5.

**Ideas**

- **Geology the player can read.** Make every metal come from geology the player can read. Rock bands are already visible in cuts and caves, and an ore's host rock is a clue to where the next ore lies.
- **One rule for tools: harder cuts softer.** Drop the arbitrary pickaxe numbers and gate by what a tool is made of. Give each material a hardness, and let a pick cut whatever is softer than its head. The scratch test is in the game already: one swing either cracks the block or does not. Mohs's scale of minerals works the same way, each one scratching those below it.
- **Signs on the surface.** A vein is a function of its cell, so its signs can be too. *Float*: loose bits of ore in the cover over a shallow vein. *Indicator plants*: wild plants over a vein differ from their neighbors. Copper already makes a charged graft, so a fern growing over copper could carry one more charged fragment. You would taste the ore, or read it with an assay kit.
- **Farming metal.** A bred strain that concentrates what is under it. Press it for a charged graft, or burn it for copper. That gives plants something to hand back to geology.
- **Heat with depth.** Warmth already falls with height (lapse rate 0.3). Let it rise with depth, so deep work needs cooling, and cold compounds or frost air matter down there.
- **Ice goes down, heat comes up.** Snow and ice sit on cold high ground. If the deep is hot, ice is cargo, and carrying it down buys working time. Lava carried up heats a forge or a glasshouse.
- **The forge tier.** Lava and the ember band of the caves as the forge tier. Melting needs heat you go down to fetch, or pipe up.
- **The deepest band as a place.** Gabbro, olivine and basalt as a place, not just a layer. Ember stones belong here (see [In](#in-perception-and-hidden-families)).
- **The shaft is the bottleneck.** With that much rock below and sideways travel so long down there, a mine is limited by its shaft. Chutes go down for free. Coming up is the work.
- **Caves hold air.** A collector in a low chamber could fill faster or richer than one on the surface. A deep chamber rich in ash would be a breeding room, since ash raises the odds of mutation.
- **Built worlds as ore.** Salvage already turns steel into iron and lamps into glass. The city, the backrooms and the library are mines of worked material: steel is found, not smelted, until you understand alloying. That gives the ruins a reason to exist in play.
- **The lattice is a steel yard.** Its poles are steel and its girders concrete, and it now hangs under the default world. It is the largest store of worked metal there is, and the hardest to stand on while taking it apart.
- **Undergrowth above a void.** The owner's picture for what lies under some grounds: the caves as a layer of undergrowth, and under them an open void world, "like that of the lattice and whatever is next". The underside of the ground is then a place of its own: a ceiling of rock with things hanging from it.
- **Sealed means kept.** A sealed cave under a built ground has had nothing leave it. It could hold what open caves lose: richer air, and the hidden-family stones the glow and ember themes already carry.

**Borrowed**

- Vintage Story [ties each ore to rock layers](https://wiki.vintagestory.at/index.php/Ore_Deposits), marks shallow deposits with loose ore stones on the surface, and gives a [prospecting pick](https://wiki.vintagestory.at/index.php/Guide:Prospecting) with a wide reading and a close one. Its in-game handbook teaches the rock layers.
- [Geobotanical prospecting](https://en.wikipedia.org/wiki/Geobotanical_prospecting) is real. The copper flower of central Africa grows almost only on copper-rich soil, and [prospectors used it](https://nzsm.pages.dev/article995.htm) in the 1950s to map ore across the Copperbelt.
- So is phytomining. Some plants hold metal in their leaves at [hundreds to thousands of times](https://smi.uq.edu.au/node/14778) the normal level, and one nickel plant reaches 2.5 percent. They are [harvested for the metal](https://ausimm.com/bulletin/bulletin-articles/growing-nickel-from-trees). It has stayed small because it is slow, which is a fair price for a game too.
- At Mponeng gold mine the rock face would reach about 60 degrees C without cooling. The mine [makes about 5,000 tonnes of ice a day](https://iifiir.org/en/news/mine-cooling) and sends it underground, because [ice carries far more cooling than chilled water](https://files.chartindustries.com/Howden_MineCooling_Case_Mponeng.pdf) for the pumping it costs.
- Naica's Cave of Crystals holds gypsum crystals meters long in air near 48 degrees C and 90 percent humidity. Explorers [wore ice-cooled suits](https://www.nationalgeographic.com/adventure/article/101007-lost-crystal-caves-mexico-science-mine-superman-ice-palace) and still counted their visits in minutes. caapi's caves already pass gypsum chandeliers and crystal beams on the way down.
- Starbound [groups its biomes by tier](https://playstarbound.com/?p=2697) and opens the next group when the player has gear against cold, heat or airlessness. caapi can make the same gate out of climate and the body instead of a backpack.

**Open.** What is at the very bottom? Under the default world it is now the lattice, in the open; whether it stays that way, and what a fall into it costs, are in [Decisions waiting](#decisions-waiting). Does the deep have its own air?

### Up: gravity and grounds

**Exists.** Gravity pulls toward the nearest ground, and the pull turns smoothly as you climb between grounds. Risen grounds (wild, city, backrooms, library) are joined by connector buildings in four styles, about 2.05 up. The lift signal lowers gravity (gain -0.8) and raises the jump (+0.8). The lattice inverts gravity. Giant trees and Babel rise as upright grounds. Vaults rise as a ground too, and nothing is built up to them: a ground can be marked as having no bridge, and then neither it nor anything rising from it gets a connector. Groves of lattice frames stand on some wild ground, about two edges tall.

**Numbers**

- A jump rises 0.085 x e^(0.8 x lift): 0.13 at lift 0.5, 0.19 at 1, 0.42 at 2, 0.94 at 3. The band halfway to a risen ground is about 1.0 up, so a standing jump reaches it at a lift of about 3.1. For scale, the test dose in `biology/dosed-climb` had the mist signal at 0.35 one second in. Lift alone will not do it. A tower and lift will.
- A risen ground is close to the one below only near its connector. If both are planes, the gap is 2.05 at the connector, 2.5 one unit to the side, 3.4 at two units and 5.3 at four.
- Towers lean apart (table above), so bridges get long quickly. The crown's bridges are the short kind.
- A deck at the height of a risen ground has about 16 times the area of its footprint.

**Ideas**

- **Lift as a way up that skips the stairs.** Dosed enough, you can jump onto a risen ground or float between two of them. Halfway between two grounds the pull changes sides, so there is a weightless band to exploit.
- **Launch towers.** Build up to just under the band, dose, and jump the rest. Coming down is the problem: the dose wears off with rebound, and rebound on lift is weight. Plan the way down before the way up.
- **Grounds with no stair.** Risen grounds you can only reach while dosed: no connector, just a gap that lift crosses. The vaults are the first: the owner asked that the more abstract structures have no bridges to them. Today nothing reaches them at all, so the way there is still to be chosen (see [Decisions waiting](#decisions-waiting)).
- **Gravity conveyors.** Things fall up there too. Thrown blocks already fall toward the nearest ground. Items, water and echoes could follow the same rule, so a drop from a risen ground carries cargo down by itself.
- **Sling lines.** By the game's own law a level throw from a height can stay up. Tower to tower, with something at the far end to catch, is long-range transport with no road. One echo throwing to another is also what the Last Clockwinder's clones do.
- **The connector is a port.** Two grounds are only close at the connector, so everything that passes between them wants to be there. Put the hub at the foot of the stair.
- **Up as an economy.** Risen grounds have their own climate and air (relief raises ash, lowers warmth), so they grow different plants. They are the places to farm what will not grow below.
- **A pit of climates.** Warmth is heat minus 0.3 x relief, per cell. If a plant read the height it actually stands at, a terraced pit would be a row of climates a few steps apart: dig down for warm, build up for cold. A breeding station made of earthworks.
- **Build wide up high.** Decks have room that footprints do not. The arbor's decks and Babel's floors could flare, and a base could grow the way the arbor does.
- **Show which ground has you.** In the band the pull turns over, and a player needs to read it at a glance: a tint for the pulling ground, a shadow that falls toward it, mist lights along the band.

**Borrowed**

- John Murra's ["vertical archipelago"](https://mapaspects.org/book/export/html/1929/index.html): Andean communities held plots at many altitudes to get what each zone grows, and reached them by travel, not by trade. Later scholars question how far the model reaches. The pattern is the one caapi's grounds invite.
- [Moray](https://assets.atlasobscura.com/places/moray), near Cusco, is rings of terraces in a hollow with as much as 15 degrees C between top and bottom. It is widely read as a crop testing station, though its purpose is not settled.
- Super Mario Galaxy pulls Mario toward the surface under him using [invisible regions that aim gravity at simple shapes](https://mariowiki.com/Gravity), and marks its stranger gravity fields with arrows.
- Manifold Garden gives each of six gravity directions [a color](https://www.pcgamer.com/uk/manifold-garden-review), and tints the surfaces and objects that belong to it. Even so, its developer spent [about 2,000 hours of playtesting](https://en.wikipedia.org/wiki/Manifold_Garden) on keeping players oriented.
- HyperRogue's [Ivory Tower and Yendorian Forest](https://www.roguetemple.com/z/hyper/gallery.php) are gravity lands built on curves at a fixed distance from a line, which are the surfaces caapi's decks would sit on.

**Further out.** A flat sheet. A horosphere is a surface inside this space whose own geometry is flat. HyperRogue builds lands on its two-dimensional cousin, the horocycle. A flat sheet would be the one place a square path closes and belts run side by side. It would not line up with the honeycomb, which is the hard part.

### In: perception and hidden families

**Exists.** Three hidden families, mist, ember and tide. Each is revealed when its channel rises above 0.6, and fades again below 0.4. Revealed blocks are solid, except while you are inside them. Only mist has anything that reveals it: the mist signal (gain 2) and the mist-sight preset. The strange stones and lights break by hand, so the player can already carry them and build with them. In the base mapping, mist drives reveal and a color turn, sway drives warp, field of view and afterimage, and lift drives gravity and jump. Two plants hold a signal down instead of pushing it up: thornbush closes mist and moss dulls.

From the review: ember and tide are "the most obvious open door".

**Ideas for what reveals them**, built on the signaling that exists:

- **Tide is revealed by rebound.** Signals adapt over about 100 seconds, so stopping a dose leaves a signal below rest. Tide shows when a signal is pushed negative. Withdrawal becomes a way to see, and the adaptation that is now only a nuisance becomes a mechanic. Tide stones sit by water and lake beds.
- **Thornbush is already a tide key.** If tide shows when a signal is below rest, thornbush does it directly and rebound does it for free. The driest plant shows the water.
- **Ember is revealed by two signals at once.** The third messenger follows both triggers and is raised by the other two. Ember shows when mist and lift are both high, which only a designed compound or two well-timed doses can do. Ember stones sit in the deep caves' ember theme and in ash-heavy high ground.
- **Leaving a place can be the dose.** If strong air acted on the body without a collector, living in a mire-rich swamp would adapt you to it, and walking out would leave a rebound. Tide stones by the water would show as you leave. Nothing has to explain it.

**Ideas for what the families are for**

- **Each family reveals a layer of the world**, not only stairs: mist for paths, ember for heat and ore (veins you can only see dosed), tide for water and flow (where liquids and items would run).
- **Each has a real sense behind it.** Mist is ultraviolet: marks that were always painted on things. Ember is heat. Tide is the sense of flow that fish have along their sides. A family with a sense behind it tells the designer what belongs in it.
- **See first, stand later.** A crafted lens shows a family without making it solid. The dose makes it real. The lens is the rumor and the dose is the proof, which is the order Outer Wilds teaches in.
- **Hidden blocks are wiring layers.** A mist stair is solid to a dosed body and air to everyone else, so two routes can cross in the same space without touching. Three families are three more layers, like underground belts or the layers of a circuit board. An undosed echo walks through the wall that a dosed echo climbs.
- **The world is your gauge.** Let hidden blocks thin as their channel falls from 0.6 to 0.4. The stair under you says how long you have. It says the same about an echo you are watching.
- **Private signs.** Mist lights show only to a dosed eye. Mark the dosed route with them.
- **Lattice sight.** A channel that shows the honeycomb itself: cell edges, which are the rails that keep cargo square, and the straight line to a beacon.

**Ideas for perception as a tool**, not only a hazard:

- Fine detail sharpens grain, and grain already varies by material, so ore stands out under sharp. Narrow plus fog hides distant things and reveals near ones. Presets could become something you craft (lenses), not just a creative key.
- A narrow field of view is a telescope. From a height it reads the ground below.
- Eye offset moves the eye behind the body. Pushed far, it is an overview: you leave your body to look at the base.
- Afterimage leaves trails. Lengthened, it turns moving echoes into flow lines, which is a traffic map.
- A color turn could separate two strains that look the same in plain light.

**Ideas for comfort**

- Comfort already scales down the strongest effects. Keep that promise everywhere.
- **Unpleasant channels are costs, never keys.** Today the keys ride on mist and lift, and sway carries the warp. Keep it so. What a player must use is comfortable, and what is uncomfortable is what a better molecule removes.

**Borrowed**

- Heinrich Klüver sorted the geometry of hallucination into four form constants: tunnels and funnels, spirals, lattices including honeycombs, and cobwebs. Bressloff, Cowan and colleagues later [derived them from the wiring of the visual cortex](https://pubmed.ncbi.nlm.nih.gov/11860679/). caapi's world is a honeycomb, so an altered eye that sees the lattice is on theme twice.
- Many flowers carry [nectar guides](https://en.wikipedia.org/wiki/Nectar_guide), and some show only in ultraviolet, which bees see and people do not. That is a hidden family in nature.
- [Didymium glass](https://www.chemistryworld.com/opinion/weiderts-and-tillyers-glasses-the-didymium-lens-story-part-2/4024037.article) cuts out the yellow glare of hot sodium, so a glassblower can see the work inside the flame. It reveals by taking light away, and it would suit ember.
- Hyperbolica's players list [motion sickness](https://vaporlens.app/app/1256230/hyperbolica) among their complaints. Hyperbolic space is hard on the stomach before any dose is added.

### Out: distance and the way back

**Exists.** The space grows exponentially, so the cells within reach more than double with every step. A compass holds its direction and comes back turned after a loop. Beacons are tracked by distance and direction. The thread lays beads, halves itself when full, and winds back up. Explored cells are remembered. Climate drifts from cell to cell, so far away is a different land.

**Numbers**

- Aiming fails (see [above](#room-is-free-closeness-is-scarce)): 1 degree off is more than a tile at 5 units.
- Heat and wetness keep 0.94 of their value at each step, so they forget where they started in about 16 cells. Broad relief takes about 12, ruggedness about 10, strata about 4. A different land is about 16 cells away, in a great many directions.
- An edge takes 4.7 seconds to walk and lays 21 beads. A lap of a tile takes 24 seconds.

**Ideas**

- **Far means rare.** Because the space is exponential, there is always more out there, and specific things are hard to find again. The frontier is a resource: a climate that suits a plant perfectly (fit near 1, yield 3) may lie twenty cells out, in one direction only.
- **Getting home is the hard part.** Make every way out pay into a way back: beacons as an infrastructure you build, thread as a path an echo can walk (see [Automation](#automation-the-player-is-the-machine)), and roads along geodesics that never bend.
- **Led, never told.** Every aid should lead step by step. A waypoint that only gives a bearing is useless past a few units.
- **The home star.** Put fixed stars at infinity. Moving through this space [reshapes the whole sky at once](https://wikiwand.com/en/articles/Sphere_at_infinity), and one consequence matters: wherever the stars are spread evenly is a center, and as you walk away from it the stars crowd toward the way back. Half of them lie within 40 degrees of that direction after 1 unit, 15 after 2, 6 after 3 and under 1 after 5. Far out, the sky is one bright point on the horizon, and coming home is the sky opening. It depends only on where you are, never on your route, so it is the one thing in the world that loops do not turn. (These numbers were worked out for this file, not found in a source.)
- **Keeping the home star from being a free arrow.** Stars show only in the dark, so a lit base hides them and the wilds show them. Or stars show only to an altered eye. Or each hidden family has its own sky, centered on a different place worth finding.
- **The compass measures land.** A quarter turn for each tile enclosed. The journal can say so the first time it happens.
- **Sniff the climate.** The air is a formula of the climate: mire rises with wet and heat, frost with cold, ash with height and strata. Three collector readings a short walk apart say which way it gets wetter. The collector is a weather instrument, and the plants are a map: birch means cold, willow means wet, acacia means warm and dry.
- **Perception warps navigation.** Warp and color turns could tilt how you read the compass. Deep perception trips need a beacon to come back to, because your own sense of direction lies.
- **Maps that only you make.** No global coordinates exist, so no map exists until you make one. A cartography station turns explored cells and beacons into a chart of the graph, not of a plane: what is adjacent to what. The chart could be the disc the hyperbolic browser used, dragged to refocus, or it could be what you would see from high enough.
- **Relay roads.** If an echo can only go so far from its anchor, a long road is a chain of echoes with a hand-off post between each pair.
- **Roads along edges.** Edges are straight, they meet at right angles, and cargo carried along them stays square. There is no second lane: a line beside a straight road is either longer or drifts away from it.
- **Worn paths.** Where you and your echoes walk often, the ground wears.
- **Knots in the thread.** A mark tied at a bead is a note left on the way. The thread halves itself when full, so a long route is remembered coarsely, which is the right kind of forgetting.
- **Holonomy as a puzzle and a tool.** Five legs with right turns close a loop and turn you a quarter. Anything carried around a loop comes back rotated (see [Logistics](#logistics-in-a-curved-space)).

**Borrowed**

- [Etak](<https://en.wikipedia.org/wiki/Etak_(navigation)>), from the Caroline Islands: the navigator treats the canoe as standing still and tracks a reference island sliding past the stars. Position is a relation, never a coordinate. caapi already stores a place that way.
- [Marshall Islands stick charts](https://en.wikipedia.org/wiki/Marshall_Islands_stick_chart) map swells and how islands bend them, not distances. They were [memorized before a voyage](https://www.amusingplanet.com/2016/02/the-stick-chart-navigation-of-marshall.html) and were often readable only by their maker. A chart of what is next to what would be the same kind of thing.
- The Inca roads ran on relays. [Chasqui runners](https://www.thecollector.com/chasquis-famed-inca-couriers/) waited at posts a short run apart and passed on messages and knotted-cord records called quipu. A message could cross about 2,000 km in a week.
- Death Stranding [wears a path](https://pcgamer.com/death-stranding-relaxed-me-so-hard-i-became-a-road-building-madman) into ground that is walked often, the way [desire paths](https://media.cordite.org.au/degrees-of-freedom-in-live-space/) form in a park. There it is other players' feet. Here it would only ever be yours.
- Subnautica ships [without a map](https://steamcommunity.com/app/264710/discussions/0/1693785035819973504/?l=latam) on purpose, with a compass and beacons instead, and players have asked for a map ever since. The lesson cuts both ways. No map makes being lost matter, and the aids have to be good enough that it stays fun.
- HyperRogue's Land of Eternal Motion: a pursuer who cannot share your straight line has to take [the longer curve beside it](https://zenorogue.blogspot.com/2012/03/hyperbolic-geometry-in-hyperbolic-rogue.html) and falls behind. That is the reason there is no second lane.

## Worlds: one default world that holds the others

**Exists.** From the code and its tests.

- **Seven worlds.** `planet`, `city`, `backrooms`, `library`, `vaults`, `caves` and `lattice`. `planet` is the default world and the only one that holds others: its root is wild ground, and city, backrooms, library, vaults and more wild ground rise from it.
- **Single buildings are debug structures, not worlds.** `tower`, `crown`, `palace`, `arbor`, `babel`, `road`, `trail` and the test rigs are reached by `--worldgen debug <name>` and by the tests, and the world menu does not list them. The default world still stands `arbor`, `babel`, `crown`, `palace`, `tower` and `trail` once each around spawn, and builds the road through it.
- **Caves under everything.** On wild ground they open as sinkholes, at 2 in 100 vertices, with one forced near spawn. Under the city, the backrooms and the vaults they are sealed and begin about two edges down. The library has its stacks below it and gets none. A single-structure world gets caves only if it asks for them.
- **Ports and wells.** A port is a ground vertex, 3 in 100 of them, where the street, the floor or the hall leaves a hole 8 cells square. A spiral stair runs from it two edges down to a cave that is always open. In the backrooms the well's column is left open on every level it passes, so it should also be a second way between levels; that is read from the code, and only the top level has been looked at. No port sits where a world starts, where a connector lands, or where a ground rises.
- **The ground has an underside.** 5.6 edges down under the default world's root, below the deepest cave, and 3.4 edges down under risen wild ground and under vaults. City and backrooms are rock all the way. Below the underside it is open, and the lattice hangs there. The look and the fog change on the way down: cave dark below half an edge under wild ground and below 1.5 edges under built ground, lattice dark below the underside.
- **Groves.** On 15 in 100 clusters of wild faces a frame of lattice poles and girders stands on the ground, with its poles sunk an edge into it.
- **City districts.** Five of them (midtown, downtown, rows, works, green), each a cluster of faces with its own lots, street trees, parks and parking.
- **Backrooms subtypes.** A biome is picked per region of faces two rings wide, and per level, and it sets more than the wallpaper: pillar halls, pools, and courtyards open to the sky, beside the rooms, rings, chapels and mazes there were. Eight office biomes, five house biomes, five maze biomes.
- **Library rooms.** Atriums, study rooms and lounges among the shelves.

**From the owner**, in the conversation that made these changes:

- "I don't want boring areas to exist."
- "There should be caves and rock and variety under anything that was just all dirt or something."
- The more abstract structures should not have bridges to them.
- On the backrooms: it "has different subtypes and various things", the way the Minecraft mods do it. It felt far too uniform, with no places that feel different.
- On the library: "think local american library but infinite. Big areas, small areas, rooms with things. Entrances that sometimes loop and sometimes don't."
- On what lies under the ground: some of it "should be sort of undergrowths above a void world like that of the lattice and whatever is next."
- On single-structure worlds: caves under them are "no by default but with an option for yes", and they "should transition into more debug than being presented as co-equal to a world, let alone a world that embeds others".

**Numbers**

- The underside of the root ground is 5.94 units down. A level surface there is 190 times longer than the ground in every sideways direction, with 36,000 times the area. So the open space just under one ground tile has the floor area of 36,000 tiles.
- A body let go 6.4 units under spawn fell half a unit in its first second and landed on a lattice girder. That is from a test, and it is the only measurement of the void there is.

**Ideas**

- **A test for places.** "No boring areas" could stand beside the seven tests: is there a stretch of this place, in any direction including down, with nothing in it to find?
- **A port is dressed by its ground.** Today every port is the same bare hole with a stone stair. A manhole in the city, a stairwell door in the backrooms, a broken inlay in a vault floor.
- **A port you can predict.** Today a port is a flat roll. It could follow something the ground already shows (the `works` district, the `sump` biome, a vault with a spire), so that a player who knows the rule knows where to look.
- **The underside can be read.** From the void, the ground overhead could show what stands on it: roots, footings, the bottoms of wells.
- **A grove is a sign.** Grove poles already go an edge into the ground. If the void's poles came up through the rock to meet them, a grove on the surface would mark a way down.
- **A fall has to end somewhere.** Under the root nothing catches a body but the lattice itself. What a fall costs is the first thing to decide about the void.
- **Whatever is next.** Candidates for the void world after the lattice: the flat sheet, a sky with fixed stars, a ground hung upside down from the crust, a sea.
- **Debug structures still carry lessons.** The crown's loop that leaves the ground, the arbor's wide decks. Each needs a home in a real world, or it is only reachable by a flag.

**Open.** The choices this left were put to the owner and answered: see [Decisions waiting](#decisions-waiting). None of the answers is built yet.

## The living chain

The chain from climate to movement is the model for everything else, and the first draft gave it one row of a table. These sections give each link room.

### Climate and air: every place has a use

**Exists.** Six climate quantities drift from cell to cell. Warmth is heat minus 0.3 x relief. The air holds three gases set by climate: mire where it is wet and hot, frost where it is cold, ash where relief and strata are high. A collector gathers each at its level x 0.02 a second for up to 120 seconds, so it holds at most 2.4 x the level. Three things already work by where they stand: a plant through fit, a collector through the air, and the bench through ash.

**Ideas**

- **Every station reads its place.** Make those three cases the rule. A furnace works by warmth. Drying works in dry air. The bench already works by ash. Then each climate is good for some kind of work, and work has a reason to be somewhere.
- **This is what gives logistics a purpose.** In Factorio you move ore because ore is in one place. Here conditions are in one place too: the hot deep, the cold heights, the ashy ridge, the wet lowland.
- **Or build the place.** Glass and a heat source make a glasshouse. Water nearby raises wetness. Ice lowers warmth. A terraced pit gives a row of climates. So "this plant wants it warm and wet" has two answers: walk sixteen cells to where it is, or haul heat and water to where you are. Two real answers make it a design question.
- **Process air.** A furnace fed ash-rich air, or starved of air, could give a different product. Charring is already an insight: wood in a furnace's heat turns to charcoal. Steel could be iron worked with charcoal where it is hot enough, which is the alloying the [Down](#down-geology) section waits for.
- **Pipes for air.** Collectors already gather gases by climate. Pipes could carry air from where it is rich (ash on high ground, mire where it is warm and wet) to where it is needed (the bench, for mutation).

**Open.** Does standing in strong air ever dose you without a collector?

### Plants and breeding

**Exists.** Four plants, each thriving in one climate. Every living block carries four genes: one builds the compound's scaffold, two encode enzymes, and one is kept for form. Genes drift from cell to cell, so the same plant makes different compounds in different places. A planted plant ripens in 60 seconds and yields 1 + round(2 x fit). At the bench a cross takes each gene from one parent, with mutation odds of 0.05, plus 0.3 x the ash in the air, plus 0.3 with sulfur.

**Numbers.** Yield comes in three bands, and a player can feel all three.

| Fit | A ripe plant gives | Spare after replanting |
| --- | --- | --- |
| under about 0.25 | 1 | none: the garden only keeps itself alive |
| about 0.25 to 0.75 | 2 | 1 a minute per plot |
| over about 0.75 | 3 | 2 a minute per plot |

In climate terms: fern is rich where wetness is above 0.22 and barren below -0.32. Moss is rich where warmth is below -0.22 and barren above 0.32. Thornbush is rich where warmth minus wetness is above 0.27 and barren below -0.27. Flower is rich within 0.47 of zero wetness and zero warmth, and barren beyond 0.88.

**Ideas**

- **The plant table has gaps, and gaps are content.**

  | Receptor | Pushes it up | Holds it down |
  | --- | --- | --- |
  | A | fern (wet) | thornbush (arid) |
  | B | cactus, mushroom cap | nothing yet |
  | C | nothing yet | moss (cold) |
  | A and B | flower, petals, pollen | nothing yet |

  Four climates have no plant of their own: hot and wet, high and ashy, shores and lake beds, and the deep. A player who has learned the table can predict that an opener for C exists and guess where it grows.
- **Chemotypes are already here.** One species making different chemistry in different places is a real thing with a name. Name strains by where they came from, and let the journal keep the pedigree.
- **Use the fourth gene.** It is kept for form and does nothing yet. Let it show as leaf shape, color or height. Then part of a genome can be read by eye, the way Mendel read his peas, and breeders get visible markers. It could also carry the farm traits: growing time, tolerance, yield.
- **Grafting.** Roots from a plant that suits the place, and a top from the plant whose compound you want. Thornbush roots would let a fern grow in the desert. (The lab already uses "graft" for adding a fragment, so one of the two needs another word.)
- **Dark earth.** Charcoal exists, clay exists, and pressing a plant could leave pulp. Worked together into the ground they make a soil that lifts fit a step and stays. The oldest part of your base would be the richest.
- **You are the bee.** Petals and pollen are living blocks. Let pollen carried from one plant to another make a cross in the field, as well as at the bench. Then breeding is something an echo can do by walking.
- **Rings of mutation.** Mutation odds rise with ash. If ash thins with distance from a source, a ring garden is a dial: the inner rows churn and the outer rows hold. In this space each further ring has far more room than the last.
- **A seed vault.** A block that keeps lines apart and shows who was crossed with whom.
- **Companions.** A mixed bed that out-yields a single crop, as maize, beans and squash do. Mixed beds are harder to automate, so it is a real trade.
- **Fungal threads.** Giant mushrooms exist. A network you plant between them could carry compounds, not items, from cap to cap: a pipe that is alive.

**Borrowed**

- A [chemotype](https://en.wikipedia.org/wiki/Chemotype) is a chemically distinct group within one plant species. Thyme has several.
- When phylloxera wrecked Europe's vineyards in the 1800s, the fix that stuck was [grafting European vines onto American roots](https://www.guildsomm.com/public_content/features/articles/b/kelli-white/posts/grapevine-rootstocks). The root resists the pest and [the top keeps the variety](https://www.decanter.com/learn/grafting-46360/).
- Terra preta, the dark earth of the Amazon, is poor soil worked with [charcoal, pottery shards, bone and waste](https://www.sciencefocus.com/planet-earth/amazonian-dark-earth-climate-change) by the people who lived on it. It is still fertile centuries later, and [farmers still plant in it](https://dialogue.earth/en/?p=50026853). How deliberate it was is still argued.
- [Gamma gardens](https://en.wikipedia.org/wiki/Atomic_gardening) of the 1950s set plants in [rings around a radiation source](https://www.atomicgardening.com/1958/10/01/rebuilding-plants/), so distance set the dose. The rows worth keeping were [the ones that looked normal but had changed](https://atomicgardening.com/?p=426).
- Forestry's bees are the best-known genetics in modded Minecraft: a genome of paired alleles, climate tolerances, and mutations that only happen in certain biomes. They are also a warning. Traits cannot be seen without an analyzer, and the pairs that make a new species are [found with tools, a wiki page, or trial and error](https://ftbwiki.org/Apiculture). That fails the test "a rule, not a list".
- [Creatures](<https://en.wikipedia.org/wiki/Creatures_(video_game_series)>) (1996) simulated its animals from genes through biochemistry to behavior. Soon after release [players were cutting genes out of one species and splicing them into another](https://www.tes.com/news/gene-genies). Simulation from the gene up holds people, and it needs windows to see through.
- The "wood wide web" comes with a caution. Fungi do link roots, but a 2023 review found the popular claims about trees feeding and warning each other [run ahead of the evidence](https://www.nature.com/articles/d41586-024-00893-0). As fiction it is still a good pipe, as long as the player has to plant it.

### Compounds: one chemistry for everything

**Exists.** A compound is a 3 x 3 x 3 grid of fragments, each with any mix of three properties: bulky, charged, polar. The whole molecule can also be conjugated. A press turns a living block into extract and four extract into a dose. Six lab reactions change a dose, each acting on "the first cell it finds" across 24 orientations. A dose is swallowed, inhaled or injected. An assay kit shows which receptors a compound binds.

**Ideas**

- **Three properties, everywhere.** The lab recipes already sort the world. Polar comes from clay, water and ice. Charged comes from copper ore and strange stone. Bulky comes from stone, gravel, lava, masonry and strange stone. Conjugant comes from leaves and cloth, and oxidizer from sulfur. Turn the pattern into the rule: every block has a signature, and a graft can be made from anything that carries the property. A player who meets a new block can then guess what it gives.
- **Tests you can watch.** Give each property one visible test, so a molecule can be worked out by experiment. Polar: a strip of paper that separates an extract into bands. Charged: a flame or a spark that changes color. Bulky: how fast it settles. Then the assay kit is a shortcut, not the only window.
- **Make orientation physical.** Today a reaction acts on "the first cell it finds", which is opaque. Give a molecule an orientation, give each station a fixed reaction site, and let the route a compound took decide which part of it is changed. Geometry becomes chemistry, and it is visible.
- **Samples hold their orientation, like the compass.** Turning a sample in your hands does nothing. Only a route turns it. Otherwise nobody would walk a loop to do what a wrist can do.
- **Ground loops give four turns of the 24.** The other twenty need a loop that leaves the ground. The crown already has one: up a tower, across a bridge, down the next, back through the hall. This is where Up meets chemistry.
- **Handedness.** No route turns a molecule into its mirror image, because the 24 orientations are all rotations. So a molecule and its mirror are different compounds, and a pocket fits one hand. Handedness could be something only breeding changes. Or one strange place could flip it.
- **Names you can learn to read.** A name is three syllables computed from the shape. If each syllable reported one thing, such as how bulky, how charged and how polar, names would be a language a player slowly decodes.
- **The library as the catalog.** There are on the order of 10^25 possible molecules. In a space where each step multiplies the cells within reach, that many shelves fit within about thirty steps of a door. So every compound could have a shelf in the library, and the walk to it could spell its shape. A reading room that shows what a shelf's compound would do to your receptors is a planner you reach on foot. This is far out, and it is also exactly what an endless library is for.
- **Byproducts.** Pressing leaves pulp, which the dark earth wants. The body's enzymes turn one compound into another, so a designer aims at what a dose becomes.

**Borrowed**

- Breath of the Wild's "chemistry engine" is the model for a small rule applied everywhere. Its technical director called it [a rule-based state calculator](https://www.thumbsticks.com/gdc-17-breath-of-the-wild-science-lies), and it runs on [three rules](https://gamesbeat.com/the-legend-of-zelda-breath-of-the-wild-makes-chemistry-just-as-important-as-physics/): elements change materials, elements change each other, and materials do not change each other. Players only had to learn the rules.
- Thief's Dark Engine let any object [give off a stimulus that spreads by contact, radius or flow](https://thief.fandom.com/wiki/DromEd/Properties/Act_React/Sources) for other objects to respond to, and The Dark Mod [rebuilt the idea](https://wiki.thedarkmod.com/index.php?title=S/R) under the same name. It is an older answer to the same wish: properties that act across a whole world, with no special cases.
- [Paper chromatography](https://www.wikipedia.org/wiki/Paper_chromatography) separates a mixture by how polar its parts are, and the result is bands you can see. It is mostly a teaching tool now, which is what caapi wants it for.
- In 1848 Louis Pasteur [sorted mirror-image crystals by hand with tweezers](https://openstax.org/books/organic-chemistry/pages/5-4-pasteurs-discovery-of-enantiomers) and found that solutions of the two piles turned light opposite ways. Handedness has been a player-scale puzzle before.

### The body: your genome is the tech tree

**Exists.** Receptor halves pair into receptors: three halves make six. A compound binds whichever way fits best, and compounds compete for a receptor. Two triggers feed three signals, mist, sway and lift, and each adapts over about 100 seconds, so a steady dose fades and stopping leaves a rebound. The blood clears a compound at 0.02 a second, faster for polar and conjugated ones. Two enzymes rework compounds, and splicing adds more. The genome holds 5 genes and has room for 16.

**Numbers.** A plain compound has a half-life of 35 seconds in the blood. One polar fragment makes it 23, two make it 17, and conjugation makes it 6. Roughly, a dose is felt for about a minute, and the body forgets it in about two.

**Ideas**

- **Sixteen slots is a build.** Eleven splices and no more. That is a budget, and budgets make specialists. If receptor halves could be spliced as enzymes are, a fourth half would add four receptors and room for a new sense. The genome becomes the tree a player climbs, made of what they found and bred. It passes the test "something they are, never a counter".
- **The caapi principle.** Ayahuasca pairs two plants. One carries a compound that the gut's enzymes destroy before it can act. The other, the caapi vine, carries compounds that hold that enzyme back, so the first survives being swallowed. Neither is enough alone. The pieces are in the game: the body's enzymes rework compounds, swallowing is the slow route, and compounds already compete for receptors. Add one rule, that enzymes have limited capacity and compounds compete for them too, and a compound that keeps your oxidase busy lets another through. Nobody scripts "plant A plus plant B". It falls out of the rule, and it is the discovery this game should make findable.
- **Compounds that need you to finish them.** A compound that only fits a receptor after your own enzyme has changed it. Splice a different enzyme and the same plant does something else. The wiki already lists "a spliced enzyme changes what a dose turns into" as a law nobody has stated.
- **Antidotes exist already.** Compounds compete for a receptor, and thornbush fits A without its trigger. So thornbush undoes fern. The journal should be able to say "this closes what that opens".
- **Holding an effect means pulsing.** The blood settles to a steady level in two to three minutes of regular dosing. But the signal adapts in about 100 seconds, so a steady level is felt as nothing. What you feel is change. Holding an effect means dosing, clearing and resting, which is a timing problem with a visible answer.
- **A dose planner.** Kerbal Space Program teaches orbits by drawing the path before the burn. The body sheet could draw the curve a dose will make before you take it: the blood level, the signal, and the 0.6 and 0.4 lines.
- **The only thing you can lose is the way back.** A proposal for the open question about danger. A dose never kills. It strands: the stair fades under you, the rebound makes you heavy, the warp turns you around. Getting lost far from home with your journal and your spools is a setback you can build your way out of, and that is one more thing blueprints are for.

**Borrowed**

- Ayahuasca is made from the vine *Banisteriopsis caapi* and a second plant. The vine's alkaloids are reversible inhibitors of the enzyme that would otherwise break down the second plant's active compound in the gut, [which is the long-standing explanation](https://pubmed.ncbi.nlm.nih.gov/6587171/) for why the brew works by mouth. People in the Amazon found the pairing long before anyone could name the mechanism.
- Codeine does little on its own. A liver enzyme [turns part of it into morphine](https://www.ncbi.nlm.nih.gov/books/NBK100662/). People with no working copy of the gene get little relief, and people with extra copies get too much. Same dose, different body, different drug.
- With regular dosing, a drug's level [settles after three to five half-lives](https://www.nps.org.au/australian-prescriber/articles/pharmacokinetics-made-easy-11-designing-dose-regimens), and a larger first dose gets there at once. caapi's numbers make that a matter of minutes.

## Crafting and learning

**Exists.** Crafting is a queue of at most 16 steps. Work for a station moves only while you are within 0.6 of one you have opened. Recipes take groups: any wood, any stone, masonry, cloth. Five insights (charring, sifting, quenching, salvage, strangeness) are learned by breaking a block or finishing work at a station, and each unlocks recipes. Two of them double a yield: charring gives twice the bars, and quenching gives twice the glass.

**Ideas**

- **Keep the ladder, rename the rungs.** Wood, stone, copper and iron can stay as scaffolding. Call each step by what the player can newly do: break, burn, cut, see, breed, repeat. The metals are how. The verbs are why.
- **Insights are alternate recipes you earn by noticing.** Add more, and let deeds trigger them as well as broken blocks: a dose that revealed something, a cross that mutated, a loop that came back turned.
- **Recipes as rules over groups.** No recipe should name one block where a group or a property would do.
- **In the world, not in a window.** Anything done in a window is hard for an echo to record and hard for a watcher to read. Where a station can show its work in the world, it should.
- **Insights worth adding.** Squareness (something came back turned). Rebound (you saw tide). Closure (a loop closed). Hardness (a tool failed to scratch). Terroir (one plant, two places, two compounds). Survey (the compass measured a field).

**Borrowed**

- Satisfactory hides its [alternate recipes](https://satisfactory.wiki.gg/wiki/Hard_Drive) in hard drives at crash sites, and each drive offers a choice of two. Exploring pays into the factory. caapi's version is stronger, because the trigger is something the player did.
- Botania states its rules outright: no windows for acting on the world, no pipes, no raw numbers. The aim is automation that is designed, not ["built blindly from blueprints in JEI or a wiki"](https://www.curseforge.com/minecraft/mc-mods/botania). Its author's [longer note](https://vazkii.notion.site/Stuff-you-won-t-see-in-Botania-0ec7343ddc86420baa47c8e69972d14f) puts it as acting on the world, not on a screen that changes things you cannot see.

## Automation: the player is the machine

The aim is a world that stays still unless you set it moving, where the machines are you.

### The loop Factorio runs on

Do it by hand. Get tired of it. Automate it. Find the next thing you are doing by hand. In caapi "automate" means "record", so the loop is built into the verb.

### Echoes

An echo is a recording of you, played back. You record a stretch of play; the echo replays it from an anchor, again and again, and does what you did: mines, places, carries, crafts at stations, presses, breathes from collectors.

Why it fits caapi in particular:

- **The engine is already built for it.** `Game.step(FrameInput, dt)` drives everything, and the tests, views and films are all recorded inputs replayed. `caapi --record <file>` already writes a played session out as a script. An echo is a script the player makes in play.
- **Generation is deterministic**, so a replay meets the same world it was recorded in, as long as you have not changed it. When the world differs (a block gone, a station moved), the echo fails at a visible place. Debugging a loop is the Factorio-style mastery.
- **The thread is a spool.** You already lay a thread of beads as you walk. An echo could walk a thread: lay a path, wind it into a spool, and give it to an echo.

**Borrowed**

- In The Last Clockwinder you record a short stretch of your own motion and a clone repeats it. Its rooms became [loose challenges with many solutions](https://www.meta.com/blog/designing-last-clockwinder-best-of-quest-2022/), not puzzles with one answer. Loops are [kept short on purpose](https://www.meta.com/blog/create-intricate-contraptions-from-your-own-clones-in-the-last-clockwinder-out-today/), so that you have to work with yourself, and the team's name for the feeling they were after was "Contraption Satisfaction". The idea began with knitting: repeated actions on a loop. They name SpaceChem and Opus Magnum as influences.
- The same game has [no fail state, and its music builds as clones are added](https://www.pushsquare.com/reviews/psvr2/the-last-clockwinder). You know a room is solved when it reaches [a reasonable rate](https://www.cgmagonline.com/review/the-last-clockwinder-psvr-2-review/). One player wrote that it [changed how they think about production games](https://blog.giovanh.com/blog/2023/05/07/the-last-clockwinder-retrospective/): no gears, no metal, and still a factory.
- In [Autonauts](https://store.steampowered.com/app/979120/Autonauts/) you teach a bot by doing the job while it records, and the recording becomes a script you can edit. Scripts can be copied from bot to bot. Players soon asked for [the same script at a different location](https://itch.io/t/135530/copying-data-between-bots), which a plain copy did not give them. That is the anchor problem, met in a shipped game.

### What a recording stores

The first draft asked: inputs or intentions? Inputs are honest and brittle. Intentions are friendly and less like you. The Last Clockwinder is at the input end and Autonauts at the intention end. There is a third way between them.

- **Movement is replayed as input, through the real physics.** The echo walks, turns and hesitates as you did. If its jump is lower than yours was, it falls short where everyone can see.
- **Each thing done to the world is a deed at an address.** Break the block at this place. Use that station. Put this in that container. The place is counted from the anchor.
- **A deed waits until it can have the effect it had when recorded.** A harvest waits for the plant to be ripe. A pick-up waits for the item to be there. While it waits, the echo stands and shows the note a player would get for a refused action. Factorio's inserters behave this way.
- **A broken loop stops where it broke.** An echo that fell, or whose block is gone for good, waits at that spot with its note. That is the failure at a visible place the first draft asked for, without the brittleness of raw input.

### Blueprints: a recording played once

The first draft said that in hyperbolic space "the same recording does different things from a different anchor". That is true of an anchor that can sit anywhere, and false of one that snaps to the honeycomb.

- **A recording is portable.** The space is the same everywhere, and so is the honeycomb. If an anchor is a ground tile plus one of its five facings, a recording replays identically at every tile of every ground that lies along cell faces, voxel for voxel. (This assumes each corner's chunk grid is laid out the same way.) What differs between two anchors is the content: terrain, climate, what you built. A square path fails to close everywhere equally. A tilted ground is the exception the first draft named, since there the pull no longer lines up with the cells.
- **One primitive, played two ways.** A recording that loops is a worker. A recording that plays once is a blueprint. Record yourself building the workshop, give the spool materials at a new tile, and it builds the workshop again.
- **A stamp is a build and its workers.** The worker spools run in the copy because the copy matches.
- **What stops a stamp is the land.** Leveling the site is the prep work.
- **Ghosts.** Placing a stamp shows what will be built, drawn the way hidden blocks are drawn. The build echo fills them in.
- **The tile is the unit.** A module is one tile, or a few around a corner. Its doors are its five edges.
- **A book of spools.** What you carry when you are lost is what lets you start again.

**Borrowed**

- In Factorio a placed [blueprint](https://wiki.factorio.com/Blueprint) lays down [ghosts](https://wiki.factorio.com/Ghost), and construction robots fill them from stores or from your own pack.
- Satisfactory designs blueprints inside [a fixed cube](https://satisfactory.wiki.gg/wiki/Blueprint_Designer), 32 meters a side at first, with a marked front. A bounded module with one facing is the shape a tile gives for free.
- Dyson Sphere Program builds on spheres, where the grid changes density at certain latitudes. Its developers call those lines [tropics](https://www.dsp-wiki.com/Glossary). A blueprint [cannot be placed](https://www.dsp-wiki.com/Blueprint) where the grid's proportions differ much from where it was made, and [fails most near the poles](https://steamcommunity.com/app/1366540/discussions/0/3759975793258200256). That is the curved-space blueprint problem in a shipped game. caapi escapes it, because every tile is the same tile.

### Hands, containers and waiting

- **An echo needs hands.** A small carry, perhaps one stack. A small carry is what makes logistics exist.
- **A container is the first missing block.** Nothing in the wiki can hold an item except the player.
- **Two ways to keep echoes in step.** A beat: loops come in lengths that divide each other, so echoes stay in phase. Or buffers: deeds wait, containers sit between echoes, and timing stops mattering. Waiting is what makes a factory correct. A beat is what makes it a pleasure to watch. Both can be true.

**Borrowed.** A [Kahn process network](https://en.wikipedia.org/wiki/Kahn_process_networks) is a set of processes joined by queues, where a read waits until there is something to read. Its result is the same whatever the timing. That is the reason waiting deeds make the next section's arithmetic safe.

### Whether the factory runs when you leave

The first draft has echoes pin their cells in memory, the way a beacon does (`graph.reference` in `addBeacon`). That makes the size of your living world a memory budget.

- **The game already has a better pattern.** A plant records its planting time and a collector records when it started filling. Both are worked out from the clock. Nothing steps them.
- **Closed loops.** Call a loop closed when one cycle leaves the world exactly as it found it, apart from what sits in its containers. Everything is deterministic and deeds wait, so a closed loop repeats for as long as its inputs last and its outputs have room.
- **Unloaded, a closed loop is arithmetic.** Count the cycles elapsed, capped by inputs and room, the way a collector is capped at 120 seconds. On return, put the echo at the right point in its cycle.
- **Open loops run only while you watch.**
- **"This loop closes" is a law the game can check and show.** Closing a loop should feel like something: a sound, a mark on the spool.
- **Two things need care.** Loops that feed loops, where the slowest link sets the pace. And an echo's body, which has to settle into a repeating curve before its loop counts as closed.

### An echo with a living body

The first draft: an echo keeps the state you recorded in. Recorded while dosed, it still sees and stands on the mist stair after your dose wears off. Recorded at low gravity, it still floats. Your altered self becomes a worker you cannot be any more. That version is simple and strong. Its cost is that one good trip becomes a permanent key, and the mastery half of pharmacology is skipped.

The alternative is an echo with a body that clears and adapts like yours.

- **No invented running cost.** You ate a fern in the recording, so the echo eats one every cycle, and the fern has to be there. A big factory is also a big pharmacy, as the first draft wanted.
- **Pulses.** Signals adapt, so a steady supply stops working. A mist-walker works in pulses: dose, work, clear, rest.
- **The dose curve is the timetable.** With tide shown by rebound, one echo sees mist on the way up and tide on the way down.
- **Shifts.** Keeping a mist route staffed takes several of you, taking turns.
- **Your past selves are specialists.** An echo keeps the genome it was recorded with. If your genome changes later, your old echoes can do what you no longer can.

**Borrowed.** From 1905 the [Welte-Mignon reproducing piano](https://pianola.org/reproducing/reproducing_welte.cfm) replayed a named pianist's own performance from a paper roll. Mahler and Debussy recorded for it. An echo is a roll: a performance by someone who is not in the room, with the hesitations left in.

### Limits that are things

The first draft made the number of echoes, the length of a loop and how far an echo may go from its anchor the tiers, each raised by something from another subsystem. Make each limit a thing in the world:

- **Length** is the thread on the spool.
- **An anchor** is a block you make, like a beacon.
- **Range** is how far a body gets before its dose or its food runs out.
- **Number** is how many anchors you can build and keep fed.

### What the factory is for

Factorio's factory exists to make science. Without something that eats output forever, automation is a toy. caapi has four candidates, and all four can be true.

1. **Your own body.** Holding a state, by pulses, for as long as you want it.
2. **Your echoes' bodies.** Every dosed echo is standing demand.
3. **Search.** Breeding is a search through gene space, and a search wants volume. The loop is: cross, plant, wait 60 seconds, test, keep the best, cross again. Ash and sulfur set how wild the search is. What the factory makes is a strain, and the hard part is deciding what to test for.
4. **Filling the world.** Roads, light, thread, dark earth, and the next stamp.

**Borrowed**

- Directed evolution, for which Frances Arnold shared the 2018 Nobel Prize in Chemistry, is [rounds of random mutation and selection](https://pmc.ncbi.nlm.nih.gov/articles/2997618/) run on purpose. Her first rule for it: ["you get what you screen for"](https://www.news-medical.net/news/20260714/Directed-enzyme-evolution-and-the-Nobel-Prize-Making-enzymes-evolve-in-the-lab.aspx).
- Factorio's Space Age expansion made everything on one planet rot, and it [split the players](https://steamcommunity.com/app/427520/discussions/0/604155009439951310). The advice that settled is to [keep everything moving and buffer nothing](https://supercraft.host/wiki/factorio/gleba_base_defense_guide/). If caapi's doses ever go stale, expect the same split. caapi already has decay where it belongs, in the body.

### Logistics in a curved space

From the review: "Logistics in a space where parallel routes diverge and loops come back rotated would be something no one has done."

- **A base is a tree.** Room is free and closeness is scarce (see [above](#room-is-free-closeness-is-scarce)). Hub and spoke is the shape, and a spoke is nearly as short as any shortcut.
- **Conveyors along honeycomb edges.** The honeycomb's edges are natural lines, and there are no parallel lines to lay belts along, only geodesics that spread apart. Layout is a graph problem, not a grid problem.
- **Holonomy rotates cargo.** An item carried around a loop arrives turned. For most items that does not matter. For a molecule it could (see [Compounds](#compounds-one-chemistry-for-everything)). Edge roads keep cargo square, and a short cut across a tile leaves it skew.
- **Gravity transport.** Things fall toward the nearest ground. A chute down from a risen ground, or a weightless band between two grounds, moves cargo without power.
- **Go up to go across.** Below ground, sideways is long. A route between two deep works runs up one shaft, across the surface and down the other.
- **Sling lines.** Thrown cargo between towers (see [Up](#up-gravity-and-grounds)).
- **Relays.** A long road is a chain of echoes with a hand-off post between each pair.
- **Hidden layers.** A route built of mist stone crosses a plain route without meeting it.
- **Air and liquids.** Collectors already gather gases by climate. Pipes could carry air from where it is rich to where it is needed.

### Steady states, the Factorio side

**Exists.** The game already has rates that ask for ratios:

- Plants ripen in 60 seconds and yield 1 to 3, depending on climate fit.
- A press takes 4 extract per dose, and extract comes 1 per block pressed.
- A collector gathers at 0.02 per second times the gas level, and holds 120 seconds' worth.
- The body clears at 0.02 plus 0.01 per polar fragment, plus 0.1 once conjugated, and adapts over about 100 seconds.

**Numbers**

- One dose is four plants and 10 seconds of press time: four pressings of 2 seconds and one more to make the dose.
- So one press makes at most 6 doses a minute, and eats 24 plants a minute doing it.
- A rich plot gives 2 spare plants a minute and a fair plot gives 1. A press running flat out is fed by 12 rich plots or 24 fair ones. One dose a minute needs 2 rich plots or 4 fair ones.

Keeping a signal at a level is a control problem: tolerance pulls it down, so a steady dose is not enough. An automated drip (an echo, or a device) that holds you at a level is a real design target. So is a garden sized to feed a press that feeds that drip.

### Reading and debugging a factory

- **Notes over heads.** A waiting echo shows why it waits, in the words the player would be given.
- **Step and scrub.** The tests and films are recordings already. Give the player the same controls over a loop: pause, step, run back.
- **Measures for a loop.** Its period, what it eats per cycle, what it makes per minute, how many hands it uses.
- **The base as a rhythm.** Loops that keep a beat make a sound together. More echoes, fuller sound.

**Borrowed.** Opus Magnum scores every solution on [cost, cycles and area](https://biggieblog.com/tracking-the-global-opus-magnum-records/) and shows where you sit among everyone else's. Its players added [rate](https://biggieblog.com/?p=286) as a measure of their own, and they share solutions as looping animations. Small machines in the open, each one readable, with more than one way to be good.

## Making it discoverable

### Why modded Minecraft sends people to wikis

From the review: it happens "when outcomes are deterministic but can't be seen". There are four causes, and this file already names a fix for each.

| Cause | Fix |
| --- | --- |
| Recipes are lists. | Rules over groups and properties. |
| State lives in windows. | Work that happens in the world. |
| Every mod brings its own vocabulary. | Three properties everywhere, and stations that read their place. |
| The numbers are hidden. | Show the thing itself: the molecule, the pocket, the curve. |

### Legibility, so no one needs a wiki

The riskiest place is the lab and the binding: a molecule in 24 orientations against a pocket of walls, triggers and brakes.

- Show the molecule and the pocket in game as their actual 3 x 3 x 3 shapes, so a player can see why something fits. The assay kit is the start of this.
- Show the fit being found. The body already tries 24 orientations. Let the player watch the winner turn into place.
- Show the reaction site (see [Compounds](#compounds-one-chemistry-for-everything)).
- Name things by what they do once you know it. The three-syllable names are good for unknowns, and the journal can add what you learned about each.
- Show the result before the commitment. The bench already shows the odds before a cross. A dose can show its curve, and a stamp can show its ghosts.
- Every rule the wiki states should be something a player can find out by watching. If a rule can only be learned by reading the code, it is a rule to change or to show.

### The journal as a ship log

The insights journal already works like Outer Wilds' ship log: something noticed, a sentence about it, recipes unlocked. Grow it:

- Entries that link: the journal shows that two notices are related, and a "?" where a link is suspected but not found.
- Rumors before facts: a hint about tide in the library, an observation about ember stones in the deep caves, confirmed later by seeing them.
- Notices from things you did, not only things you broke. A dose that revealed something. A cross that mutated. A loop that came back turned.
- A mark on any entry that still has more to give.

**Borrowed.** Outer Wilds opens up through knowledge alone, kept in the ship's log as [a growing web of rumors](https://www.pressreader.com/australia/edge/20190620/282278141843961), with a mark on any place that has not given up everything. Its makers [rebuilt the ship computer as a detective board](https://www.mobiusdigitalgames.com/news/a-look-into-playtests) after playtests, to help players who were stuck see what to try next.

### The wiki you earn

caapi writes its own wiki from laws that tests check. The same laws can be watched for in play. When the player's own play satisfies a law, write that law into their journal in the same words. "Not yet a law" becomes the rumors. No outside wiki is needed, because the game writes one for each player as they witness it.

### Replay the moment

The engine records inputs. Keep the last few seconds before each insight, and let the journal play them back as an echo. It is a tutorial the player made without knowing.

**Borrowed.** Create's Ponder was built [so that players would not need a wiki or long tooltips](https://github.com/Creators-of-Create/Create/wiki/Internal---Ponder-UI): hold a key on an item and watch a small animated scene of it working.

### Each world teaches one rule

Outer Wilds teaches a rule in one place and asks for it in another. The built worlds can each carry one lesson. These are suggestions.

| World | What it could teach | Where it pays off |
| --- | --- | --- |
| `city` | Blocks have five sides, and a lap of one turns you a quarter. | The compass, square cargo, measuring land |
| `arbor`, `babel` | Up is big: a deck is wider than what it stands on. | Decks, launch towers, slings |
| `crown` | A loop can leave the ground. | Turning a sample the other twenty ways |
| `lattice` | Gravity belongs to a ground, and can sit on its far side. | The band between grounds |
| `caves` | Depth changes the rules: heat, air, what is there. | The forge, cooling, ember |
| `library` | Every combination has a shelf. | The catalog of compounds |
| `backrooms` | Sameness is how you get lost. | Thread, knots, beacons |
| `vaults` | What is hidden is solid once seen. | The hidden connector |
| `road`, `trail` | A straight line never bends, and a winding one costs. | Edge roads, relays, huts as hand-off posts |

Two things have moved since this table was written.

- `arbor`, `babel`, `crown`, `road` and `trail` are no longer worlds. They are debug structures, and the default world stands most of them once around spawn. Their lessons still need a home a player can reach.
- The backrooms' lesson pulls against what the owner asked of it. It felt far too uniform, so it now has subtypes that differ in plan and not only in wallpaper. Whether sameness holds inside one subtype, or moves to the maze level, or goes, is in [Decisions waiting](#decisions-waiting).

**Borrowed.** Games gated by knowledge have picked up the name "metroidbrainia": [exploration that knowledge unlocks](https://thinkygames.com/features/metroidbrainia-an-in-depth-exploration-of-knowledge-gated-games/). Toki Tori 2 is a clean case: two verbs, and a world to learn. The label is [argued over](https://blog.vbuckenham.com/database-games/), but the design is what "knowledge first" means.

### Tables with gaps

Design content as tables whose empty cells a player can predict: plants by receptor, lenses by family, stations by climate, insights by verb. Mendeleev left gaps in his table and described the elements that would fill them. A player who can say "there must be a plant that opens C" has understood the game.

### Clues need homes

Outer Wilds runs on places that tell you something. The built worlds are already places:

- The library: books are blocks today. A few shelves could hold readable notes, a ship log left by someone else.
- The caves change with depth, and each theme is a chapter: frost, dripstone, gypsum, crystal, ember.
- The strange stones' insight already says they "still carry charge and bulk". That is a hint pointing at chemistry; there should be more like it, pointing at ember and tide.
- The hidden connector style, built of mist stone, has no weight in the base content today. It could become the way into a place that is only reached by changing yourself. The vaults are now such a place in waiting: they rise with no bridge at all.
- The library now has rooms (atriums, study rooms, lounges), and the things in them are plain blocks. What a player can do with them is undecided.

## A lonely world that fills with you

- **Nothing spreads by itself.** Wild plants stay where they grew; only what you plant grows. Keep it that way, so every garden is yours.
- **Light is yours too.** Glowing blocks exist (light panels, sunlight, lava, the hidden lights). A world dark until you light it shows how far you have filled it.
- **Echoes are the population.** The world's only motion is your own, recorded and repeated. A busy base is a crowd of yourselves.
- **Traces.** Thread beads, beacons and explored cells already record where you have been. Make them visible as a history: worn paths where you and your echoes walk often.
- **The geometry is lonely already.** Light and sound thin out fast, there is always more room, and nothing far away can be pointed at. The design can lean on that and does not have to manufacture emptiness.
- **Home is a sound.** A base of looping echoes has a rhythm. You hear it only when you are nearly there, which is what arriving should feel like.
- **Echoes carry your manner.** They pause where you paused.
- **The soil remembers.** The oldest part of a base has the darkest earth.
- **Names.** The beacons you name are the only place names the world has.
- **An ending that fits.** A base that closes: every loop fed by another, nothing waiting on you. The game could notice the first time you leave and come back to find all of it still running.

**Borrowed**

- For tone, with no link: the lone keeper in Susanna Clarke's *Piranesi* who logs the tides of an endless house, Borges's library that holds every book, the caretaking of The Last Clockwinder, the ruins of Outer Wilds.
- A caution from Hyperbolica. Players praise its space and fault the game in it: [walking, talking and fetch quests that leave the geometry underused](https://gamebrain.co/game/hyperbolica). Every mechanic in caapi should need the geometry.

## Width: what each subsystem trades

The coherence test from the review: "does each system both take something from another system and give something to one?" Today mining, crafting, learning, navigation and gravity are islands, joined only by dotted lines on the wiki's map. This is the table with this file's ideas filled in.

| Subsystem | Takes from | Gives to |
| --- | --- | --- |
| geology (down) | climate (strata), tools, ice from high ground, plants that show ore | metals, hosts for ore, heat, a deep with room |
| gravity and grounds (up) | lift signal, structures | reach, a separate climate, gravity transport, sling lines, wide decks |
| perception (in) | the body's signals, lenses made of glass | hidden layers: paths, ore, flow; extra routing layers; instruments |
| navigation (out) | perception (it can mislead), beacons, thread, the sky | the way back, echo routes, maps, the measure of land |
| climate and air | relief, heat, wetness, what you build | plants' fit, gases, ash for mutation, working conditions for stations |
| agriculture and genetics | climate, the bench, ash and sulfur, dark earth | compounds, enzymes for your genome, signs of ore, metal |
| pharmacology | plants, the lab, reagents from geology | signals, which drive perception and movement; working hours for echoes |
| crafting and learning | whatever you break, make or do | tools, stations, insights |
| automation (echoes) | your recordings, your dosed state, threads, containers | labor, transport, persistence, search |

## Candidate content

Every item here comes from an idea above. None is decided.

**Blocks and stations**

- A container. It comes first, since nothing else can hold an item.
- A catcher: a container with a mouth, for thrown blocks.
- An anchor, where a spool plays.
- A hand-off post, for relays.
- A paper strip or column that separates an extract into bands.
- A seed vault that shows pedigree.
- A chart table, or an observatory on a risen ground.
- A glasshouse: glass, which exists, and a source of heat.
- Dark earth.
- A pit of terraces.

**Items**

- The spool: a recording you can carry, copy and place.
- Three lenses, one for each hidden family.
- A sample case that holds its orientation.
- A knot for the thread.
- Tools named by what their head is made of.

**Living things**

- A plant that opens C. A plant that closes B.
- A plant each for hot wet ground, high ashy ground, shores, and the deep.
- Grafted plants. Metal-gathering strains. A fungus that carries compounds.

**Insights**

- Squareness, rebound, closure, hardness, terroir, survey.

**Places**

- A launch tower. A sling line. A ring garden.
- A risen ground with no stair. (The vaults are one now. The way onto it is not built.)
- A dressed port for each built ground. A way from the caves into the void. A floor for the void.
- The void world after the lattice.
- The place where the sky is even.
- A flat sheet.

## Cheap experiments

Each is written the way the wiki writes a law, so it can become a claim.

1. **An echo that replays a recording ends where the recording ended.** The cheapest test of the whole direction: a creative key that replays your last 30 seconds from where you stand. It also answers whether watching yourself work feels good.
2. **A recording replayed from another tile, in another facing, places the same blocks.** On a flat world. This is the blueprint claim.
3. **A level throw from above 1.15 does not come down.** Checks whether thrown blocks obey the body's law.
4. **A closed loop leaves the world as it found it, apart from its containers.** A harvest-and-replant loop is enough.
5. **A deed whose block is missing waits, and says why.**
6. **A recorded meal, replayed without the food, stops the echo at the meal.**
7. **A frame carried around a tile comes back a quarter turn. Carried around the crown's loop, it comes back turned about a level axis.** The compass test in three dimensions.
8. **The compass, walked around a field, turns by the field's area.**
9. **A plant in a fit under 0.25 yields one.** Checks the yield bands.
10. **Half the stars lie within 2 atan(e^-d) of the way back to where the sky is even.** If there is ever a sky.

## Inspiration index

Each source once, with what caapi takes from it and where in this file it is used.

### Factories and recorded selves

| Source | What caapi takes | Where |
| --- | --- | --- |
| [The Last Clockwinder](https://www.meta.com/blog/designing-last-clockwinder-best-of-quest-2022/) | Recorded selves as machines, short loops, no fail state, a base that sounds like music | Echoes |
| [Autonauts](https://store.steampowered.com/app/979120/Autonauts/) | Teaching by doing, and the wish for the same lesson somewhere else | Echoes |
| [Factorio](https://wiki.factorio.com/Blueprint) | Blueprints and ghosts, waiting inserters, a sink for output, a warning about rot | Blueprints, What the factory is for |
| [Satisfactory](https://satisfactory.wiki.gg/wiki/Blueprint_Designer) | A bounded module with a front; recipes found by exploring | Blueprints, Crafting |
| [Dyson Sphere Program](https://www.dsp-wiki.com/Blueprint) | What goes wrong with blueprints on a curved grid | Blueprints |
| [Opus Magnum](https://biggieblog.com/tracking-the-global-opus-magnum-records/) | Several ways to be good, shown openly | Reading and debugging |
| [Kahn process networks](https://en.wikipedia.org/wiki/Kahn_process_networks) | Waiting makes timing irrelevant | Hands, containers and waiting |
| [Welte-Mignon](https://pianola.org/reproducing/reproducing_welte.cfm) | A roll that plays a person | An echo with a living body |

### Knowledge, legibility and tone

| Source | What caapi takes | Where |
| --- | --- | --- |
| [Outer Wilds](https://www.mobiusdigitalgames.com/news/a-look-into-playtests) | Knowledge as progress, the ship log, places that teach | Making it discoverable |
| [Breath of the Wild](https://gamesbeat.com/the-legend-of-zelda-breath-of-the-wild-makes-chemistry-just-as-important-as-physics/) | A few rules applied everywhere | Compounds |
| [Thief](https://thief.fandom.com/wiki/DromEd/Properties/Act_React/Sources) | Properties that act across a world | Compounds |
| [Create](https://github.com/Creators-of-Create/Create/wiki/Internal---Ponder-UI) | Explanation inside the game | Replay the moment |
| [Botania](https://www.curseforge.com/minecraft/mc-mods/botania) | Work in the world, not in windows | Crafting |
| [Metroidbrainias](https://thinkygames.com/features/metroidbrainia-an-in-depth-exploration-of-knowledge-gated-games/) | Gates made of knowledge | Each world teaches one rule |
| [Subnautica](https://steamcommunity.com/app/264710/discussions/0/1693785035819973504/?l=latam) | No map, and what that costs | Out |
| [Death Stranding](https://pcgamer.com/death-stranding-relaxed-me-so-hard-i-became-a-road-building-madman) | Paths worn by walking | Out, A lonely world |
| [Vintage Story](https://wiki.vintagestory.at/index.php/Ore_Deposits) | Geology a player can read | Down |
| [Starbound](https://playstarbound.com/?p=2697) | Tiers set by what the place does to you | Down |
| [Forestry](https://ftbwiki.org/Apiculture) | A warning: genetics as a lookup table | Plants |
| [Creatures](<https://en.wikipedia.org/wiki/Creatures_(video_game_series)>) | Simulation from the gene up | Plants |

### Hyperbolic space and gravity

| Source | What caapi takes | Where |
| --- | --- | --- |
| [HyperRogue](https://roguetemple.com/z/hyper) | Quests that need the geometry; gravity lands; why there is no second lane | The space, Up, Out |
| [Hypermine](https://github.com/Ralith/hypermine) | A sibling project meeting the same problems | The space |
| [Hyperbolica](https://gamebrain.co/game/hyperbolica) | A warning: a great space with too little to do in it | A lonely world, In |
| [The hyperbolic browser](https://www.chi1995.chistatic.hosting.acm.org/proceedings/papers/jl_bdy.htm) | A tree in a disc you drag | The space, Out |
| [The south-pointing chariot](https://arxiv.org/pdf/0906.0288) | A machine that shows curvature | The space |
| [Super Mario Galaxy](https://mariowiki.com/Gravity) | Gravity that belongs to a surface | Up |
| [Manifold Garden](https://en.wikipedia.org/wiki/Manifold_Garden) | Color for which way is down, and how much testing it takes | Up |

### Real practices

| Source | What caapi takes | Where |
| --- | --- | --- |
| [Ayahuasca](https://pubmed.ncbi.nlm.nih.gov/6587171/) | Two plants, neither enough alone | The body |
| [Codeine and CYP2D6](https://www.ncbi.nlm.nih.gov/books/NBK100662/) | A compound your body has to finish; a genome that changes the drug | The body |
| [Dose regimens](https://www.nps.org.au/australian-prescriber/articles/pharmacokinetics-made-easy-11-designing-dose-regimens) | How levels settle | The body |
| [Directed evolution](https://pmc.ncbi.nlm.nih.gov/articles/2997618/) | Search as the product | What the factory is for |
| [Gamma gardens](https://en.wikipedia.org/wiki/Atomic_gardening) | Mutation set by distance | Plants |
| [Geobotanical prospecting](https://en.wikipedia.org/wiki/Geobotanical_prospecting) | Plants that show ore | Down |
| [Phytomining](https://smi.uq.edu.au/node/14778) | Farming metal | Down |
| [Mponeng](https://iifiir.org/en/news/mine-cooling) and [Naica](https://www.nationalgeographic.com/adventure/article/101007-lost-crystal-caves-mexico-science-mine-superman-ice-palace) | Ice as the price of depth | Down |
| [The vertical archipelago](https://mapaspects.org/book/export/html/1929/index.html) and [Moray](https://assets.atlasobscura.com/places/moray) | Climates by height | Up |
| [Terra preta](https://www.sciencefocus.com/planet-earth/amazonian-dark-earth-climate-change) | Soil that remembers | Plants |
| [Grafting after phylloxera](https://www.guildsomm.com/public_content/features/articles/b/kelli-white/posts/grapevine-rootstocks) | Roots from one plant, top from another | Plants |
| [Chemotypes](https://en.wikipedia.org/wiki/Chemotype) | Strains named by place | Plants |
| [Chasqui relays](https://www.thecollector.com/chasquis-famed-inca-couriers/) | Roads run by hand-offs | Out |
| [Etak](<https://en.wikipedia.org/wiki/Etak_(navigation)>) and [stick charts](https://en.wikipedia.org/wiki/Marshall_Islands_stick_chart) | Position as a relation; maps of what bends what | Out |
| [Form constants](https://pubmed.ncbi.nlm.nih.gov/11860679/) | The lattice an altered eye sees | In |
| [Nectar guides](https://en.wikipedia.org/wiki/Nectar_guide) and [didymium glass](https://www.chemistryworld.com/opinion/weiderts-and-tillyers-glasses-the-didymium-lens-story-part-2/4024037.article) | Hidden marks, and lenses that reveal | In |
| [Paper chromatography](https://www.wikipedia.org/wiki/Paper_chromatography) and [Pasteur's crystals](https://openstax.org/books/organic-chemistry/pages/5-4-pasteurs-discovery-of-enantiomers) | Tests you can watch; handedness | Compounds |
| [Fungal networks](https://www.nature.com/articles/d41586-024-00893-0) | A living pipe, and a caution about the science | Plants |

Named in this file from general knowledge, and not looked up for it: Mohs's hardness scale, Mendel's peas, Mendeleev's gaps, Borges's library, *Piranesi*, Kerbal Space Program's flight planning, flame tests, planting maize with beans and squash, Factorio's inserters and science packs, the flow sense of fish, and Toki Tori 2.

## Decisions waiting

Choices left open by joining the worlds. A reviewer drew them up from the code and this file, and the owner answered them. "Built now" says what the game does today, and "Answer" is the owner's, in their words where they wrote some. What waits is the building: where an answer differs from "Built now", nothing has been done about it yet.

1. **Under the default world's root, does the void replace the deep or lie below it?** (a) A thin crust about two edges down, with the lattice close and the deep geology moved elsewhere. (b) A full-depth crust, with the lattice as the very bottom. (c) Shields and windows: clusters of faces roll thick or thin. (d) No void under the root, only under risen grounds. Built now: (b), at 5.6 edges. Answer: (c), shields and windows.
2. **What happens to a player who steps off the lattice into the void?** (a) You land somewhere deeper, and lose only the way back. (b) You fall back up onto the crust's underside. (c) The thread winds you back to your last bead. (d) The fall is real unless you stop it. Built now: nothing catches a body but the lattice. Answer: (d), with a way back. "The fall is real but we plan for a mechanism to get back. Like a respawn, with keepinventory-style things. Maybe 1/3 of items you have 3 or more of are lost."
3. **How does a player get from the caves through the crust into the void?** (a) The lowest chambers open through the floor. (b) A well goes on past its chamber. (c) The void's poles rise through the crust and stand on the surface as groves. Built now: no way through. Answer: (a), through the caves.
4. **Is the way back up the way the player came down?** (a) The same way: every well is a stair from top to bottom. (b) Another way: a last drop on the way down, and rarer stairs back up somewhere else. (c) Your own way: blocks you place, or a lift dose. Built now: wells are stairs both ways, and stop at the caves. Answer: near (b), and more than one. "A network that almost doesn't feel so. I think the another way is good but not exactly one way out, but not too obvious either".
5. **What decides where a port is?** (a) Its own flat roll. (b) A feature of the place. (c) The connector's foot. (d) One for each cluster of faces. Built now: (a), 3 in 100 vertices. Answer: (b), a feature of the place.
6. **Where does the line between a world and a debug structure fall?** (a) Only `planet` is a world. (b) Endless grounds and spaces are worlds; anything that is one structure is debug. (c) As (b), but endless single structures (`arbor`, `babel`, `road`, `trail`) stay worlds. Built now: (b). Answer: (b), as built.
7. **How does a player reach a ground that has no bridge?** (a) The hidden stair of mist stone. (b) A tower and a lift jump. (c) From below, through its underside. (d) By a giant tree or Babel passing it. Built now: nothing reaches the vaults. Answer: (a), the hidden stair.
8. **What may rise from a no-bridge ground?** (a) Nothing. (b) Grounds that are cut off as well. (c) Grounds with their connectors. Built now: (b). Answer: (b), as built.
9. **What decides which void world lies under a crust?** (a) The ground above names it. (b) Depth: void worlds are layers. (c) Region: clusters of faces roll it. (d) The surface: the void is the underside of what stands above. Built now: (a), with one void world. Answer: (a), (b) and (d) together: the ground above, depth, and the surface. Not region.
10. **Which void world comes after the lattice?** (a) The flat sheet. (b) The sky. (c) The far side: a ground hung upside down from the crust. (d) The sea. Built now: none. Answer: none of the four as offered. "More abstract things. Different ways of filling the lattice. Megaphobia structures and fractals. It's meant to be more nightmare than a place. Repeating patterns that break once in awhile. Island worlds that connect. A flat maze horosphere that is dangling from whatever's above it. Sparse islands".
11. **Is what lies under a built ground set by depth alone or by what is built above it?** (a) Depth alone. (b) The ground above writes its own underground. (c) Same geology, but sealed caves keep what open ones lose. Built now: (a). Answer: (b) and (c) together: the ground above writes its own underground, and sealed caves keep what open ones lose.
12. **What makes a backrooms subtype a place and not a repaint?** (a) Regions with edges you can find and follow. (b) Rare rooms in a plain field. (c) Levels: sameness sideways, variety downward. (d) Uses: a subtype is where one thing is found. Built now: (a), by region and by level. Answer: all four. "All of these are good, but don't close off. This is where variety really matters. Take inspiration from minecraft's multiple table worldgen".
13. **What do the library's rooms hold that a player can use?** (a) Notes that enter the journal as rumors. (b) The catalog of compounds. (c) Working stations. (d) Stock to salvage. Built now: plain blocks. Answer: (a), (b) and (c): notes, the catalog and working rooms. On (d): "Stock goes in the backrooms, tho maybe library-ish stock once and a while. More like a break room for library employees".
14. **Where does a player in a normal game meet a debug structure?** (a) Nowhere. (b) Once each around spawn. (c) Across the land, by roll or by a rule of the place. (d) In a creative menu. Built now: (b). Answer: (d). "Essentially debug worlds are for seeing a structure out of context or in isolation. Normal play doesn't really see them. Think the concept of a scene or prefab in unity or godot". Asked afterwards whether the default world should stop standing six of them at spawn: "I think placing them is fine, but rather the goal is to turn them into real things that are not just for testing. Like, real places and objects".

What the answers ask for, in the order the pieces depend on each other:

- **A crust that varies.** Thick and thin rolled per cluster of faces, so some wild ground has the full deep and some has the void close under it.
- **Caves that open downward.** Where the crust is thin, the lowest chambers break through it. That is the way into the void, and with wells, pole stairs and other caves it makes the several ways back that the owner asked for: a network that does not feel like one, with no single exit and none too obvious.
- **A fall that is real, and a way back from it.** A respawn that keeps most of what is carried. The owner's first number: lose a third of every item held three or more of. This also answers part of an older open question: something in the game can now end a trip.
- **Ports that belong somewhere.** Tied to a feature of the ground and dressed by it, in place of a flat roll.
- **The hidden stair up to the vaults.** The mist-stone connector style, used for grounds with no bridge. Whatever rises from such a ground stays unbridged.
- **Void worlds by ground, by depth and by what stands above.** Named by the ground over them, stacked as layers, and showing the underside of the surface.
- **The void as nightmare.** More ways of filling the lattice, structures too large to take in, fractals, patterns that repeat and break once in a while, sparse islands and island worlds that connect, a flat maze sheet dangling from whatever is above it.
- **An underground written by what is built over it,** with sealed caves keeping what open ones lose.
- **Backrooms variety from several tables at once.** Regions with edges, rare rooms, levels and uses together, and nothing closed off.
- **A library with notes, the catalog and working rooms.** Salvage stock belongs in the backrooms; the library gets a little of its own kind, such as a staff break room.
- **A debug list in the creative menu.** A debug world is a scene for looking at one structure in isolation, and normal play does not go there.
- **Landmarks that are real.** The tower, the crown, the palace and the rest stop being test pieces that happen to stand at spawn and become places and objects with a reason to be where they are.
- **Threes in what is held and needed.** Recipe inputs, yields and the like lean to powers of three. The fall's loss rule is already one.

The work is laid out in `plan.md`.

## Open questions

From the first draft:

- Should the wood, stone, copper and iron ladder stay as early scaffolding, or be replaced by tools whose power comes from their material's place in geology?
- How many echoes, and how long a loop, before the world is too busy to keep loaded?
- Is a dose ever dangerous, or only disorienting? Starbound-style threat tiers could map onto depth (heat) and up (falls) instead of monsters. (Since answered for falls: a fall into the void is real, with a respawn that keeps most of the inventory. See [Decisions waiting](#decisions-waiting). Doses are still open.)
- Should mods be able to add a direction, or only deepen the existing ones?

New in this version:

- Does the factory run when you leave by keeping cells loaded, or by arithmetic on closed loops?
- Does an echo keep a frozen state, or does it have a living body?
- Do deeds wait, do loops keep a beat, or both?
- Does an echo get in the way of you, or of other echoes?
- Which sink comes first: your body, your echoes, search, or building?
- Can receptor halves be spliced? Can a splice be undone?
- Does every station read its place, or only some?
- Do thrown blocks obey the body's law? If they do, is a throw that never lands a feature?
- Is there a sky?
- Does anything ever go stale outside the body?
- Is there an ending, and is it the world running without you?