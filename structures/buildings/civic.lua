local building = require("buildings.building")

local civic = {}

civic.STORIES = { 3, 6 }
civic.PALETTES = {
  { wall = "marble", trim = "limestone", floor = "marble", roof = "slate" },
  { wall = "limestone", trim = "marble", floor = "marble", roof = "steel" },
  { wall = "sandstone", trim = "limestone", floor = "wood_planks", roof = "clay" },
  { wall = "granite", trim = "marble", floor = "marble", roof = "slate" },
}

local SETBACKS = 1
local ROOF = "slate"
local COLUMN_SPACING = 3

local function arcade(part, palette)
  local box = building.footprint(part, 0, true, 1, building.STORY - 1)
  for _, side in ipairs(building.SIDES) do
    if part.kinds[side] == building.STREET then
      local face = building.face_of(box, side)
      part.tower:paint("air", face)
      for _, column in ipairs(building.strips(face, COLUMN_SPACING)) do
        part.tower:paint(palette.trim, column)
      end
      local behind = building.moved_out(face, side, -1)
      local run = building.along(behind, side)
      part.tower:paint("glass", building.with_along(behind, side, { run[1] + 1, run[2] - 1 }))
    end
  end
end

local function dome(part, palette, tier)
  local roof_box = building.footprint(part, tier.shrink + 1, false, tier.high, tier.high)
  local reach = (math.min(building.width(roof_box.x), building.width(roof_box.y)) - 1) // 2
  local x, y = building.middle(roof_box.x), building.middle(roof_box.y)
  for level = 0, reach do
    local spread = math.floor(math.sqrt(reach * reach - level * level) + 0.5)
    local z = tier.high + level + 1
    part.tower:paint(palette.roof, { x = { x - spread, x + spread }, y = { y - spread, y + spread }, z = { z, z } })
  end
end

local CROWNS = { dome, dome, building.pyramid }

function civic.build(lots, spec)
  local parts = building.parts(lots, spec)
  local setbacks = building.setbacks(parts, SETBACKS)
  for _, part in ipairs(parts) do
    for _, tier in ipairs(building.tiers(part, spec, setbacks)) do
      building.masonry(part, spec.palette, building.shell(part, spec.palette, tier), tier)
      if tier.is_roofed then
        building.roof(part, spec.palette, ROOF, tier)
      end
    end
    arcade(part, spec.palette)
  end
  building.enter(parts, spec)
  building.crown(parts, spec.palette, building.pick(parts, CROWNS))
end

return civic
