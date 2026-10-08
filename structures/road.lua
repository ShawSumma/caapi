local HALF = 6
local STRIPE_HALF = 3
local DECK = 2
local SUPPORT_SPACING = 6
local ROUTE_STOP_CELLS = 12
local ROUTE_STOPS = 5
local ROUTE_LANE = 0.5

return function(site)
  local road = site:branch("along")
  local below, above = road:column()
  local width = { -HALF, HALF - 1 }
  local posts = { every = SUPPORT_SPACING, from = 0, span = 1 }
  road:paint("air", { across = width, along = { DECK, above } })
  road:paint("grey_brick", { across = width, along = { 0, DECK - 1 } })
  road:paint("white_brick", { across = { -STRIPE_HALF, STRIPE_HALF - 1 }, along = { DECK - 1, DECK - 1 } })
  road:fill("wood_planks", { across = width, along = { -1, -1 } }, posts)
  road:fill("wood_planks", { across = { -HALF, -HALF }, along = { below, -1 } }, posts)
  road:fill("wood_planks", { across = { HALF - 1, HALF - 1 }, along = { below, -1 } }, posts)
  for stop = 0, ROUTE_STOPS - 1 do
    road:stop(ROUTE_LANE, DECK, 0.5 + stop * ROUTE_STOP_CELLS)
  end
end
