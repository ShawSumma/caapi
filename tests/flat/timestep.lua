local walk = require("lib.walk")

local FLY_SPEED = 8
local DROP_HEIGHT = 6
local DROP_STEP_SECONDS = 2
local WALK_SECONDS = 2
local LONG_STEP_SECONDS = 0.5
local STAIR_SECONDS = 2.5
local STAIR_STEP_SECONDS = 0.25
local STOP_SECONDS = 0.5
local WALK_TOLERANCE = 0.02
local MIN_WALKED_FRACTION = 0.95
local MIN_STAIR_RISE = 0.5
local STEP_HEIGHT = 1.1

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
  world:worldgen("flat")
  walk.spawn(world)
  walk.check_standing(world, "before the drop")

  world:mode("fly")
  world:press(DROP_HEIGHT / FLY_SPEED, "up")
  world:mode("walk")
  world:step(DROP_STEP_SECONDS)
  walk.check_standing(world, string.format("after one %.1f s step falling %d m", DROP_STEP_SECONDS, DROP_HEIGHT))

  local short = walk_from_rest(world, world:timestep())
  local long = walk_from_rest(world, LONG_STEP_SECONDS)
  assert(math.abs(long - short) <= WALK_TOLERANCE, string.format("walked %.3f m in %.1f s steps and %.3f m in %.3f s steps", long, LONG_STEP_SECONDS, short, world:timestep()))
  walk.check_standing(world, "after walking in long steps")

  walk.build_step(world)

  local standing = world:altitude()
  local apex = standing
  world:on_step(function()
    apex = math.max(apex, world:altitude())
  end)
  local start = world:traveled()
  world:hold("fwd")
  world:wait(STAIR_SECONDS, STAIR_STEP_SECONDS)
  world:release("fwd")
  world:step(STAIR_STEP_SECONDS)
  local walked = world:traveled() - start
  local free = walk.SPEED * STAIR_SECONDS
  local rise = apex - standing
  assert(rise >= MIN_STAIR_RISE and rise <= STEP_HEIGHT, string.format("stepped up %.3f m in %.2f s steps", rise, STAIR_STEP_SECONDS))
  assert(walked >= MIN_WALKED_FRACTION * free, string.format("walked %.2f m over the stair in %.2f s steps (free %.1f m)", walked, STAIR_STEP_SECONDS, free))
  walk.check_standing(world, "after stepping up in long steps")
end
