local building = require("buildings.building")

local deco = {}

deco.STORIES = { 14, 34 }
deco.PALETTES = {
  { wall = "limestone", trim = "steel", floor = "concrete" },
  { wall = "sandstone", trim = "marble", floor = "concrete" },
  { wall = "white_brick", trim = "steel", floor = "concrete" },
  { wall = "diorite", trim = "granite", floor = "concrete" },
  { wall = "dolomite", trim = "slate", floor = "concrete" },
}

local SETBACKS = 2
local ROOF = "slate"
local SPIRE = 10

local function spire(part, palette, tier)
  local roof_box = building.footprint(part, tier.shrink, false, tier.high, tier.high)
  local x, y = building.middle(roof_box.x), building.middle(roof_box.y)
  part.tower:paint(palette.trim, { x = { x - 1, x + 1 }, y = { y - 1, y + 1 }, z = { tier.high + 1, tier.high + 2 } })
  part.tower:paint(palette.trim, { x = { x, x }, y = { y, y }, z = { tier.high + 3, tier.high + SPIRE } })
end

local CROWNS = { spire, spire, building.pyramid }

function deco.build(lots, spec)
  local parts = building.parts(lots, spec)
  local setbacks = building.setbacks(parts, SETBACKS)
  for _, part in ipairs(parts) do
    for _, tier in ipairs(building.tiers(part, spec, setbacks)) do
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

return deco
