local building = require("buildings.building")

local tenement = {}

tenement.STORIES = { 5, 9 }
tenement.PALETTES = {
  { wall = "grey_brick", trim = "white_brick", floor = "wood_planks" },
  { wall = "white_brick", trim = "grey_brick", floor = "wood_planks" },
  { wall = "red_sandstone", trim = "white_brick", floor = "wood_planks" },
  { wall = "clay", trim = "limestone", floor = "wood_planks" },
  { wall = "andesite", trim = "sandstone", floor = "wood_planks" },
}

local ROOF = "basalt"
local CROWNS = { building.water_tower, building.water_tower, building.chimney }

function tenement.build(lots, spec)
  local parts = building.parts(lots, spec)
  for _, part in ipairs(parts) do
    for _, tier in ipairs(building.tiers(part, spec, 0)) do
      building.masonry(part, spec.palette, building.shell(part, spec.palette, tier), tier)
      if tier.is_roofed then
        building.roof(part, spec.palette, ROOF, tier)
      end
    end
    building.storefront(part)
  end
  building.enter(parts, spec)
  building.crown(parts, spec.palette, building.pick(parts, CROWNS))
end

return tenement
