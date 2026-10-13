local building = require("buildings.building")

local modern = {}

modern.STORIES = { 6, 20 }
modern.PALETTES = {
  { wall = "concrete", trim = "steel", floor = "concrete" },
  { wall = "white_brick", trim = "glass", floor = "marble" },
  { wall = "diorite", trim = "steel", floor = "concrete" },
  { wall = "gabbro", trim = "glass", floor = "concrete" },
}

local SETBACKS = 1
local ROOF = "concrete"
local RAILS = { every = building.STORY, from = 1, span = 1 }
local LEAST_GARDEN = 5

local function balconied(part, palette, box, tier)
  building.banded(part, box, tier, building.WINDOW_ROWS)
  local low = math.max(tier.low, building.STORY)
  if low < tier.high then
    for _, side in ipairs(building.SIDES) do
      if part.kinds[side] == building.STREET then
        local slab = building.moved_out(building.face_of(box, side), side, 1)
        local run = building.along(slab, side)
        slab = building.with_along(slab, side, { run[1] + 1, run[2] - 1 })
        slab.z = { low, tier.high - 1 }
        part.tower:paint(palette.floor, slab, building.FLOORS)
        part.tower:paint(palette.trim, slab, RAILS)
      end
    end
  end
end

local function garden(part, tier)
  local lawn = building.footprint(part, tier.shrink + 1, false, tier.high, tier.high)
  if not building.is_empty(lawn) then
    part.tower:paint("grass", lawn)
    if building.width(lawn.x) >= LEAST_GARDEN and building.width(lawn.y) >= LEAST_GARDEN then
      local x, y, z = building.middle(lawn.x), building.middle(lawn.y), tier.high
      part.tower:paint("oak_leaves", { x = { x - 1, x + 1 }, y = { y - 1, y + 1 }, z = { z + 3, z + 4 } })
      part.tower:paint("oak_leaves", { x = { x, x }, y = { y, y }, z = { z + 5, z + 5 } })
      part.tower:paint("oak_wood", { x = { x, x }, y = { y, y }, z = { z + 1, z + 3 } })
    end
  end
end

local CROWNS = { building.helipad, building.masts, building.plain }

function modern.build(lots, spec)
  local parts = building.parts(lots, spec)
  local setbacks = building.setbacks(parts, SETBACKS)
  for _, part in ipairs(parts) do
    for _, tier in ipairs(building.tiers(part, spec, setbacks)) do
      balconied(part, spec.palette, building.shell(part, spec.palette, tier), tier)
      if tier.is_roofed then
        building.roof(part, spec.palette, ROOF, tier)
      end
    end
    building.storefront(part)
    garden(part, part.top)
  end
  building.enter(parts, spec)
  building.crown(parts, spec.palette, building.pick(parts, CROWNS))
end

return modern
