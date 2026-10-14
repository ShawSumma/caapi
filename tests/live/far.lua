local walk = require("lib.walk")

local CLIMB_SECONDS = 2
local LEGS = 8
local LEG_DISTANCE = 4.0
local ALTITUDE_DRIFT = 0.01
local MOST_PROBE_DEPTH = 2.0
local AWAY_FROM_TREE_DEGREES = 180

local function look_down(world)
  world:look(0, walk.STRAIGHT_DOWN_DEGREES)
  local below = world:target_material()
  world:look(0, -walk.STRAIGHT_DOWN_DEGREES)
  return below
end

-- Sinks until the ground is within reach, then rises the same number of steps back to the flight altitude.
local function ground_below(world)
  local most_steps = math.ceil(MOST_PROBE_DEPTH / (walk.NOCLIP_SPEED * world:timestep()))
  local below = look_down(world)
  local steps = 0
  world:hold("down")
  while below == nil and steps < most_steps do
    world:step()
    steps = steps + 1
    below = look_down(world)
  end
  world:release("down")
  world:hold("up")
  for _ = 1, steps do
    world:step()
  end
  world:release("up")
  return below, steps * walk.NOCLIP_SPEED * world:timestep()
end

-- Noclip, because the world may build a tower in the way and fly mode would climb its wall.
return function(world)
  world:live()
  world:look(AWAY_FROM_TREE_DEGREES, 0)
  world:mode("fly")
  world:press(CLIMB_SECONDS, "up")
  world:mode("noclip")
  local start = world:altitude()
  for leg = 1, LEGS do
    world:press(LEG_DISTANCE / walk.NOCLIP_SPEED, "fwd")
    local altitude = world:altitude()
    local fresh, generating, dropped, missing = world:unloaded_within(0.5)
    local below, depth = ground_below(world)
    local what = string.format("after %.0f units: altitude %.3f from %.3f, %d fresh %d generating %d nodes missing, %s below within %.2f", leg * LEG_DISTANCE, altitude, start, fresh, generating, missing, tostring(below), depth)
    assert(math.abs(altitude - start) < ALTITUDE_DRIFT, what)
    assert(below ~= nil, what)
  end
end
