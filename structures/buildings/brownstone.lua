local kit = require("buildings.kit")

local brownstone = {}

brownstone.STORIES = { 4, 5 }
brownstone.PALETTES = {
  { wall = "red_sandstone", trim = "sandstone", floor = "wood_planks" },
  { wall = "red_sandstone", trim = "limestone", floor = "wood_planks" },
  { wall = "shale", trim = "limestone", floor = "wood_planks" },
  { wall = "clay", trim = "sandstone", floor = "wood_planks" },
  { wall = "spruce_wood", trim = "diorite", floor = "wood_planks" },
}

local DESIGN = {
  setbacks = 0,
  facade = kit.masonry,
  roof = "slate",
  crowns = { kit.chimney, false },
}

function brownstone.build(lots, spec)
  kit.build(lots, spec, DESIGN)
end

return brownstone
