local sky = require("sky")

local EDGES = 2

return function(site)
  local backrooms = site:sky(0, "flat", sky.backrooms, { route = true })
  site:open_sky(backrooms, EDGES)
end
