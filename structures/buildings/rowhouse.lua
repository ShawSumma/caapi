local building = require("buildings.building")

local rowhouse = {}

rowhouse.STORIES = { 2, 3 }
rowhouse.PALETTES = {
  { wall = "white_brick", trim = "spruce_wood", floor = "wood_planks", roof = "slate" },
  { wall = "wood_planks", trim = "white_brick", floor = "wood_planks", roof = "red_sandstone" },
  { wall = "birch_wood", trim = "spruce_wood", floor = "wood_planks", roof = "shale" },
  { wall = "sandstone", trim = "clay", floor = "wood_planks", roof = "clay" },
  { wall = "limestone", trim = "grey_brick", floor = "wood_planks", roof = "slate" },
}

local ROOF = "wood_planks"
local PIER_SPACING = 2
local CROWNS = { building.chimney, building.chimney, building.plain }

local function hip_roof(part, palette, tier)
  local rise = 1
  local box = building.footprint(part, tier.shrink + rise, false, tier.high + rise, tier.high + rise)
  while not building.is_empty(box) do
    part.tower:paint(palette.roof, box)
    rise = rise + 1
    box = building.footprint(part, tier.shrink + rise, false, tier.high + rise, tier.high + rise)
  end
end

function rowhouse.build(lots, spec)
  local parts = building.parts(lots, spec)
  for _, part in ipairs(parts) do
    for _, tier in ipairs(building.tiers(part, spec, 0)) do
      building.punched(part, spec.palette, building.shell(part, spec.palette, tier), tier, PIER_SPACING)
      if tier.is_roofed then
        building.roof(part, spec.palette, ROOF, tier)
      end
    end
    hip_roof(part, spec.palette, part.top)
  end
  building.enter(parts, spec)
  building.crown(parts, spec.palette, building.pick(parts, CROWNS))
end

return rowhouse
