local kit = require("buildings.kit")

local civic = {}

civic.STORIES = { 3, 6 }
civic.PALETTES = {
  { wall = "marble", trim = "limestone", floor = "marble", roof = "slate" },
  { wall = "limestone", trim = "marble", floor = "marble", roof = "steel" },
  { wall = "sandstone", trim = "limestone", floor = "wood_planks", roof = "clay" },
  { wall = "granite", trim = "marble", floor = "marble", roof = "slate" },
}

local DESIGN = {
  setbacks = 1,
  facade = kit.masonry,
  ground = kit.arcade,
  roof = "slate",
  crowns = { kit.dome, kit.dome, kit.pyramid },
}

function civic.build(lots, spec)
  kit.build(lots, spec, DESIGN)
end

return civic
