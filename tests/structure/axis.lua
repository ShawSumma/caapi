local walk = require("lib.walk")

local HEIGHTS = { 0.25, 1, 2, 3 }

return function(world)
  world:worldgen("structure", "tower")
  world:mode("noclip")
  for _, height in ipairs(HEIGHTS) do
    world:enter_structure(height)
    world:look(0, walk.STRAIGHT_DOWN_DEGREES)
    world:step()
    local below = world:target_material()
    assert(below ~= nil, string.format("%.2f up the axis: no floor within reach below", height))
    world:look(0, -walk.STRAIGHT_DOWN_DEGREES)
  end
end
