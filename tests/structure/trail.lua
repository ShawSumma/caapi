local climb = require("lib.climb")
local walk = require("lib.walk")

local STOPS = 12
local MAX_STRAIGHTNESS = 0.8

local function stop_count(world)
  local count = 0
  while world:route_waypoint(count + 1) do
    count = count + 1
  end
  return count
end

return function(world)
  world:worldgen("structure", "trail")
  local built = stop_count(world)
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  local start = world:traveled()
  local reached = climb.follow(world, STOPS)
  world:wait(walk.SETTLE_SECONDS)
  assert(reached == STOPS, string.format("walked %d of %d trail stops", reached, STOPS))
  assert(stop_count(world) > built, string.format("the trail did not grow past its first %d stops as the world grew", built))
  local _, back = world:route_waypoint(1)
  local walked = world:traveled() - start
  assert(back < MAX_STRAIGHTNESS * walked, string.format("the trail ran straight: %.3f back to its start after walking %.3f", back, walked))
  world:look(0, walk.STRAIGHT_DOWN_DEGREES)
  assert(world:target_material() == "gravel", string.format("standing on %s instead of the trail", tostring(world:target_material())))
end
