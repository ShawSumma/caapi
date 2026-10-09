local box = require("box")
local town = require("town")

local sky = {}

local TOWER_PERCENT = 35
local TOWER_EDGES = 6
local NO_OPTIONS = {}

local function settings_of(options)
  return options or NO_OPTIONS
end

local function is_foot(corner, foot)
  return corner:hash("vertex") == foot:hash("vertex")
end

function sky.wild(face, foot, options)
  local settings = settings_of(options)
  for _, corner in ipairs(town.corners_of(face)) do
    if is_foot(corner, foot) and town.is_owner(town.quarters_of(corner)) then
      box.connector(foot, { terrain = true, route = settings.route })
    end
  end
end

function sky.city(face, foot, options)
  local settings = settings_of(options)
  town.tile(face, { vertex = foot:hash("vertex"), face = foot:hash("face"), foot = foot, connector = { route = settings.route } })
end

local function meadow(quarters)
  for _, quarter in ipairs(quarters) do
    local ground = town.upright(quarter)
    local _, far = ground:column()
    ground:paint("grass", { x = { 0, far }, y = { 0, far }, z = { -1, -1 } })
  end
end

local function spire(corner)
  local tower = corner:pitch_up()
  box.tower(tower, box.top(tower, corner:pick(TOWER_EDGES)), box.palette(tower))
  box.door(tower)
end

function sky.towers(face, foot, options)
  local settings = settings_of(options)
  for _, corner in ipairs(town.corners_of(face)) do
    local quarters = town.quarters_of(corner)
    if town.is_owner(quarters) then
      meadow(quarters)
      if is_foot(corner, foot) then
        box.connector(foot, { route = settings.route })
      elseif corner:pick(100) <= TOWER_PERCENT then
        spire(corner)
      end
    end
  end
end

return sky
