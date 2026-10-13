local wild = require("skies.wild")

local EDGES = 2

return function(site)
  local kind = site:sky(0, "terrain", wild, true)
  site:open_sky(kind, EDGES)
end
