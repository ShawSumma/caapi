local kit = {}

kit.STORY = 4
kit.STREET = "street"
kit.JOINED = "joined"
kit.LOT = "lot"

local STORY = kit.STORY
local STREET = kit.STREET
local JOINED = kit.JOINED
local FLOORS = { every = STORY, from = 0, span = 1 }
local ROOMS = { every = STORY, from = 1, span = STORY - 1 }
local WINDOW_ROWS = { every = STORY, from = 1, span = 2 }
local SPANDRELS = { every = STORY, from = STORY - 1, span = 1 }
local DOOR_TOP = STORY - 1
local DOOR_WIDTH = 2
local PIER_SPACING = 3
local MULLION_SPACING = 3
local SPIRE = 10
local ANTENNA = 6
local LEAST_WIDTH = 3
local PENTHOUSE_SETBACK = 2
local CORE_LENGTH = STORY + 1
local CORE_WIDTH = 5
local CORE_ROOM = CORE_WIDTH + 2
local WALKWAY = 2
local SECOND_LANE = 3
local ROAD_STOP = 3
local SIDEWALK_STOP = 2
local SIDES = { "x_low", "y_low", "x_high", "y_high" }

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
    x = { bound_low(lot.x_low, spec), bound_high(lot.x_high, spec, far) },
    y = { bound_low(lot.y_low, spec), bound_high(lot.y_high, spec, far) },
    kinds = { x_low = lot.x_low, y_low = lot.y_low, x_high = lot.x_high, y_high = lot.y_high },
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

local function footprint(part, shrink, is_below_split, low, high)
  return {
    x = range(part.x[1], part.x[2], is_open(part, "x_low", is_below_split), is_open(part, "x_high", is_below_split), shrink),
    y = range(part.y[1], part.y[2], is_open(part, "y_low", is_below_split), is_open(part, "y_high", is_below_split), shrink),
    z = { low, high },
  }
end

local function middle(span)
  return (span[1] + span[2]) // 2
end

local function area(box)
  return (box.x[2] - box.x[1] + 1) * (box.y[2] - box.y[1] + 1)
end

local function face_of(box, side)
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

local function walls(part, box, is_below_split)
  local list = {}
  for _, side in ipairs(SIDES) do
    if not is_open(part, side, is_below_split) then
      list[#list + 1] = face_of(box, side)
    end
  end
  return list
end

local function strips(face, spacing)
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

local function narrowing(box, wanted, least)
  local width = math.min(box.x[2] - box.x[1], box.y[2] - box.y[1]) + 1
  return math.max(0, math.min(wanted, (width - least) // 2))
end

local function setbacks_of(parts, wanted)
  local setbacks = wanted
  for _, part in ipairs(parts) do
    setbacks = math.min(setbacks, narrowing(part, wanted, CORE_ROOM))
  end
  return setbacks
end

local function tiers_of(top, split, setbacks)
  local tiers = { { low = 0, high = math.min(top, split - 1), shrink = 0, is_below_split = true } }
  local low = split
  for tier = 0, setbacks do
    local high = top
    if tier < setbacks then
      high = split + (top - split) * (tier + 1) // (setbacks + 1) // STORY * STORY
    end
    if high >= low then
      tiers[#tiers + 1] = { low = low, high = high, shrink = tier, is_below_split = false }
      low = high + 1
    end
  end
  return tiers
end

local function shell(part, palette, tier)
  local box = footprint(part, tier.shrink, tier.is_below_split, tier.low, tier.high)
  local inside = footprint(part, tier.shrink + 1, tier.is_below_split, tier.low, tier.high)
  part.tower:paint(palette.wall, box)
  if palette.band then
    part.tower:paint(palette.band, box, FLOORS)
  end
  part.tower:paint(palette.floor, inside, FLOORS)
  part.tower:paint("air", inside, ROOMS)
  return box
end

local function roof(part, palette, material, tier, above)
  part.tower:paint(material, footprint(part, tier.shrink, tier.is_below_split, tier.high, tier.high))
  if above then
    part.tower:paint(palette.floor, footprint(part, above.shrink + 1, above.is_below_split, tier.high, tier.high))
  end
end

local function ring(part, palette, shrink, z)
  part.tower:paint(palette.trim, footprint(part, shrink, false, z, z))
  part.tower:paint("air", footprint(part, shrink + 1, false, z, z))
end

function kit.masonry(part, palette, box, is_below_split)
  for _, face in ipairs(walls(part, box, is_below_split)) do
    part.tower:paint("glass", face, WINDOW_ROWS)
    for _, pier in ipairs(strips(face, PIER_SPACING)) do
      part.tower:paint(palette.wall, pier)
    end
  end
end

function kit.curtain(part, palette, box, is_below_split)
  for _, face in ipairs(walls(part, box, is_below_split)) do
    part.tower:paint(palette.band, face, SPANDRELS)
    for _, mullion in ipairs(strips(face, MULLION_SPACING)) do
      part.tower:paint(palette.trim, mullion)
    end
  end
end

function kit.penthouse(part, palette, tier)
  local roof = footprint(part, tier.shrink, false, tier.high, tier.high)
  local cap = { low = tier.high + 1, high = tier.high + STORY, shrink = tier.shrink + narrowing(roof, PENTHOUSE_SETBACK, LEAST_WIDTH), is_below_split = false }
  shell(part, { wall = palette.band, floor = palette.floor }, cap)
end

function kit.antenna(part, palette, tier)
  local roof = footprint(part, tier.shrink, false, tier.high, tier.high)
  local x, y = middle(roof.x), middle(roof.y)
  part.tower:paint(palette.trim, { x = { x, x }, y = { y, y }, z = { tier.high + STORY + 1, tier.high + STORY + ANTENNA } })
end

function kit.spire(part, palette, tier)
  local roof = footprint(part, tier.shrink, false, tier.high, tier.high)
  local x, y = middle(roof.x), middle(roof.y)
  part.tower:paint(palette.trim, { x = { x - 1, x + 1 }, y = { y - 1, y + 1 }, z = { tier.high + 1, tier.high + 2 } })
  part.tower:paint(palette.trim, { x = { x, x }, y = { y, y }, z = { tier.high + 3, tier.high + SPIRE } })
end

function kit.water_tower(part, palette, tier)
  local roof = footprint(part, tier.shrink, false, tier.high, tier.high)
  local x, y = roof.x[2] - 2, roof.y[2] - 2
  part.tower:paint("steel", { x = { x, x }, y = { y, y }, z = { tier.high + 1, tier.high + 1 } })
  part.tower:paint("steel", { x = { x + 1, x + 1 }, y = { y + 1, y + 1 }, z = { tier.high + 1, tier.high + 1 } })
  part.tower:paint("wood_planks", { x = { x, x + 1 }, y = { y, y + 1 }, z = { tier.high + 2, tier.high + 4 } })
end

local function storefront(part)
  local box = footprint(part, 0, true, 1, DOOR_TOP)
  for _, side in ipairs(SIDES) do
    if part.kinds[side] == STREET then
      local face = face_of(box, side)
      if face.x[1] == face.x[2] then
        face.y = { face.y[1] + 1, face.y[2] - 1 }
      else
        face.x = { face.x[1] + 1, face.x[2] - 1 }
      end
      part.tower:paint("glass", face)
    end
  end
end

local function core_of(part, interior)
  local side = part.front
  local is_x = side == "x_low" or side == "x_high"
  local along = interior.y
  local across = interior.x
  if is_x then
    along = interior.x
    across = interior.y
  end
  local sign = 1
  local first = along[1]
  if side == "x_high" or side == "y_high" then
    sign = -1
    first = along[2]
  end
  if along[2] - along[1] + 1 < CORE_LENGTH or across[2] - across[1] + 1 < CORE_WIDTH then
    return nil
  else
    return { is_x = is_x, sign = sign, first = first, across = across[1] + (across[2] - across[1] + 1 - CORE_WIDTH) // 2 }
  end
end

local function core_box(core, along_low, along_high, across_low, across_high, z)
  local a = core.first + core.sign * along_low
  local b = core.first + core.sign * along_high
  local along = { math.min(a, b), math.max(a, b) }
  local across = { core.across + across_low, core.across + across_high }
  if core.is_x then
    return { x = along, y = across, z = z }
  else
    return { x = across, y = along, z = z }
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
  local along = ground.y
  if core.is_x then
    along = ground.x
  end
  if core.sign > 0 then
    return along[1]
  else
    return along[2]
  end
end

local function door(part, core, ground)
  local wall = wall_along(core, ground)
  local box = core_box(core, 0, 0, WALKWAY, WALKWAY + DOOR_WIDTH - 1, { 1, DOOR_TOP })
  if core.is_x then
    box.x = { wall, wall }
  else
    box.y = { wall, wall }
  end
  part.tower:paint("air", box)
end

local function route(part, core, ground, stories)
  local wall = wall_along(core, ground)
  local walkway = core.across + WALKWAY + 0.5
  local function stop(along, across, z)
    if core.is_x then
      part.tower:stop(along, across, z)
    else
      part.tower:stop(across, along, z)
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

local function enter(parts, tops, spec)
  local index = 1
  while index <= #parts and not parts[index].front do
    index = index + 1
  end
  local entry = parts[index]
  if entry then
    local highest = tops[entry]
    local core = core_of(entry, footprint(entry, highest.shrink + 1, highest.is_below_split, 0, 0))
    if core then
      local ground = footprint(entry, 0, true, 0, 0)
      door(entry, core, ground)
      if spec.stories > 1 then
        stairs(entry, core, spec.stories * STORY, spec.palette.floor)
      end
      if spec.route_stories then
        route(entry, core, ground, spec.route_stories)
      end
    end
  end
end

local function main_part(parts, tops)
  local main = parts[1]
  for _, part in ipairs(parts) do
    local top = tops[part]
    local best = tops[main]
    if area(footprint(part, top.shrink, false, 0, 0)) > area(footprint(main, best.shrink, false, 0, 0)) then
      main = part
    end
  end
  return main
end

function kit.build(lots, spec, design)
  local parts = {}
  for index, lot in ipairs(lots) do
    parts[index] = part_of(lot, spec)
  end
  local top = spec.stories * STORY
  local setbacks = setbacks_of(parts, design.setbacks)
  local tops = {}
  for _, part in ipairs(parts) do
    local tiers = tiers_of(top, part.split, setbacks)
    for index, tier in ipairs(tiers) do
      design.facade(part, spec.palette, shell(part, spec.palette, tier), tier.is_below_split)
      local above = tiers[index + 1]
      if not above or above.shrink > tier.shrink then
        roof(part, spec.palette, design.roof, tier, above)
        ring(part, spec.palette, tier.shrink, tier.high + 1)
      end
    end
    if design.has_storefront then
      storefront(part)
    end
    local highest = tiers[#tiers]
    if design.cap then
      design.cap(part, spec.palette, highest)
    end
    tops[part] = highest
  end
  enter(parts, tops, spec)
  if design.crown then
    local main = main_part(parts, tops)
    design.crown(main, spec.palette, tops[main])
  end
end

return kit
