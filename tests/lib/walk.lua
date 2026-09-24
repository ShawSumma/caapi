local walk = {}

walk.SPEED = 4
walk.MAX_HOP_SPEED = 2 * walk.SPEED
walk.MIN_WALKED_FRACTION = 0.5

function walk.spawn()
  wait(1.92)
  mode("walk")
  wait(3.84)
  check(on_ground(), "landed after switching to walk")
end

function walk.forward(seconds)
  local start = traveled()
  press(seconds, "fwd")
  local walked = traveled() - start
  local free = walk.SPEED * seconds
  check(walked >= walk.MIN_WALKED_FRACTION * free, string.format("walked %.1f m of an unobstructed %.1f m", walked, free))
end

function walk.track_motion()
  local motion = { max_hspeed = 0, at = 0 }
  every_frame(function()
    local h = horizontal_speed()
    if h > motion.max_hspeed then
      motion.max_hspeed = h
      motion.at = time()
    end
  end)
  return motion
end

function walk.check_hop_speed(motion)
  check(motion.max_hspeed <= walk.MAX_HOP_SPEED, string.format("horizontal speed reached %.1f m/s at t=%.2f (limit %.1f)", motion.max_hspeed, motion.at, walk.MAX_HOP_SPEED))
end

return walk
