local HALF = 6
local DECK = 2
local PARAPET = 1
local INNER_HALF = HALF - 1
local PIER_HALF = 2
local PIER_EDGES = 8
local CROWN = -2
local DASHES = { every = 8, from = 2, span = 4 }
local ROUTE_STOP_CELLS = 12
local ROUTE_STOPS = 5
local ROUTE_LANE = 0
local PALETTE = {
  surface = "basalt",
  stripe = "white_brick",
  deck = "grey_brick",
  parapet = "concrete",
  masonry = "grey_brick",
  ring = "limestone",
}

local function soffits(edge, below)
  local half = edge / 2 - PIER_HALF
  local rise = CROWN - below
  local heights = {}
  for offset = PIER_HALF, edge - PIER_HALF - 1 do
    local from_middle = math.abs(offset + 0.5 - edge / 2)
    local sag = rise * (1 - math.sqrt(1 - (from_middle / half) ^ 2))
    heights[offset] = CROWN - math.floor(sag + 0.5)
  end
  return heights
end

local function arch_rows(edge, below)
  local heights = soffits(edge, below)
  local rows = {}
  for offset = PIER_HALF, edge - PIER_HALF - 1 do
    local inner = offset + 1
    if offset + 0.5 > edge / 2 then
      inner = offset - 1
    end
    local soffit = heights[offset]
    local row = { from = offset, span = 1, soffit = soffit, ring = math.max(soffit, heights[inner]) }
    local last = rows[#rows]
    if last and last.soffit == row.soffit and last.ring == row.ring then
      last.span = last.span + 1
    else
      rows[#rows + 1] = row
    end
  end
  return rows
end

local function arches(road, below)
  local edge = road:edge_cells()
  local width = { -INNER_HALF, INNER_HALF - 1 }
  for _, row in ipairs(arch_rows(edge, below)) do
    local rhythm = { every = edge, from = row.from, span = row.span }
    road:fill(PALETTE.masonry, { x = width, y = { row.soffit, -1 } }, rhythm)
    road:fill(PALETTE.ring, { x = width, y = { row.soffit, row.ring } }, rhythm)
  end
end

local function pier(site)
  local depth = PIER_EDGES * site:edge_cells()
  site:pitch_down():fill(PALETTE.masonry, { x = { -INNER_HALF, INNER_HALF - 1 }, y = { -PIER_HALF, PIER_HALF - 1 }, z = { 0, depth - 1 } })
  assert(site:forward(1):place(pier), "the next pier is behind the road's piers")
end

return function(road)
  local below, above = road:column()
  local width = { -HALF, HALF - 1 }
  local lanes = { -INNER_HALF, INNER_HALF - 1 }
  road:paint("air", { x = width, y = { DECK, above } })
  road:paint(PALETTE.deck, { x = width, y = { 0, DECK - 1 } })
  road:paint(PALETTE.surface, { x = lanes, y = { DECK - 1, DECK - 1 } })
  road:paint(PALETTE.stripe, { x = { -1, 0 }, y = { DECK - 1, DECK - 1 } }, DASHES)
  road:paint(PALETTE.parapet, { x = { -HALF, -HALF }, y = { DECK - 1, DECK + PARAPET - 1 } })
  road:paint(PALETTE.parapet, { x = { HALF - 1, HALF - 1 }, y = { DECK - 1, DECK + PARAPET - 1 } })
  arches(road, below)
  road:place(pier)
  road:left():left():forward(1):place(pier)
  for stop = 0, ROUTE_STOPS - 1 do
    road:stop(ROUTE_LANE, DECK, 0.5 + stop * ROUTE_STOP_CELLS)
  end
end
