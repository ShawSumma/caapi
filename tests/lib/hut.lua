local box = require("box")

local STORIES = 2
local TIMBER = { wall = "oak_wood", floor = "wood_planks", trim = "spruce_wood" }

return function(site)
  local tower = site:pitch_up()
  local top = STORIES * box.STORY
  box.tower(tower, top, TIMBER)
  box.door(tower)
  box.stair_route(tower, 0, top)
  tower:entrance(-box.HALF, 0, 1)
end
