local walk = require("lib.walk")

local DROP_HEIGHT = 0.3
local DROP_STEP_SECONDS = 2
local WALK_SECONDS = 2
local LONG_STEP_SECONDS = 0.5
local CLIMB_SECONDS = 4
local CLIMB_STEP_SECONDS = 0.25
local STOP_SECONDS = 0.5
local WALK_TOLERANCE = 0.001

local function walk_from_rest(world, dt)
  local start = world:traveled()
  world:hold("fwd")
  world:wait(WALK_SECONDS, dt)
  world:release("fwd")
  local walked = world:traveled() - start
  world:wait(STOP_SECONDS)
  return walked
end

return function(world)
  world:worldgen("plane")
  walk.spawn(world)
  walk.check_standing(world, "before the drop")

  world:mode("fly")
  world:press(DROP_HEIGHT / walk.FLY_SPEED, "up")
  world:step()
  world:mode("walk")
  world:step(DROP_STEP_SECONDS)
  walk.check_standing(world, string.format("after one %.1f s step falling %.2f", DROP_STEP_SECONDS, DROP_HEIGHT))

  local short = walk_from_rest(world, world:timestep())
  local long = walk_from_rest(world, LONG_STEP_SECONDS)
  assert(math.abs(long - short) <= WALK_TOLERANCE, string.format("walked %.5f in %.1f s steps and %.5f in %.3f s steps", long, LONG_STEP_SECONDS, short, world:timestep()))
  walk.check_standing(world, "after walking in long steps")

  walk.build_step(world)
  local standing = world:altitude()
  walk.climb_forward(world, CLIMB_SECONDS, CLIMB_STEP_SECONDS, function()
    return walk.is_on_step(world, standing)
  end)
  world:wait(walk.SETTLE_SECONDS)
  walk.check_on_step(world, standing, string.format("after jumping onto the step in %.2f s steps", CLIMB_STEP_SECONDS))
end
