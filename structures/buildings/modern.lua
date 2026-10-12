local kit = require("buildings.kit")

local modern = {}

modern.STORIES = { 6, 20 }
modern.PALETTES = {
  { wall = "concrete", trim = "steel", floor = "concrete" },
  { wall = "white_brick", trim = "glass", floor = "marble" },
  { wall = "diorite", trim = "steel", floor = "concrete" },
  { wall = "gabbro", trim = "glass", floor = "concrete" },
}

local DESIGN = {
  setbacks = 1,
  facade = kit.balconied,
  ground = kit.storefront,
  roof = "concrete",
  cap = kit.garden,
  crowns = { kit.helipad, kit.masts, false },
}

function modern.build(lots, spec)
  kit.build(lots, spec, DESIGN)
end

return modern
