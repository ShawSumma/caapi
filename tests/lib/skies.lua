local sky = require("sky")

return function(site)
  local city = site:sky(0, "flat", sky.city, { route = true })
  site:open_sky(city)
end
