local blocks = require("city.blocks")
local levels = require("backrooms.levels")
local rooms = require("backrooms.rooms")

local layout = {}

local TOP_FLOOR = -2

layout.GROUND = TOP_FLOOR + 1

local DOOR_LOW = 3
local DOOR_HIGH = 8
local SLOT_SALT = 0x2F4A7C15
local SECOND_SALT = 0x4F1BBCDD
local OFFSET_SALT = 0x6B43A9B5
local MISSING_SALT = 0x1F83D9AB
local DOOR_SALT = 0x5BE0CD19
local STAIR_SALT = 0x6A09E667
local STAIR_ODDS_SALT = 0x510E527F
local BIOME_SALT = 0x3C6EF372
local HALL_SALT = 0x7F4A7C15
local SOLID_SALT = 0x1B873593
local PLAN_SALT = 0x5BD1E995
local GRID_DROPPED = 0.12
local SECOND_PASSAGE_ODDS = 0.5

local function floors_of()
  local floors = {}
  local base = TOP_FLOOR
  for index, level in ipairs(levels.LAYERS) do
    if index > 1 then
      base = base - level.room - rooms.SEPARATION - 2
    end
    floors[index] = { level = level, base = base, is_top = index == 1 }
  end
  return floors
end

local FLOORS = floors_of()

local function is_hall(turtle, root, level, index)
  if level.halls == "none" then
    return false
  elseif level.halls == "streets" then
    return blocks.is_street(turtle, root)
  elseif turtle:hash("vertex") == root.vertex or turtle:forward(1):hash("vertex") == root.vertex then
    return true
  else
    return blocks.roll(turtle:hash("edge"), HALL_SALT + index) >= GRID_DROPPED
  end
end

local function is_solid(face, level, index)
  return blocks.roll(face, SOLID_SALT + index) < level.solid
end

local function line_doors(hash, index, level, is_closed)
  if level.is_maze then
    local first = blocks.mixed(hash, SLOT_SALT + index) % rooms.MAZE_CELLS
    local slots = { first }
    if blocks.roll(hash, SECOND_SALT + index) < SECOND_PASSAGE_ODDS then
      slots[2] = (first + 1 + blocks.mixed(hash, OFFSET_SALT + index) % (rooms.MAZE_CELLS - 1)) % rooms.MAZE_CELLS
    end
    return slots
  elseif is_closed then
    return {}
  elseif blocks.roll(hash, MISSING_SALT + index) < level.missing then
    return "open"
  else
    return { DOOR_LOW + blocks.mixed(hash, DOOR_SALT + index) % (DOOR_HIGH - DOOR_LOW + 1) }
  end
end

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

local function stair_of(corner, root, halls, is_lobby)
  local hash = corner:hash("vertex") ~ corner:hash("face")
  local upper = 1 + blocks.mixed(hash, STAIR_SALT) % (#FLOORS - 1)
  local forced = root.forced_stair
  local is_forced = forced ~= nil and corner:hash("vertex") == forced.vertex and corner:hash("face") == forced.face
  if is_forced then
    upper = forced.upper
  end
  if is_lobby or (not is_forced and blocks.roll(hash, STAIR_ODDS_SALT) >= FLOORS[upper].level.stairs) then
    return nil
  else
    local lower = upper + 1
    local a, b = FLOORS[upper].level, FLOORS[lower].level
    local x = math.max(rooms.origin(halls[upper].x, a), rooms.origin(halls[lower].x, b))
    local y = math.max(rooms.origin(halls[upper].y, a), rooms.origin(halls[lower].y, b))
    return { upper = upper, lower = lower, x = x, y = y, is_forced = is_forced }
  end
end

local function plan_of(corner, q, floor, index, is_solid_block, has_stair, has_halls)
  local level = floor.level
  local chance = blocks.roll(corner:hash("vertex") ~ corner:hash("face"), PLAN_SALT + index)
  if level.is_maze then
    return "maze"
  elseif q.is_lobby and (floor.is_top or q.has_shaft) then
    return "lobby"
  elseif has_stair then
    return "rooms"
  elseif is_solid_block then
    return "solid"
  elseif chance < level.rings then
    return "rings"
  elseif not has_halls.x and not has_halls.y and chance < level.rings + level.chapel then
    return "chapel"
  else
    return "rooms"
  end
end

local function quarter(corner, root, biomes)
  local vertex, face = corner:hash("vertex"), corner:hash("face")
  local is_lobby = vertex == root.vertex
  local q = {
    tower = blocks.upright(corner),
    is_lobby = is_lobby,
    has_shaft = is_lobby and root.has_shaft,
  }
  local owns = {
    x_high = vertex > corner:forward(1):hash("vertex"),
    y_high = vertex > corner:right():forward(1):hash("vertex"),
  }
  local halls = {}
  for index, floor in ipairs(FLOORS) do
    halls[index] = { y = is_hall(corner, root, floor.level, index), x = is_hall(corner:right(), root, floor.level, index) }
  end
  local lines = lines_of(corner)
  local stair = stair_of(corner, root, halls, q.is_lobby)
  if stair ~= nil and not stair.is_forced and (is_solid(face, FLOORS[stair.upper].level, stair.upper) or is_solid(face, FLOORS[stair.lower].level, stair.lower)) then
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
    local plan = plan_of(corner, q, floor, index, is_mine_solid, has_stair, halls[index])
    local floor_stair = nil
    if has_stair then
      floor_stair = stair
    end
    local f = rooms.frame(q, halls[index], floor, biomes[index], floor_stair, plan == "lobby", owns)
    rooms.floor(f, doors, plan)
    frames[index] = f
  end
  if stair ~= nil then
    rooms.stairs(frames[stair.lower], frames[stair.upper], stair, root.is_routed and stair.is_forced)
  end
end

function layout.tile(face, root)
  local corners = blocks.corners_of(face)
  local strongest = face:hash("face")
  for _, corner in ipairs(corners) do
    strongest = math.max(strongest, corner:left():hash("face"))
  end
  local biomes = {}
  for index, level in ipairs(levels.LAYERS) do
    biomes[index] = level.biomes[blocks.mixed(strongest, BIOME_SALT + index) % #level.biomes + 1]
  end
  for _, corner in ipairs(corners) do
    quarter(corner, root, biomes)
  end
end

return layout
