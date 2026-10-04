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

local function fly(world, meters, key)
  world:press(meters / FLY_SPEED, key)
end

local function strafe(world, meters)
  if meters > 0 then
    fly(world, meters, "right")
  elseif meters < 0 then
    fly(world, -meters, "left")
  end
end

local function build_wall(world)
  world:mode("fly")
  fly(world, HOVER_HEIGHT, "up")
  fly(world, WALL_DISTANCE, "fwd")
  world:look(0, STRAIGHT_DOWN_DEGREES)
  local previous = 0
  for _, column in ipairs(WALL_COLUMNS) do
    strafe(world, column - previous)
    previous = column
    for block = 1, WALL_BLOCKS do
      assert(world:place_block(), string.format("placed wall block %d of column %d", block, column))
    end
  end
  strafe(world, -previous)
  world:look(0, -STRAIGHT_DOWN_DEGREES)
  fly(world, WALL_DISTANCE, "back")
  world:mode("walk")
end

return function(world)
  world:worldgen("flat")
  walk.spawn(world)
  walk.check_standing(world, "before building")
  build_wall(world)
  world:wait(2)
  walk.check_standing(world, "back on the floor")

  local standing = world:altitude()
  local motion = { apex = standing, vertical = 0, slowest = math.huge, pushing = false }
  local peak = walk.track_horizontal_speed(world)
  world:on_step(function()
    motion.apex = math.max(motion.apex, world:altitude())
    motion.vertical = math.max(motion.vertical, math.abs(world:vertical_speed()))
    peak.speed = math.max(peak.speed, world:horizontal_speed())
    if motion.pushing then
      motion.slowest = math.min(motion.slowest, world:horizontal_speed())
    end
  end)

  world:hold("fwd")
  world:wait(APPROACH_SECONDS)
  motion.pushing = true
  world:wait(PUSH_SECONDS)
  world:release("fwd")

  assert(motion.slowest <= CONTACT_SPEED_FRACTION * walk.SPEED, string.format("never slowed below %.2f m/s, so the wall was not reached", motion.slowest))
  assert(motion.apex - standing <= MAX_CLIMB, string.format("climbed %.3f m up a two-block wall", motion.apex - standing))
  assert(motion.vertical <= VERTICAL_SPEED_TOLERANCE, string.format("vertical speed reached %.2f m/s against the wall", motion.vertical))
  walk.check_speed_limit(peak)
  walk.check_standing(world, "against the wall")
end
