local box = require("tower.box")

local HALF_WIDTH = 2
local HUT_EVERY = 3
local HUT_STORIES = 2
local TIMBER = { wall = "oak_wood", floor = "wood_planks", trim = "spruce_wood" }
local ROUTE_LANE = 0.5

local TURNS = {
  function(site) return site end,
  function(site) return site:left() end,
  function(site) return site:right() end,
}

local function pave(segment)
  local length = segment:edge_cells()
  segment:paint("gravel", { x = { -HALF_WIDTH, HALF_WIDTH - 1 }, y = { -1, -1 }, z = { -HALF_WIDTH, length + HALF_WIDTH - 1 } })
  segment:stop(ROUTE_LANE, 0, length / 2)
end

local function hut(site)
  local tower = site:pitch_up()
  box.tower(tower, HUT_STORIES * box.STORY, TIMBER)
  box.door(tower)
end

local function add_hut(tip)
  local yard = tip:right():forward(1)
  if not yard:is_claimed() then
    local is_placed = yard:left():place(hut)
    if is_placed then
      yard:claim()
    end
  end
end

local trail

local function extend(segment)
  local ahead = segment:forward(1)
  if ahead:is_claimed() then
    return false
  else
    local is_placed = segment:place(trail)
    if is_placed then
      ahead:claim()
    end
    return is_placed
  end
end

trail = function(segment)
  segment:claim()
  segment:forward(1):claim()
  pave(segment)
  local tip = segment:forward(1)
  if segment:hash("edge") % HUT_EVERY == 0 then
    add_hut(tip)
  end
  local first = segment:pick(#TURNS)
  local tried = 0
  local is_extended = false
  while tried < #TURNS and not is_extended do
    local turn = TURNS[(first + tried - 1) % #TURNS + 1]
    is_extended = extend(turn(tip))
    tried = tried + 1
  end
end

return trail
