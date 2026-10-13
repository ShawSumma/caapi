local rooms = {}

rooms.SEPARATION = 3
rooms.MAZE_CELLS = 4

local PERCENT = 100
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
local MURAL_HALF_WIDTH = 2
local STAIR_ROWS = 4
local STAIR_DEPTH = STAIR_ROWS + 1

local function chance(f, odds)
  return f.tower:pick(PERCENT) <= odds * PERCENT
end

local function between(f, low, high)
  return low + f.tower:pick(high - low + 1) - 1
end

local function choose(f, list)
  return list[f.tower:pick(#list)]
end

local function width(span)
  return span[2] - span[1] + 1
end

local function middle(span)
  return (span[1] + span[2]) // 2
end

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

local function axis_of(side)
  if side == "x_low" or side == "x_high" then
    return "x"
  else
    return "y"
  end
end

local function is_low(side)
  return side == "x_low" or side == "y_low"
end

local function room_z(f)
  return { f.base + 1, f.base + f.room }
end

local function ceiling_z(f)
  return f.base + f.room + 1
end

function rooms.origin(has_hall, level)
  if has_hall then
    return level.hall_width + 1
  else
    return 1
  end
end

local function outside_shaft(f, area)
  if not f.has_shaft then
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
  if not f.is_lobby or at > LOBBY then
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

local function wall(f, axis, at, span, doors)
  for _, piece in ipairs(outside_lobby(f, at, span)) do
    f.tower:paint(f.biome.wall, line(axis, at, piece, room_z(f)))
    if f.has_skirting then
      f.tower:paint(f.biome.trim, line(axis, at, piece, { f.base + 1, f.base + 1 }))
    end
    if f.biome.has_vents and chance(f, VENT_ODDS) then
      local vent = between(f, piece[1], piece[2])
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
  if f.has_hall_y then
    list[#list + 1] = { x = { 0, f.far }, y = { 0, f.hall_width - 1 } }
  end
  if f.has_hall_x then
    list[#list + 1] = { x = { 0, f.hall_width - 1 }, y = { 0, f.far } }
  end
  return list
end

local function shell(f)
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

local function hall_edge(has_hall, hall_width)
  if has_hall then
    return hall_width
  else
    return 0
  end
end

local function wall_doors(has_hall, doors)
  if has_hall then
    return {}
  else
    return doors
  end
end

local function walls(f, lines)
  local from_x = hall_edge(f.has_hall_x, f.hall_width)
  local from_y = hall_edge(f.has_hall_y, f.hall_width)
  local sides = {
    y_low = { axis = "y", at = from_y, span = { from_x, f.far }, doors = wall_doors(f.has_hall_y, lines.y_low) },
    x_low = { axis = "x", at = from_x, span = { from_y, f.far }, doors = wall_doors(f.has_hall_x, lines.x_low) },
    x_high = { axis = "x", at = f.far, span = { from_y, f.far }, doors = lines.x_high },
    y_high = { axis = "y", at = f.far, span = { from_x, f.far }, doors = lines.y_high },
  }
  local forbid = { x = {}, y = {} }
  for _, side in ipairs(SIDES) do
    local planned = sides[side]
    if planned.doors ~= "open" then
      wall(f, planned.axis, planned.at, planned.span, planned.doors)
      for _, door in ipairs(planned.doors) do
        forbid[other(planned.axis)][door] = true
        forbid[other(planned.axis)][door + 1] = true
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

local function split(f, region, forbid, found, depth)
  local axes = {}
  for _, axis in ipairs({ "x", "y" }) do
    if width(region[axis]) >= 2 * MIN_ROOM + 1 then
      axes[#axes + 1] = axis
    end
  end
  local is_stopped = chance(f, f.biome.big * math.min(depth, 1))
  if #axes == 0 or is_stopped then
    found[#found + 1] = region
  else
    local axis = choose(f, axes)
    if #axes == 2 and width(region.x) > width(region.y) then
      axis = "x"
    elseif #axes == 2 and width(region.x) < width(region.y) then
      axis = "y"
    end
    local span = region[axis]
    local candidates = {}
    for at = span[1] + MIN_ROOM, span[2] - MIN_ROOM do
      if forbid[axis][at] ~= true then
        candidates[#candidates + 1] = at
      end
    end
    if #candidates == 0 then
      found[#found + 1] = region
    else
      local at = choose(f, candidates)
      local along = region[other(axis)]
      local inner = copy(forbid)
      if not chance(f, f.biome.open) then
        local door = between(f, along[1], along[2] - DOOR_WIDTH + 1)
        wall(f, axis, at, along, { door })
        inner[other(axis)][door] = true
        inner[other(axis)][door + 1] = true
      end
      local low = { x = region.x, y = region.y }
      local high = { x = region.x, y = region.y }
      low[axis] = { span[1], at - 1 }
      high[axis] = { at + 1, span[2] }
      split(f, low, inner, found, depth + 1)
      split(f, high, inner, found, depth + 1)
    end
  end
end

local function rooms_of(f, forbid)
  local found = {}
  split(f, f.region, forbid, found, 0)
  return found
end

local function hall_doors(f, found)
  for _, room in ipairs(found) do
    if f.has_hall_y and room.y[1] == f.y0 and chance(f, f.biome.hall_doors) then
      doorway(f, "y", f.hall_width, between(f, room.x[1], room.x[2] - DOOR_WIDTH + 1))
    end
    if f.has_hall_x and room.x[1] == f.x0 and chance(f, f.biome.hall_doors) then
      doorway(f, "x", f.hall_width, between(f, room.y[1], room.y[2] - DOOR_WIDTH + 1))
    end
  end
end

local function is_shaft(f, x, y)
  return f.has_shaft and x <= SHAFT and y <= SHAFT
end

local function light(f, material, x, y)
  if material ~= nil and not is_shaft(f, x, y) then
    f.tower:paint(material, { x = { x, x }, y = { y, y }, z = { ceiling_z(f), ceiling_z(f) } })
  end
end

local function skylight(f, x, y)
  if not is_shaft(f, x, y) then
    f.tower:paint("glass", { x = { x, x }, y = { y, y }, z = { ceiling_z(f), ceiling_z(f) + ROOF } })
    f.tower:paint("sunlight", { x = { x, x }, y = { y, y }, z = { f.base, f.base } })
  end
end

local function lamp(f, material, odds, x, y)
  if f.is_top and chance(f, odds) then
    skylight(f, x, y)
  else
    light(f, material, x, y)
  end
end

local function along_wall(f, room, side, from, length)
  local cells = {}
  local is_blocked = false
  for step = 0, length - 1 do
    local x = from + step
    local y = from + step
    if axis_of(side) == "x" then
      x = room.x[2]
      if is_low(side) then
        x = room.x[1]
      end
    else
      y = room.y[2]
      if is_low(side) then
        y = room.y[1]
      end
    end
    cells[#cells + 1] = { x, y }
    is_blocked = is_blocked or f.near_doors[cell_key(x, y)] == true
  end
  return cells, is_blocked
end

local function side_span(room, side)
  if axis_of(side) == "x" then
    return room.y
  else
    return room.x
  end
end

local function boxes(f, room)
  local side = choose(f, SIDES)
  local span = side_span(room, side)
  if width(span) >= LEAST_ATTACHED_WALL then
    local cells, is_blocked = along_wall(f, room, side, between(f, span[1], span[2] - 1), 2)
    if not is_blocked then
      local top = f.base + between(f, 2, math.min(f.biome.box_height, f.room))
      for _, cell in ipairs(cells) do
        f.tower:paint(f.biome.boxes, { x = { cell[1], cell[1] }, y = { cell[2], cell[2] }, z = { f.base + 1, top } })
      end
    end
  end
end

local function shelves(f, room)
  if width(room.x) >= 5 and width(room.y) >= 5 then
    for y = room.y[1] + 1, room.y[2] - 1, 2 do
      f.tower:paint(f.biome.shelf, { x = { room.x[1] + 1, room.x[2] - 1 }, y = { y, y }, z = { f.base + 1, f.base + f.door_height } })
    end
  end
end

local function furnish(f, found)
  hall_doors(f, found)
  for _, room in ipairs(found) do
    if f.biome.room_floors ~= nil then
      f.tower:paint(choose(f, f.biome.room_floors), { x = room.x, y = room.y, z = { f.base, f.base } })
    end
    lamp(f, f.biome.light, f.biome.skylight, middle(room.x), middle(room.y))
    if f.biome.damp ~= nil and chance(f, DAMP_ODDS) then
      local x, y = between(f, room.x[1], room.x[2] - 1), between(f, room.y[1], room.y[2] - 1)
      f.tower:paint(f.biome.damp, { x = { x, x + 1 }, y = { y, y + 1 }, z = { f.base, f.base } })
    end
    if f.biome.shelf ~= nil then
      shelves(f, room)
    end
    if f.biome.boxes ~= nil and chance(f, f.biome.box_odds) then
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

local function maze_span(f, index)
  local low = index * MAZE_PITCH + 1
  return { low, math.min(low + MAZE_WIDTH - 1, f.far) }
end

local function maze_gap(f, axis, i, j)
  local at = (i + 1) * MAZE_PITCH
  if axis == "x" then
    return { x = { at, at }, y = maze_span(f, j), z = room_z(f) }
  else
    return { x = maze_span(f, j), y = { at, at }, z = room_z(f) }
  end
end

local function maze_key(i, j)
  return i * rooms.MAZE_CELLS + j
end

local function maze(f, lines)
  local cells = rooms.MAZE_CELLS
  f.tower:paint(f.biome.wall, { x = { 0, f.far }, y = { 0, f.far }, z = room_z(f) })
  local exits = {}
  for i = 0, cells - 1 do
    for j = 0, cells - 1 do
      f.tower:paint("air", { x = maze_span(f, i), y = maze_span(f, j), z = room_z(f) })
      exits[maze_key(i, j)] = 0
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
      if i >= 0 and i < cells and j >= 0 and j < cells and visited[maze_key(i, j)] ~= true then
        moves[#moves + 1] = { i, j }
      end
    end
    if #moves == 0 then
      trail[#trail] = nil
    else
      local chosen = choose(f, moves)
      visited[maze_key(chosen[1], chosen[2])] = true
      openings[#openings + 1] = { at, chosen }
      trail[#trail + 1] = chosen
    end
  end
  local function open(a, b)
    exits[maze_key(a[1], a[2])] = exits[maze_key(a[1], a[2])] + 1
    exits[maze_key(b[1], b[2])] = exits[maze_key(b[1], b[2])] + 1
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
      if chance(f, MAZE_LOOP_ODDS) then
        open({ i, j }, { i + 1, j })
      end
      if chance(f, MAZE_LOOP_ODDS) then
        open({ j, i }, { j, i + 1 })
      end
    end
  end
  if chance(f, MAZE_ROOM_ODDS) then
    local i, j = between(f, 0, cells - 2), between(f, 0, cells - 2)
    f.tower:paint("air", { x = { maze_span(f, i)[1], maze_span(f, i + 1)[2] }, y = { maze_span(f, j)[1], maze_span(f, j + 1)[2] }, z = room_z(f) })
  end
  for _, side in ipairs(SIDES) do
    local axis = axis_of(side)
    if is_low(side) or f.owns[side] then
      local at = 0
      if not is_low(side) then
        at = f.far
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
      if chance(f, MAZE_LIGHT_ODDS) then
        light(f, f.biome.light, x[1], y[1])
      end
      if exits[maze_key(i, j)] == 1 and chance(f, f.biome.nowhere) then
        for step = 1, NOWHERE_STEPS do
          f.tower:paint(f.biome.stair, { x = { x[1] + step - 1, x[1] + step - 1 }, y = y, z = { f.base + 1, f.base + step } })
        end
      end
    end
  end
end

local function chapel(f)
  local region = f.region
  local depth = rooms.SEPARATION
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
    local x = between(f, region.x[1] + depth, region.x[2] - PODIUM_SIZE + 1)
    local y = between(f, region.y[1] + 2, region.y[2] - PODIUM_SIZE + 1)
    f.tower:paint(f.biome.wall, { x = { x, x + PODIUM_SIZE - 1 }, y = { y, y + PODIUM_SIZE - 1 }, z = { floor + 1, floor + between(f, 1, depth + 2) } })
  end
  for _ = 1, HANGING do
    local x = between(f, region.x[1] + 1, region.x[2] - PODIUM_SIZE + 1)
    local y = between(f, region.y[1] + 2, region.y[2] - PODIUM_SIZE + 1)
    f.tower:paint(f.biome.wall, { x = { x, x + PODIUM_SIZE - 1 }, y = { y, y + PODIUM_SIZE - 1 }, z = { top - between(f, 1, CHAPEL_RISE), top - 1 } })
  end
  local x, y = middle(region.x), middle(region.y)
  f.tower:paint("glass", { x = { x, x + 1 }, y = { y, y + 1 }, z = { top, top + ROOF } })
  f.tower:paint("sunlight", { x = { x, x + 1 }, y = { y, y + 1 }, z = { floor, floor } })
  local far_wall = region.y[2] + 1
  local mural = { middle(region.x) - MURAL_HALF_WIDTH, middle(region.x) + MURAL_HALF_WIDTH }
  f.tower:paint("slate", { x = mural, y = { far_wall, far_wall }, z = { f.base + 1, f.base + f.room } })
  f.tower:paint("white_brick", { x = mural, y = { far_wall, far_wall }, z = { f.base + 2, f.base + 2 } })
  f.tower:paint("white_brick", { x = { middle(region.x), middle(region.x) }, y = { far_wall, far_wall }, z = { f.base + 1, f.base + f.room } })
end

local function rings(f)
  for _, inset in ipairs(RINGS) do
    local x = { f.region.x[1] + inset, f.region.x[2] - inset }
    local y = { f.region.y[1] + inset, f.region.y[2] - inset }
    if width(x) >= 3 and width(y) >= 3 then
      f.tower:paint(f.biome.wall, { x = x, y = y, z = room_z(f) })
      f.tower:paint("air", { x = { x[1] + 1, x[2] - 1 }, y = { y[1] + 1, y[2] - 1 }, z = room_z(f) })
      local side = choose(f, SIDES)
      local axis = axis_of(side)
      local at = ({ x_low = x[1], x_high = x[2], y_low = y[1], y_high = y[2] })[side]
      local along = x
      if axis == "x" then
        along = y
      end
      if width(along) >= DOOR_WIDTH + 2 then
        f.tower:paint("air", line(axis, at, { along[1] + 1, along[1] + DOOR_WIDTH }, { f.base + 1, f.base + f.door_height }))
      end
    end
  end
end

function rooms.stairs(lower, upper, stair, is_routed)
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
  local function enclose(x, y)
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
  enclose({ x0, x0 }, low_rows)
  enclose({ x0 + 1, x0 + first + 1 }, { y0 + STAIR_ROWS, y0 + STAIR_ROWS })
  enclose({ x0 + first + 2, x0 + first + 2 }, { y0, y0 + STAIR_ROWS - 1 })
  stop(x0 + 0.5, y0 + 3, upper.base + 1)
  stop(x0 + 0.5, y0 + STAIR_ROWS + 0.5, upper.base + 1)
  if is_routed then
    for _, spot in ipairs(stops) do
      lower.tower:stop(spot[1], spot[2], spot[3])
    end
  end
end

function rooms.frame(q, halls, floor, biome, stair, is_lobby, owns)
  local level = floor.level
  local _, far = q.tower:column()
  local x0 = rooms.origin(halls.x, level)
  local y0 = rooms.origin(halls.y, level)
  local region_y = y0
  if stair ~= nil then
    region_y = stair.y + STAIR_DEPTH
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
    has_hall_x = halls.x,
    has_hall_y = halls.y,
    is_lobby = is_lobby,
    has_shaft = q.has_shaft and not level.is_maze,
    is_top = floor.is_top,
    x0 = x0,
    y0 = y0,
    region = { x = { x0, far - 1 }, y = { region_y, far - 1 } },
    near_doors = {},
    owns = owns,
  }
  f.has_skirting = biome.trim ~= nil and chance(f, SKIRTING_ODDS)
  return f
end

function rooms.floor(f, lines, plan)
  shell(f)
  if plan == "maze" then
    maze(f, lines)
  else
    local forbid = walls(f, lines)
    if plan == "lobby" then
      light(f, f.biome.light, f.far - 2, f.far - 2)
    elseif plan == "solid" then
      f.tower:paint(f.biome.wall, { x = f.region.x, y = f.region.y, z = room_z(f) })
    elseif plan == "rings" then
      rings(f)
      furnish(f, { f.region })
    elseif plan == "chapel" then
      chapel(f)
    else
      furnish(f, rooms_of(f, forbid))
    end
  end
end

return rooms
