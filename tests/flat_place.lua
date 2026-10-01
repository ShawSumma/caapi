local world = ...
local walk = require("lib.walk")

local STRAIGHT_DOWN_DEGREES = 89
local AHEAD_DEGREES = 30

local player = world.player
world:worldgen("flat")
walk.spawn(world)

player:look(0, STRAIGHT_DOWN_DEGREES)
world:check(not player:place_block(), "placing a block where the player stands is refused")
world:wait(0.5)
walk.check_standing(world, "after the refused placement")
player:look(0, AHEAD_DEGREES - STRAIGHT_DOWN_DEGREES)
world:check(player:place_block(), "placing a block ahead succeeds")
world:wait(0.5)
walk.check_standing(world, "after placing ahead")
