local HALF = 6
local STRIPE_HALF = 3
local DECK = 2
local SUPPORT_SPACING = 6
local ROUTE_STOP_CELLS = 12
local ROUTE_STOPS = 5
local ROUTE_LANE = 0.5

return function(road)
  local below, above = road:column()
  local width = { -HALF, HALF - 1 }
  local posts = { every = SUPPORT_SPACING, from = 0, span = 1 }
  road:paint("air", { x = width, y = { DECK, above } })
  road:paint("grey_brick", { x = width, y = { 0, DECK - 1 } })
  road:paint("white_brick", { x = { -STRIPE_HALF, STRIPE_HALF - 1 }, y = { DECK - 1, DECK - 1 } })
  road:fill("wood_planks", { x = width, y = { -1, -1 } }, posts)
  road:fill("wood_planks", { x = { -HALF, -HALF }, y = { below, -1 } }, posts)
  road:fill("wood_planks", { x = { HALF - 1, HALF - 1 }, y = { below, -1 } }, posts)
  for stop = 0, ROUTE_STOPS - 1 do
    road:stop(ROUTE_LANE, DECK, 0.5 + stop * ROUTE_STOP_CELLS)
  end
end
