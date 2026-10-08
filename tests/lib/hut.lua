local box = require("box")

local STORIES = 2
local TIMBER = { wall = "oak_wood", floor = "wood_planks", trim = "spruce_wood" }

return function(site)
  local top = STORIES * box.STORY
  box.tower(site, top, TIMBER)
  box.door(site)
  box.stair_route(site, 0, top)
  site:entrance(-box.HALF, 0, 1)
end
