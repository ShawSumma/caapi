local world = ...
local walk = require("lib.walk")

local FLY_SPEED = 8
local DROP_HEIGHT = 6
local DROP_FRAME_SECONDS = 2
local WALK_FRAME_SECONDS = 0.5
local WALK_FRAMES = 4
local STEP_FRAME_SECONDS = 0.25
local STEP_FRAMES = 10
local STOP_SECONDS = 0.5
local WALK_TOLERANCE = 0.02
local MIN_WALKED_FRACTION = 0.95
local AIM_DOWN_DEGREES = 30
local ROW_YAWS = { -16, 0, 16 }
local MIN_STEP_RISE = 0.5
local STEP_HEIGHT = 1.1

local player = world.player
world:worldgen("flat")
walk.spawn(world)
walk.check_standing(world, "before the drop")

player:mode("fly")
player:press(DROP_HEIGHT / FLY_SPEED, "up")
player:mode("walk")
world:frames(1, DROP_FRAME_SECONDS)
walk.check_standing(world, string.format("after one %.1f s frame falling %d m", DROP_FRAME_SECONDS, DROP_HEIGHT))

local function walk_from_rest(frames, dt)
  local start = player:traveled()
  player:hold("fwd")
  world:frames(frames, dt)
  player:release("fwd")
  local walked = player:traveled() - start
  world:wait(STOP_SECONDS)
  return walked
end

local seconds = WALK_FRAMES * WALK_FRAME_SECONDS
local short = walk_from_rest(math.floor(seconds / world:timestep() + 0.5), world:timestep())
local long = walk_from_rest(WALK_FRAMES, WALK_FRAME_SECONDS)
world:check(math.abs(long - short) <= WALK_TOLERANCE, string.format("walked %.3f m in %.1f s frames and %.3f m in %.3f s frames", long, WALK_FRAME_SECONDS, short, world:timestep()))
walk.check_standing(world, "after walking in long frames")

player:look(0, AIM_DOWN_DEGREES)
for _, yaw in ipairs(ROW_YAWS) do
  player:look(yaw, 0)
  world:check(player:place_block(), string.format("placed step block at yaw %d", yaw))
  player:look(-yaw, 0)
end
player:look(0, -AIM_DOWN_DEGREES)

local standing = player:altitude()
local apex = standing
world:every_frame(function()
  apex = math.max(apex, player:altitude())
end)
start = player:traveled()
player:hold("fwd")
world:frames(STEP_FRAMES, STEP_FRAME_SECONDS)
player:release("fwd")
world:frames(1, STEP_FRAME_SECONDS)
walked = player:traveled() - start
local free = walk.SPEED * STEP_FRAMES * STEP_FRAME_SECONDS
local rise = apex - standing
world:check(rise >= MIN_STEP_RISE and rise <= STEP_HEIGHT, string.format("stepped up %.3f m in %.2f s frames", rise, STEP_FRAME_SECONDS))
world:check(walked >= MIN_WALKED_FRACTION * free, string.format("walked %.2f m over the step in %.2f s frames (free %.1f m)", walked, STEP_FRAME_SECONDS, free))
walk.check_standing(world, "after stepping in long frames")
