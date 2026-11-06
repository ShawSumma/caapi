# mined

A voxel engine in hyperbolic space. The world is the {5,3,4} honeycomb: right-angled dodecahedra, four around every edge, each split into twenty cubes of voxels. Ground follows horospheres, surfaces that are flat to walk on while the space around them grows exponentially, and structures are built along the honeycomb's edges and planes.

It is written in D (betterC, LDC). Worlds are plugins: shared libraries the engine loads at startup and that build through a table of functions.

This is an early release (0.0.1). Expect rough edges and changes to the plugin API.

## Building

Linux needs:

- LDC (developed with 1.36.0) and dub
- a C compiler on the path (`cc`), which LDC uses to read the Vulkan and X11 headers
- `glslc` to compile the shaders
- the Vulkan loader and headers, X11 and libXi (on Ubuntu: `libvulkan-dev libx11-dev libxi-dev glslc`)
- a Vulkan 1.1 driver whose device supports `multiDrawIndirect` and `drawIndirectFirstInstance`, and an X server with XInput 2.1

On macOS the build looks for the Vulkan loader and MoltenVK under `/opt/homebrew`.

Build and run:

```sh
dub run -b release --compiler=ldc2
```

The plugins are built into `lib/` next to the executable before the engine itself, and the engine loads them from there. `dub run -b release --compiler=ldc2 -- --help` lists the options.

## Playing

- Click in the window to capture the mouse, Esc to release it.
- Mouse or arrow keys to look, WASD to move.
- Space jumps when walking; when flying or in noclip, Space rises and Shift sinks.
- V toggles walking and N toggles noclip; turning either off leaves you flying.
- Left click breaks a block and keeps it, right click places one of the chosen kind, 1 to 9 choose from the hotbar at the bottom. Slot 9 holds beacons: the compass grows a cyan needle toward each placed beacon and shows the distance to the nearest.
- `--save <file>` loads that save if it exists and writes it on quit (not in the web page).
- E uses what you aim at: on a plant it scans the plant's product (its fragments, and how strongly it binds each of your receptors); on a collector (slot 8) it breathes in the air gathered since it was placed or last used. F eats the plant you aim at, once it has grown. Breaking a plant keeps its seed; placing a plant plants your newest seed of that kind. Aiming at a bench (slot 7) shows your genes and seeds: E there crosses your two newest seeds, F splices the newest seed's enzyme gene into you.
- `[` and `]` step through the terrain and every world the plugins register.
- O takes the next of three test doses (swallowed, inhaled, injected); a panel shows the body's signals and bound receptors while anything is in the body.
- P steps through test perception presets: heavy and light change walking, gravity and jumps; wide and narrow change the field of view and fog; behind draws from a camera pulled back behind you; swaying warps the view; turned rotates colors; mist reveals hidden mist blocks, such as the stair in the `hiddenstair` world.

Settings are read from `mined.cfg` in the working directory (or `--config <file>`), one `key = value` per line: `mouse_sensitivity` (radians per mouse count), `turn_speed` (radians per second for the arrow keys), `reach` (in units of the space's curvature radius) and `invert_y`.

## Worlds

Each world is a dub sub-package under `plugins/` that builds a shared library whose entry point, `pragma(mangle, ENTRY)`, registers its worlds by name. `plugins/api/api.d` is the whole API; `plugins/turtle/` wraps it in a turtle that walks the honeycomb's sites. The plugins shipped here include `planet` (the terrain world), `city`, `backrooms`, `library`, `palace`, `babel`, `arbor`, `lattice` and others. To add one, declare it in `dub.sdl` like the existing ones and add it to the root package's `preGenerateCommands`.

The entry point's name carries the API version, so a plugin built against another version of `api.d` is refused when it loads instead of misreading the engine's tables.

## Tests

```sh
dub test -q --compiler=ldc2
dub run -q -b release --compiler=ldc2 -c headless -- tests
```

`dub run -q -b release --compiler=ldc2 -c headless -- --help` lists the world checks and benchmarks. `CLAUDE.md` describes the code's structure and the rules it keeps.

## License

MIT, see `LICENSE`.
