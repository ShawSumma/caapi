local STORY = 4
local HALF_WIDTH = 4
local INNER = HALF_WIDTH - 1
local CORE = 2 * INNER
local TURN = 8
local FLIP_CLEARANCE = 1
local FLIP_SLACK = 2
local FOOTING = 8
local DOOR_TOP = 3
local DOOR = { -1, 0 }
local STOOP = { -2, 1 }
local LANDING = "concrete"
local GLASS = { { -3, -2 }, { 1, 2 } }
local WELL = { 2, 3 }
local SEGMENTS = {
  { 0, 2 },
  { 0, 4 },
  { 2, 4 },
  { 4, 4 },
  { 4, 2 },
  { 4, 0 },
  { 2, 0 },
  { 0, 0 },
}
local PALETTES = {
  { wall = "white_brick", trim = "limestone", floor = "wood_planks" },
  { wall = "red_sandstone", trim = "white_brick", floor = "wood_planks" },
  { wall = "limestone", trim = "steel", floor = "concrete" },
  { wall = "grey_brick", trim = "white_brick", floor = "wood_planks" },
}

local function cells(along, across, z)
  return { x = { along[1] - INNER, along[2] - INNER }, y = { across[1] - INNER, across[2] - INNER }, z = z }
end

local function windows(tower, z, rows)
  for _, run in ipairs(GLASS) do
    tower:paint("glass", { x = { -HALF_WIDTH, -HALF_WIDTH }, y = run, z = z }, rows)
    tower:paint("glass", { x = { HALF_WIDTH - 1, HALF_WIDTH - 1 }, y = run, z = z }, rows)
    tower:paint("glass", { x = run, y = { -HALF_WIDTH, -HALF_WIDTH }, z = z }, rows)
    tower:paint("glass", { x = run, y = { HALF_WIDTH - 1, HALF_WIDTH - 1 }, z = z }, rows)
  end
end

local function shell(tower, palette, layout)
  local base, top, split = layout.base, layout.top, layout.split
  local bands = { every = STORY, from = base % STORY, span = 1 }
  tower:paint(palette.wall, { x = { -HALF_WIDTH, HALF_WIDTH - 1 }, y = { -HALF_WIDTH, HALF_WIDTH - 1 }, z = { base, base + top } })
  tower:paint(palette.trim, { x = { -HALF_WIDTH, HALF_WIDTH - 1 }, y = { -HALF_WIDTH, HALF_WIDTH - 1 }, z = { base, base + top } }, bands)
  windows(tower, { base + 1, base + split }, { every = STORY, from = (base + 1) % STORY, span = 2 })
  windows(tower, { base + split + 1, base + top - 1 }, { every = STORY, from = (base + top - 2) % STORY, span = 2 })
  tower:paint(palette.floor, cells({ 0, CORE - 1 }, { 0, CORE - 1 }, { base, base }))
  tower:paint(palette.floor, cells({ 0, CORE - 1 }, { 0, CORE - 1 }, { base + top, base + top }))
end

local function landing_layer(flip)
  return flip - FLIP_SLACK + 1 + TURN
end

local function helix(tower, material, layout)
  local base, top, flip = layout.base, layout.top, layout.flip
  local landing = base + landing_layer(flip)
  tower:paint("air", cells({ 0, CORE - 1 }, { 0, CORE - 1 }, { base + 1, base + top - 1 }))
  tower:paint(material, cells(WELL, WELL, { landing, landing + 1 }))
  for index, segment in ipairs(SEGMENTS) do
    local along = { segment[1], segment[1] + 1 }
    local across = { segment[2], segment[2] + 1 }
    local last = flip - (flip - index + 1) % TURN
    if last >= 0 then
      tower:paint(material, cells(along, across, { base, base + last }), { every = TURN, from = (base + index - 2) % TURN, span = 2 })
    end
    if last + TURN <= top then
      tower:paint(material, cells(along, across, { base + last + TURN, base + top }), { every = TURN, from = (base + index - 1) % TURN, span = 2 })
    end
  end
end

local function planet_door(tower, palette, layout)
  local base, below = layout.base, layout.below
  tower:paint("air", { x = { -HALF_WIDTH, -HALF_WIDTH }, y = DOOR, z = { base + 1, base + DOOR_TOP } })
  for distance = 1, layout.stoop + 1 do
    local x = { -HALF_WIDTH - distance, -HALF_WIDTH - distance }
    local surface = math.max(below, base + 1 - distance)
    tower:fill(palette.trim, { x = x, y = STOOP, z = { below - FOOTING, below - 2 } })
    tower:paint(palette.trim, { x = x, y = STOOP, z = { below - 1, surface - 1 } })
    tower:paint("air", { x = x, y = STOOP, z = { surface, base + DOOR_TOP } })
  end
end

local function sky_door(tower, layout)
  local floor = layout.base + layout.top
  local x = { -HALF_WIDTH - 1, -HALF_WIDTH - 1 }
  tower:paint("air", { x = { -HALF_WIDTH, -HALF_WIDTH }, y = DOOR, z = { floor - DOOR_TOP, floor - 1 } })
  tower:fill(LANDING, { x = x, y = STOOP, z = { floor + 1, floor + FOOTING } })
  tower:paint(LANDING, { x = x, y = STOOP, z = { floor, floor } })
  tower:paint("air", { x = x, y = STOOP, z = { floor - DOOR_TOP, floor - 1 } })
end

local function tread(tower, layer, z)
  local segment = SEGMENTS[layer % TURN + 1]
  tower:stop(segment[1] + 1 - INNER, segment[2] + 1 - INNER, z)
end

local function route(tower, layout)
  local base, top, flip = layout.base, layout.top, layout.flip
  tower:stop(-HALF_WIDTH - layout.stoop - 0.5, 0, layout.below)
  tower:stop(0.5 - INNER, 0, base + 1)
  for layer = 1, flip - FLIP_SLACK do
    tread(tower, layer, base + layer + 1)
  end
  for layer = landing_layer(flip), top do
    tread(tower, layer, base + layer)
  end
  tower:stop(0.5 - INNER, 0, base + top)
  tower:stop(-HALF_WIDTH - 0.5, 0, base + top)
end

local function layout_of(site, sky, ground)
  local length = sky.edges * site:edge_cells()
  local sky_floor = length - ground
  local stoop = (sky_floor - sky.below + 1) % TURN
  local base = sky.below - 1 + stoop
  local split = length - sky.balance - base - 1
  return { below = sky.below, stoop = stoop, base = base, top = sky_floor - base, split = split, flip = split + 1 - FLIP_CLEARANCE }
end

return function(site, sky, ground, is_routed)
  local layout = layout_of(site, sky, ground)
  if layout.split >= STORY and layout.top - layout.split > STORY and layout.top >= 2 * TURN then
    local palette = PALETTES[site:pick(#PALETTES)]
    local tower = site:pitch_up():roll_right():forward(sky.edges):pitch_up():pitch_up():roll_right()
    tower:fill(palette.trim, { x = { -HALF_WIDTH, HALF_WIDTH - 1 }, y = { -HALF_WIDTH, HALF_WIDTH - 1 }, z = { layout.below - FOOTING, layout.base - 1 } })
    tower:fill(palette.trim, { x = { -HALF_WIDTH, HALF_WIDTH - 1 }, y = { -HALF_WIDTH, HALF_WIDTH - 1 }, z = { layout.base + layout.top + 1, layout.base + layout.top + FOOTING } })
    shell(tower, palette, layout)
    helix(tower, palette.floor, layout)
    planet_door(tower, palette, layout)
    sky_door(tower, layout)
    if is_routed then
      route(tower, layout)
    end
  end
end
