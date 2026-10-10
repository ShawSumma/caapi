local sky = require("sky")

local EDGES = 2

return function(site)
  local wild = site:sky(0, "terrain", sky.wild, { route = true })
  site:open_sky(wild, EDGES)
end
