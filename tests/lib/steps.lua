local STEPS = 8
local DEPTH = 2
local WIDTH = { -1, 0 }
local LANE = 0
local APPROACH = -1.5

return function(site)
  site:stop(LANE, 0, APPROACH)
  for step = 1, STEPS do
    local near = (step - 1) * DEPTH
    site:paint("wood_planks", { x = WIDTH, y = { 0, step - 1 }, z = { near, near + DEPTH - 1 } })
    site:stop(LANE, step, near + DEPTH / 2)
  end
end
