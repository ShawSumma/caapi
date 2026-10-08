local climb = require("lib.climb")
local walk = require("lib.walk")

local ENTRY_STOPS = 2
local STOPS_PER_STORY = 7
local ROUTE_STORIES = 2
local MIN_CLIMB = 0.25
local STREET = {
  basalt = true,
  white_brick = true,
}

return function(world)
  world:worldgen("structure", "city")
  walk.spawn(world)
  world:look(0, walk.STRAIGHT_DOWN_DEGREES)
  assert(STREET[world:target_material()], string.format("spawned on %s instead of the street", tostring(world:target_material())))
  world:look(0, -walk.STRAIGHT_DOWN_DEGREES)
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  local ground = world:altitude()
  local reached = climb.follow(world, math.huge)
  world:wait(walk.SETTLE_SECONDS)
  assert(reached == ENTRY_STOPS + ROUTE_STORIES * STOPS_PER_STORY, string.format("reached %d stops from the street up the stairs", reached))
  assert(world:is_on_ground(), "standing upstairs")
  assert(world:altitude() - ground >= MIN_CLIMB, string.format("climbed only %.3f", world:altitude() - ground))
end
