local world = ...
local walk = require("lib.walk")

local LEG_SECONDS = 3
local MIN_WALKED_FRACTION = 0.95

local player = world.player
world:worldgen("flat")
walk.spawn(world)
walk.check_standing(world, "after landing")

local peak = walk.track_horizontal_speed(world)
for _, heading in ipairs({ 0, 90, 180, 270 }) do
  local start = player:traveled()
  player:press(LEG_SECONDS, "fwd")
  world:wait(0.5)
  local walked = player:traveled() - start
  local free = walk.SPEED * LEG_SECONDS
  world:check(walked >= MIN_WALKED_FRACTION * free, string.format("heading %d: walked %.2f m of %.1f m", heading, walked, free))
  walk.check_standing(world, string.format("heading %d", heading))
  player:turn(90, 0, 0.5)
end

player:press(LEG_SECONDS, "fwd", "jump")
world:wait(1)
walk.check_speed_limit(world, peak)
walk.check_standing(world, "after hopping")
