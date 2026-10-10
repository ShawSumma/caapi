local sky = require("sky")

local EDGES = 2

return function(site)
  local city = site:sky(0, "flat", sky.city, { route = true })
  site:open_sky(city, EDGES)
end
