local walk = {}

walk.SPEED = 4
walk.SPEED_TOLERANCE = 0.05
walk.HALF_HEIGHT = 0.9
walk.CONTACT_SKIN = 0.01
walk.STANDING_ALTITUDE = walk.HALF_HEIGHT + walk.CONTACT_SKIN
walk.ALTITUDE_TOLERANCE = 0.002
walk.MAX_FALL_SPEED = 15

function walk.spawn(world)
  local player = world.player
  world:check(player:mode() == "walk", "spawned walking")
  world:check(player:on_ground(), "spawned standing on the ground")
end

function walk.forward(world, seconds, min_fraction)
  local player = world.player
  local start = player:traveled()
  player:press(seconds, "fwd")
  local walked = player:traveled() - start
  local free = walk.SPEED * seconds
  world:check(walked >= min_fraction * free, string.format("walked %.1f m of an unobstructed %.1f m", walked, free))
  return walked
end

function walk.track_horizontal_speed(world)
  local peak = { speed = 0, at = 0, fall = 0 }
  world:every_frame(function()
    local speed = world.player:horizontal_speed()
    if speed > peak.speed then
      peak.speed = speed
      peak.at = world:time()
    end
    peak.fall = math.max(peak.fall, -world.player:vertical_speed())
  end)
  return peak
end

function walk.check_speed_limit(world, peak)
  local limit = walk.SPEED + walk.SPEED_TOLERANCE
  world:check(peak.speed <= limit, string.format("horizontal speed reached %.2f m/s at t=%.2f (limit %.2f)", peak.speed, peak.at, limit))
  world:check(peak.fall <= walk.MAX_FALL_SPEED, string.format("fell at %.1f m/s (limit %.1f), through the ground or off a cliff", peak.fall, walk.MAX_FALL_SPEED))
end

function walk.check_standing(world, what)
  local altitude = world.player:altitude()
  world:check(world.player:on_ground(), what .. ": on ground")
  world:check(math.abs(altitude - walk.STANDING_ALTITUDE) <= walk.ALTITUDE_TOLERANCE, string.format("%s: standing at altitude %.3f m (expected %.2f)", what, altitude, walk.STANDING_ALTITUDE))
end

return walk
