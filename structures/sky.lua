local backrooms = require("backrooms")
local connector = require("connector")
local kit = require("buildings.kit")
local town = require("town")

local sky = {}

local SPIRE_PERCENT = 30
local SPIRE_TYPES = {
  require("buildings.deco"),
  require("buildings.glass"),
  require("buildings.modern"),
}
local VARIANTS = 1024
local LOT_FRONT = 4
local MEADOW_GROUND = 0
local BACKROOMS_GROUND = 1
local NO_OPTIONS = {}

local function settings_of(options)
  return options or NO_OPTIONS
end

local function is_foot(corner, info)
  return corner:hash("vertex") == info.foot:hash("vertex")
end

local function corner_lot(site)
  return { site = site, x_low = kit.STREET, y_low = kit.STREET, x_high = kit.LOT, y_high = kit.LOT, front = "y_low" }
end

local function connect(face, info, ground, settings)
  for _, corner in ipairs(town.corners_of(face)) do
    if is_foot(corner, info) and town.is_owner(town.quarters_of(corner)) then
      connector.build(info.foot, info, ground, settings.route)
    end
  end
end

function sky.wild(face, info, options)
  connect(face, info, info.ground, settings_of(options))
end

function sky.city(face, info, options)
  local settings = settings_of(options)
  town.tile(face, { vertex = info.foot:hash("vertex"), face = info.foot:hash("face"), sky = info, is_routed = settings.route })
end

function sky.backrooms(face, info, options)
  backrooms.tile(face, { foot = info.foot:hash("vertex") })
  connect(face, info, BACKROOMS_GROUND, settings_of(options))
end

local function meadow(quarters)
  for _, quarter in ipairs(quarters) do
    local ground = town.upright(quarter)
    local _, far = ground:column()
    ground:paint("grass", { x = { 0, far }, y = { 0, far }, z = { -1, -1 } })
  end
end

local function spire(corner)
  local tower = town.upright(corner)
  local _, far = tower:column()
  tower:paint("concrete", { x = { 0, far }, y = { 0, far }, z = { -1, 0 } })
  local type = SPIRE_TYPES[corner:pick(#SPIRE_TYPES)]
  local stories = town.fit(corner, type.STORIES[1] + corner:pick(type.STORIES[2] - type.STORIES[1] + 1) - 1)
  local palette = type.PALETTES[corner:pick(#type.PALETTES)]
  if stories >= 1 then
    type.build({ corner_lot(corner) }, { stories = stories, palette = palette, front = LOT_FRONT, gap = 0, variant = corner:pick(VARIANTS) })
  end
end

function sky.spires(face, info, options)
  local settings = settings_of(options)
  for _, corner in ipairs(town.corners_of(face)) do
    local quarters = town.quarters_of(corner)
    if town.is_owner(quarters) then
      meadow(quarters)
      if is_foot(corner, info) then
        connector.build(info.foot, info, MEADOW_GROUND, settings.route)
      elseif corner:pick(100) <= SPIRE_PERCENT then
        spire(corner)
      end
    end
  end
end

return sky
