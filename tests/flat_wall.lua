local world = ...
local walk = require("lib.walk")

local FLY_SPEED = 8
local HOVER_HEIGHT = 4
local WALL_DISTANCE = 3
local WALL_COLUMNS = { -1, 0, 1 }
local WALL_BLOCKS = 2
local STRAIGHT_DOWN_DEGREES = 89
local APPROACH_SECONDS = 0.3
local PUSH_SECONDS = 2.5
local CONTACT_SPEED_FRACTION = 0.8
local MAX_CLIMB = 0.05
local VERTICAL_SPEED_TOLERANCE = 0.1

local player = world.player
world:worldgen("flat")
walk.spawn(world)
walk.check_standing(world, "before building")

local function fly(meters, key)
  player:press(meters / FLY_SPEED, key)
end

local function strafe(meters)
  if meters > 0 then
    fly(meters, "right")
  elseif meters < 0 then
    fly(-meters, "left")
  end
end

player:mode("fly")
fly(HOVER_HEIGHT, "up")
fly(WALL_DISTANCE, "fwd")
player:look(0, STRAIGHT_DOWN_DEGREES)
local lateral = 0
for _, column in ipairs(WALL_COLUMNS) do
  strafe(column - lateral)
  lateral = column
  for block = 1, WALL_BLOCKS do
    world:check(player:place_block(), string.format("placed wall block %d of column %d", block, column))
  end
end
strafe(-lateral)
player:look(0, -STRAIGHT_DOWN_DEGREES)
fly(WALL_DISTANCE, "back")
player:mode("walk")
world:wait(2)
walk.check_standing(world, "back on the floor")

local standing = player:altitude()
local motion = { apex = standing, vertical = 0, slowest = math.huge, pushing = false }
local peak = walk.track_horizontal_speed(world)
world:every_frame(function()
  motion.apex = math.max(motion.apex, player:altitude())
  motion.vertical = math.max(motion.vertical, math.abs(player:vertical_speed()))
  peak.speed = math.max(peak.speed, player:horizontal_speed())
  if motion.pushing then
    motion.slowest = math.min(motion.slowest, player:horizontal_speed())
  end
end)

player:hold("fwd")
world:wait(APPROACH_SECONDS)
motion.pushing = true
world:wait(PUSH_SECONDS)
player:release("fwd")

world:check(motion.slowest <= CONTACT_SPEED_FRACTION * walk.SPEED, string.format("never slowed below %.2f m/s, so the wall was not reached", motion.slowest))
world:check(motion.apex - standing <= MAX_CLIMB, string.format("climbed %.3f m up a two-block wall", motion.apex - standing))
world:check(motion.vertical <= VERTICAL_SPEED_TOLERANCE, string.format("vertical speed reached %.2f m/s against the wall", motion.vertical))
walk.check_speed_limit(world, peak)
walk.check_standing(world, "against the wall")
