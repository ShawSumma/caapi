local walk = require("lib.walk")

local TILT_DEGREES = 25
local WALK_SECONDS = 8
local MIN_WALKED_FRACTION = 0.8

return walk.across_slope(TILT_DEGREES, 90, WALK_SECONDS, MIN_WALKED_FRACTION)
