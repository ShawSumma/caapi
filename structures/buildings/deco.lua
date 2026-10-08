local kit = require("buildings.kit")

local deco = {}

deco.STORIES = { 14, 34 }
deco.PALETTES = {
  { wall = "limestone", trim = "steel", floor = "concrete" },
  { wall = "sandstone", trim = "marble", floor = "concrete" },
  { wall = "white_brick", trim = "steel", floor = "concrete" },
  { wall = "diorite", trim = "granite", floor = "concrete" },
}

local DESIGN = {
  setbacks = 2,
  facade = kit.masonry,
  has_storefront = true,
  roof = "slate",
  crown = kit.spire,
}

function deco.build(lots, spec)
  kit.build(lots, spec, DESIGN)
end

return deco
