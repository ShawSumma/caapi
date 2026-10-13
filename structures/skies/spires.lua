local blocks = require("city.blocks")
local building = require("buildings.building")
local connector = require("connector")

local SPIRE_PERCENT = 30
local PERCENT = 100
local SPIRE_TYPES = {
  require("buildings.deco"),
  require("buildings.glass"),
  require("buildings.modern"),
}
local LOT_FRONT = 4
local MEADOW_GROUND = 0

local function corner_lot(site)
  return { site = site, x_low = building.STREET, y_low = building.STREET, x_high = building.LOT, y_high = building.LOT, front = "y_low" }
end

local function meadow(quarters)
  for _, quarter in ipairs(quarters) do
    local ground = blocks.upright(quarter)
    local _, far = ground:column()
    ground:paint("grass", { x = { 0, far }, y = { 0, far }, z = { -1, -1 } })
  end
end

local function spire(corner)
  local tower = blocks.upright(corner)
  local _, far = tower:column()
  tower:paint("concrete", { x = { 0, far }, y = { 0, far }, z = { -1, 0 } })
  local chosen = SPIRE_TYPES[corner:pick(#SPIRE_TYPES)]
  local stories = blocks.fit(corner, chosen.STORIES[1] + corner:pick(chosen.STORIES[2] - chosen.STORIES[1] + 1) - 1)
  local palette = chosen.PALETTES[corner:pick(#chosen.PALETTES)]
  if stories >= 1 then
    chosen.build({ corner_lot(corner) }, { stories = stories, palette = palette, front = LOT_FRONT, gap = 0 })
  end
end

return function(face, sky, is_routed)
  for _, corner in ipairs(blocks.corners_of(face)) do
    local quarters = blocks.quarters_of(corner)
    if blocks.is_owner(quarters) then
      meadow(quarters)
      if blocks.is_foot(corner, sky) then
        connector(sky.foot, sky, MEADOW_GROUND, is_routed)
      elseif corner:pick(PERCENT) <= SPIRE_PERCENT then
        spire(corner)
      end
    end
  end
end
