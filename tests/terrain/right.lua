local walk = require("lib.walk")

local HEADING_DEGREES = 90
local MIN_WALKED_FRACTION = 0.75

return walk.across_terrain(HEADING_DEGREES, MIN_WALKED_FRACTION)
