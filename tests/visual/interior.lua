local AXIS_METERS = 2.5
local LOOK_DOWN_DEGREES = 25
local TURN_DEGREES = 110
local TURN_SECONDS = 0.016
local NOCLIP_SPEED = 12
local BACK_METERS = 2

return function(world)
  world:worldgen("structure", "tower")
  world:mode("noclip")
  world:enter_structure(AXIS_METERS)
  world:turn(TURN_DEGREES, 0, TURN_SECONDS)
  world:press(BACK_METERS / NOCLIP_SPEED, "back")
  world:look(0, LOOK_DOWN_DEGREES)
  world:step()
end
