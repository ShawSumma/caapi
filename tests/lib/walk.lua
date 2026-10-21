local walk = {}

walk.SPEED = 0.225
walk.SPEED_TOLERANCE = 0.0025
walk.BLOCKED_SPEED = walk.SPEED / 2
walk.HALF_HEIGHT = 0.045
walk.CONTACT_SKIN = 0.0005
walk.STANDING_ALTITUDE = walk.HALF_HEIGHT + walk.CONTACT_SKIN
walk.ALTITUDE_TOLERANCE = 0.0001
walk.FLY_SPEED = 0.4
walk.NOCLIP_SPEED = 0.6
walk.STRAIGHT_DOWN_DEGREES = 89
walk.WALL_HOVER_PER_BLOCK = 0.1
walk.WALL_DISTANCE = 0.15
walk.WALL_HALF_WIDTH = 0.075
walk.ROW_STEP = 0.0125
walk.STEP_DEPTH = 0.075
walk.GROUND = "dirt"
walk.LAYER_SLOTS = { 1, 4, 5 }
walk.LAYER_MATERIALS = { "wood_planks", "grey_brick", "white_brick" }
walk.TURN_SECONDS = 0.96
walk.SETTLE_SECONDS = 0.48
walk.LANDING_SECONDS = 2
walk.MIN_BLOCK_EDGE = 0.035
walk.MAX_BLOCK_EDGE = 0.077
walk.STREET_MATERIALS = { basalt = true, white_brick = true }
walk.TOWER_MATERIALS = { concrete = true, white_brick = true, grey_brick = true, sandstone = true, wood_planks = true, steel = true, marble = true }
walk.BACKROOMS_FLOORS = { carpet = true, damp_carpet = true, red_carpet = true, concrete = true }
walk.BACKROOMS_CEILINGS = { ceiling_tile = true, light_panel = true, concrete = true }

function walk.spawn(world)
  assert(world:mode() == "walk", "spawned walking")
  assert(world:is_on_ground(), "spawned standing on the ground")
end

function walk.on_slope(world, degrees, heading)
  world:worldgen("plane", degrees)
  walk.spawn(world)
  if heading ~= 0 then
    world:turn(heading, 0, walk.TURN_SECONDS)
  end
  world:wait(walk.SETTLE_SECONDS)
end

function walk.forward(world, seconds, min_fraction)
  local start = world:traveled()
  world:press(seconds, "fwd")
  local walked = world:traveled() - start
  local free = walk.SPEED * seconds
  assert(walked >= min_fraction * free, string.format("walked %.4f of an unobstructed %.4f, facing %s", walked, free, tostring(world:target_material())))
  return walked
end

function walk.is_on_step(world, standing)
  world:look(0, walk.STRAIGHT_DOWN_DEGREES)
  local below = world:target_material()
  world:look(0, -walk.STRAIGHT_DOWN_DEGREES)
  return world:is_on_ground() and world:altitude() - standing > walk.MIN_BLOCK_EDGE / 2 and below == walk.LAYER_MATERIALS[1]
end

function walk.climb_forward(world, seconds, dt, is_done)
  local step = dt
  if step == nil then
    step = world:timestep()
  end
  local deadline = world:time() + seconds
  world:hold("fwd")
  world:step(step)
  while world:time() < deadline and not (is_done ~= nil and is_done()) do
    walk.jump_if_blocked(world)
    world:step(step)
  end
  world:release("fwd", "up")
end

function walk.jump_if_blocked(world)
  world:release("up")
  if world:is_on_ground() and world:horizontal_speed() < walk.BLOCKED_SPEED then
    world:hold("up")
  end
end

function walk.track_motion(world)
  local motion = { excess = 0, excess_at = 0, cap = walk.SPEED, was_on_ground = world:is_on_ground(), rise = 0, off_ground = 0, lowest = world:altitude(), highest = world:altitude() }
  world:on_step(function()
    walk.observe(world, motion)
  end)
  return motion
end

function walk.observe(world, motion)
  local speed = world:horizontal_speed()
  local altitude = world:altitude()
  if world:is_on_ground() then
    if not motion.was_on_ground then
      motion.cap = math.max(walk.SPEED, speed)
    end
    if speed - motion.cap > motion.excess then
      motion.excess = speed - motion.cap
      motion.excess_at = world:time()
    end
    motion.cap = math.max(walk.SPEED, math.min(motion.cap, speed))
  else
    motion.off_ground = motion.off_ground + 1
  end
  motion.was_on_ground = world:is_on_ground()
  motion.rise = math.max(motion.rise, world:vertical_speed())
  motion.lowest = math.min(motion.lowest, altitude)
  motion.highest = math.max(motion.highest, altitude)
end

function walk.check_speed_limit(motion)
  assert(motion.excess <= walk.SPEED_TOLERANCE, string.format("walking sped up %.4f past the walk speed or the landing speed at t=%.2f", motion.excess, motion.excess_at))
end

function walk.check_on_step(world, standing, what)
  assert(world:is_on_ground(), what .. ": on ground")
  local rise = world:altitude() - standing
  assert(rise > walk.MIN_BLOCK_EDGE / 2, string.format("%s: rose %.4f", what, rise))
  world:look(0, walk.STRAIGHT_DOWN_DEGREES)
  local below = world:target_material()
  world:look(0, -walk.STRAIGHT_DOWN_DEGREES)
  assert(below == walk.LAYER_MATERIALS[1], string.format("%s: standing on %s", what, tostring(below)))
end

function walk.check_standing(world, what)
  local altitude = world:altitude()
  assert(world:is_on_ground(), what .. ": on ground")
  assert(math.abs(altitude - walk.STANDING_ALTITUDE) <= walk.ALTITUDE_TOLERANCE, string.format("%s: standing at altitude %.5f (expected %.5f)", what, altitude, walk.STANDING_ALTITUDE))
end

local function fly(world, distance, key)
  world:press(distance / walk.FLY_SPEED, key)
end

local function strafe(world, distance)
  if distance > 0 then
    fly(world, distance, "right")
  elseif distance < 0 then
    fly(world, -distance, "left")
  end
end

local OPPOSITE_KEYS = { fwd = "back", back = "fwd", left = "right", right = "left" }

local function build_layer(world, below, key, steps)
  for step = 0, steps do
    world:look(0, walk.STRAIGHT_DOWN_DEGREES)
    if world:target_material() == below then
      assert(world:place_block(), string.format("placed a block on %s %d steps along the row", below, step))
    end
    world:look(0, -walk.STRAIGHT_DOWN_DEGREES)
    if step < steps then
      fly(world, walk.ROW_STEP, key)
    end
  end
end

function walk.build_row(world, blocks, key, length)
  local steps = math.ceil(length / walk.ROW_STEP)
  local below = walk.GROUND
  for layer = 1, blocks do
    world:material(walk.LAYER_SLOTS[layer])
    build_layer(world, below, key, steps)
    below = walk.LAYER_MATERIALS[layer]
    if layer < blocks then
      fly(world, steps * walk.ROW_STEP, OPPOSITE_KEYS[key])
    end
  end
  world:material(walk.LAYER_SLOTS[1])
end

function walk.hover(world, blocks)
  world:mode("fly")
  fly(world, walk.WALL_HOVER_PER_BLOCK * blocks, "up")
end

function walk.land(world)
  world:step()
  world:mode("walk")
  world:wait(walk.LANDING_SECONDS)
end

function walk.build_wall(world, blocks)
  walk.hover(world, blocks)
  fly(world, walk.WALL_DISTANCE, "fwd")
  strafe(world, -walk.WALL_HALF_WIDTH)
  walk.build_row(world, blocks, "right", 2 * walk.WALL_HALF_WIDTH)
  strafe(world, -walk.WALL_HALF_WIDTH)
  fly(world, walk.WALL_DISTANCE, "back")
  walk.land(world)
end

function walk.build_step(world)
  walk.hover(world, 1)
  fly(world, walk.WALL_DISTANCE, "fwd")
  strafe(world, -walk.WALL_HALF_WIDTH)
  local key = "right"
  local rows = math.ceil(walk.STEP_DEPTH / walk.ROW_STEP)
  for row = 0, rows do
    walk.build_row(world, 1, key, 2 * walk.WALL_HALF_WIDTH)
    key = OPPOSITE_KEYS[key]
    if row < rows then
      fly(world, walk.ROW_STEP, "fwd")
    end
  end
  if key == "right" then
    strafe(world, walk.WALL_HALF_WIDTH)
  else
    strafe(world, -walk.WALL_HALF_WIDTH)
  end
  fly(world, walk.WALL_DISTANCE + rows * walk.ROW_STEP, "back")
  walk.land(world)
end

function walk.build_corner(world, blocks)
  walk.hover(world, blocks)
  fly(world, walk.WALL_DISTANCE, "fwd")
  strafe(world, -walk.WALL_HALF_WIDTH)
  walk.build_row(world, blocks, "right", 2 * walk.WALL_HALF_WIDTH)
  walk.build_row(world, blocks, "back", walk.WALL_DISTANCE)
  strafe(world, -walk.WALL_HALF_WIDTH)
  walk.land(world)
end

function walk.across_slope(degrees, heading, seconds, min_fraction)
  return function(world)
    walk.on_slope(world, degrees, heading)
    local motion = walk.track_motion(world)
    local start = world:altitude()
    local before = world:traveled()
    walk.climb_forward(world, seconds)
    local walked = world:traveled() - before
    local free = walk.SPEED * seconds
    assert(walked >= min_fraction * free, string.format("walked %.4f of an unobstructed %.4f, facing %s", walked, free, tostring(world:target_material())))
    world:wait(walk.LANDING_SECONDS)
    walk.check_speed_limit(motion)
    assert(world:is_on_ground(), "on ground at the end")
    return walked, world:altitude() - start
  end
end

return walk
