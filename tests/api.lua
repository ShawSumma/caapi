local DEFAULT_TIMESTEP = 0.016
local CHOSEN_TIMESTEP = 0.02
local TIMESTEP_TOLERANCE = 1e-6
local CLOCK_TOLERANCE = 1e-4
local REST_TOLERANCE = 5e-5

return function(world)
  local is_unbound_call_accepted, unbound_message = pcall(world.wait, 1)
  assert(not is_unbound_call_accepted and string.find(unbound_message, "table expected", 1, true) ~= nil, "calling a method without its object is an error")
  assert(not pcall(world.hold, world, "sideways"), "unknown keys are an error")
  assert(not pcall(world.mode, world, "swim"), "unknown modes are an error")
  assert(not pcall(world.material, world, 10), "material slots past the palette are an error")

  assert(math.abs(world:timestep() - DEFAULT_TIMESTEP) < TIMESTEP_TOLERANCE, "default timestep is 0.016 s")
  world:timestep(CHOSEN_TIMESTEP)
  world:worldgen("plane")
  assert(world:mode() == "walk" and world:is_on_ground(), "the player starts walking, standing on the ground")
  world:wait(1)
  assert(math.abs(world:time() - 1) < CLOCK_TOLERANCE, string.format("waited 1 s, clock reads %.4f s", world:time()))
  world:step(CHOSEN_TIMESTEP / 2)
  assert(math.abs(world:time() - 1 - CHOSEN_TIMESTEP / 2) < CLOCK_TOLERANCE, string.format("one half step, clock reads %.4f s", world:time()))
  assert(not pcall(world.worldgen, world, "terrain"), "worldgen cannot change after the first step")
  assert(not pcall(world.wait, world, 1, 0), "a zero timestep is an error")

  local steps = 0
  world:on_step(function()
    steps = steps + 1
    assert(not pcall(world.wait, world, 1), "a step hook cannot advance time")
  end)
  world:wait(0.1)
  assert(steps == 5, string.format("the step hook ran %d times in 5 steps", steps))
  world:on_step(nil)
  world:wait(0.1)
  assert(steps == 5, "a removed step hook does not run")

  local rest_yaw, rest_pitch = world:turn_rate()
  assert(rest_yaw == 0 and rest_pitch == 0, "turn rate starts at rest")
  world:turn(90, 0, 0.5)
  local turned_yaw, turned_pitch = world:turn_rate()
  assert(turned_yaw == 0 and turned_pitch == 0, "turn restores the previous turn rate")

  world:wait(3)
  assert(world:is_on_ground(), "standing after turning")
  assert(math.abs(world:speed()) < REST_TOLERANCE and math.abs(world:vertical_speed()) < REST_TOLERANCE, "at rest when no key is held")

  world:hold("fwd")
  world:look(0.25, -0.5)
  world:wait(0.48, DEFAULT_TIMESTEP)
  world:release("fwd")
  world:wait(0.48, DEFAULT_TIMESTEP)
  assert(world:traveled() > 0, "holding fwd moves the player")
  assert(world:material(3) == 3, "material slot is set and read back")
end
