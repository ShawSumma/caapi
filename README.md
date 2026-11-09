# caapi

caapi is a voxel game set in hyperbolic space, and the engine under it. This is version 0.0.1: the game, its save files and the plugin interface all still change.

## The world

Space is hyperbolic 3-space, tiled by right-angled dodecahedra. Every cell is cut into twenty cubes of voxels, one at each of its corners. Nothing has global coordinates. A place is a cell and a position inside it, and the farther out you go, the more room there is, exponentially.

The ground is a hyperbolic plane. Some worlds raise further planes above it and join them with buildings, and gravity follows whichever ground is near. The code calls these planes horospheres, but they are geodesic planes: walk five equal legs with a right turn after each and your compass ends up a quarter turn off.

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

The plugins are built into `lib/` first, and the game loads them from there when it starts.

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
- E opens the inventory: the hotbar plus 36 more slots, 64 to a stack.
- Hold F to eat what you hold.

What there is to do:

- **Mining** takes time. Harder blocks need a better pickaxe, and a better pickaxe also mines faster.
- **Crafting** is a queue. Queue a recipe and the recipes that make its missing ingredients are queued ahead of it. Cancel one that has started and its ingredients come back. Work that needs a station only moves while you are near one you have used. Some recipes have to be learned first, by breaking the right block or by working at a station.
- **Living blocks** carry genes, and their genes make a compound. A press extracts it and a lab changes it with reagents. A dose can be swallowed, inhaled or injected.
- **Your body** has receptors, and what a compound does depends on which of them it binds. It can change how fast you walk, how hard gravity pulls, how high you jump and how the world looks, and it can reveal blocks that were not there before.
- **Plants** grow from what you plant, ripen in a minute, and yield more where the climate suits them. At a bench you can cross two plants, or splice a plant's enzyme into yourself. A collector fills with the local air, which you can then breathe.
- **Beacons** mark a place so that you can find it again.

`--creative` starts you with blocks and mines fast. It also adds these keys: V to switch between walking and flying, N for noclip, [ and ] for the previous and next world, T to throw a block, O to take a test dose and P for the next perception preset.

The game saves to `saves/<world>-<mode>.save`.

Settings are read from `caapi.cfg` in the working directory, one `key = value` per line:

- `mouse_sensitivity`: radians turned per mouse count.
- `turn_speed`: radians per second for the arrow keys.
- `invert_y`: `yes` inverts vertical mouse look.
- `comfort`: from 0 to 1; lower values tone down the strongest view effects.
- `thread_beads` and `thread_spacing`: how many beads of thread to lay behind you as you walk, and how far apart. The thread is off at 0, which is the default.
- `reach`: how far you can reach to mine and place, in units of the space's curvature radius.
- `bind_<action> = <key>` for each key, such as `bind_inventory = i`.

## Worlds and mods

Each world is a plugin: a dub subpackage under `plugins/` that builds a shared library into `lib/`. `plugins/api/` is the whole interface between the engine and a plugin, and `plugins/turtle/` wraps it in a turtle that walks the honeycomb.

What a mod adds to the game (materials, items, recipes, plants and their chemistry) is data beside its code: a `.decl` schema, a `.content` file and a `settings.conf`.

To add a plugin, give it a subpackage and a `preGenerateCommands` line in `dub.sdl` like the others. The web build keeps its own list of plugins; `CLAUDE.md` says where.

## Tests

```sh
dub test -q --compiler=ldc2
dub run -q -b release --compiler=ldc2 -c headless -- tests
```

The first runs the unit tests. The second runs the behavior tests, which are scripted play sessions; name prefixes after `tests` pick some of them, as in `tests flat/ gene/`. Put `--help` in place of `tests` to list the other checks, dumps and benchmarks.

`CLAUDE.md` describes the structure of the code, how it handles hyperbolic space and the style it keeps.

## License

MIT, see `LICENSE`.
