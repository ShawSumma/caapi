local box = require("box")

local EDGES = 2
local HALL_ROOF = 2 * box.STORY
local HALL_WINDOW_OFFSET = 2
local FIRST_BALCONY_STORY = 3
local BALCONY_DEPTH = 2
local BALCONY_WIDTH = 4
local ARCH_STOP_CELLS = box.STORY

local function hall_wall(corner, palette, is_ahead, has_door)
  local _, far = corner:column()
  local window = box.HALF + HALL_WINDOW_OFFSET
  local function strip(from, to, low, high)
    if is_ahead then
      return { across = { 0, 0 }, along = { from, to }, height = { low, high } }
    else
      return { across = { from, to }, along = { 0, 0 }, height = { low, high } }
    end
  end
  corner:paint(palette.wall, strip(0, far, 0, HALL_ROOF))
  corner:paint(palette.trim, strip(0, far, 0, HALL_ROOF), box.FLOORS)
  corner:paint("air", strip(window, window + box.WINDOW_WIDTH - 1, 0, HALL_ROOF - 1), box.WINDOW_ROW)
  if has_door then
    corner:paint("air", strip(far, far, 1, box.DOOR))
  end
end

local function hall(corner, palette, has_door_ahead, has_door_behind)
  local _, far = corner:column()
  local inside = { 0, far }
  corner:paint(palette.wall, { across = inside, along = inside, height = { -box.FOUNDATION, -1 } })
  corner:paint(palette.floor, { across = inside, along = inside, height = { 0, HALL_ROOF } }, box.FLOORS)
  corner:paint("air", { across = inside, along = inside, height = { 0, HALL_ROOF - 1 } }, box.ROOMS)
  hall_wall(corner, palette, true, has_door_ahead)
  hall_wall(corner, palette, false, has_door_behind)
end

local function open_to_hall(corner, palette)
  local quarter = { 0, box.HALF - 1 }
  corner:paint(palette.floor, { across = quarter, along = quarter, height = { 0, HALL_ROOF } }, box.FLOORS)
  corner:paint("air", { across = quarter, along = quarter, height = { 0, HALL_ROOF - 1 } }, box.ROOMS)
end

local function doors(corner)
  local face = { box.HALF - 1, box.HALF - 1 }
  local terrace = { HALL_ROOF + 1, HALL_ROOF + box.DOOR }
  local bridge = { corner:edge_cells() + 1, corner:edge_cells() + box.DOOR }
  corner:paint("air", { across = face, along = { 1, 2 }, height = terrace })
  corner:paint("air", { across = { 1, 2 }, along = face, height = terrace })
  corner:paint("air", { across = face, along = { -1, 0 }, height = bridge })
  corner:paint("air", { across = { -1, 0 }, along = face, height = bridge })
end

local function balcony(corner, palette, is_on_across_face, side_low, story, top)
  local every_other_story = 2 * box.STORY
  local floor = (story % 2) * box.STORY
  local heights = { story * box.STORY, top - 1 }
  local function place(outward, sideways)
    if is_on_across_face then
      return { across = outward, along = sideways, height = heights }
    else
      return { across = sideways, along = outward, height = heights }
    end
  end
  local slab = place({ -box.HALF - BALCONY_DEPTH, -box.HALF - 1 }, { side_low, side_low + BALCONY_WIDTH - 1 })
  local door = place({ -box.HALF, -box.HALF }, { side_low + 1, side_low + BALCONY_WIDTH - 2 })
  corner:paint(palette.floor, slab, { every = every_other_story, from = floor, span = 1 })
  corner:paint("air", door, { every = every_other_story, from = floor + 1, span = box.DOOR })
end

local function balconies(corner, palette, top)
  balcony(corner, palette, true, -2, FIRST_BALCONY_STORY, top)
  balcony(corner, palette, false, -1, FIRST_BALCONY_STORY + 1, top)
end

local function bridge_ahead(corner)
  return corner:up(1):branch("along")
end

local function bridge_behind(corner)
  return corner:up(1):branch("across")
end

local function deck(bridge, palette)
  bridge:paint(palette.floor, { across = { -1, 0 }, along = { 0, 0 }, height = { box.HALF, bridge:edge_cells() } })
end

local function arch_route(from, to)
  local apex = from:edge_cells() - 0.5
  local stops = {}
  local height = box.HALF + 0.5
  while height < apex do
    stops[#stops + 1] = height
    height = height + ARCH_STOP_CELLS
  end
  stops[#stops + 1] = apex
  for index = 1, #stops do
    from:stop(box.ROUTE_LANE, 1, stops[index])
  end
  for index = #stops, 1, -1 do
    to:stop(box.ROUTE_LANE, 1, stops[index])
  end
end

return function(site)
  local palette = box.palette(site)
  local top = box.top(site, EDGES)
  local bridge_floor = site:edge_cells()
  local corners = site:face()
  for index, corner in ipairs(corners) do
    hall(corner, palette, index == 1, index == 2)
    box.tower(corner, top, palette)
    open_to_hall(corner, palette)
    doors(corner)
    balconies(corner, palette, top)
  end
  for _, corner in ipairs(corners) do
    deck(bridge_ahead(corner), palette)
    deck(bridge_behind(corner), palette)
  end
  local first = corners[1]
  local second = corners[2]
  box.stair_route(first, 0, bridge_floor)
  first:stop(box.ROUTE_LANE, box.HALF - 1.5, bridge_floor + 1)
  first:stop(box.ROUTE_LANE, box.HALF + 0.5, bridge_floor + 1)
  arch_route(bridge_ahead(first), bridge_behind(second))
  second:stop(box.HALF - 1.5, box.ROUTE_LANE, bridge_floor + 1)
  second:stop(box.ROUTE_LANE, box.ROUTE_LANE, bridge_floor + 1)
  box.stair_route(second, bridge_floor, top)
  first:entrance(0, site:edge_cells() // 2, 1)
end
