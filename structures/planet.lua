local road = require("road")
local sky = require("sky")

local WILD_ODDS = 0.02
local CITY_ODDS = 0.02
local SPIRES_ODDS = 0.02

return function(site)
  road(site)
  site:sky(WILD_ODDS, "terrain", sky.wild)
  site:sky(CITY_ODDS, "flat", sky.city)
  site:sky(SPIRES_ODDS, "flat", sky.spires)
end
