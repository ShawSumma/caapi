local walk = require("lib.walk")

local WALL_BLOCKS = 2
local ARRIVAL_MARGIN_SECONDS = 0.5
local PUSH_SECONDS = 2
local MAX_PUSH_TRAVEL = 0.0025
local MAX_CAMERA_ACCELERATION = 0.05

return function(world)
  world:worldgen("plane")
  walk.spawn(world)
  walk.build_corner(world, WALL_BLOCKS)
  walk.check_standing(world, "back on the floor")

  local corner_yaw = math.deg(math.atan(walk.WALL_HALF_WIDTH, walk.WALL_DISTANCE))
  world:look(corner_yaw, 0)
  world:hold("fwd")
  world:wait(math.sqrt(walk.WALL_DISTANCE ^ 2 + walk.WALL_HALF_WIDTH ^ 2) / walk.SPEED + ARRIVAL_MARGIN_SECONDS)
  local start = world:traveled()
  local shake = 0
  world:on_step(function()
    shake = math.max(shake, world:camera_vertical_acceleration())
  end)
  world:wait(PUSH_SECONDS)
  world:release("fwd")
  world:on_step(nil)

  local pushed = world:traveled() - start
  assert(pushed <= MAX_PUSH_TRAVEL, string.format("moved %.4f while pushed into the corner for %.1f s", pushed, PUSH_SECONDS))
  assert(shake <= MAX_CAMERA_ACCELERATION, string.format("camera shook at %.4f/s^2 in the corner", shake))
  walk.check_standing(world, "in the corner")
end
