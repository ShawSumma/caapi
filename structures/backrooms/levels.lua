local levels = {}

local function biome(fields)
  local made = {
    big = 0.25, open = 0, hall_doors = 0.35, has_vents = false, box_odds = 0, box_height = 0, skylight = 0, nowhere = 0,
  }
  for key, value in pairs(fields) do
    made[key] = value
  end
  return made
end

local function level(fields)
  local made = {
    halls = "none", hall_width = 0, room = 4, is_maze = false, solid = 0, missing = 0, rings = 0, chapel = 0, stairs = 0,
    hall = { floor = "carpet", ceiling = "ceiling_tile", light = "light_panel", skylight = 0 },
  }
  for key, value in pairs(fields) do
    made[key] = value
  end
  return made
end

levels.LAYERS = {
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
        damp = "damp_carpet", stair = "carpet", has_vents = true, boxes = "wallpaper", box_odds = 0.15, box_height = 4,
        skylight = 0.2,
      }),
      biome({
        wall = "wallpaper", floor = "damp_carpet", ceiling = "ceiling_tile", light = "light_panel", damp = "carpet",
        stair = "carpet", has_vents = true, boxes = "wallpaper", box_odds = 0.25, box_height = 3, skylight = 0.1,
      }),
      biome({
        wall = "stained_wallpaper", floor = "carpet", ceiling = "ceiling_tile", light = "light_panel",
        damp = "damp_carpet", stair = "carpet", has_vents = true, skylight = 0.15,
      }),
    },
  }),
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
  level({
    room = 3,
    is_maze = true,
    biomes = {
      biome({ wall = "concrete", floor = "concrete", ceiling = "concrete", light = "light_panel", stair = "concrete", nowhere = 0.15 }),
      biome({ wall = "grey_brick", floor = "wet_concrete", ceiling = "concrete", light = "light_panel", stair = "concrete", nowhere = 0.2 }),
      biome({ wall = "concrete", floor = "wet_concrete", ceiling = "wet_concrete", stair = "wet_concrete", nowhere = 0.25 }),
    },
  }),
}

return levels
