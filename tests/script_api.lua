local world = ...
local player = world.player

local STANDARD_GLOBALS = {
  _G = true,
  _VERSION = true,
  assert = true,
  collectgarbage = true,
  coroutine = true,
  dofile = true,
  error = true,
  getmetatable = true,
  ipairs = true,
  load = true,
  loadfile = true,
  math = true,
  next = true,
  package = true,
  pairs = true,
  pcall = true,
  rawequal = true,
  rawget = true,
  rawlen = true,
  rawset = true,
  require = true,
  select = true,
  setmetatable = true,
  string = true,
  table = true,
  tonumber = true,
  tostring = true,
  type = true,
  utf8 = true,
  xpcall = true,
}

for name in pairs(_G) do
  world:check(STANDARD_GLOBALS[name], string.format("unexpected global '%s'", tostring(name)))
end
world:check(type(world) == "table" and type(player) == "table", "the script receives the world and its player")

local ok, message = pcall(world.frames, 1)
world:check(not ok and string.find(message, "table expected", 1, true), "calling a method without its object is an error")
ok = pcall(player.hold, player, "sideways")
world:check(not ok, "unknown keys are an error")

world:check(math.abs(world:timestep() - 0.016) < 1e-6, "default timestep is 0.016 s")
world:timestep(0.02)
world:worldgen("flat")
world:wait(1)
world:check(world.player:mode() == "fly", "the player starts flying")
world:check(math.abs(world:time() - 1) < 1e-4, string.format("waited 1 s, clock reads %.4f s", world:time()))
ok = pcall(world.worldgen, world, "terrain")
world:check(not ok, "worldgen cannot change after the first frame")

local yaw, pitch = player:turn_rate()
world:check(yaw == 0 and pitch == 0, "turn rate starts at rest")
player:turn(90, 0, 0.5)
yaw, pitch = player:turn_rate()
world:check(yaw == 0 and pitch == 0, "turn restores the previous turn rate")

player:mode("walk")
world:wait(3)
world:check(player:on_ground(), "landed in walk mode")
world:check(math.abs(player:speed()) < 1e-3 and math.abs(player:vertical_speed()) < 1e-3, "at rest after landing")

player:hold("fwd")
player:look(0.25, -0.5)
world:frames(30, 0.016)
player:release("fwd")
world:frames(30, 0.016)
world:check(player:traveled() > 0, "recorder-form frames advance the player")
world:check(player:material(3) == 3, "material slot is set and read back")
