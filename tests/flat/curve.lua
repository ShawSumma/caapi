local walk = require("lib.walk")

local ALTITUDE = 1
local FALL_SECONDS = 0.25
local MIN_FRACTION = 0.75
local MAX_FRACTION = 1.25

local function rise_to(world, altitude)
  world:mode("fly")
  world:press((altitude - world:altitude()) / walk.FLY_SPEED, "up")
  world:step()
end

local function fall(world, key)
  if key then
    world:hold(key)
    world:step()
  end
  world:mode("walk")
  if key then
    world:release(key)
  end
  local altitude = world:altitude()
  local speed = world:horizontal_speed()
  world:wait(FALL_SECONDS)
  return world:vertical_speed(), speed, altitude
end

return function(world)
  world:worldgen("plane")
  walk.spawn(world)
  rise_to(world, ALTITUDE)
  local still = fall(world)
  rise_to(world, ALTITUDE)
  local moving, speed, altitude = fall(world, "fwd")
  local doubled = math.exp(2 * altitude)
  local predicted = speed ^ 2 * (doubled - 1) / (doubled + 1) * FALL_SECONDS
  local gained = moving - still
  assert(gained >= MIN_FRACTION * predicted and gained <= MAX_FRACTION * predicted, string.format("moving at %.3f, %.3f up: the fall was %.4f slower than from rest, a geodesic predicts %.4f", speed, altitude, gained, predicted))
end
