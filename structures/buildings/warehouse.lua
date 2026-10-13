local building = require("buildings.building")

local warehouse = {}

warehouse.STORIES = { 2, 4 }
warehouse.PALETTES = {
  { wall = "red_sandstone", trim = "grey_brick", floor = "concrete" },
  { wall = "grey_brick", trim = "steel", floor = "concrete" },
  { wall = "concrete", trim = "steel", floor = "concrete" },
  { wall = "clay", trim = "basalt", floor = "wood_planks" },
}

local ROOF = "basalt"
local HIGH_ROWS = { every = building.STORY, from = 2, span = 1 }
local CROWNS = { building.chimney, building.water_tower, building.plain }

function warehouse.build(lots, spec)
  local parts = building.parts(lots, spec)
  for _, part in ipairs(parts) do
    for _, tier in ipairs(building.tiers(part, spec, 0)) do
      building.banded(part, building.shell(part, spec.palette, tier), tier, HIGH_ROWS)
      if tier.is_roofed then
        building.roof(part, spec.palette, ROOF, tier)
      end
    end
  end
  building.enter(parts, spec)
  building.crown(parts, spec.palette, building.pick(parts, CROWNS))
end

return warehouse
