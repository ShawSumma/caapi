local walk = require("lib.walk")

local WALL_BLOCKS = 2
local LOWER_BLOCK_DEGREES = 18
local MAX_BREAKS = 4
local WALK_SECONDS = 2
local MIN_PAST_WALL_METERS = 1

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

  local start = world:traveled()
  world:press(WALK_SECONDS, "fwd")
  local walked = world:traveled() - start
  assert(walked >= walk.WALL_DISTANCE + MIN_PAST_WALL_METERS, string.format("walked %.2f m, so the body did not pass the 1x2 hole", walked))
  walk.check_standing(world, "past the hole")
end
