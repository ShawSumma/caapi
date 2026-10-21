local walk = require("lib.walk")

local BARK = "oak_wood"
local TOP_ALTITUDE = 3.2
local CLIMB = 0.1
local NUDGE = 0.01
local MOST_NUDGES = 200

-- Up the trunk of the tree by the terrain world's spawn, keeping in reach of its bark, past where any tree drawn once
-- would end: it rises one segment at a time without end.
local function approach(world)
  local nudges = 0
  while world:target_material() ~= BARK and nudges < MOST_NUDGES do
    world:press(NUDGE / walk.NOCLIP_SPEED, "fwd")
    nudges = nudges + 1
  end
  assert(world:target_material() == BARK, string.format("no bark ahead at altitude %.3f, facing %s", world:altitude(), tostring(world:target_material())))
end

return function(world)
  world:worldgen("terrain")
  world:mode("noclip")
  approach(world)
  while world:altitude() < TOP_ALTITUDE do
    world:press(CLIMB / walk.NOCLIP_SPEED, "up")
    approach(world)
  end
end
