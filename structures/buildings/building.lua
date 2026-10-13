local building = {}

building.STORY = 4
building.STREET = "street"
building.JOINED = "joined"
building.LOT = "lot"
building.SIDES = { "x_low", "y_low", "x_high", "y_high" }
building.FLOORS = { every = building.STORY, from = 0, span = 1 }
building.WINDOW_ROWS = { every = building.STORY, from = 1, span = 2 }

local STORY = building.STORY
local STREET = building.STREET
local JOINED = building.JOINED
local LOT = building.LOT
local SIDES = building.SIDES
local FLOORS = building.FLOORS
local WINDOW_ROWS = building.WINDOW_ROWS
local ROOMS = { every = STORY, from = 1, span = STORY - 1 }
local DOOR_TOP = STORY - 1
local DOOR_WIDTH = 2
local PIER_SPACING = 3
local ANTENNA = 6
local MAST_SPACING = 3
local CHIMNEY = 3
local LEAST_PAD = 5
local CORE_LENGTH = STORY + 1
local CORE_WIDTH = 5
local CORE_ROOM = CORE_WIDTH + 2
local WALKWAY = 2
local SECOND_LANE = 3
local ROAD_STOP = 3
local SIDEWALK_STOP = 2

local function upright(site)
  return site:pitch_up():roll_right()
end

local function bound_low(kind, spec)
  if kind == STREET then
    return spec.front
  elseif kind == JOINED then
    return 0
  else
    return spec.gap
  end
end

local function bound_high(kind, spec, far)
  if kind == JOINED then
    return far
  else
    return far - spec.gap
  end
end

local function part_of(lot, spec)
  local tower = upright(lot.site)
  local _, far = tower:column()
  return {
    tower = tower,
    site = lot.site,
    x = { bound_low(lot.x_low, spec), bound_high(lot.x_high, spec, far) },
    y = { bound_low(lot.y_low, spec), bound_high(lot.y_high, spec, far) },
    kinds = { x_low = lot.x_low, y_low = lot.y_low, x_high = lot.x_high, y_high = lot.y_high },
    joins = {},
    front = lot.front,
    split = far + 1,
  }
end

local function is_open(part, side, is_below_split)
  local is_joined = part.kinds[side] == JOINED
  if side == "x_low" or side == "y_low" then
    return is_joined
  else
    return is_joined and is_below_split
  end
end

local function range(low, high, is_low_open, is_high_open, shrink)
  local span = { low + shrink, high - shrink }
  if is_low_open then
    span[1] = low
  end
  if is_high_open then
    span[2] = high
  end
  return span
end

function building.footprint(part, shrink, is_below_split, low, high)
  return {
    x = range(part.x[1], part.x[2], is_open(part, "x_low", is_below_split), is_open(part, "x_high", is_below_split), shrink),
    y = range(part.y[1], part.y[2], is_open(part, "y_low", is_below_split), is_open(part, "y_high", is_below_split), shrink),
    z = { low, high },
  }
end

local footprint = building.footprint

function building.middle(span)
  return (span[1] + span[2]) // 2
end

function building.width(span)
  return span[2] - span[1] + 1
end

local middle = building.middle
local width = building.width

local function area(box)
  return width(box.x) * width(box.y)
end

function building.is_empty(box)
  return box.x[1] > box.x[2] or box.y[1] > box.y[2]
end

local is_empty = building.is_empty

function building.face_of(box, side)
  if side == "x_low" then
    return { x = { box.x[1], box.x[1] }, y = box.y, z = box.z }
  elseif side == "x_high" then
    return { x = { box.x[2], box.x[2] }, y = box.y, z = box.z }
  elseif side == "y_low" then
    return { x = box.x, y = { box.y[1], box.y[1] }, z = box.z }
  else
    return { x = box.x, y = { box.y[2], box.y[2] }, z = box.z }
  end
end

local face_of = building.face_of

local function is_along_y(side)
  return side == "x_low" or side == "x_high"
end

function building.along(box, side)
  if is_along_y(side) then
    return box.y
  else
    return box.x
  end
end

local along = building.along

function building.with_along(face, side, span)
  local piece = { x = face.x, y = face.y, z = face.z }
  if is_along_y(side) then
    piece.y = span
  else
    piece.x = span
  end
  return piece
end

local with_along = building.with_along

function building.moved_out(face, side, cells)
  local sign = cells
  if side == "x_low" or side == "y_low" then
    sign = -cells
  end
  if is_along_y(side) then
    return { x = { face.x[1] + sign, face.x[2] + sign }, y = face.y, z = face.z }
  else
    return { x = face.x, y = { face.y[1] + sign, face.y[2] + sign }, z = face.z }
  end
end

local function uncovered(part, box, side, tier)
  local join = part.joins[side]
  local pieces = {}
  if join ~= nil then
    local theirs = along(footprint(join.part, tier.shrink, tier.is_below_split, tier.low, tier.high), join.side)
    local mine = along(box, side)
    local face = face_of(box, side)
    if mine[1] < theirs[1] then
      pieces[#pieces + 1] = with_along(face, side, { mine[1], math.min(mine[2], theirs[1] - 1) })
    end
    if mine[2] > theirs[2] then
      pieces[#pieces + 1] = with_along(face, side, { math.max(mine[1], theirs[2] + 1), mine[2] })
    end
  end
  return pieces
end

function building.walls(part, box, tier)
  local list = {}
  for _, side in ipairs(SIDES) do
    if not is_open(part, side, tier.is_below_split) then
      list[#list + 1] = face_of(box, side)
    else
      for _, piece in ipairs(uncovered(part, box, side, tier)) do
        list[#list + 1] = piece
      end
    end
  end
  return list
end

local walls = building.walls

function building.strips(face, spacing)
  local is_along_x = face.x[1] ~= face.x[2]
  local run = face.y
  if is_along_x then
    run = face.x
  end
  local cells = {}
  for cell = run[1], run[2], spacing do
    cells[#cells + 1] = cell
  end
  if cells[#cells] ~= run[2] then
    cells[#cells + 1] = run[2]
  end
  local list = {}
  for _, cell in ipairs(cells) do
    if is_along_x then
      list[#list + 1] = { x = { cell, cell }, y = face.y, z = face.z }
    else
      list[#list + 1] = { x = face.x, y = { cell, cell }, z = face.z }
    end
  end
  return list
end

local strips = building.strips

function building.narrowing(box, wanted, least)
  local narrowest = math.min(width(box.x), width(box.y))
  return math.max(0, math.min(wanted, (narrowest - least) // 2))
end

local narrowing = building.narrowing

function building.parts(lots, spec)
  local parts = {}
  for index, lot in ipairs(lots) do
    parts[index] = part_of(lot, spec)
  end
  for index, lot in ipairs(lots) do
    if lot.joins ~= nil then
      for side, join in pairs(lot.joins) do
        parts[index].joins[side] = { part = parts[join.lot], side = join.side }
      end
    end
  end
  return parts
end

function building.setbacks(parts, wanted)
  local setbacks = wanted
  for _, part in ipairs(parts) do
    setbacks = math.min(setbacks, narrowing(part, wanted, CORE_ROOM))
  end
  return setbacks
end

function building.tiers(part, spec, setbacks)
  local top = spec.stories * STORY
  local tiers = { { low = 0, high = math.min(top, part.split - 1), shrink = 0, is_below_split = true } }
  local low = part.split
  for tier = 0, setbacks do
    local high = top
    if tier < setbacks then
      high = part.split + (top - part.split) * (tier + 1) // (setbacks + 1) // STORY * STORY
    end
    if high >= low then
      tiers[#tiers + 1] = { low = low, high = high, shrink = tier, is_below_split = false }
      low = high + 1
    end
  end
  for index, tier in ipairs(tiers) do
    local above = tiers[index + 1]
    tier.above = above
    tier.is_roofed = index == #tiers or above.shrink > tier.shrink
  end
  part.top = tiers[#tiers]
  part.stand = part.top
  return tiers
end

function building.shell(part, palette, tier)
  local box = footprint(part, tier.shrink, tier.is_below_split, tier.low, tier.high)
  local inside = footprint(part, tier.shrink + 1, tier.is_below_split, tier.low, tier.high)
  part.tower:paint(palette.wall, box)
  if palette.band ~= nil then
    part.tower:paint(palette.band, box, FLOORS)
  end
  part.tower:paint(palette.floor, inside, FLOORS)
  part.tower:paint("air", inside, ROOMS)
  for _, side in ipairs(SIDES) do
    if is_open(part, side, tier.is_below_split) then
      for _, piece in ipairs(uncovered(part, box, side, tier)) do
        part.tower:paint(palette.wall, piece)
        if palette.band ~= nil then
          part.tower:paint(palette.band, piece, FLOORS)
        end
      end
    end
  end
  return box
end

local function ring(part, palette, tier)
  local z = tier.high + 1
  local level = { low = z, high = z, shrink = tier.shrink, is_below_split = false }
  local box = footprint(part, tier.shrink, false, z, z)
  part.tower:paint(palette.trim, box)
  part.tower:paint("air", footprint(part, tier.shrink + 1, false, z, z))
  for _, side in ipairs(SIDES) do
    if is_open(part, side, false) then
      for _, piece in ipairs(uncovered(part, box, side, level)) do
        part.tower:paint(palette.trim, piece)
      end
    end
  end
end

function building.roof(part, palette, material, tier)
  part.tower:paint(material, footprint(part, tier.shrink, tier.is_below_split, tier.high, tier.high))
  if tier.above ~= nil then
    part.tower:paint(palette.floor, footprint(part, tier.above.shrink + 1, tier.above.is_below_split, tier.high, tier.high))
  end
  ring(part, palette, tier)
end

function building.punched(part, palette, box, tier, spacing)
  for _, face in ipairs(walls(part, box, tier)) do
    part.tower:paint("glass", face, WINDOW_ROWS)
    for _, pier in ipairs(strips(face, spacing)) do
      part.tower:paint(palette.wall, pier)
    end
  end
end

function building.masonry(part, palette, box, tier)
  building.punched(part, palette, box, tier, PIER_SPACING)
end

function building.banded(part, box, tier, rows)
  for _, face in ipairs(walls(part, box, tier)) do
    part.tower:paint("glass", face, rows)
  end
end

function building.storefront(part)
  local box = footprint(part, 0, true, 1, DOOR_TOP)
  for _, side in ipairs(SIDES) do
    if part.kinds[side] == STREET then
      local face = face_of(box, side)
      local run = along(face, side)
      part.tower:paint("glass", with_along(face, side, { run[1] + 1, run[2] - 1 }))
    end
  end
end

function building.plain()
end

function building.masts(part, palette, tier)
  local roof_box = footprint(part, tier.shrink + 1, false, tier.high, tier.high)
  if not is_empty(roof_box) then
    local x, y = middle(roof_box.x), middle(roof_box.y)
    local is_along_x = width(roof_box.x) >= width(roof_box.y)
    local run = roof_box.y
    if is_along_x then
      run = roof_box.x
    end
    local height = ANTENNA + STORY
    for cell = run[1] + 1, run[2] - 1, MAST_SPACING do
      local mast = { x = { x, x }, y = { cell, cell }, z = { tier.high + 1, tier.high + height } }
      if is_along_x then
        mast = { x = { cell, cell }, y = { y, y }, z = mast.z }
      end
      part.tower:paint(palette.trim, mast)
      height = math.max(2, height - 2)
    end
  end
end

function building.pyramid(part, palette, tier)
  local roof_box = footprint(part, tier.shrink + 1, false, tier.high, tier.high)
  local reach = (math.min(width(roof_box.x), width(roof_box.y)) - 1) // 2
  local x, y = middle(roof_box.x), middle(roof_box.y)
  for level = 1, reach + 1 do
    local spread = reach + 1 - level
    part.tower:paint(palette.trim, { x = { x - spread, x + spread }, y = { y - spread, y + spread }, z = { tier.high + level, tier.high + level } })
  end
end

function building.helipad(part, palette, tier)
  local roof_box = footprint(part, tier.shrink + 1, false, tier.high, tier.high)
  if width(roof_box.x) >= LEAST_PAD and width(roof_box.y) >= LEAST_PAD then
    local x, y, z = middle(roof_box.x), middle(roof_box.y), tier.high + 1
    part.tower:paint("concrete", { x = { x - 2, x + 2 }, y = { y - 2, y + 2 }, z = { z, z } })
    part.tower:paint("white_brick", { x = { x - 1, x - 1 }, y = { y - 1, y + 1 }, z = { z, z } })
    part.tower:paint("white_brick", { x = { x + 1, x + 1 }, y = { y - 1, y + 1 }, z = { z, z } })
    part.tower:paint("white_brick", { x = { x, x }, y = { y, y }, z = { z, z } })
  end
end

function building.chimney(part, palette, tier)
  local roof_box = footprint(part, tier.shrink + 1, false, tier.high, tier.high)
  if not is_empty(roof_box) then
    local x, y = roof_box.x[2], roof_box.y[2]
    part.tower:paint(palette.trim, { x = { x, x }, y = { y, y }, z = { tier.high + 1, tier.high + CHIMNEY } })
  end
end

function building.water_tower(part, palette, tier)
  local roof_box = footprint(part, tier.shrink, false, tier.high, tier.high)
  local x, y = roof_box.x[2] - 2, roof_box.y[2] - 2
  part.tower:paint("steel", { x = { x, x }, y = { y, y }, z = { tier.high + 1, tier.high + 1 } })
  part.tower:paint("steel", { x = { x + 1, x + 1 }, y = { y + 1, y + 1 }, z = { tier.high + 1, tier.high + 1 } })
  part.tower:paint("wood_planks", { x = { x, x + 1 }, y = { y, y + 1 }, z = { tier.high + 2, tier.high + 4 } })
end

local function core_of(part, interior)
  local side = part.front
  local is_x = side == "x_low" or side == "x_high"
  local along_span = interior.y
  local across = interior.x
  if is_x then
    along_span = interior.x
    across = interior.y
  end
  local sign = 1
  local first = along_span[1]
  if side == "x_high" or side == "y_high" then
    sign = -1
    first = along_span[2]
  end
  return { is_x = is_x, sign = sign, first = first, across = across[1] + (width(across) - CORE_WIDTH) // 2, is_roomy = width(along_span) >= CORE_LENGTH and width(across) >= CORE_WIDTH }
end

local function core_box(core, along_low, along_high, across_low, across_high, z)
  local a = core.first + core.sign * along_low
  local b = core.first + core.sign * along_high
  local along_span = { math.min(a, b), math.max(a, b) }
  local across = { core.across + across_low, core.across + across_high }
  if core.is_x then
    return { x = along_span, y = across, z = z }
  else
    return { x = across, y = along_span, z = z }
  end
end

local function stairs(part, core, top, material)
  local last = top - STORY
  for parity = 0, 1 do
    local lane = SECOND_LANE * parity
    local floor = parity * STORY
    for tread = 1, STORY - 1 do
      part.tower:paint(material, core_box(core, tread, tread, lane, lane + 1, { 1, last - 1 }), { every = 2 * STORY, from = floor + 1, span = tread })
    end
    part.tower:paint("air", core_box(core, 0, STORY - 1, lane, lane + 1, { STORY, last }), { every = 2 * STORY, from = floor + STORY, span = 1 })
  end
end

local function wall_along(core, ground)
  local along_span = ground.y
  if core.is_x then
    along_span = ground.x
  end
  if core.sign > 0 then
    return along_span[1]
  else
    return along_span[2]
  end
end

local function door(part, core, ground)
  local wall = wall_along(core, ground)
  local box = core_box(core, 0, 0, WALKWAY, WALKWAY + DOOR_WIDTH - 1, { 1, DOOR_TOP })
  local through = { math.min(wall, wall + core.sign), math.max(wall, wall + core.sign) }
  if core.is_x then
    box.x = through
  else
    box.y = through
  end
  part.tower:paint("air", box)
end

local function route(part, core, ground, stories)
  local wall = wall_along(core, ground)
  local walkway = core.across + WALKWAY + 0.5
  local function stop(along_at, across, z)
    if core.is_x then
      part.tower:stop(along_at, across, z)
    else
      part.tower:stop(across, along_at, z)
    end
  end
  local function cell(k)
    return core.first + core.sign * k + 0.5
  end
  local function outside(distance)
    return wall - core.sign * distance + 0.5
  end
  stop(outside(ROAD_STOP), walkway, 0)
  stop(outside(SIDEWALK_STOP), walkway, 1)
  for story = 0, stories - 1 do
    local floor = story * STORY
    local lane = core.across + SECOND_LANE * (story % 2) + 1
    stop(cell(0), walkway, floor + 1)
    stop(cell(0), lane, floor + 1)
    for tread = 1, STORY - 1 do
      stop(cell(tread), lane, floor + tread + 1)
    end
    stop(cell(STORY), lane, floor + STORY + 1)
    stop(cell(STORY), walkway, floor + STORY + 1)
  end
end

function building.enter(parts, spec)
  local index = 1
  while index <= #parts and parts[index].front == nil do
    index = index + 1
  end
  if index <= #parts then
    local entry = parts[index]
    local core = core_of(entry, footprint(entry, entry.top.shrink + 1, entry.top.is_below_split, 0, 0))
    if core.is_roomy then
      local ground = footprint(entry, 0, true, 0, 0)
      door(entry, core, ground)
      if spec.stories > 1 then
        stairs(entry, core, spec.stories * STORY, spec.palette.floor)
      end
      if spec.route_stories ~= nil then
        route(entry, core, ground, spec.route_stories)
      end
    end
  end
end

function building.crown(parts, palette, crown)
  local main = parts[1]
  for _, part in ipairs(parts) do
    if area(footprint(part, part.stand.shrink, false, 0, 0)) > area(footprint(main, main.stand.shrink, false, 0, 0)) then
      main = part
    end
  end
  crown(main, palette, main.stand)
end

function building.pick(parts, list)
  return list[parts[1].site:pick(#list)]
end

return building
