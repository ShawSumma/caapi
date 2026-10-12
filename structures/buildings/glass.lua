local kit = require("buildings.kit")

local glass = {}

glass.STORIES = { 12, 38 }
glass.PALETTES = {
  { wall = "glass", trim = "steel", band = "concrete", floor = "concrete" },
  { wall = "glass", trim = "basalt", band = "slate", floor = "concrete" },
  { wall = "glass", trim = "steel", band = "steel", floor = "marble" },
  { wall = "glass", trim = "gabbro", band = "gabbro", floor = "concrete" },
}

local DESIGN = {
  setbacks = 1,
  facade = kit.curtain,
  roof = "concrete",
  cap = kit.penthouse,
  crowns = { kit.antenna, kit.masts, kit.helipad },
}

function glass.build(lots, spec)
  kit.build(lots, spec, DESIGN)
end

return glass
