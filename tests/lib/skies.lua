local city = require("skies.city")

local EDGES = 2

return function(site)
  local kind = site:sky(0, "flat", city, true)
  site:open_sky(kind, EDGES)
end
