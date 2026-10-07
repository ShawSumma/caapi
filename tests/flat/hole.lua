local walk = require("lib.walk")

local WALL_BLOCKS = 2
local LOWER_BLOCK_DEGREES = 18
local MAX_BREAKS = 4
local APPROACH_SECONDS = 1
local SEARCH_SECONDS = 0.5
local THROUGH_SECONDS = 2
local FREE_SECONDS = 1
local MIN_FREE_FRACTION = 0.8

local function is_wall(material)
  return material == walk.LAYER_MATERIALS[1] or material == walk.LAYER_MATERIALS[2]
end

local function clear_ahead(world, pitch, what)
  world:look(0, pitch)
  local breaks = 0
  while is_wall(world:target_material()) and breaks < MAX_BREAKS do
    assert(world:break_block(), string.format("broke the %s block of the hole", what))
    breaks = breaks + 1
  end
  assert(breaks > 0 and not is_wall(world:target_material()), string.format("cleared the %s of the hole in %d breaks, facing %s", what, breaks, tostring(world:target_material())))
  world:look(0, -pitch)
end

return function(world)
  world:worldgen("plane")
  walk.spawn(world)
  walk.build_wall(world, WALL_BLOCKS)
  walk.check_standing(world, "back on the floor")

  clear_ahead(world, 0, "upper half")
  clear_ahead(world, LOWER_BLOCK_DEGREES, "lower half")

  world:hold("fwd")
  world:wait(APPROACH_SECONDS)
  world:press(SEARCH_SECONDS, "left")
  world:press(2 * SEARCH_SECONDS, "right")
  world:wait(THROUGH_SECONDS)
  world:release("fwd")
  walk.check_standing(world, "after squeezing through the hole")
  walk.forward(world, FREE_SECONDS, MIN_FREE_FRACTION)
end
