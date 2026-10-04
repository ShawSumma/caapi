local walk = require("lib.walk")

local LEG_SECONDS = 3
local MIN_WALKED_FRACTION = 0.95

return function(world)
  world:worldgen("flat")
  walk.spawn(world)
  walk.check_standing(world, "after landing")

  local peak = walk.track_horizontal_speed(world)
  for _, heading in ipairs({ 0, 90, 180, 270 }) do
    local start = world:traveled()
    world:press(LEG_SECONDS, "fwd")
    world:wait(0.5)
    local walked = world:traveled() - start
    local free = walk.SPEED * LEG_SECONDS
    assert(walked >= MIN_WALKED_FRACTION * free, string.format("heading %d: walked %.2f m of %.1f m", heading, walked, free))
    walk.check_standing(world, string.format("heading %d", heading))
    world:turn(90, 0, 0.5)
  end

  world:press(LEG_SECONDS, "fwd", "jump")
  world:wait(1)
  walk.check_speed_limit(peak)
  walk.check_standing(world, "after hopping")
end
