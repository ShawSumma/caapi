local world = ...
local walk = require("lib.walk")

local JUMP_SPEED = 9
local GRAVITY = 32
local IDEAL_RISE = JUMP_SPEED * JUMP_SPEED / (2 * GRAVITY)
local MIN_RISE_FRACTION = 0.9

local player = world.player
world:worldgen("flat")
walk.spawn(world)
walk.check_standing(world, "before jumping")

local standing = player:altitude()
local apex = standing
local drift = 0
world:every_frame(function()
  apex = math.max(apex, player:altitude())
  drift = math.max(drift, player:horizontal_speed())
end)
player:press(0.1, "jump")
world:wait(1.5)

local rise = apex - standing
world:check(rise >= MIN_RISE_FRACTION * IDEAL_RISE and rise <= IDEAL_RISE, string.format("standing jump rose %.3f m (ideal %.3f m)", rise, IDEAL_RISE))
world:check(drift < walk.SPEED_TOLERANCE, string.format("standing jump drifted at %.3f m/s", drift))
walk.check_standing(world, "after landing")
