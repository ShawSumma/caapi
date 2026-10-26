local walk = require("lib.walk")

local PLATFORMS = { wood_planks = true, marble = true, grey_brick = true }

return function(world)
  world:worldgen("structure", "lattice")
  walk.spawn(world)
  local standing = world:altitude()
  assert(standing > 0, string.format("standing at altitude %.4f, not below the plane gravity points away from", standing))
  world:look(0, walk.STRAIGHT_DOWN_DEGREES)
  local below = world:target_material()
  assert(PLATFORMS[below] ~= nil, string.format("standing on %s instead of the root platform", tostring(below)))
  world:press(world:timestep(), "up")
  world:step()
  assert(not world:is_on_ground(), "jumped off the platform")
  assert(world:altitude() > standing, string.format("jumped to %.4f from %.4f, not away from the platform", world:altitude(), standing))
  world:wait(walk.LANDING_SECONDS)
  assert(world:is_on_ground(), "landed back on the platform")
  assert(math.abs(world:altitude() - standing) < walk.ALTITUDE_TOLERANCE, string.format("landed at %.4f instead of %.4f", world:altitude(), standing))
end
