-- The backrooms' layers from the ground down, each a little stranger than the one above. A level names its hallways'
-- palette, how often a shared wall is left out altogether, how often its rare rooms turn up, and the biomes its
-- regions take. A biome's big is the chance of a room not being split again, open the chance of a dividing wall
-- being left out, and hall_doors the chance of a room opening onto a hallway beside it.
local levels = {}

levels.LAYERS = {
  {
    hall = { floor = "carpet", ceiling = "ceiling_tile", light = "light_panel", pipes = false },
    missing = 0.04,
    atrium = 0,
    rings = 0,
    biomes = {
      {
        wall = "wallpaper", floor = "carpet", ceiling = "ceiling_tile", light = "light_panel", trim = "wood_planks",
        damp = "damp_carpet", big = 0.25, open = 0.08, hall_doors = 0.8, shelf = false, stair = "carpet",
      },
      {
        wall = "wallpaper", floor = "damp_carpet", ceiling = "ceiling_tile", light = "light_panel", trim = false,
        damp = "carpet", big = 0.15, open = 0.12, hall_doors = 0.7, shelf = false, stair = "carpet",
      },
      {
        wall = "birch_wood", floor = "red_carpet", ceiling = "ceiling_tile", light = "light_panel", trim = "spruce_wood",
        damp = false, big = 0.05, open = 0, hall_doors = 0.95, shelf = false, stair = "red_carpet",
      },
      {
        wall = "grey_brick", floor = "concrete", ceiling = "concrete", light = "light_panel", trim = false,
        damp = false, big = 0.6, open = 0.2, hall_doors = 0.6, shelf = false, stair = "concrete",
      },
    },
  },
  {
    hall = { floor = "concrete", ceiling = "concrete", light = "light_panel", pipes = "steel" },
    missing = 0.06,
    atrium = 0,
    rings = 0,
    biomes = {
      {
        wall = "concrete", floor = "concrete", ceiling = "steel", light = "light_panel", trim = false,
        damp = false, big = 0.4, open = 0.1, hall_doors = 0.7, shelf = false, stair = "steel",
      },
      {
        wall = "red_sandstone", floor = "basalt", ceiling = "slate", light = false, trim = "steel",
        damp = false, big = 0.3, open = 0.15, hall_doors = 0.6, shelf = false, stair = "steel",
      },
      {
        wall = "wood_planks", floor = "carpet", ceiling = "ceiling_tile", light = "light_panel", trim = false,
        damp = "damp_carpet", big = 0.5, open = 0.05, hall_doors = 0.7, shelf = "spruce_wood", stair = "wood_planks",
      },
    },
  },
  {
    hall = { floor = "red_carpet", ceiling = "ceiling_tile", light = "light_panel", pipes = false },
    missing = 0.1,
    atrium = 0.12,
    rings = 0.08,
    biomes = {
      {
        wall = "red_sandstone", floor = "red_carpet", ceiling = "red_sandstone", light = "light_panel", trim = false,
        damp = false, big = 0.2, open = 0.1, hall_doors = 0.8, shelf = false, stair = "red_carpet",
      },
      {
        wall = "basalt", floor = "gabbro", ceiling = "basalt", light = false, trim = false,
        damp = false, big = 0.5, open = 0.25, hall_doors = 0.5, shelf = false, stair = "gabbro",
      },
      {
        wall = "white_brick", floor = "slate", ceiling = "ceiling_tile", light = "light_panel", trim = false,
        damp = false, big = 0.3, open = 0.1, hall_doors = 0.8, shelf = false, stair = "slate",
      },
      {
        wall = "wallpaper", floor = "carpet", ceiling = "ceiling_tile", light = "light_panel", trim = "wood_planks",
        damp = "damp_carpet", big = 0.1, open = 0, hall_doors = 0.9, shelf = false, stair = "carpet",
      },
    },
  },
}

return levels
