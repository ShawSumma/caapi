local LOAD_FRAMES = 300
local STILL_FRAMES = 30
local TURN_COUNTS = 300
local TURN_FRAMES = 60
local FLY_FRAMES = 180

return function(drive)
  drive:frames(LOAD_FRAMES)
  drive:summary("loading")
  drive:watch(true)
  drive:capture("screenshots/drivestill1.png")
  drive:frames(STILL_FRAMES)
  drive:summary("standing still")
  drive:move(TURN_COUNTS, 0, TURN_FRAMES)
  drive:summary("turning by mouse")
  drive:capture("screenshots/driveturned1.png")
  drive:frames(1)
  drive:tap("n")
  drive:hold("w")
  drive:frames(FLY_FRAMES)
  drive:release("w")
  drive:summary("flying forward in noclip")
  drive:capture("screenshots/driveflown1.png")
  drive:frames(1)
end
