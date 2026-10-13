local BARK = "oak_wood"
local LEAVES = "oak_leaves"
local GOLDEN = 137.5
local STEP = 3
local THINNEST = 0.7

local TRUNK = {
  height = 48,
  sink = 12,
  radius = 5,
  top = 2.5,
  flare = 3,
  flare_height = 4,
  wander = 2,
  steer = 2,
}

local ROOTS = {
  count = 7,
  height = 3,
  length = 22,
  radius = 3,
  tip = 1,
  dip = 20,
  droop = 5,
  wander = 10,
}

local LIMBS = {
  count = 12,
  low = 0.3,
  high = 0.97,
  lowest_angle = 80,
  highest_angle = 25,
  spread = 8,
  length = 36,
  shortening = 0.45,
  width = 0.65,
}

local ORDERS = {
  { children = 6, first = 0.3, angle = 45, length = 0.55, width = 0.6, wander = 5, elevation = 8, steer = 3, tip = 0.35 },
  { children = 5, first = 0.2, angle = 50, length = 0.6, width = 0.6, wander = 8, elevation = 15, steer = 4, tip = 0.4 },
  { children = 4, first = 0.2, angle = 55, length = 0.65, width = 0.6, wander = 12, elevation = 20, steer = 5, tip = 0.5 },
  { children = 0, wander = 15, elevation = 25, steer = 5, tip = 0.6 },
}
local SPREAD = 10
local LATER_SHORTER = 0.5
local LEAF_START = 0.4
local TWIG_LEAVES = { 3, 4 }
local TIP_LEAVES = { 3.5, 5 }
local SPAWN = { -14, 12, 0 }

local function between(pen, low, high)
  return low + (high - low) * pen:random()
end

local function wandered(pen, degrees)
  return pen:turn(between(pen, -degrees, degrees), between(pen, -degrees, degrees))
end

local function steered(pen, elevation, rate)
  local off = elevation - pen:rise()
  return pen:lift(math.max(-rate, math.min(rate, off)))
end

local function sprouts(pen, shape)
  local places = {}
  for child = 1, shape.children do
    local slot = (child - between(pen, 0.2, 0.8)) / shape.children
    places[child] = shape.first + (1 - shape.first) * slot
  end
  return places
end

local function branch(pen, length, radius, order)
  local shape = ORDERS[order]
  local steps = math.max(1, math.ceil(length / STEP))
  local step = length / steps
  local tip = math.max(THINNEST, radius * shape.tip)
  local roll = between(pen, 0, 360)
  local places = {}
  if order < #ORDERS then
    places = sprouts(pen, shape)
  end
  local child = 1
  for index = 1, steps do
    local done = index / steps
    local from = radius + (tip - radius) * (index - 1) / steps
    local to = radius + (tip - radius) * done
    pen = pen:limb(BARK, step, from, to)
    while child <= #places and places[child] <= done do
      local fork = pen:roll(roll + child * GOLDEN):turn(0, between(pen, shape.angle - SPREAD, shape.angle + SPREAD))
      local reach = length * shape.length * (1 - LATER_SHORTER * places[child])
      branch(fork, reach, math.max(THINNEST, to * shape.width), order + 1)
      child = child + 1
    end
    if order == #ORDERS and done >= LEAF_START then
      pen:leaves(LEAVES, between(pen, TWIG_LEAVES[1], TWIG_LEAVES[2]))
    end
    pen = steered(wandered(pen, shape.wander), shape.elevation, shape.steer)
  end
  if order >= #ORDERS - 1 then
    pen:leaves(LEAVES, between(pen, TIP_LEAVES[1], TIP_LEAVES[2]))
  end
end

local function trunk_radius(height)
  local along = math.max(0, height) / TRUNK.height
  local taper = TRUNK.top + (TRUNK.radius - TRUNK.top) * (1 - along)
  return taper + TRUNK.flare * math.exp(-math.max(0, height) / TRUNK.flare_height)
end

local function roots(base)
  local turn = between(base, 0, 360)
  for root = 1, ROOTS.count do
    local around = turn + root * 360 / ROOTS.count + between(base, -ROOTS.wander, ROOTS.wander)
    local pen = base:roll(around):turn(0, 90 + ROOTS.dip + between(base, -ROOTS.wander, ROOTS.wander))
    local steps = math.ceil(ROOTS.length / STEP)
    for index = 1, steps do
      local from = ROOTS.radius + (ROOTS.tip - ROOTS.radius) * (index - 1) / steps
      local to = ROOTS.radius + (ROOTS.tip - ROOTS.radius) * index / steps
      pen = wandered(pen:limb(BARK, STEP, from, to), ROOTS.wander):lift(-ROOTS.droop)
    end
  end
end

local function limbs(trunk, height, radius, placed)
  local limb = placed.next
  local is_due = true
  while limb <= LIMBS.count and is_due do
    local along = LIMBS.low + (LIMBS.high - LIMBS.low) * (limb - 1) / (LIMBS.count - 1)
    is_due = along * TRUNK.height <= height
    if is_due then
      local angle = LIMBS.lowest_angle + (LIMBS.highest_angle - LIMBS.lowest_angle) * (limb - 1) / (LIMBS.count - 1)
      local pen = trunk:roll(placed.roll + limb * GOLDEN):turn(0, between(trunk, angle - LIMBS.spread, angle + LIMBS.spread))
      branch(pen, LIMBS.length * (1 - LIMBS.shortening * along), radius * LIMBS.width, 1)
      limb = limb + 1
    end
  end
  placed.next = limb
end

return function(site)
  local pen = site:pitch_up():pen():forward(-TRUNK.sink)
  local placed = { next = 1, roll = between(pen, 0, 360) }
  local steps = math.ceil((TRUNK.height + TRUNK.sink) / STEP)
  for index = 1, steps do
    local height = (index - 1) * STEP - TRUNK.sink
    if height == ROOTS.height then
      roots(pen)
    end
    pen = pen:limb(BARK, STEP, trunk_radius(height), trunk_radius(height + STEP))
    limbs(pen, height + STEP, trunk_radius(height + STEP), placed)
    pen = steered(wandered(pen, TRUNK.wander), 90, TRUNK.steer)
  end
  pen:leaves(LEAVES, TIP_LEAVES[2])
  site:entrance(SPAWN[1], SPAWN[2], SPAWN[3])
end
