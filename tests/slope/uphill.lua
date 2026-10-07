local walk = require("lib.walk")

local TILT_DEGREES = 25
local WALK_SECONDS = 8
local MIN_WALKED_FRACTION = 0.8
local MIN_CLIMB_FRACTION = 0.4

local across = walk.across_slope(TILT_DEGREES, 0, WALK_SECONDS, MIN_WALKED_FRACTION)

return function(world)
  local walked, climbed = across(world)
  local ideal = walked * math.sin(math.rad(TILT_DEGREES))
  assert(climbed >= MIN_CLIMB_FRACTION * ideal, string.format("climbed %.4f walking %.4f up a %d degree slope", climbed, walked, TILT_DEGREES))
end
