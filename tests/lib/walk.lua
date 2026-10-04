local walk = {}

walk.SPEED = 4
walk.SPEED_TOLERANCE = 0.05
walk.HALF_HEIGHT = 0.9
walk.CONTACT_SKIN = 0.01
walk.STANDING_ALTITUDE = walk.HALF_HEIGHT + walk.CONTACT_SKIN
walk.ALTITUDE_TOLERANCE = 0.002
walk.MAX_FALL_SPEED = 15
walk.STEP_AIM_DOWN_DEGREES = 30
walk.STEP_ROW_YAWS = { -16, 0, 16 }
walk.TURN_SECONDS = 0.96
walk.TERRAIN_WALK_SECONDS = 11.2
walk.SETTLE_SECONDS = 0.48

function walk.spawn(world)
  assert(world:mode() == "walk", "spawned walking")
  assert(world:is_on_ground(), "spawned standing on the ground")
end

function walk.forward(world, seconds, min_fraction)
  local start = world:traveled()
  world:press(seconds, "fwd")
  local walked = world:traveled() - start
  local free = walk.SPEED * seconds
  assert(walked >= min_fraction * free, string.format("walked %.1f m of an unobstructed %.1f m, facing %s", walked, free, tostring(world:target_material())))
  return walked
end

function walk.track_horizontal_speed(world)
  local peak = { speed = 0, at = 0, fall = 0, facing = nil }
  world:on_step(function()
    local speed = world:horizontal_speed()
    if speed > peak.speed then
      peak.speed = speed
      peak.at = world:time()
      peak.facing = world:target_material()
    end
    peak.fall = math.max(peak.fall, -world:vertical_speed())
  end)
  return peak
end

function walk.check_speed_limit(peak)
  local limit = walk.SPEED + walk.SPEED_TOLERANCE
  assert(peak.speed <= limit, string.format("horizontal speed reached %.2f m/s at t=%.2f facing %s (limit %.2f)", peak.speed, peak.at, tostring(peak.facing), limit))
  assert(peak.fall <= walk.MAX_FALL_SPEED, string.format("fell at %.1f m/s (limit %.1f), through the ground or off a cliff", peak.fall, walk.MAX_FALL_SPEED))
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

function walk.across_terrain(heading_degrees, min_fraction)
  return function(world)
    walk.spawn(world)
    world:turn(heading_degrees, 0, walk.TURN_SECONDS)
    local peak = walk.track_horizontal_speed(world)
    walk.forward(world, walk.TERRAIN_WALK_SECONDS, min_fraction)
    world:wait(walk.SETTLE_SECONDS)
    walk.check_speed_limit(peak)
    assert(world:is_on_ground(), "on ground at the end")
  end
end

return walk
