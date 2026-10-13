local box = require("tower.box")

local CORNERS = 5
local HEIGHT_EDGES = 2
local HALL_ROOF = 2 * box.STORY
local HALL_WINDOW_OFFSET = 2
local FIRST_BALCONY_STORY = 3
local BALCONY_DEPTH = 2
local BALCONY_WIDTH = 4
local ARCH_STOP_CELLS = box.STORY

local function corners_of(site)
  local corners = {}
  local corner = site
  for index = 1, CORNERS do
    corners[index] = corner
    corner = corner:forward(1):right()
  end
  return corners
end

local function upright(corner)
  return corner:pitch_up():roll_right()
end

local function hall_wall(tower, palette, is_ahead, has_door)
  local _, far = tower:column()
  local window = box.HALF_WIDTH + HALL_WINDOW_OFFSET
  local function strip(from, to, low, high)
    if is_ahead then
      return { x = { from, to }, y = { 0, 0 }, z = { low, high } }
    else
      return { x = { 0, 0 }, y = { from, to }, z = { low, high } }
    end
  end
  tower:paint(palette.wall, strip(0, far, 0, HALL_ROOF))
  tower:paint(palette.trim, strip(0, far, 0, HALL_ROOF), box.FLOORS)
  tower:paint("air", strip(window, window + box.WINDOW_WIDTH - 1, 0, HALL_ROOF - 1), box.WINDOW_ROW)
  if has_door then
    tower:paint("air", strip(far, far, 1, box.DOOR))
  end
end

local function hall(tower, palette, has_door_ahead, has_door_behind)
  local _, far = tower:column()
  local inside = { 0, far }
  tower:paint(palette.wall, { x = inside, y = inside, z = { -box.FOUNDATION, -1 } })
  tower:paint(palette.floor, { x = inside, y = inside, z = { 0, HALL_ROOF } }, box.FLOORS)
  tower:paint("air", { x = inside, y = inside, z = { 0, HALL_ROOF - 1 } }, box.ROOMS)
  hall_wall(tower, palette, true, has_door_ahead)
  hall_wall(tower, palette, false, has_door_behind)
end

local function open_to_hall(tower, palette)
  local quarter = { 0, box.HALF_WIDTH - 1 }
  tower:paint(palette.floor, { x = quarter, y = quarter, z = { 0, HALL_ROOF } }, box.FLOORS)
  tower:paint("air", { x = quarter, y = quarter, z = { 0, HALL_ROOF - 1 } }, box.ROOMS)
end

local function doors(tower)
  local face = { box.HALF_WIDTH - 1, box.HALF_WIDTH - 1 }
  local terrace = { HALL_ROOF + 1, HALL_ROOF + box.DOOR }
  local bridge = { tower:edge_cells() + 1, tower:edge_cells() + box.DOOR }
  tower:paint("air", { x = face, y = { 1, 2 }, z = terrace })
  tower:paint("air", { x = { 1, 2 }, y = face, z = terrace })
  tower:paint("air", { x = face, y = { -1, 0 }, z = bridge })
  tower:paint("air", { x = { -1, 0 }, y = face, z = bridge })
end

local function balcony(tower, palette, is_on_x_face, side_low, story, top)
  local every_other_story = 2 * box.STORY
  local floor = (story % 2) * box.STORY
  local heights = { story * box.STORY, top - 1 }
  local function place(outward, sideways)
    if is_on_x_face then
      return { x = outward, y = sideways, z = heights }
    else
      return { x = sideways, y = outward, z = heights }
    end
  end
  local slab = place({ -box.HALF_WIDTH - BALCONY_DEPTH, -box.HALF_WIDTH - 1 }, { side_low, side_low + BALCONY_WIDTH - 1 })
  local door = place({ -box.HALF_WIDTH, -box.HALF_WIDTH }, { side_low + 1, side_low + BALCONY_WIDTH - 2 })
  tower:paint(palette.floor, slab, { every = every_other_story, from = floor, span = 1 })
  tower:paint("air", door, { every = every_other_story, from = floor + 1, span = box.DOOR })
end

local function balconies(tower, palette, top)
  balcony(tower, palette, true, -2, FIRST_BALCONY_STORY, top)
  balcony(tower, palette, false, -1, FIRST_BALCONY_STORY + 1, top)
end

local function bridge_ahead(corner)
  return corner:pitch_up():forward(1):pitch_down()
end

local function bridge_behind(corner)
  return bridge_ahead(corner):right()
end

local function deck(bridge, palette)
  bridge:paint(palette.floor, { x = { -1, 0 }, y = { 0, 0 }, z = { box.HALF_WIDTH, bridge:edge_cells() } })
end

local function arch_route(from, to)
  local apex = from:edge_cells() - 0.5
  local stops = {}
  local along = box.HALF_WIDTH + 0.5
  while along < apex do
    stops[#stops + 1] = along
    along = along + ARCH_STOP_CELLS
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
  local top = box.top(site, HEIGHT_EDGES)
  local bridge_floor = site:edge_cells()
  local corners = corners_of(site)
  for index, corner in ipairs(corners) do
    local tower = upright(corner)
    hall(tower, palette, index == 1, index == 2)
    box.tower(tower, top, palette)
    open_to_hall(tower, palette)
    doors(tower)
    balconies(tower, palette, top)
    deck(bridge_ahead(corner), palette)
    deck(bridge_behind(corner), palette)
  end
  local first = upright(corners[1])
  local second = upright(corners[2])
  box.stair_route(first, 0, bridge_floor)
  first:stop(box.HALF_WIDTH - 1.5, box.ROUTE_LANE, bridge_floor + 1)
  first:stop(box.HALF_WIDTH + 0.5, box.ROUTE_LANE, bridge_floor + 1)
  arch_route(bridge_ahead(corners[1]), bridge_behind(corners[2]))
  second:stop(box.ROUTE_LANE, box.HALF_WIDTH - 1.5, bridge_floor + 1)
  second:stop(box.ROUTE_LANE, box.ROUTE_LANE, bridge_floor + 1)
  box.stair_route(second, bridge_floor, top)
  corners[1]:entrance(0, 1, site:edge_cells() // 2)
end
