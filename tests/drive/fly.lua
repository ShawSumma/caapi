local LOAD_FRAMES = 300
local FLY_FRAMES = 180

return function(drive)
  drive:frames(LOAD_FRAMES)
  drive:summary("loading")
  drive:tap("n")
  drive:hold("w")
  drive:log(true)
  drive:frames(FLY_FRAMES)
  drive:log(false)
  drive:release("w")
  drive:summary("flying forward in noclip")
end
