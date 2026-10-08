local walk = require("lib.walk")

local NOCLIP_SPEED = 0.6
local FLIGHT = 5
local SAMPLES = 10

return function(world)
  world:worldgen("structure", "city")
  world:mode("noclip")
  for sample = 1, SAMPLES do
    world:press(FLIGHT / SAMPLES / NOCLIP_SPEED, "fwd")
    world:look(0, walk.STRAIGHT_DOWN_DEGREES)
    world:step()
    local below = world:target_material()
    assert(below ~= nil and below ~= walk.GROUND, string.format("bare %s below after %.1f of %.1f", tostring(below), sample * FLIGHT / SAMPLES, FLIGHT))
    world:look(0, -walk.STRAIGHT_DOWN_DEGREES)
  end
end
