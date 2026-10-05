local NOCLIP_SPEED = 12
local VIEW_HEIGHT_METERS = 110
local BACK_OUT_METERS = 25
local LOOK_UP_DEGREES = 60
local TURN_AROUND_DEGREES = 180

return function(world)
  world:worldgen("structure", "tower")
  world:mode("noclip")
  world:enter_structure(VIEW_HEIGHT_METERS)
  world:press(BACK_OUT_METERS / NOCLIP_SPEED, "fwd")
  world:look(TURN_AROUND_DEGREES, LOOK_UP_DEGREES)
  world:step()
end
