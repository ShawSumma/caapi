local building = require("buildings.building")

local FRONT = 4
local SHOWN = {
  { type = require("buildings.brownstone"), stories = 5 },
  { type = require("buildings.tenement"), stories = 8 },
  { type = require("buildings.deco"), stories = 24 },
  { type = require("buildings.glass"), stories = 30 },
}

return function(site)
  local quarter = site
  for _, shown in ipairs(SHOWN) do
    local part = { site = quarter, x_low = building.STREET, y_low = building.STREET, x_high = building.LOT, y_high = building.LOT, front = "y_low" }
    shown.type.build({ part }, { stories = shown.stories, palette = shown.type.PALETTES[1], front = FRONT, gap = 0 })
    quarter = quarter:right()
  end
end
