local NOCLIP_SPEED = 0.6
local UP_DEGREES = 89
local RISE = 0.7
local AHEAD = 2.0
local LOOK_DOWN_DEGREES = 25

-- Over the ground and well along it, looking out across it; any higher and the ground shrinks to a disc below.
return function(world)
  world:mode("noclip")
  world:press(AHEAD / NOCLIP_SPEED, "fwd")
  world:look(0, -UP_DEGREES)
  world:press(RISE / NOCLIP_SPEED, "fwd")
  world:look(0, UP_DEGREES + LOOK_DOWN_DEGREES)
  world:step()
end
