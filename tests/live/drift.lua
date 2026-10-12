local walk = require("lib.walk")

-- The nodes around the camera are drawn where a fresh search from the camera puts them, however far the camera has
-- flown since the set it draws from was last searched afresh.
local CLIMB_SECONDS = 2
local LEGS = 6
local LEG_DISTANCE = 1.0
local RADIUS = 2.0
local MOST_DRIFT = 1e-3

return function(world)
  world:live()
  world:mode("fly")
  world:press(CLIMB_SECONDS, "up")
  local worst = 0
  local drifts = {}
  for leg = 1, LEGS do
    world:press(LEG_DISTANCE / walk.FLY_SPEED, "fwd")
    local drift = world:frame_drift(RADIUS)
    drifts[leg] = string.format("%.2g", drift)
    worst = math.max(worst, drift)
  end
  assert(worst < MOST_DRIFT, string.format("nodes drawn up to %.3g from where they are, after each unit flown: %s", worst, table.concat(drifts, " ")))
end
