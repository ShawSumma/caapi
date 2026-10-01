local world = ...
local walk = require("lib.walk")

local AIM_DOWN_DEGREES = 30
local ROW_YAWS = { -16, 0, 16 }
local WALK_SECONDS = 2.5
local MIN_WALKED_FRACTION = 0.9
local MIN_STEP_RISE = 0.5
local STEP_HEIGHT = 1.1
local VERTICAL_SPEED_TOLERANCE = 0.1

local player = world.player
world:worldgen("flat")
walk.spawn(world)
walk.check_standing(world, "before building")

player:look(0, AIM_DOWN_DEGREES)
for _, yaw in ipairs(ROW_YAWS) do
  player:look(yaw, 0)
  world:check(player:place_block(), string.format("placed step block at yaw %d", yaw))
  player:look(-yaw, 0)
end
player:look(0, -AIM_DOWN_DEGREES)

local standing = player:altitude()
local motion = { apex = standing, vertical = 0, airborne = 0 }
world:every_frame(function()
  motion.apex = math.max(motion.apex, player:altitude())
  motion.vertical = math.max(motion.vertical, math.abs(player:vertical_speed()))
  if not player:on_ground() then
    motion.airborne = motion.airborne + 1
  end
end)

local walked = walk.forward(world, WALK_SECONDS, MIN_WALKED_FRACTION)
world:wait(0.5)

local rise = motion.apex - standing
world:check(rise >= MIN_STEP_RISE and rise <= STEP_HEIGHT, string.format("stepped up %.3f m (expected a block between %.1f and %.1f m)", rise, MIN_STEP_RISE, STEP_HEIGHT))
world:check(motion.vertical <= VERTICAL_SPEED_TOLERANCE, string.format("vertical speed reached %.2f m/s while stepping", motion.vertical))
world:check(motion.airborne == 0, string.format("left the ground for %d frames while stepping", motion.airborne))
walk.check_standing(world, string.format("after walking %.1f m over the step", walked))
