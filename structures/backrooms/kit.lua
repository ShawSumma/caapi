-- Painting one level of one quarter of the backrooms. A quarter is a square of cells with a vertex of the tiling at
-- (0, 0) and the middle of its face at (far, far); its low sides run along edges of the tiling and its high sides
-- across the face. A frame holds what painting it needs: the quarter's tower, the level's floor height and sizes, the
-- biome, and where hallways run along its low sides.
local kit = {}

-- The top level's floor sits a little below the ground's plane, so eye level is about on it: in hyperbolic space
-- only that plane looks flat, and surfaces any distance above or below it curve away.
kit.TOP_FLOOR = -2
-- Cells of solid ground between one level's ceiling and the floor of the level below.
kit.SEPARATION = 3
kit.DOOR_LOW = 3
kit.DOOR_HIGH = 8
-- A maze's passages are two cells wide with a wall between, so they repeat every three cells; a quarter holds four
-- along each side, the last reaching the middle of the face and running on into the next quarter's.
kit.MAZE_CELLS = 4
local MAZE_PITCH = 3
local MAZE_WIDTH = 2
local MAZE_LOOP_ODDS = 0.1
local MAZE_ROOM_ODDS = 0.25
local MAZE_LIGHT_ODDS = 0.15
local DOOR_WIDTH = 2
local MOST_DOOR_HEIGHT = 3
local MIN_ROOM = 3
local LOBBY = 5
local SHAFT = 3
local LIGHT_FROM = 2
local LIGHT_EVERY = 4
local SKIRTING_ODDS = 0.5
local DAMP_ODDS = 0.3
local VENT_ODDS = 0.15
local ROOF = 1
local RINGS = { 1, 3 }
local SIDES = { "x_low", "y_low", "x_high", "y_high" }
local LEAST_ATTACHED_WALL = 4
local NOWHERE_STEPS = 2
local CHAPEL_RISE = 3
local PODIUMS = 5
local HANGING = 2
local PODIUM_SIZE = 2
local MURAL_HALF = 2
local STAIR_ROWS = 4

local function width(span)
  return span[2] - span[1] + 1
end

local function middle(span)
  return (span[1] + span[2]) // 2
end

-- The cells of a wall line: axis names the coordinate that stays at `at`, and span runs along the other.
local function line(axis, at, span, z)
  if axis == "x" then
    return { x = { at, at }, y = span, z = z }
  else
    return { x = span, y = { at, at }, z = z }
  end
end

local function other(axis)
  if axis == "x" then
    return "y"
  else
    return "x"
  end
end

local function room_z(f)
  return { f.base + 1, f.base + f.room }
end

local function ceiling_z(f)
  return f.base + f.room + 1
end

-- Where a quarter's rooms start on a level: past a hallway and its wall along a low side, or past the shared wall.
function kit.origin(is_hall, level)
  if is_hall then
    return level.hall_width + 1
  else
    return 1
  end
end

-- How many rows from the quarter's y side a stairwell takes, with the wall round it on the level above.
kit.STAIR_ROWS = STAIR_ROWS + 1

-- A lobby with a connector rising through it leaves the corner by the vertex to the shaft on every level: the shaft
-- above the top one and its footing below, which fills only open cells, so painting there would make what is built
-- depend on which tile ran first. Below the top level the corner stays solid ground. A lobby keeps the ring around
-- that corner clear of walls.
local function outside_shaft(f, area)
  if not f.shaft then
    return { area }
  else
    local pieces = {}
    if area.x[2] > SHAFT then
      pieces[#pieces + 1] = { x = { math.max(area.x[1], SHAFT + 1), area.x[2] }, y = area.y }
    end
    if area.x[1] <= SHAFT and area.y[2] > SHAFT then
      pieces[#pieces + 1] = { x = { area.x[1], math.min(area.x[2], SHAFT) }, y = { math.max(area.y[1], SHAFT + 1), area.y[2] } }
    end
    return pieces
  end
end

local function outside_lobby(f, at, span)
  if not f.lobby or at > LOBBY then
    return { span }
  elseif span[2] > LOBBY then
    return { { math.max(span[1], LOBBY + 1), span[2] } }
  else
    return {}
  end
end

local function cell_key(x, y)
  return x * 64 + y
end

-- A doorway two wide and three tall, or as tall as the rooms where they are lower. The cells on both sides of it are
-- kept clear of anything later stood in a room.
local function doorway(f, axis, at, door)
  f.tower:paint("air", line(axis, at, { door, door + DOOR_WIDTH - 1 }, { f.base + 1, f.base + f.door_height }))
  for along = door, door + DOOR_WIDTH - 1 do
    for across = at - 1, at + 1 do
      if axis == "x" then
        f.near_doors[cell_key(across, along)] = true
      else
        f.near_doors[cell_key(along, across)] = true
      end
    end
  end
end

-- A wall up to the ceiling with a doorway starting at each of the doors, now and then a vent up by the ceiling.
function kit.wall(f, axis, at, span, doors)
  for _, piece in ipairs(outside_lobby(f, at, span)) do
    f.tower:paint(f.biome.wall, line(axis, at, piece, room_z(f)))
    if f.skirting then
      f.tower:paint(f.biome.trim, line(axis, at, piece, { f.base + 1, f.base + 1 }))
    end
    if f.biome.vents and math.random() < VENT_ODDS then
      local vent = math.random(piece[1], piece[2])
      f.tower:paint("steel", line(axis, at, { vent, vent }, { f.base + f.room, f.base + f.room }))
    end
  end
  for _, door in ipairs(doors) do
    doorway(f, axis, at, door)
  end
end

local function slab(f, material, area, z)
  for _, piece in ipairs(outside_shaft(f, area)) do
    f.tower:paint(material, { x = piece.x, y = piece.y, z = { z, z } })
  end
end

local function bands(f)
  local list = {}
  if f.path_y then
    list[#list + 1] = { x = { 0, f.far }, y = { 0, f.hall_width - 1 } }
  end
  if f.path_x then
    list[#list + 1] = { x = { 0, f.hall_width - 1 }, y = { 0, f.far } }
  end
  return list
end

function kit.shell(f)
  local whole = { x = { 0, f.far }, y = { 0, f.far } }
  slab(f, f.biome.floor, whole, f.base)
  for _, piece in ipairs(outside_shaft(f, whole)) do
    f.tower:paint("air", { x = piece.x, y = piece.y, z = room_z(f) })
  end
  slab(f, f.biome.ceiling, whole, ceiling_z(f))
  for _, band in ipairs(bands(f)) do
    slab(f, f.hall.floor, band, f.base)
    slab(f, f.hall.ceiling, band, ceiling_z(f))
  end
  if f.is_top then
    slab(f, "steel", whole, ceiling_z(f) + ROOF)
  end
end

-- The quarter's walls: a hallway's side wall where a hallway runs along a low side, otherwise the wall shared with
-- the next quarter with the doorways both sides agreed on, or no wall at all where they agreed on none. Walls stop
-- short of the hallways they meet. Returns the cells where a room's own wall may not meet these, since a doorway
-- opens there.
function kit.walls(f, lines)
  local hall = f.hall_width
  local from_x = f.path_x and hall or 0
  local from_y = f.path_y and hall or 0
  local walls = {
    y_low = { axis = "y", at = f.path_y and hall or 0, span = { from_x, f.far }, doors = f.path_y and {} or lines.y_low },
    x_low = { axis = "x", at = f.path_x and hall or 0, span = { from_y, f.far }, doors = f.path_x and {} or lines.x_low },
    x_high = { axis = "x", at = f.far, span = { from_y, f.far }, doors = lines.x_high },
    y_high = { axis = "y", at = f.far, span = { from_x, f.far }, doors = lines.y_high },
  }
  local forbid = { x = {}, y = {} }
  for _, side in ipairs(SIDES) do
    local wall = walls[side]
    if wall.doors ~= "open" then
      kit.wall(f, wall.axis, wall.at, wall.span, wall.doors)
      for _, door in ipairs(wall.doors) do
        forbid[other(wall.axis)][door] = true
        forbid[other(wall.axis)][door + 1] = true
      end
    end
  end
  return forbid
end

local function copy(forbid)
  local result = { x = {}, y = {} }
  for axis, set in pairs(forbid) do
    for cell in pairs(set) do
      result[axis][cell] = true
    end
  end
  return result
end

-- Splits a region into rooms with walls across it, each with one doorway, until the rooms are small or the biome
-- likes them big. A wall never stands where it would meet a doorway in the wall it runs into. Some walls the biome
-- leaves out, joining two rooms into one.
local function split(f, region, forbid, rooms, depth)
  local axes = {}
  for _, axis in ipairs({ "x", "y" }) do
    if width(region[axis]) >= 2 * MIN_ROOM + 1 then
      axes[#axes + 1] = axis
    end
  end
  local stops = math.random() < f.biome.big * math.min(depth, 1)
  if #axes == 0 or stops then
    rooms[#rooms + 1] = region
  else
    local axis = axes[math.random(#axes)]
    if #axes == 2 and width(region.x) ~= width(region.y) then
      axis = width(region.x) > width(region.y) and "x" or "y"
    end
    local span = region[axis]
    local candidates = {}
    for at = span[1] + MIN_ROOM, span[2] - MIN_ROOM do
      if not forbid[axis][at] then
        candidates[#candidates + 1] = at
      end
    end
    if #candidates == 0 then
      rooms[#rooms + 1] = region
    else
      local at = candidates[math.random(#candidates)]
      local along = region[other(axis)]
      local inner = copy(forbid)
      if math.random() >= f.biome.open then
        local door = math.random(along[1], along[2] - DOOR_WIDTH + 1)
        kit.wall(f, axis, at, along, { door })
        inner[other(axis)][door] = true
        inner[other(axis)][door + 1] = true
      end
      local low = { x = region.x, y = region.y }
      local high = { x = region.x, y = region.y }
      low[axis] = { span[1], at - 1 }
      high[axis] = { at + 1, span[2] }
      split(f, low, inner, rooms, depth + 1)
      split(f, high, inner, rooms, depth + 1)
    end
  end
end

function kit.rooms(f, forbid)
  local rooms = {}
  split(f, f.region, forbid, rooms, 0)
  return rooms
end

-- Doorways from rooms out to the hallways beside them.
local function hall_doors(f, rooms)
  for _, room in ipairs(rooms) do
    if f.path_y and room.y[1] == f.y0 and math.random() < f.biome.hall_doors then
      doorway(f, "y", f.hall_width, math.random(room.x[1], room.x[2] - DOOR_WIDTH + 1))
    end
    if f.path_x and room.x[1] == f.x0 and math.random() < f.biome.hall_doors then
      doorway(f, "x", f.hall_width, math.random(room.y[1], room.y[2] - DOOR_WIDTH + 1))
    end
  end
end

local function is_shaft(f, x, y)
  return f.shaft and x <= SHAFT and y <= SHAFT
end

local function light(f, material, x, y)
  if material and not is_shaft(f, x, y) then
    f.tower:paint(material, { x = { x, x }, y = { y, y }, z = { ceiling_z(f), ceiling_z(f) } })
  end
end

-- A pane through the ceiling and the roof above it, and the square of sunlight it lets onto the floor.
local function skylight(f, x, y)
  if not is_shaft(f, x, y) then
    f.tower:paint("glass", { x = { x, x }, y = { y, y }, z = { ceiling_z(f), ceiling_z(f) + ROOF } })
    f.tower:paint("sunlight", { x = { x, x }, y = { y, y }, z = { f.base, f.base } })
  end
end

-- The top level lets daylight in through some of its lights; the levels below only have lights.
local function lamp(f, material, odds, x, y)
  if f.is_top and math.random() < odds then
    skylight(f, x, y)
  else
    light(f, material, x, y)
  end
end

-- The cells of a room along one of its walls, from the corner given, and whether any of them is by a doorway.
local function along_wall(f, room, side, from, length)
  local cells = {}
  local is_blocked = false
  for step = 0, length - 1 do
    local x, y
    if side == "x_low" or side == "x_high" then
      x = side == "x_low" and room.x[1] or room.x[2]
      y = from + step
    else
      x = from + step
      y = side == "y_low" and room.y[1] or room.y[2]
    end
    cells[#cells + 1] = { x, y }
    is_blocked = is_blocked or f.near_doors[cell_key(x, y)] == true
  end
  return cells, is_blocked
end

local function side_span(room, side)
  if side == "x_low" or side == "x_high" then
    return room.y
  else
    return room.x
  end
end

-- Solid boxes built against a room's walls for no reason, never in front of a doorway.
local function boxes(f, room)
  local side = SIDES[math.random(#SIDES)]
  local span = side_span(room, side)
  if width(span) >= LEAST_ATTACHED_WALL then
    local cells, is_blocked = along_wall(f, room, side, math.random(span[1], span[2] - 1), 2)
    if not is_blocked then
      local top = f.base + math.random(2, math.min(f.biome.box_height, f.room))
      for _, cell in ipairs(cells) do
        f.tower:paint(f.biome.boxes, { x = { cell[1], cell[1] }, y = { cell[2], cell[2] }, z = { f.base + 1, top } })
      end
    end
  end
end

-- Rows of shelves across a room, clear of the cells along its walls so every doorway stays reachable.
local function shelves(f, room)
  if width(room.x) >= 5 and width(room.y) >= 5 then
    for y = room.y[1] + 1, room.y[2] - 1, 2 do
      f.tower:paint(f.biome.shelf, { x = { room.x[1] + 1, room.x[2] - 1 }, y = { y, y }, z = { f.base + 1, f.base + f.door_height } })
    end
  end
end

function kit.furnish(f, rooms)
  hall_doors(f, rooms)
  for _, room in ipairs(rooms) do
    if f.biome.room_floors then
      f.tower:paint(f.biome.room_floors[math.random(#f.biome.room_floors)], { x = room.x, y = room.y, z = { f.base, f.base } })
    end
    lamp(f, f.biome.light, f.biome.skylight, middle(room.x), middle(room.y))
    if f.biome.damp and math.random() < DAMP_ODDS then
      local x, y = math.random(room.x[1], room.x[2] - 1), math.random(room.y[1], room.y[2] - 1)
      f.tower:paint(f.biome.damp, { x = { x, x + 1 }, y = { y, y + 1 }, z = { f.base, f.base } })
    end
    if f.biome.shelf then
      shelves(f, room)
    end
    if f.biome.boxes and math.random() < f.biome.box_odds then
      boxes(f, room)
    end
  end
  for _, band in ipairs(bands(f)) do
    local is_along_x = band.x[2] == f.far
    for at = LIGHT_FROM, f.far, LIGHT_EVERY do
      if is_along_x then
        lamp(f, f.hall.light, f.hall.skylight, at, 0)
      else
        lamp(f, f.hall.light, f.hall.skylight, 0, at)
      end
    end
  end
end

-- The span of a maze cell along one axis, the last running on to the quarter's far side.
local function maze_span(f, index)
  local low = index * MAZE_PITCH + 1
  return { low, math.min(low + MAZE_WIDTH - 1, f.far) }
end

-- Where a maze's passage crosses the wall between a cell and the next one along an axis.
local function maze_gap(f, axis, i, j)
  local at = (i + 1) * MAZE_PITCH
  if axis == "x" then
    return { x = { at, at }, y = maze_span(f, j), z = room_z(f) }
  else
    return { x = maze_span(f, j), y = { at, at }, z = room_z(f) }
  end
end

local function maze_key(i, j)
  return i * kit.MAZE_CELLS + j
end

-- A tight maze of passages two cells wide, carved out of solid wall with a depth-first walk so it winds with few
-- straight runs, a few walls knocked through to make loops, now and then four cells opened into a small room, and
-- steps to nowhere at some dead ends. Every cell is reached. The walls on the low sides are built back to back with
-- the next quarters' and let through at the passages both sides agreed on. Across a high side the next quarter's
-- last cells meet this one's, so only one of the two, the owner, builds a wall there, again with the agreed passages.
function kit.maze(f, lines)
  local cells = kit.MAZE_CELLS
  f.tower:paint(f.biome.wall, { x = { 0, f.far }, y = { 0, f.far }, z = room_z(f) })
  for i = 0, cells - 1 do
    for j = 0, cells - 1 do
      f.tower:paint("air", { x = maze_span(f, i), y = maze_span(f, j), z = room_z(f) })
    end
  end
  local openings = {}
  local visited = { [maze_key(0, 0)] = true }
  local trail = { { 0, 0 } }
  while #trail > 0 do
    local at = trail[#trail]
    local moves = {}
    for _, move in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local i, j = at[1] + move[1], at[2] + move[2]
      if i >= 0 and i < cells and j >= 0 and j < cells and not visited[maze_key(i, j)] then
        moves[#moves + 1] = { i, j }
      end
    end
    if #moves == 0 then
      trail[#trail] = nil
    else
      local chosen = moves[math.random(#moves)]
      visited[maze_key(chosen[1], chosen[2])] = true
      openings[#openings + 1] = { at, chosen }
      trail[#trail + 1] = chosen
    end
  end
  local exits = {}
  local function open(a, b)
    exits[maze_key(a[1], a[2])] = (exits[maze_key(a[1], a[2])] or 0) + 1
    exits[maze_key(b[1], b[2])] = (exits[maze_key(b[1], b[2])] or 0) + 1
    if a[1] ~= b[1] then
      f.tower:paint("air", maze_gap(f, "x", math.min(a[1], b[1]), a[2]))
    else
      f.tower:paint("air", maze_gap(f, "y", math.min(a[2], b[2]), a[1]))
    end
  end
  for _, pair in ipairs(openings) do
    open(pair[1], pair[2])
  end
  for i = 0, cells - 2 do
    for j = 0, cells - 1 do
      if math.random() < MAZE_LOOP_ODDS then
        open({ i, j }, { i + 1, j })
      end
      if math.random() < MAZE_LOOP_ODDS then
        open({ j, i }, { j, i + 1 })
      end
    end
  end
  if math.random() < MAZE_ROOM_ODDS then
    local i, j = math.random(0, cells - 2), math.random(0, cells - 2)
    f.tower:paint("air", { x = { maze_span(f, i)[1], maze_span(f, i + 1)[2] }, y = { maze_span(f, j)[1], maze_span(f, j + 1)[2] }, z = room_z(f) })
  end
  for _, side in ipairs(SIDES) do
    local axis = (side == "x_low" or side == "x_high") and "x" or "y"
    local is_low = side == "x_low" or side == "y_low"
    if is_low or f.owns[side] then
      local at = is_low and 0 or f.far
      if not is_low then
        f.tower:paint(f.biome.wall, line(axis, at, { 0, f.far }, room_z(f)))
      end
      for _, slot in ipairs(lines[side]) do
        f.tower:paint("air", line(axis, at, maze_span(f, slot), room_z(f)))
      end
    end
  end
  for i = 0, cells - 1 do
    for j = 0, cells - 1 do
      local x, y = maze_span(f, i), maze_span(f, j)
      if math.random() < MAZE_LIGHT_ODDS then
        light(f, f.biome.light, x[1], y[1])
      end
      if exits[maze_key(i, j)] == 1 and math.random() < f.biome.nowhere then
        for step = 1, NOWHERE_STEPS do
          f.tower:paint(f.biome.stair, { x = { x[1] + step - 1, x[1] + step - 1 }, y = y, z = { f.base + 1, f.base + step } })
        end
      end
    end
  end
end

-- A chapel: the floor sunk into the ground below with steps down at one corner, the ceiling raised under a skylight,
-- square podiums of every height rising from the floor and hanging from the ceiling, and a map on the far wall.
function kit.chapel(f)
  local region = f.region
  local depth = kit.SEPARATION
  local floor = f.base - depth
  local top = ceiling_z(f) + CHAPEL_RISE
  local around = { x = { region.x[1] - 1, region.x[2] + 1 }, y = { region.y[1] - 1, region.y[2] + 1 } }
  f.tower:paint(f.biome.wall, { x = around.x, y = around.y, z = { floor, f.base } })
  f.tower:paint(f.biome.wall, { x = around.x, y = around.y, z = { ceiling_z(f), top } })
  f.tower:paint("air", { x = region.x, y = region.y, z = { floor + 1, top - 1 } })
  f.tower:paint(f.biome.floor, { x = region.x, y = region.y, z = { floor, floor } })
  f.tower:paint(f.biome.ceiling, { x = region.x, y = region.y, z = { top, top } })
  f.tower:paint("steel", { x = around.x, y = around.y, z = { top + ROOF, top + ROOF } })
  local steps = { region.y[1], region.y[1] + 1 }
  for step = 1, depth - 1 do
    local x = region.x[1] + step - 1
    f.tower:paint(f.biome.stair, { x = { x, x }, y = steps, z = { floor + 1, f.base - step } })
  end
  for _ = 1, PODIUMS do
    local x = math.random(region.x[1] + depth, region.x[2] - PODIUM_SIZE + 1)
    local y = math.random(region.y[1] + 2, region.y[2] - PODIUM_SIZE + 1)
    f.tower:paint(f.biome.wall, { x = { x, x + PODIUM_SIZE - 1 }, y = { y, y + PODIUM_SIZE - 1 }, z = { floor + 1, floor + math.random(1, depth + 2) } })
  end
  for _ = 1, HANGING do
    local x = math.random(region.x[1] + 1, region.x[2] - PODIUM_SIZE + 1)
    local y = math.random(region.y[1] + 2, region.y[2] - PODIUM_SIZE + 1)
    f.tower:paint(f.biome.wall, { x = { x, x + PODIUM_SIZE - 1 }, y = { y, y + PODIUM_SIZE - 1 }, z = { top - math.random(1, CHAPEL_RISE), top - 1 } })
  end
  local x, y = middle(region.x), middle(region.y)
  f.tower:paint("glass", { x = { x, x + 1 }, y = { y, y + 1 }, z = { top, top + ROOF } })
  f.tower:paint("sunlight", { x = { x, x + 1 }, y = { y, y + 1 }, z = { floor, floor } })
  local wall = region.y[2] + 1
  local mural = { middle(region.x) - MURAL_HALF, middle(region.x) + MURAL_HALF }
  f.tower:paint("slate", { x = mural, y = { wall, wall }, z = { f.base + 1, f.base + f.room } })
  f.tower:paint("white_brick", { x = mural, y = { wall, wall }, z = { f.base + 2, f.base + 2 } })
  f.tower:paint("white_brick", { x = { middle(region.x), middle(region.x) }, y = { wall, wall }, z = { f.base + 1, f.base + f.room } })
end

-- Rooms inside rooms, each with one doorway, down to one barely big enough to stand in.
function kit.rings(f)
  for _, inset in ipairs(RINGS) do
    local x = { f.region.x[1] + inset, f.region.x[2] - inset }
    local y = { f.region.y[1] + inset, f.region.y[2] - inset }
    if width(x) >= 3 and width(y) >= 3 then
      f.tower:paint(f.biome.wall, { x = x, y = y, z = room_z(f) })
      f.tower:paint("air", { x = { x[1] + 1, x[2] - 1 }, y = { y[1] + 1, y[2] - 1 }, z = room_z(f) })
      local side = SIDES[math.random(#SIDES)]
      local axis = (side == "x_low" or side == "x_high") and "x" or "y"
      local at = ({ x_low = x[1], x_high = x[2], y_low = y[1], y_high = y[2] })[side]
      local along = axis == "x" and y or x
      if width(along) >= DOOR_WIDTH + 2 then
        f.tower:paint("air", line(axis, at, { along[1] + 1, along[1] + DOOR_WIDTH }, { f.base + 1, f.base + f.door_height }))
      end
    end
  end
end

-- Stairs from one level's floor up to the floor of the level above, in the corner of a quarter past both levels'
-- hallways: up a flight along two rows, round a landing and back up the next two rows, so it fits however far apart
-- the levels are. The steps are single treads with open space beneath them. On the level above, walls stand round the
-- hole the stairs leave, open where they arrive. A routed stairwell puts a stop on the floor below at its foot, one
-- on every step and on the landing, and one on the floor above past it.
function kit.stairs(lower, upper, stair, is_routed)
  local rise = upper.base - lower.base
  local x0, y0 = stair.x, stair.y
  local first = (rise + 2) // 2
  local low_rows, high_rows = { y0, y0 + 1 }, { y0 + 2, y0 + 3 }
  local stops = {}
  local function stop(x, y, z)
    stops[#stops + 1] = { x, y, z }
  end
  local function tread(x, rows, height)
    lower.tower:paint(lower.biome.stair, { x = x, y = rows, z = { lower.base + height, lower.base + height } })
  end
  local function wall(x, y)
    upper.tower:paint(upper.biome.wall, { x = x, y = y, z = { upper.base + 1, upper.base + upper.room } })
  end
  lower.tower:paint("air", { x = { x0, x0 + first + 1 }, y = { y0, y0 + STAIR_ROWS - 1 }, z = { lower.base + 1, upper.base } })
  stop(x0 + 0.5, y0 + 3, lower.base + 1)
  for height = 1, first do
    tread({ x0 + height - 1, x0 + height - 1 }, low_rows, height)
    stop(x0 + height - 0.5, y0 + 1, lower.base + height + 1)
  end
  tread({ x0 + first, x0 + first + 1 }, { y0, y0 + STAIR_ROWS - 1 }, first)
  stop(x0 + first + 1, y0 + 1, lower.base + first + 1)
  stop(x0 + first + 1, y0 + 3, lower.base + first + 1)
  for height = first + 1, rise do
    local x = x0 + 2 * first - height
    tread({ x, x }, high_rows, height)
    stop(x + 0.5, y0 + 3, lower.base + height + 1)
  end
  local arrival = x0 + 2 * first - rise - 1
  if arrival >= x0 then
    upper.tower:paint(upper.biome.floor, { x = { x0, arrival }, y = high_rows, z = { upper.base, upper.base } })
  end
  wall({ x0, x0 }, low_rows)
  wall({ x0 + 1, x0 + first + 1 }, { y0 + STAIR_ROWS, y0 + STAIR_ROWS })
  wall({ x0 + first + 2, x0 + first + 2 }, { y0, y0 + STAIR_ROWS - 1 })
  stop(x0 + 0.5, y0 + 3, upper.base + 1)
  stop(x0 + 0.5, y0 + STAIR_ROWS + 0.5, upper.base + 1)
  if is_routed then
    for _, spot in ipairs(stops) do
      lower.tower:stop(spot[1], spot[2], spot[3])
    end
  end
end

-- A frame for one level of a quarter, given where hallways run along its low sides on that level, the quarter's
-- stairwell, which keeps its rows clear of rooms on both levels it joins, whether it is a lobby on this level, and
-- which high sides it owns the wall on. A maze lies deep enough to pay no heed to a connector's shaft.
function kit.frame(q, path, floor, biome, stair, is_lobby, owns)
  local level = floor.level
  local _, far = q.tower:column()
  local x0 = kit.origin(path.x, level)
  local y0 = kit.origin(path.y, level)
  local region_y = y0
  if stair then
    region_y = stair.y + kit.STAIR_ROWS
  end
  local f = {
    tower = q.tower,
    base = floor.base,
    room = level.room,
    door_height = math.min(MOST_DOOR_HEIGHT, level.room),
    hall_width = level.hall_width,
    far = far,
    biome = biome,
    hall = level.hall,
    path_x = path.x,
    path_y = path.y,
    lobby = is_lobby,
    shaft = q.shaft and not level.maze,
    is_top = floor.is_top,
    x0 = x0,
    y0 = y0,
    region = { x = { x0, far - 1 }, y = { region_y, far - 1 } },
    near_doors = {},
    owns = owns,
  }
  f.skirting = biome.trim and math.random() < SKIRTING_ODDS
  return f
end

-- Paints one level of a quarter given the doorways of its shared walls: a maze, or its walls and then a solid block,
-- one of the level's rare rooms, or rooms split from its region.
function kit.floor(f, lines, level, plan)
  kit.shell(f)
  if plan == "maze" then
    kit.maze(f, lines)
  else
    local forbid = kit.walls(f, lines)
    if plan == "lobby" then
      light(f, f.biome.light, f.far - 2, f.far - 2)
    elseif plan == "solid" then
      f.tower:paint(f.biome.wall, { x = f.region.x, y = f.region.y, z = room_z(f) })
    elseif plan == "rings" then
      kit.rings(f)
      kit.furnish(f, { f.region })
    elseif plan == "chapel" then
      kit.chapel(f)
    else
      kit.furnish(f, kit.rooms(f, forbid))
    end
  end
end

return kit
