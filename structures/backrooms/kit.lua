-- Painting one layer of one quarter of the backrooms. A quarter is a square of cells with a vertex of the tiling at
-- (0, 0) and the middle of its face at (far, far); its low sides run along edges of the tiling and its high sides
-- across the face. A frame holds what painting it needs: the quarter's tower, the layer's floor height, the biome,
-- and where hallways run along its low sides.
local kit = {}

-- Each layer's floor lies this many cells below the one above, leaving solid ground between one layer's ceiling and
-- the next layer's floor.
kit.PITCH = 9
kit.ROOM = 4
kit.HALL = 2
kit.DOOR_LOW = 3
kit.DOOR_HIGH = 8
local DOOR_WIDTH = 2
local DOOR_HEIGHT = 3
local MIN_ROOM = 3
local LOBBY = 5
local SHAFT = 3
local LIGHT_FROM = 2
local LIGHT_EVERY = 4
local STAIR_RUN = kit.PITCH
local SKIRTING_ODDS = 0.5
local DAMP_ODDS = 0.3
local ROOF = 1
local RINGS = { 1, 3 }
local SIDES = { "x_low", "y_low", "x_high", "y_high" }

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
  return { f.base + 1, f.base + kit.ROOM }
end

local function ceiling_z(f)
  return f.base + kit.ROOM + 1
end

-- A lobby with a connector rising through it leaves the corner by the vertex to the shaft on every layer: the shaft
-- above the top one and its footing below, which fills only open cells, so painting there would make what is built
-- depend on which tile ran first. Below the top layer the corner stays solid ground. Every lobby keeps the ring
-- around that corner clear of walls.
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

local function doorway(f, axis, at, door)
  f.tower:paint("air", line(axis, at, { door, door + DOOR_WIDTH - 1 }, { f.base + 1, f.base + DOOR_HEIGHT }))
end

-- A wall four cells tall with a doorway two wide and three tall starting at each of the doors.
function kit.wall(f, axis, at, span, doors)
  for _, piece in ipairs(outside_lobby(f, at, span)) do
    f.tower:paint(f.biome.wall, line(axis, at, piece, room_z(f)))
    if f.skirting then
      f.tower:paint(f.biome.trim, line(axis, at, piece, { f.base + 1, f.base + 1 }))
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
    list[#list + 1] = { x = { 0, f.far }, y = { 0, kit.HALL - 1 } }
  end
  if f.path_x then
    list[#list + 1] = { x = { 0, kit.HALL - 1 }, y = { 0, f.far } }
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
  local from_x = f.path_x and kit.HALL or 0
  local from_y = f.path_y and kit.HALL or 0
  local walls = {
    y_low = { axis = "y", at = f.path_y and kit.HALL or 0, span = { from_x, f.far }, doors = f.path_y and {} or lines.y_low },
    x_low = { axis = "x", at = f.path_x and kit.HALL or 0, span = { from_y, f.far }, doors = f.path_x and {} or lines.x_low },
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

-- Doorways from rooms out to the hallways beside them, kept clear of a stairwell's run.
local function hall_doors(f, rooms)
  for _, room in ipairs(rooms) do
    if f.path_y and room.y[1] == f.region.y[1] and math.random() < f.biome.hall_doors then
      local low = room.x[1]
      if f.strip then
        low = math.max(low, f.x0 + STAIR_RUN + 1)
      end
      if low <= room.x[2] - DOOR_WIDTH + 1 then
        doorway(f, "y", kit.HALL, math.random(low, room.x[2] - DOOR_WIDTH + 1))
      end
    end
    if f.path_x and room.x[1] == f.region.x[1] and math.random() < f.biome.hall_doors then
      doorway(f, "x", kit.HALL, math.random(room.y[1], room.y[2] - DOOR_WIDTH + 1))
    end
  end
end

local function light(f, material, x, y)
  if material and not (f.shaft and x <= SHAFT and y <= SHAFT) then
    f.tower:paint(material, { x = { x, x }, y = { y, y }, z = { ceiling_z(f), ceiling_z(f) } })
  end
end

-- Rows of shelves across a room, clear of the cells along its walls so every doorway stays reachable.
local function shelves(f, room)
  if width(room.x) >= 5 and width(room.y) >= 5 then
    for y = room.y[1] + 1, room.y[2] - 1, 2 do
      f.tower:paint(f.biome.shelf, { x = { room.x[1] + 1, room.x[2] - 1 }, y = { y, y }, z = { f.base + 1, f.base + DOOR_HEIGHT } })
    end
  end
end

function kit.furnish(f, rooms)
  hall_doors(f, rooms)
  for _, room in ipairs(rooms) do
    light(f, f.biome.light, middle(room.x), middle(room.y))
    if f.biome.damp and math.random() < DAMP_ODDS then
      local x, y = math.random(room.x[1], room.x[2] - 1), math.random(room.y[1], room.y[2] - 1)
      f.tower:paint(f.biome.damp, { x = { x, x + 1 }, y = { y, y + 1 }, z = { f.base, f.base } })
    end
    if f.biome.shelf then
      shelves(f, room)
    end
  end
  for _, band in ipairs(bands(f)) do
    local is_along_x = band.x[2] == f.far
    for at = LIGHT_FROM, f.far, LIGHT_EVERY do
      if is_along_x then
        light(f, f.hall.light, at, 0)
      else
        light(f, f.hall.light, 0, at)
      end
    end
    if f.hall.pipes then
      local pipe = { x = { 0, f.far }, y = { kit.HALL - 1, kit.HALL - 1 }, z = { f.base + kit.ROOM, f.base + kit.ROOM } }
      if not is_along_x then
        pipe = { x = { kit.HALL - 1, kit.HALL - 1 }, y = { 0, f.far }, z = pipe.z }
      end
      f.tower:paint(f.hall.pipes, pipe)
    end
  end
end

-- One tall room up into the ground below the layer above, its walls carried up, with a pane of glass in its ceiling.
function kit.atrium(f)
  local region = f.region
  local top = f.base + kit.PITCH - 1
  local outer = { x = { region.x[1] - 1, region.x[2] + 1 }, y = { region.y[1] - 1, region.y[2] + 1 }, z = { ceiling_z(f), top } }
  f.tower:paint(f.biome.wall, outer)
  f.tower:paint("air", { x = region.x, y = region.y, z = { ceiling_z(f), top - 1 } })
  f.tower:paint(f.biome.ceiling, { x = region.x, y = region.y, z = { top, top } })
  local x, y = middle(region.x), middle(region.y)
  f.tower:paint("glass", { x = { x, x + 1 }, y = { y, y + 1 }, z = { top, top } })
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
        f.tower:paint("air", line(axis, at, { along[1] + 1, along[1] + DOOR_WIDTH }, { f.base + 1, f.base + DOOR_HEIGHT }))
      end
    end
  end
end

-- Steps along the strip by the quarter's y side, rising a cell for each cell along it, from one layer's floor up
-- through its ceiling and the ground above to the floor of the layer above, with a rail round the hole they leave
-- there. The run is as long as the layers are apart, so it fits only from the quarter's first cell.
function kit.stairs(lower, upper)
  local strip = { lower.y0, lower.y0 + 1 }
  lower.tower:paint("air", { x = { lower.x0 + 1, lower.x0 + STAIR_RUN - 1 }, y = strip, z = { ceiling_z(lower), upper.base } })
  for step = 1, STAIR_RUN do
    local x = lower.x0 + step - 1
    lower.tower:paint(lower.biome.stair, { x = { x, x }, y = strip, z = { lower.base + 1, lower.base + step } })
  end
  upper.tower:paint("steel", { x = { upper.x0, upper.x0 + STAIR_RUN - 1 }, y = { strip[2] + 1, strip[2] + 1 }, z = { upper.base + 1, upper.base + 1 } })
end

-- A frame for one layer of a quarter. A quarter with a stairwell keeps a strip along its y side clear of rooms on
-- both layers the stairs join.
function kit.frame(q, layer, level, biome, has_strip, is_top)
  local _, far = q.tower:column()
  local x0 = q.path_x and kit.HALL + 1 or 1
  local y0 = q.path_y and kit.HALL + 1 or 1
  local region_y = has_strip and y0 + 2 or y0
  local f = {
    tower = q.tower,
    base = -(layer - 1) * kit.PITCH,
    far = far,
    biome = biome,
    hall = level.hall,
    path_x = q.path_x,
    path_y = q.path_y,
    lobby = q.lobby,
    shaft = q.shaft,
    strip = has_strip,
    is_top = is_top,
    x0 = x0,
    y0 = y0,
    region = { x = { x0, far - 1 }, y = { region_y, far - 1 } },
  }
  f.skirting = biome.trim and math.random() < SKIRTING_ODDS
  return f
end

-- Paints one layer of a quarter given the doorways of its shared walls, choosing among the level's rare plans.
function kit.layer(f, lines, level)
  kit.shell(f)
  local forbid = kit.walls(f, lines)
  local rooms = { f.region }
  local roll = math.random()
  if f.lobby then
    light(f, f.biome.light, f.far - 2, f.far - 2)
  elseif not f.strip and roll < level.atrium then
    kit.atrium(f)
    kit.furnish(f, rooms)
  elseif not f.strip and roll < level.atrium + level.rings then
    kit.rings(f)
    kit.furnish(f, rooms)
  else
    kit.furnish(f, kit.rooms(f, forbid))
  end
end

return kit
