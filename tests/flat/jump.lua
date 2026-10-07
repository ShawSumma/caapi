local walk = require("lib.walk")

local IDEAL_RISE = 0.085
local MIN_RISE_FRACTION = 0.97
local MAX_RISE_FRACTION = 1.001

return function(world)
  world:worldgen("plane")
  walk.spawn(world)
  walk.check_standing(world, "before jumping")

  local standing = world:altitude()
  local apex = standing
  local drift = 0
  world:on_step(function()
    apex = math.max(apex, world:altitude())
    drift = math.max(drift, world:horizontal_speed())
  end)
  world:press(0.1, "up")
  world:wait(1.5)

  local rise = apex - standing
  assert(rise >= MIN_RISE_FRACTION * IDEAL_RISE and rise <= MAX_RISE_FRACTION * IDEAL_RISE, string.format("standing jump rose %.5f (ideal %.5f)", rise, IDEAL_RISE))
  assert(drift < walk.SPEED_TOLERANCE, string.format("standing jump drifted at %.5f", drift))
  walk.check_standing(world, "after landing")
end
