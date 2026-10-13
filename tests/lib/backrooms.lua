local backrooms = require("skies.backrooms")

local EDGES = 2

return function(site)
  local kind = site:sky(0, "flat", backrooms, true)
  site:open_sky(kind, EDGES)
end
