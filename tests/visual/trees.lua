local RISE_SECONDS = 1
local FORWARD_SECONDS = 5
local LOOK_DOWN_DEGREES = 20

return function(world)
  world:mode("fly")
  world:press(RISE_SECONDS, "up")
  world:press(FORWARD_SECONDS, "fwd")
  world:look(0, LOOK_DOWN_DEGREES)
  world:step()
end
