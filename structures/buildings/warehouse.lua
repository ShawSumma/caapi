local kit = require("buildings.kit")

local warehouse = {}

warehouse.STORIES = { 2, 4 }
warehouse.PALETTES = {
  { wall = "red_sandstone", trim = "grey_brick", floor = "concrete" },
  { wall = "grey_brick", trim = "steel", floor = "concrete" },
  { wall = "concrete", trim = "steel", floor = "concrete" },
  { wall = "clay", trim = "basalt", floor = "wood_planks" },
}

local DESIGN = {
  setbacks = 0,
  facade = kit.clerestory,
  roof = "basalt",
  crowns = { kit.chimney, kit.water_tower, false },
}

function warehouse.build(lots, spec)
  kit.build(lots, spec, DESIGN)
end

return warehouse
