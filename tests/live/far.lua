local walk = require("lib.walk")

-- Far from the root everything is still drawn and stands where it should: flying level keeps the altitude, the
-- ground stays loaded right below, and a ray straight down still hits it.
local CLIMB_SECONDS = 2
local LEGS = 8
local LEG_DISTANCE = 4.0
local ALTITUDE_DRIFT = 0.1

return function(world)
  world:live()
  world:mode("fly")
  world:press(CLIMB_SECONDS, "up")
  local start = world:altitude()
  for leg = 1, LEGS do
    world:press(LEG_DISTANCE / walk.FLY_SPEED, "fwd")
    local altitude = world:altitude()
    local fresh, generating, dropped, missing = world:unloaded_within(0.5)
    world:look(0, walk.STRAIGHT_DOWN_DEGREES)
    local below = world:target_material()
    world:look(0, -walk.STRAIGHT_DOWN_DEGREES)
    local what = string.format("after %.0f units: altitude %.3f from %.3f, %d fresh %d generating %d nodes missing, %s below", leg * LEG_DISTANCE, altitude, start, fresh, generating, missing, tostring(below))
    assert(math.abs(altitude - start) < ALTITUDE_DRIFT, what)
    assert(below ~= nil, what)
  end
end
