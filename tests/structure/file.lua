local climb = require("lib.climb")

local STEPS = "tests/lib/steps.lua"
local REFUSED = {
  { path = "tests/lib/broken.lua", reason = "unknown material" },
  { path = "tests/lib/wide.lua", reason = "leaves the site's column" },
}
local MIN_CLIMB = 0.2

return function(world)
  for _, refused in ipairs(REFUSED) do
    local is_built, message = pcall(world.worldgen, world, "structure", refused.path)
    assert(not is_built, string.format("%s is refused", refused.path))
    assert(string.find(message, refused.reason, 1, true), string.format("%s is refused for %s: %s", refused.path, refused.reason, tostring(message)))
  end
  world:worldgen("structure", STEPS)
  climb.route(world, MIN_CLIMB)
end
