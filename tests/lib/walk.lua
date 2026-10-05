local walk = {}

walk.SPEED = 4.5
walk.SPRINT_SPEED = 6.5
walk.SPEED_TOLERANCE = 0.05
walk.HALF_HEIGHT = 0.9
walk.CONTACT_SKIN = 0.01
walk.STANDING_ALTITUDE = walk.HALF_HEIGHT + walk.CONTACT_SKIN
walk.ALTITUDE_TOLERANCE = 0.002
walk.MAX_FALL_SPEED = 15
walk.FLY_SPEED = 8
walk.STEP_AIM_DOWN_DEGREES = 30
walk.STEP_ROW_YAWS = { -16, 0, 16 }
walk.STRAIGHT_DOWN_DEGREES = 89
walk.WALL_HOVER_PER_BLOCK = 2
walk.WALL_DISTANCE = 3
walk.WALL_HALF_WIDTH = 1.5
walk.ROW_STEP_METERS = 0.25
walk.GROUND = "dirt"
walk.LAYER_SLOTS = { 1, 4, 5 }
walk.LAYER_MATERIALS = { "wood_planks", "grey_brick", "white_brick" }
walk.TURN_SECONDS = 0.96
walk.SETTLE_SECONDS = 0.48
walk.LANDING_SECONDS = 2

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
  assert(walked >= min_fraction * free, string.format("walked %.1f m of an unobstructed %.1f m, facing %s", walked, free, tostring(world:target_material())))
  return walked
end

function walk.track_motion(world)
  local motion = { speed = 0, at = 0, fall = 0, rise = 0, airborne = 0, lowest = world:altitude(), highest = world:altitude() }
  world:on_step(function()
    local speed = world:horizontal_speed()
    local vertical = world:vertical_speed()
    local altitude = world:altitude()
    if speed > motion.speed then
      motion.speed = speed
      motion.at = world:time()
    end
    motion.fall = math.max(motion.fall, -vertical)
    motion.rise = math.max(motion.rise, vertical)
    motion.lowest = math.min(motion.lowest, altitude)
    motion.highest = math.max(motion.highest, altitude)
    if not world:is_on_ground() then
      motion.airborne = motion.airborne + 1
    end
  end)
  return motion
end

function walk.check_speed_limit(motion, limit)
  local cap = (limit or walk.SPEED) + walk.SPEED_TOLERANCE
  assert(motion.speed <= cap, string.format("horizontal speed reached %.2f m/s at t=%.2f (limit %.2f)", motion.speed, motion.at, cap))
  assert(motion.fall <= walk.MAX_FALL_SPEED, string.format("fell at %.1f m/s (limit %.1f), through the ground or off a cliff", motion.fall, walk.MAX_FALL_SPEED))
end

function walk.check_standing(world, what)
  local altitude = world:altitude()
  assert(world:is_on_ground(), what .. ": on ground")
  assert(math.abs(altitude - walk.STANDING_ALTITUDE) <= walk.ALTITUDE_TOLERANCE, string.format("%s: standing at altitude %.3f m (expected %.2f)", what, altitude, walk.STANDING_ALTITUDE))
end

function walk.build_step(world)
  world:look(0, walk.STEP_AIM_DOWN_DEGREES)
  for _, yaw in ipairs(walk.STEP_ROW_YAWS) do
    world:look(yaw, 0)
    assert(world:place_block(), string.format("placed step block at yaw %d", yaw))
    world:look(-yaw, 0)
  end
  world:look(0, -walk.STEP_AIM_DOWN_DEGREES)
end

local function fly(world, meters, key)
  world:press(meters / walk.FLY_SPEED, key)
end

local function strafe(world, meters)
  if meters > 0 then
    fly(world, meters, "right")
  elseif meters < 0 then
    fly(world, -meters, "left")
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
      fly(world, walk.ROW_STEP_METERS, key)
    end
  end
end

function walk.build_row(world, blocks, key, meters)
  local steps = math.ceil(meters / walk.ROW_STEP_METERS)
  local below = walk.GROUND
  for layer = 1, blocks do
    world:material(walk.LAYER_SLOTS[layer])
    build_layer(world, below, key, steps)
    below = walk.LAYER_MATERIALS[layer]
    if layer < blocks then
      fly(world, steps * walk.ROW_STEP_METERS, OPPOSITE_KEYS[key])
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
    local walked = walk.forward(world, seconds, min_fraction)
    world:wait(walk.SETTLE_SECONDS)
    walk.check_speed_limit(motion)
    assert(world:is_on_ground(), "on ground at the end")
    return walked, world:altitude() - start
  end
end

return walk
