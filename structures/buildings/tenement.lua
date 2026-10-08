local kit = require("buildings.kit")

local tenement = {}

tenement.STORIES = { 5, 9 }
tenement.PALETTES = {
  { wall = "grey_brick", trim = "white_brick", floor = "wood_planks" },
  { wall = "white_brick", trim = "grey_brick", floor = "wood_planks" },
  { wall = "red_sandstone", trim = "white_brick", floor = "wood_planks" },
  { wall = "clay", trim = "limestone", floor = "wood_planks" },
}

local DESIGN = {
  setbacks = 0,
  facade = kit.masonry,
  has_storefront = true,
  roof = "basalt",
  crown = kit.water_tower,
}

function tenement.build(lots, spec)
  kit.build(lots, spec, DESIGN)
end

return tenement
