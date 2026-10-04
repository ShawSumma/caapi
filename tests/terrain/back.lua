local walk = require("lib.walk")

local HEADING_DEGREES = 180
local MIN_WALKED_FRACTION = 0.7

return walk.across_terrain(HEADING_DEGREES, MIN_WALKED_FRACTION)
