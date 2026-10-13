local building = require("buildings.building")

local glass = {}

glass.STORIES = { 12, 38 }
glass.PALETTES = {
  { wall = "glass", trim = "steel", band = "concrete", floor = "concrete" },
  { wall = "glass", trim = "basalt", band = "slate", floor = "concrete" },
  { wall = "glass", trim = "steel", band = "steel", floor = "marble" },
  { wall = "glass", trim = "gabbro", band = "gabbro", floor = "concrete" },
}

local SETBACKS = 1
local ROOF = "concrete"
local SPANDRELS = { every = building.STORY, from = building.STORY - 1, span = 1 }
local MULLION_SPACING = 3
local PENTHOUSE_SETBACK = 2
local LEAST_WIDTH = 3
local ANTENNA = 6

local function curtain(part, palette, box, tier)
  for _, face in ipairs(building.walls(part, box, tier)) do
    part.tower:paint(palette.band, face, SPANDRELS)
    for _, mullion in ipairs(building.strips(face, MULLION_SPACING)) do
      part.tower:paint(palette.trim, mullion)
    end
  end
end

local function penthouse(part, palette, tier)
  local roof_box = building.footprint(part, tier.shrink, false, tier.high, tier.high)
  local cap = { low = tier.high + 1, high = tier.high + building.STORY, shrink = tier.shrink + building.narrowing(roof_box, PENTHOUSE_SETBACK, LEAST_WIDTH), is_below_split = false }
  local closed = { tower = part.tower, x = part.x, y = part.y, kinds = { x_low = building.LOT, y_low = building.LOT, x_high = building.LOT, y_high = building.LOT }, joins = {} }
  building.shell(closed, { wall = palette.band, floor = palette.floor }, cap)
  return cap
end

local function antenna(part, palette, tier)
  local roof_box = building.footprint(part, tier.shrink, false, tier.high, tier.high)
  local x, y = building.middle(roof_box.x), building.middle(roof_box.y)
  part.tower:paint(palette.trim, { x = { x, x }, y = { y, y }, z = { tier.high + 1, tier.high + ANTENNA } })
end

local CROWNS = { antenna, building.masts, building.helipad }

function glass.build(lots, spec)
  local parts = building.parts(lots, spec)
  local setbacks = building.setbacks(parts, SETBACKS)
  for _, part in ipairs(parts) do
    for _, tier in ipairs(building.tiers(part, spec, setbacks)) do
      curtain(part, spec.palette, building.shell(part, spec.palette, tier), tier)
      if tier.is_roofed then
        building.roof(part, spec.palette, ROOF, tier)
      end
    end
    part.stand = penthouse(part, spec.palette, part.top)
  end
  building.enter(parts, spec)
  building.crown(parts, spec.palette, building.pick(parts, CROWNS))
end

return glass
