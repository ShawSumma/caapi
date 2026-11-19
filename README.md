# Caapi

Caapi is a voxel game set in hyperbolic space, and the engine under it. This is version 0.0.1: the game, its save files and the plugin interface all still change.

## Credit

Caapi is largely inspired by and builds on the technical work done by [hypermine](https://github.com/Ralith/hypermine), please check them out!

Generative AI was used in the development of caapi. There was an interesting discussion of it in the [HyperRogue Lounge discord](https://discord.gg/qnrR4hRy7m), which I highly suggest joining if you want to find people interested in hyperbolic space.


## The world

Space is hyperbolic 3-space, tiled by right-angled dodecahedra. Every cell is cut into twenty cubes of voxels, one at each of its corners. Nothing has global coordinates. A place is a cell and a position inside it, and the farther out you go, the more room there is, exponentially.

The ground is a hyperbolic plane. Some worlds raise further planes above it and join them with buildings, and gravity follows whichever ground is near. The code calls these planes horospheres, but they are geodesic planes: walk five equal legs with a right turn after each and you are back where you started, which on flat ground takes four.

The terrain world has a climate, soil and rock, trees and plants. The other worlds are built places such as a city, the backrooms, a library, a palace, caves and vaults.

## Building

You need:

- LDC and dub. The build flags are LDC's, so always pass `--compiler=ldc2`. It is developed with LDC 1.36.0.
- A C compiler, which LDC uses to read the C headers pulled in from `source/bindings/`.
- `glslc`, to compile the shaders.
- On Linux: the Vulkan loader and headers, X11 and libXi.
- On macOS: the Vulkan loader under `/opt/homebrew`.

Build and play:

```sh
dub run -b release --compiler=ldc2
```

The world plugins are built into `lib/` first, and the game loads them from there when it starts. The gameplay plugins (`crafting`, `game` and `pharmacology`) are linked into the program itself.

`dub run -b release --compiler=ldc2 -- --help` lists the options. Among them:

- `--worldgen terrain | plane <tilt in degrees> | structure <world>` picks the world.
- `--creative` starts creative mode.
- `--save <file>` and `--config <file>` choose the save and settings files.
- `--screenshot <png>` and `--film <directory>` render a named view or film offscreen.

The browser build packs the whole game into one page, `caapi.html`:

```sh
dub build -b release --compiler=ldc2 :web
```

It needs LLVM's wasm linker and the wasm32-wasi C library under `/usr/lib/wasm32-wasi`.

## Playing

Default keys:

- W, A, S and D walk. Space jumps and left Shift crouches.
- The mouse or the arrow keys look around.
- Hold the left mouse button to mine. The right button places the block you hold, or uses the block you aim at.
- 1 to 9, 0, - and = pick one of the twelve hotbar slots, and the mouse wheel steps through them.
- E opens the inventory: the hotbar plus 36 more slots, 81 to a stack. Its other tabs show your body, the compounds you hold and your surroundings.
- J opens the journal of what you have noticed.
- Esc opens the menu. It lists every world and marks the ones that have a save; pick one to play it, or to delete its save and start it over. The key bindings are behind its controls button. In creative mode it also lists the scenes, marked `~`: each is one structure standing alone, to look at, and nothing in a scene is saved.
- Hold F to eat what you hold.
- In any screen the mouse wheel scrolls a list that is longer than its panel.

What there is to do:

- **Mining** takes time. Harder blocks need a better pickaxe, and a better pickaxe also mines faster.
- **Crafting** is a queue with no size. Queue a recipe and the recipes that make its missing ingredients are queued ahead of it; what the whole job needs leaves your inventory at once, and cancelling any step gives the whole job back, with a note if some of it no longer fits. A click on a recipe queues one, a right click three, and a click with crouch held as many as you can pay for. Work that needs a station only moves while you are near one you have used. The queue is part of the save. No recipe is locked: breaking the right block or working at a station makes you notice something, and the journal keeps what you noticed.
- **Living blocks** carry genes, and their genes make a compound. A press extracts it and a lab changes it with reagents. A dose can be swallowed, inhaled or injected. What a living block makes is unidentified until you hold that compound or own an assay kit. Unidentified blocks of one species share a stack, each keeping its own genes, and the ones you identify move to a stack of their own. A stack that holds several kinds is a bundle: its slot shows a mark for each kind, and pointing at it lists them by their genes, so you can tell them apart without knowing what any of them makes.
- **Your body** has receptors, and what a compound does depends on which of them it binds. It can change how fast you walk, how hard gravity pulls, how high you jump and how the world looks, and it can reveal blocks that were not there before.
- **Plants** grow from what you plant, ripen in a minute, and yield more where the climate suits them. A plant found growing wild gives just one. At a bench you can cross two plants, or splice a plant's enzyme into yourself. A collector fills with the local air, which you can then breathe.
- **Beacons** mark a place so that you can find it again.

`--creative` starts you with blocks and mines fast. It also adds these keys: V to switch between walking and flying, N for noclip, [ and ] for the previous and next world, T to throw a block, O to take a test dose and P for the next perception preset.

The game saves to `saves/<world>-<mode>.save`. Each world has its own save, and a world without one starts you fresh. A save written by another version of the game is left as it is and nothing is saved over it; the menu says so, and deleting it there starts that world over.

In the browser the page opens on the menu: click any empty spot to play, and Esc brings the menu back. The saves are kept in the page's local storage, one for each world, and the page reopens in the world you last entered.

Settings are read from `caapi.cfg` in the working directory, one `key = value` per line:

- `mouse_sensitivity`: radians turned per mouse count.
- `turn_speed`: radians per second for the arrow keys.
- `invert_y`: `yes` inverts vertical mouse look.
- `comfort`: from 0 to 1; lower values tone down the strongest view effects.
- `thread_beads` and `thread_spacing`: how many beads of thread to lay behind you as you walk, and how far apart. The thread is off at 0, which is the default.
- `reach`: how far you can reach to mine and place, in units of the space's curvature radius.
- `bind_<action> = <key>` for each key, such as `bind_inventory = i`.

## Where the code lives

- `source/` is the engine and nothing else: the honeycomb, world generation, streaming, meshing, rendering, the character controller, and the content graph that mods fill. It knows materials, groups, the terrain palette, looks and perception; it does not know items, recipes or bodies. Its own schemas are written in the D modules that read them. Three things it takes from plugins instead of naming them:
  - A hidden family of materials is its own sense. Perception holds one level for each family a mod defines, beside the fixed channels the engine reads (speed, gravity, the view effects), and a preset or a body may set either.
  - A tree's shape is a function a plugin registers by name (`registry.addForm`). The engine frames the tree and asks the shape, cell by cell, whether it is wood, heart or leaves.
  - What happens in a session is passed to the mods' hooks as two names, an event and its subject. The engine names no event.
- `plugins/api/` is the whole interface between the engine and a plugin, and `plugins/turtle/` wraps it in a turtle that walks the honeycomb.
- `plugins/base/` is the base content: materials, the terrain, and the tree shapes its trees name (`forms.d`).
- The world plugins (`planet`, `city`, `backrooms`, `library`, `vaults`, `caves`, `lattice`, `skies` and the rest) each build a shared library into `lib/`.
- The gameplay is three plugins linked into the program, each above the one before:
  - `plugins/crafting/`: items, the inventory, stations, recipes, upgrades, insights and the roles an item can fill.
  - `plugins/game/`: the player, mining, the crafting queue, beacons, the HUD and screens, input, settings and saves. It names the events it fires (`play.d`) and offers extension points (hooks on the player, queued work, written notes, inventory sheets, machine screens, save sections, key bindings) and names no plugin above it.
  - `plugins/pharmacology/`: molecules, receptors, the body, genes and breeding, syntheses and doses, with its own sheets, screens, save section and keys (eating and the test dose), all registered through the game's extension points.
- `app/` is the programs: the windowed game, the headless tool, the list of linked plugins, and the behavior tests, views and films, which exercise everything together.
- `web/` is the browser program.

What a mod adds to the game is data beside its code: a `.decl` schema, a `.content` file and a `settings.conf`. A mod may add to what another mod defined, so the game plugin gives the base materials their mining times and pharmacology marks which of them are living. An `extend` may also declare an edge again with further targets, which is how crafting lets a group hold wares as well as materials.

To add a world plugin, give it a subpackage and a `preGenerateCommands` line in `dub.sdl` like the others, and a line in `WORLD_PLUGINS` in `web/main.d`. A plugin linked into the program goes into `app/linked.d` instead.

## Tests

```sh
dub run -q -b release --compiler=ldc2 -c headless -- tests
```

This runs the behavior tests, which are scripted play sessions; name prefixes after `tests` pick some of them, as in `tests flat/ gene/`. Put `--help` in place of `tests` to list the other checks, dumps and benchmarks.

## License

MIT, see `LICENSE`.
