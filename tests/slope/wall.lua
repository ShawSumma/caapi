local walk = require("lib.walk")

local TILT_DEGREES = 25
local HEADINGS = { 0, 90, 180, 270 }
local WALL_BLOCKS = 3
local APPROACH_SECONDS = 0.5
local PUSH_SECONDS = 2.5
local CONTACT_SPEED_FRACTION = 0.8
local MAX_RISE_SPEED = 2

return function(world)
  walk.on_slope(world, TILT_DEGREES, 0)
  for _, heading in ipairs(HEADINGS) do
    if heading ~= 0 then
      world:turn(90, 0, walk.TURN_SECONDS)
    end
    walk.build_wall(world, WALL_BLOCKS)
    world:wait(2)
    assert(world:is_on_ground(), string.format("heading %d: back on the ground after building", heading))

    local motion = walk.track_motion(world)
    world:hold("fwd")
    world:wait(APPROACH_SECONDS)
    local slowest = math.huge
    world:on_step(function()
      slowest = math.min(slowest, world:horizontal_speed())
      motion.speed = math.max(motion.speed, world:horizontal_speed())
      motion.rise = math.max(motion.rise, world:vertical_speed())
      motion.fall = math.max(motion.fall, -world:vertical_speed())
      if not world:is_on_ground() then
        motion.airborne = motion.airborne + 1
      end
    end)
    world:wait(PUSH_SECONDS)
    world:release("fwd")
    world:wait(walk.SETTLE_SECONDS)
    world:on_step(nil)

    assert(slowest <= CONTACT_SPEED_FRACTION * walk.SPEED, string.format("heading %d: never slowed below %.2f m/s, so the wall was not reached", heading, slowest))
    assert(motion.rise <= MAX_RISE_SPEED, string.format("heading %d: rose at %.2f m/s against the wall", heading, motion.rise))
    assert(motion.airborne == 0, string.format("heading %d: left the ground for %d steps against the wall", heading, motion.airborne))
    walk.check_speed_limit(motion)
    assert(world:is_on_ground(), string.format("heading %d: on ground against the wall", heading))
    world:press(walk.WALL_DISTANCE / walk.SPEED, "back")
  end
end
