local walk = require("lib.walk")

local FLY_SECONDS = 40
local NOCLIP_SECONDS = 30
local NOCLIP_SPEED = 0.6
local MIN_FRACTION = 0.9
local CLOSE = 0.5
-- High enough above the spawn to clear the relief along the way, so slowing down can only mean waiting on chunks.
local CLIMB_SECONDS = 3

-- Chunks still generating are only late, but ones never asked for this close to the body mean the streamer lost track.
local function check_close(world, what)
  local fresh, generating, dropped, missing, building = world:unloaded_within(CLOSE)
  assert(fresh + dropped == 0, string.format("%s: %d fresh and %d dropped chunks right around the body (%d generating, %d waiting for a building, %d nodes missing)", what, fresh, dropped, generating, building, missing))
end

-- Loads the world a budget at a time as the game does and checks that moving never waits on chunks the body needs.
return function(world)
  world:live()
  world:mode("fly")
  world:press(CLIMB_SECONDS, "up")
  for second = 1, FLY_SECONDS do
    local before = world:traveled()
    world:press(1, "fwd")
    local flown = world:traveled() - before
    assert(flown >= MIN_FRACTION * walk.FLY_SPEED, string.format("flew %.3f in second %d, %s at altitude %.3f", flown, second, world:is_loaded() and "loaded" or "not loaded", world:altitude()))
    check_close(world, string.format("flying, second %d", second))
  end
  world:mode("walk")
  world:wait(walk.LANDING_SECONDS)
  assert(world:is_loaded(), "landed where the world is loaded")
  world:mode("noclip")
  for second = 1, NOCLIP_SECONDS do
    local before = world:traveled()
    world:press(1, "fwd")
    assert(world:traveled() - before >= MIN_FRACTION * NOCLIP_SPEED, string.format("noclip moved %.3f in second %d", world:traveled() - before, second))
    check_close(world, string.format("noclip, second %d", second))
  end
end
