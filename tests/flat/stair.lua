local walk = require("lib.walk")

local WALK_SECONDS = 2.5
local MIN_WALKED_FRACTION = 0.9
local MIN_STAIR_RISE = 0.5
local STEP_HEIGHT = 1.1
local VERTICAL_SPEED_TOLERANCE = 0.1

return function(world)
  world:worldgen("flat")
  walk.spawn(world)
  walk.check_standing(world, "before building")
  walk.build_step(world)

  local standing = world:altitude()
  local motion = { apex = standing, vertical = 0, airborne = 0, previous = standing, steepest = 0 }
  world:on_step(function()
    local altitude = world:altitude()
    motion.apex = math.max(motion.apex, altitude)
    motion.steepest = math.max(motion.steepest, altitude - motion.previous)
    motion.previous = altitude
    motion.vertical = math.max(motion.vertical, math.abs(world:vertical_speed()))
    if not world:is_on_ground() then
      motion.airborne = motion.airborne + 1
    end
  end)

  local walked = walk.forward(world, WALK_SECONDS, MIN_WALKED_FRACTION)
  world:wait(0.5)

  local rise = motion.apex - standing
  assert(rise >= MIN_STAIR_RISE, string.format("rose %.3f m over the stair (expected at least %.1f m)", rise, MIN_STAIR_RISE))
  assert(motion.steepest <= STEP_HEIGHT, string.format("rose %.3f m in one step (step height %.1f m)", motion.steepest, STEP_HEIGHT))
  assert(motion.vertical <= VERTICAL_SPEED_TOLERANCE, string.format("vertical speed reached %.2f m/s while stepping up", motion.vertical))
  assert(motion.airborne == 0, string.format("left the ground for %d steps while stepping up", motion.airborne))
  walk.check_standing(world, string.format("after walking %.1f m over the stair", walked))
end
