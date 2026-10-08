local box = {}

box.HALF = 5
box.STORY = 4
box.DOOR = box.STORY - 1
box.FOUNDATION = 3
box.STAIR_START = 2 - box.HALF
box.WINDOW_INSET = 1
box.WINDOW_WIDTH = 2
box.MIDDLE_LANE = 0
box.ROUTE_LANE = 0.5
box.FLOORS = { every = box.STORY, from = 0, span = 1 }
box.ROOMS = { every = box.STORY, from = 1, span = box.STORY - 1 }
box.WINDOW_ROW = { every = box.STORY, from = box.STORY // 2, span = 1 }
box.PALETTES = {
  { wall = "concrete", floor = "concrete", trim = "steel" },
  { wall = "white_brick", floor = "grey_brick", trim = "steel" },
  { wall = "sandstone", floor = "wood_planks", trim = "steel" },
  { wall = "grey_brick", floor = "concrete", trim = "marble" },
}

local LOW = -box.HALF
local HIGH = box.HALF - 1
local SQUARE = { LOW, HIGH }
local INSIDE = { LOW + 1, HIGH - 1 }

function box.palette(site)
  return box.PALETTES[site:pick(#box.PALETTES)]
end

function box.top(site, edges)
  return edges * site:edge_cells() // box.STORY * box.STORY
end

function box.lane(story)
  if story % 2 == 0 then
    return 1 - box.HALF
  else
    return box.HALF - 3
  end
end

function box.shell(tower, top, palette)
  tower:paint(palette.wall, { x = SQUARE, y = SQUARE, z = { -box.FOUNDATION, top } })
  tower:paint(palette.trim, { x = SQUARE, y = SQUARE, z = { 0, top } }, box.FLOORS)
  for _, x in ipairs({ LOW, HIGH }) do
    for _, y in ipairs({ LOW, HIGH }) do
      tower:paint(palette.trim, { x = { x, x }, y = { y, y }, z = { 0, top } })
    end
  end
end

function box.floors(tower, top, palette)
  tower:paint(palette.floor, { x = INSIDE, y = INSIDE, z = { 0, top } }, box.FLOORS)
  tower:paint("air", { x = INSIDE, y = INSIDE, z = { 0, top } }, box.ROOMS)
end

function box.windows(tower, top)
  local rows = { 0, top - 1 }
  for _, start in ipairs({ LOW + 1 + box.WINDOW_INSET, HIGH - box.WINDOW_INSET - box.WINDOW_WIDTH }) do
    local window = { start, start + box.WINDOW_WIDTH - 1 }
    tower:paint("air", { x = { LOW, LOW }, y = window, z = rows }, box.WINDOW_ROW)
    tower:paint("air", { x = { HIGH, HIGH }, y = window, z = rows }, box.WINDOW_ROW)
    tower:paint("air", { x = window, y = { LOW, LOW }, z = rows }, box.WINDOW_ROW)
    tower:paint("air", { x = window, y = { HIGH, HIGH }, z = rows }, box.WINDOW_ROW)
  end
end

function box.stairs(tower, top, palette)
  local every_other_story = 2 * box.STORY
  for parity = 0, 1 do
    local lane = { box.lane(parity), box.lane(parity) + 1 }
    local floor = parity * box.STORY
    for tread = 0, box.STORY - 2 do
      local step = { box.STAIR_START + tread, box.STAIR_START + tread }
      tower:paint(palette.floor, { x = step, y = lane, z = { 0, top - 1 } }, { every = every_other_story, from = floor + 1, span = tread + 1 })
    end
    local well = { box.STAIR_START - 1, box.STAIR_START + box.STORY - 2 }
    tower:paint("air", { x = well, y = lane, z = { box.STORY, top } }, { every = every_other_story, from = floor + box.STORY, span = 1 })
  end
end

function box.merlons(tower, z, palette)
  for x = LOW, HIGH do
    for y = LOW, HIGH do
      local is_ring = x == LOW or x == HIGH or y == LOW or y == HIGH
      if is_ring and (x + y) % 2 == 0 then
        tower:paint(palette.trim, { x = { x, x }, y = { y, y }, z = { z, z } })
      end
    end
  end
end

function box.tower(tower, top, palette)
  box.shell(tower, top, palette)
  box.floors(tower, top, palette)
  box.windows(tower, top)
  box.stairs(tower, top, palette)
  box.merlons(tower, top + 1, palette)
end

function box.door(tower)
  tower:paint("air", { x = { LOW, LOW }, y = { -1, 0 }, z = { 1, box.DOOR } })
end

function box.stair_route(tower, first_floor, top)
  local approach = box.STAIR_START - 0.5
  local landing = box.STAIR_START + box.STORY - 0.5
  for floor = first_floor, top - 1, box.STORY do
    local lane = box.lane(floor // box.STORY) + 1
    tower:stop(approach, box.MIDDLE_LANE, floor + 1)
    tower:stop(approach, lane, floor + 1)
    for tread = 0, box.STORY - 2 do
      tower:stop(box.STAIR_START + tread + 0.5, lane, floor + tread + 2)
    end
    tower:stop(landing, lane, floor + box.STORY + 1)
    tower:stop(landing, box.MIDDLE_LANE, floor + box.STORY + 1)
  end
end

return box
