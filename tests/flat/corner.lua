local walk = require("lib.walk")

local WALL_BLOCKS = 2
local APPROACH_SECONDS = 1.5
local PUSH_SECONDS = 2
local MAX_PUSH_TRAVEL_METERS = 0.05
local MAX_CAMERA_ACCELERATION = 1

return function(world)
  world:worldgen("plane")
  walk.spawn(world)
  walk.build_corner(world, WALL_BLOCKS)
  walk.check_standing(world, "back on the floor")

  local corner_yaw = math.deg(math.atan(walk.WALL_HALF_WIDTH, walk.WALL_DISTANCE))
  world:look(corner_yaw, 0)
  world:hold("fwd")
  world:wait(APPROACH_SECONDS)
  local start = world:traveled()
  local shake = 0
  world:on_step(function()
    shake = math.max(shake, world:camera_vertical_acceleration())
  end)
  world:wait(PUSH_SECONDS)
  world:release("fwd")
  world:on_step(nil)

  local pushed = world:traveled() - start
  assert(pushed <= MAX_PUSH_TRAVEL_METERS, string.format("moved %.3f m while pushed into the corner for %.1f s", pushed, PUSH_SECONDS))
  assert(shake <= MAX_CAMERA_ACCELERATION, string.format("camera shook at %.2f m/s^2 in the corner", shake))
  walk.check_standing(world, "in the corner")
end
