-- The backrooms' levels from the ground down, tighter and stranger as they go, each one floor. A level names how its
-- hallways run (a grid along nearly every edge of the tiling, the city's streets, or none), how wide they are on each
-- side of the edge, how tall its rooms are, whether it is a maze rather than rooms, how many of its blocks are solid,
-- how often a shared wall is left out altogether, how often its rare rooms turn up, how often a quarter picking it for
-- stairs down gets them, and the biomes its regions take. Each level keeps to one family of colours.
-- A biome's big is the chance of a room not being split again, open the chance of a dividing wall being left out,
-- hall_doors the chance of a room opening onto a hallway beside it, skylight the chance of a light being daylight on
-- the top level, boxes what is built against walls and how often, nowhere the chance of steps up into the ceiling at
-- a maze's dead end, and room_floors the floors its rooms choose among.
local levels = {}

local function biome(fields)
  local made = {
    trim = false, damp = false, big = 0.25, open = 0, hall_doors = 0.35, shelf = false, vents = false, boxes = false,
    box_odds = 0, box_height = 0, skylight = 0, nowhere = 0, room_floors = false,
  }
  for key, value in pairs(fields) do
    made[key] = value
  end
  return made
end

local function level(fields)
  local made = {
    halls = "none", hall_width = 0, room = 4, maze = false, solid = 0, missing = 0, rings = 0, chapel = 0, stairs = 0,
    hall = { floor = "carpet", ceiling = "ceiling_tile", light = "light_panel", skylight = 0 },
  }
  for key, value in pairs(fields) do
    made[key] = value
  end
  return made
end

levels.LAYERS = {
  -- Long yellow halls under ceiling tiles and lights, daylight now and then, and a block of rooms once in a while.
  level({
    halls = "grid",
    hall_width = 2,
    solid = 0.6,
    rings = 0.02,
    chapel = 0.04,
    stairs = 0.24,
    hall = { floor = "carpet", ceiling = "ceiling_tile", light = "light_panel", skylight = 0.25 },
    biomes = {
      biome({
        wall = "wallpaper", floor = "carpet", ceiling = "ceiling_tile", light = "light_panel", trim = "wood_planks",
        damp = "damp_carpet", stair = "carpet", vents = true, boxes = "wallpaper", box_odds = 0.15, box_height = 4,
        skylight = 0.2,
      }),
      biome({
        wall = "wallpaper", floor = "damp_carpet", ceiling = "ceiling_tile", light = "light_panel", damp = "carpet",
        stair = "carpet", vents = true, boxes = "wallpaper", box_odds = 0.25, box_height = 3, skylight = 0.1,
      }),
      biome({
        wall = "stained_wallpaper", floor = "carpet", ceiling = "ceiling_tile", light = "light_panel",
        damp = "damp_carpet", stair = "carpet", vents = true, skylight = 0.15,
      }),
    },
  }),
  -- An endless house: room after room through doorways, cream plaster and wood.
  level({
    missing = 0.03,
    stairs = 0.24,
    biomes = {
      biome({
        wall = "plaster", floor = "wood_planks", ceiling = "plaster", light = "light_panel", trim = "spruce_wood",
        big = 0.35, stair = "wood_planks", room_floors = { "wood_planks", "wood_planks", "carpet" },
      }),
      biome({
        wall = "birch_wood", floor = "wood_planks", ceiling = "plaster", light = "light_panel", trim = "spruce_wood",
        big = 0.3, stair = "spruce_wood", shelf = "spruce_wood", room_floors = { "wood_planks", "spruce_wood" },
      }),
      biome({
        wall = "plaster", floor = "spruce_wood", ceiling = "plaster", light = "light_panel", trim = "wood_planks",
        big = 0.4, stair = "spruce_wood", damp = "damp_carpet",
        room_floors = { "spruce_wood", "carpet", "damp_carpet" },
      }),
    },
  }),
  -- A low concrete maze of narrow passages, dim, with the odd small room and steps that go nowhere.
  level({
    room = 3,
    maze = true,
    biomes = {
      biome({ wall = "concrete", floor = "concrete", ceiling = "concrete", light = "light_panel", stair = "concrete", nowhere = 0.15 }),
      biome({ wall = "grey_brick", floor = "wet_concrete", ceiling = "concrete", light = "light_panel", stair = "concrete", nowhere = 0.2 }),
      biome({ wall = "concrete", floor = "wet_concrete", ceiling = "wet_concrete", light = false, stair = "wet_concrete", nowhere = 0.25 }),
    },
  }),
}

return levels
