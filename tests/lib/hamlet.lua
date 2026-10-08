local hut = require("hut")

local HUTS = 5

return function(site)
  local corner = site
  for _ = 1, HUTS do
    hut(corner)
    corner = corner:forward(1):right()
  end
end
