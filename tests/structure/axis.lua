local SEED = 3
local HEIGHTS = { 5, 40, 80, 120, 160, 200 }

return function(world)
  world:worldgen("structure", SEED)
  world:mode("noclip")
  for _, height in ipairs(HEIGHTS) do
    world:enter_structure(height)
    world:step()
    local target = world:target_material()
    assert(target ~= nil, string.format("%d m up the axis: no wall within reach", height))
  end
end
