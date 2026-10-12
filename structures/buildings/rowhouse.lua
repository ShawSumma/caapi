local kit = require("buildings.kit")

local rowhouse = {}

rowhouse.STORIES = { 2, 3 }
rowhouse.PALETTES = {
  { wall = "white_brick", trim = "spruce_wood", floor = "wood_planks", roof = "slate" },
  { wall = "wood_planks", trim = "white_brick", floor = "wood_planks", roof = "red_sandstone" },
  { wall = "birch_wood", trim = "spruce_wood", floor = "wood_planks", roof = "shale" },
  { wall = "sandstone", trim = "clay", floor = "wood_planks", roof = "clay" },
  { wall = "limestone", trim = "grey_brick", floor = "wood_planks", roof = "slate" },
}

local DESIGN = {
  setbacks = 0,
  facade = kit.grid,
  roof = "wood_planks",
  cap = kit.hip_roof,
  crowns = { kit.chimney, kit.chimney, false },
}

function rowhouse.build(lots, spec)
  kit.build(lots, spec, DESIGN)
end

return rowhouse
