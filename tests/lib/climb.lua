local walk = require("lib.walk")

local climb = {}

local REACHED_METERS = 0.8
local REACHED_RISE_METERS = 1
local MAX_STEPS_PER_WAYPOINT = 150
local WAYPOINT_LOOKAHEAD = 4
local MIN_CLIMB_METERS = 10

local function is_reached(world, index)
  local _, horizontal, rise = world:stair_waypoint(index)
  return horizontal < REACHED_METERS and math.abs(rise) < REACHED_RISE_METERS
end

local function furthest_reached(world, reached)
  local furthest = reached
  for index = reached + 1, reached + WAYPOINT_LOOKAHEAD do
    if world:stair_waypoint(index) and is_reached(world, index) then
      furthest = index
    end
  end
  return furthest
end

local function follow(world)
  local reached = 0
  local steps = 0
  world:hold("fwd")
  while world:stair_waypoint(reached + 1) do
    local furthest = furthest_reached(world, reached)
    if furthest > reached then
      reached = furthest
      steps = 0
    else
      local yaw, horizontal, rise = world:stair_waypoint(reached + 1)
      assert(steps < MAX_STEPS_PER_WAYPOINT, string.format("stuck before stair cell %d, %.2f m away and %.2f m up", reached + 1, horizontal, rise))
      world:look(yaw, 0)
      world:step()
      steps = steps + 1
    end
  end
  world:release("fwd")
  return reached
end

function climb.stairs(world)
  world:enter_stairs()
  world:wait(walk.SETTLE_SECONDS)
  assert(world:is_on_ground(), "standing at the foot of the stairs")
  local start = world:altitude()
  local motion = walk.track_motion(world)
  local reached = follow(world)
  world:wait(walk.SETTLE_SECONDS)
  assert(world:is_on_ground(), string.format("standing after climbing %d stair cells", reached))
  assert(world:altitude() - start >= MIN_CLIMB_METERS, string.format("climbed only %.1f m over %d stair cells", world:altitude() - start, reached))
  assert(motion.airborne == 0, string.format("left the ground for %d steps on the stairs", motion.airborne))
  walk.check_speed_limit(motion)
end

return climb
