local building = require("buildings.building")

local brownstone = {}

brownstone.STORIES = { 4, 5 }
brownstone.PALETTES = {
  { wall = "red_sandstone", trim = "sandstone", floor = "wood_planks" },
  { wall = "red_sandstone", trim = "limestone", floor = "wood_planks" },
  { wall = "shale", trim = "limestone", floor = "wood_planks" },
  { wall = "clay", trim = "sandstone", floor = "wood_planks" },
  { wall = "spruce_wood", trim = "diorite", floor = "wood_planks" },
}

local ROOF = "slate"
local CROWNS = { building.chimney, building.plain }

function brownstone.build(lots, spec)
  local parts = building.parts(lots, spec)
  for _, part in ipairs(parts) do
    for _, tier in ipairs(building.tiers(part, spec, 0)) do
      building.masonry(part, spec.palette, building.shell(part, spec.palette, tier), tier)
      if tier.is_roofed then
        building.roof(part, spec.palette, ROOF, tier)
      end
    end
  end
  building.enter(parts, spec)
  building.crown(parts, spec.palette, building.pick(parts, CROWNS))
end

return brownstone
