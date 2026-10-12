local kit = require("backrooms.kit")
local levels = require("backrooms.levels")
local town = require("town")

-- Endless rooms and hallways in levels going down into the ground, laid out like the city. Hallways run along edges
-- of the tiling, which go on in straight lines through every vertex; the blocks between them are split into rooms,
-- or on a maze level carved into passages. A quarter's walls on its sides are its own, built back to back with the
-- next quarter's, and both take their doorways from the line they share, so they line up. Each face takes its biome
-- on every level from the strongest of it and its neighbors, so biomes come in clumps, and on levels with solid
-- blocks it is solid or not as a whole. Stairwells now and then lead from one level down to the next.
local layout = {}

-- Where one stands on the top level's floor, for whatever arrives there.
layout.GROUND = kit.TOP_FLOOR + 1

local MIX = 0x2545F4914F6CDD1D
local MIX_SHIFT = 24
local LINE_SALT = 0x2F4A7C15
local STAIR_SALT = 0x6A09E667
local BIOME_SALT = 0x3C6EF372
local LEVEL_SALT = 0x9E3779B9
local HALL_SALT = 0x7F4A7C15
local SOLID_SALT = 0x1B873593
local PLAN_SALT = 0x5BD1E995
local GRID_DROPPED_PERCENT = 12
local SECOND_PASSAGE_ODDS = 0.5
local PERCENT = 100

local function mixed(hash, salt)
  return ((hash ~ salt) * MIX) >> MIX_SHIFT
end

local function roll(hash, salt)
  return (mixed(hash, salt) % PERCENT) / PERCENT
end

-- Every level's floor from the top down: each stands the separation and the next level's rooms below the last.
local function floors_of()
  local floors = {}
  local base = kit.TOP_FLOOR
  for index, level in ipairs(levels.LAYERS) do
    if index > 1 then
      base = base - level.room - kit.SEPARATION - 2
    end
    floors[index] = { level = level, base = base, is_top = index == 1 }
  end
  return floors
end

local FLOORS = floors_of()

-- Whether a hallway runs along the edge a turtle faces on a level. The grid and the streets keep the edges at the
-- root, so their hallways all reach the lobby there.
local function is_hall(turtle, root, level, index)
  if level.halls == "none" then
    return false
  elseif level.halls == "streets" then
    return town.is_street(turtle, root)
  elseif turtle:hash("vertex") == root.vertex or turtle:forward(1):hash("vertex") == root.vertex then
    return true
  else
    return mixed(turtle:hash("edge"), HALL_SALT + index) % PERCENT >= GRID_DROPPED_PERCENT
  end
end

local function is_solid(face, level, index)
  return roll(face, SOLID_SALT + index) < level.solid
end

-- A shared wall's doorway, or now and then no wall at all, from the line's own hash. A wall against a solid block
-- has no doorway. On a maze level, the passages through it instead: one, sometimes two.
local function line_doors(hash, index, level, is_closed)
  math.randomseed(hash ~ LINE_SALT ~ index)
  if level.maze then
    local slots = { math.random(0, kit.MAZE_CELLS - 1) }
    if math.random() < SECOND_PASSAGE_ODDS then
      slots[#slots + 1] = (slots[1] + math.random(1, kit.MAZE_CELLS - 1)) % kit.MAZE_CELLS
    end
    return slots
  elseif is_closed then
    return {}
  elseif math.random() < level.missing then
    return "open"
  else
    return { math.random(kit.DOOR_LOW, kit.DOOR_HIGH) }
  end
end

-- A quarter's lines are named by the edge they lie on or cross, and by the vertex or the face they belong to; the
-- faces beyond the low lines are other blocks, and those beyond the high lines are this one.
local function lines_of(corner)
  local vertex, face = corner:hash("vertex"), corner:hash("face")
  local edge_y, edge_x = corner:hash("edge"), corner:right():hash("edge")
  return {
    y_low = { hash = edge_y ~ vertex, beyond = corner:left():hash("face") },
    x_low = { hash = edge_x ~ vertex, beyond = corner:right():hash("face") },
    x_high = { hash = edge_y ~ face, beyond = face },
    y_high = { hash = edge_x ~ face, beyond = face },
  }
end

-- At most one stairwell per quarter, from some level down to the next, set back from both levels' hallways. A root
-- may name a quarter that has one from a given level whatever the odds.
local function stair_of(corner, root, paths, is_lobby)
  math.randomseed(corner:hash("vertex") ~ corner:hash("face") ~ STAIR_SALT)
  local upper = math.random(#FLOORS - 1)
  local forced = root.forced_stair
  local is_forced = forced ~= nil and corner:hash("vertex") == forced.vertex and corner:hash("face") == forced.face
  if is_forced then
    upper = forced.upper
  end
  if is_lobby or (not is_forced and math.random() >= FLOORS[upper].level.stairs) then
    return nil
  else
    local lower = upper + 1
    local a, b = FLOORS[upper].level, FLOORS[lower].level
    local x = math.max(kit.origin(paths[upper].x, a), kit.origin(paths[lower].x, b))
    local y = math.max(kit.origin(paths[upper].y, a), kit.origin(paths[lower].y, b))
    return { upper = upper, lower = lower, x = x, y = y, is_forced = is_forced }
  end
end

-- A lobby stays on every level a connector's shaft runs down through, short of a maze, which lies too deep for it.
local function plan_of(corner, q, floor, index, is_solid_block, has_stair, path)
  local level = floor.level
  local chance = roll(corner:hash("vertex") ~ corner:hash("face"), PLAN_SALT + index)
  if level.maze then
    return "maze"
  elseif q.lobby and (floor.is_top or q.shaft) then
    return "lobby"
  elseif has_stair then
    return "rooms"
  elseif is_solid_block then
    return "solid"
  elseif chance < level.rings then
    return "rings"
  elseif not path.x and not path.y and chance < level.rings + level.chapel then
    return "chapel"
  else
    return "rooms"
  end
end

local function quarter(corner, root, biomes)
  local vertex, face = corner:hash("vertex"), corner:hash("face")
  local q = {
    tower = town.upright(corner),
    lobby = vertex == root.vertex,
  }
  q.shaft = q.lobby and root.has_shaft
  local owns = {
    x_high = vertex > corner:forward(1):hash("vertex"),
    y_high = vertex > corner:right():forward(1):hash("vertex"),
  }
  local paths = {}
  for index, floor in ipairs(FLOORS) do
    paths[index] = { y = is_hall(corner, root, floor.level, index), x = is_hall(corner:right(), root, floor.level, index) }
  end
  local lines = lines_of(corner)
  local stair = stair_of(corner, root, paths, q.lobby)
  if stair and not stair.is_forced and (is_solid(face, FLOORS[stair.upper].level, stair.upper) or is_solid(face, FLOORS[stair.lower].level, stair.lower)) then
    stair = nil
  end
  local frames = {}
  for index = #FLOORS, 1, -1 do
    local floor = FLOORS[index]
    local level = floor.level
    local is_mine_solid = is_solid(face, level, index)
    local doors = {}
    for side, shared in pairs(lines) do
      doors[side] = line_doors(shared.hash, index, level, is_mine_solid or is_solid(shared.beyond, level, index))
    end
    local has_stair = stair ~= nil and (stair.upper == index or stair.lower == index)
    local plan = plan_of(corner, q, floor, index, is_mine_solid, has_stair, paths[index])
    math.randomseed(vertex ~ face ~ index * LEVEL_SALT)
    local f = kit.frame(q, paths[index], floor, biomes[index], has_stair and stair or nil, plan == "lobby", owns)
    kit.floor(f, doors, level, plan)
    frames[index] = f
  end
  if stair then
    kit.stairs(frames[stair.lower], frames[stair.upper], stair, root.is_routed and stair.is_forced)
  end
end

-- Paints a face's quarters on every level, the lowest first. The root names the vertex every hallway near it leads
-- to, which becomes an open lobby, and whether a connector's shaft rises through it; it may also force a stairwell as
-- { vertex, face, upper } for the quarter at that vertex of that face and the level its stairs go down from, routed
-- when is_routed is set.
function layout.tile(face, root)
  local corners = town.corners_of(face)
  local strongest = face:hash("face")
  for _, corner in ipairs(corners) do
    strongest = math.max(strongest, corner:left():hash("face"))
  end
  local biomes = {}
  for index, level in ipairs(levels.LAYERS) do
    biomes[index] = level.biomes[mixed(strongest, BIOME_SALT + index) % #level.biomes + 1]
  end
  for _, corner in ipairs(corners) do
    quarter(corner, root, biomes)
  end
end

return layout
