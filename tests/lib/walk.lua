-- Scenario pieces shared by the walking tests.
local walk = {}

walk.SPEED = 4 -- m/s, CharacterConfigRaw.maxGroundSpeed

-- Spawn hovers in fly mode, switches to walk, and lands.
function walk.spawn()
  wait(1.92)
  mode("walk")
  wait(3.84)
  check(on_ground(), "landed after switching to walk")
end

-- Holds forward for `seconds`; the distance covered must be at least half
-- of an unobstructed walk (stairs cost time, walls should not stop it).
function walk.forward(seconds)
  local start = traveled()
  press(seconds, "fwd")
  local walked = traveled() - start
  local free = walk.SPEED * seconds
  check(walked >= 0.5 * free,
    string.format("walked %.1f m of an unobstructed %.1f m", walked, free))
end

-- Starts recording the peak horizontal speed (m/s) and when it happened.
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

-- Jumping must not be a way to outrun walking: air control and landings
-- may add some speed, but repeated hops must not keep compounding it.
walk.MAX_HOP_SPEED = 2 * walk.SPEED -- m/s

function walk.check_hop_speed(motion)
  check(motion.max_hspeed <= walk.MAX_HOP_SPEED,
    string.format("horizontal speed reached %.1f m/s at t=%.2f (limit %.1f)",
      motion.max_hspeed, motion.at, walk.MAX_HOP_SPEED))
end

return walk
