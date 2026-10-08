local hut = require("hut")

return function(site)
  for _, corner in ipairs(site:face()) do
    hut(corner)
  end
end
