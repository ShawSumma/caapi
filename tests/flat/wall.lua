local walk = require("lib.walk")

local WALL_BLOCKS = 2
local APPROACH_SECONDS = 0.3
local PUSH_SECONDS = 2.5
local CONTACT_SPEED_FRACTION = 0.8
local MAX_CLIMB = 0.0025
local VERTICAL_SPEED_TOLERANCE = 0.005

return function(world)
  world:worldgen("plane")
  walk.spawn(world)
  walk.check_standing(world, "before building")
  walk.build_wall(world, WALL_BLOCKS)
  world:wait(2)
  walk.check_standing(world, "back on the floor")

  local standing = world:altitude()
  local motion = walk.track_motion(world)
  local start = world:traveled()
  world:hold("fwd")
  world:wait(APPROACH_SECONDS + PUSH_SECONDS)
  world:release("fwd")
  local walked = world:traveled() - start

  local free = walk.SPEED * (APPROACH_SECONDS + PUSH_SECONDS)
  assert(walked <= CONTACT_SPEED_FRACTION * free, string.format("walked %.4f of a free %.4f, so the wall was not reached", walked, free))
  assert(motion.highest - standing <= MAX_CLIMB, string.format("climbed %.4f up a two-block wall", motion.highest - standing))
  assert(motion.rise <= VERTICAL_SPEED_TOLERANCE, string.format("vertical speed reached %.4f against the wall", motion.rise))
  assert(motion.off_ground == 0, string.format("left the ground on %d steps walking into the wall", motion.off_ground))
  walk.check_speed_limit(motion)
  walk.check_standing(world, "against the wall")
end
