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

function box.shell(site, top, palette)
  site:paint(palette.wall, { across = SQUARE, along = SQUARE, height = { -box.FOUNDATION, top } })
  site:paint(palette.trim, { across = SQUARE, along = SQUARE, height = { 0, top } }, box.FLOORS)
  for _, across in ipairs({ LOW, HIGH }) do
    for _, along in ipairs({ LOW, HIGH }) do
      site:paint(palette.trim, { across = { across, across }, along = { along, along }, height = { 0, top } })
    end
  end
end

function box.floors(site, top, palette)
  site:paint(palette.floor, { across = INSIDE, along = INSIDE, height = { 0, top } }, box.FLOORS)
  site:paint("air", { across = INSIDE, along = INSIDE, height = { 0, top } }, box.ROOMS)
end

function box.windows(site, top)
  local rows = { 0, top - 1 }
  for _, start in ipairs({ LOW + 1 + box.WINDOW_INSET, HIGH - box.WINDOW_INSET - box.WINDOW_WIDTH }) do
    local window = { start, start + box.WINDOW_WIDTH - 1 }
    site:paint("air", { across = { LOW, LOW }, along = window, height = rows }, box.WINDOW_ROW)
    site:paint("air", { across = { HIGH, HIGH }, along = window, height = rows }, box.WINDOW_ROW)
    site:paint("air", { across = window, along = { LOW, LOW }, height = rows }, box.WINDOW_ROW)
    site:paint("air", { across = window, along = { HIGH, HIGH }, height = rows }, box.WINDOW_ROW)
  end
end

function box.stairs(site, top, palette)
  local every_other_story = 2 * box.STORY
  for parity = 0, 1 do
    local lane = { box.lane(parity), box.lane(parity) + 1 }
    local floor = parity * box.STORY
    for tread = 0, box.STORY - 2 do
      local step = { box.STAIR_START + tread, box.STAIR_START + tread }
      site:paint(palette.floor, { across = step, along = lane, height = { 0, top - 1 } }, { every = every_other_story, from = floor + 1, span = tread + 1 })
    end
    local well = { box.STAIR_START - 1, box.STAIR_START + box.STORY - 2 }
    site:paint("air", { across = well, along = lane, height = { box.STORY, top } }, { every = every_other_story, from = floor + box.STORY, span = 1 })
  end
end

function box.merlons(site, height, palette)
  for across = LOW, HIGH do
    for along = LOW, HIGH do
      local is_ring = across == LOW or across == HIGH or along == LOW or along == HIGH
      if is_ring and (across + along) % 2 == 0 then
        site:paint(palette.trim, { across = { across, across }, along = { along, along }, height = { height, height } })
      end
    end
  end
end

function box.tower(site, top, palette)
  box.shell(site, top, palette)
  box.floors(site, top, palette)
  box.windows(site, top)
  box.stairs(site, top, palette)
  box.merlons(site, top + 1, palette)
end

function box.door(site)
  site:paint("air", { across = { LOW, LOW }, along = { -1, 0 }, height = { 1, box.DOOR } })
end

function box.stair_route(site, first_floor, top)
  local approach = box.STAIR_START - 0.5
  local landing = box.STAIR_START + box.STORY - 0.5
  for floor = first_floor, top - 1, box.STORY do
    local lane = box.lane(floor // box.STORY) + 1
    site:stop(approach, box.MIDDLE_LANE, floor + 1)
    site:stop(approach, lane, floor + 1)
    for tread = 0, box.STORY - 2 do
      site:stop(box.STAIR_START + tread + 0.5, lane, floor + tread + 2)
    end
    site:stop(landing, lane, floor + box.STORY + 1)
    site:stop(landing, box.MIDDLE_LANE, floor + box.STORY + 1)
  end
end

return box
