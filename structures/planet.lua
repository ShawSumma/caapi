local road = require("road")
local sky = require("sky")

local WILD_ODDS = 0.012
local CITY_ODDS = 0.012
local TOWERS_ODDS = 0.012

return function(site)
  road(site)
  site:sky(WILD_ODDS, "terrain", sky.wild)
  site:sky(CITY_ODDS, "flat", sky.city)
  site:sky(TOWERS_ODDS, "flat", sky.towers)
end
