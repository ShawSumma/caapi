local bigtree = require("bigtree")
local road = require("road")

local SKY_ODDS = 0.02
local SKIES = {
  { ground = "terrain", tile = require("skies.wild") },
  { ground = "flat", tile = require("skies.city") },
  { ground = "flat", tile = require("skies.spires") },
  { ground = "flat", tile = require("skies.backrooms") },
}
local TREE_EDGES = 1

return function(site)
  road(site)
  bigtree(site:right():forward(TREE_EDGES))
  for _, sky in ipairs(SKIES) do
    site:sky(SKY_ODDS, sky.ground, sky.tile, false)
  end
end
