local kit = require("buildings.kit")

local TYPES = {
  brownstone = require("buildings.brownstone"),
  tenement = require("buildings.tenement"),
  deco = require("buildings.deco"),
  glass = require("buildings.glass"),
}

local STREET = kit.STREET
local JOINED = kit.JOINED
local BOUNDARY = kit.LOT

local AROUND = 4
local SIDES = 5
local DROPPED_STREET = 0.5
local ISLAND = 0.05
local STREET_TREES = 0.5
local PARK_PERCENT = 6
local PLAZA_PERCENT = 5
local PARKING_PERCENT = 3
local ALLEY_PERCENT = 20
local MAX_INSET = 1
local KINDS = {
  {
    name = "corner",
    types = { "tenement", "tenement", "deco", "glass" },
    most = 22,
  },
  {
    name = "slab",
    types = { "brownstone", "brownstone", "tenement", "deco", "glass" },
    most = 30,
  },
  {
    name = "wide",
    types = { "deco", "glass", "glass", "tenement" },
    most = 38,
  },
  {
    name = "around",
    types = { "deco", "glass", "tenement" },
    most = 38,
  },
}
local ISLAND_TYPES = { "deco", "glass" }
local ROUTE_SPEC = { type = "tenement", stories = 4, gap = 0, route_stories = 2 }

local ROAD = { -2, 1 }
local SIDEWALK = { 2, 3 }
local FAR_SIDEWALK = { -4, -3 }
local FRONT = 4
local CROSSING = 1
local TREE_SPACING = 8
local CURB = SIDEWALK[1]
local PARKING_SPACING = 3
local SPAWN_SPOT = { 6, 0, -0.5 }

local function roll(site, part)
  math.randomseed(site:hash(part))
  return math.random()
end

local function corners_of(face)
  local corners = {}
  local corner = face
  for index = 1, SIDES do
    corners[index] = corner
    corner = corner:forward(1):right()
  end
  return corners
end

local function quarters_of(corner)
  local quarters = {}
  local turtle = corner
  for index = 1, AROUND do
    quarters[index] = turtle
    turtle = turtle:right()
  end
  return quarters
end

local function upright(site)
  return site:pitch_up():roll_right()
end

local function is_root_vertex(site, root)
  return site:hash("vertex") == root.vertex
end

local function is_island(face, root)
  if roll(face, "face") >= ISLAND then
    return false
  else
    local index = 1
    local corners = corners_of(face)
    while index <= SIDES and not is_root_vertex(corners[index], root) do
      index = index + 1
    end
    return index > SIDES
  end
end

local function is_planned_street(edge, root)
  if is_root_vertex(edge, root) or is_root_vertex(edge:forward(1), root) then
    return true
  elseif is_island(edge, root) or is_island(edge:left(), root) then
    return true
  else
    return roll(edge, "edge") >= DROPPED_STREET
  end
end

local function is_kept_for_access(edge, root)
  local mine = edge:hash("edge")
  local index = 1
  local turtle = edge:right()
  while index < AROUND and not is_planned_street(turtle, root) and turtle:hash("edge") < mine do
    index = index + 1
    turtle = turtle:right()
  end
  return index == AROUND
end

local function is_street(edge, root)
  if is_planned_street(edge, root) then
    return true
  else
    return is_kept_for_access(edge, root) or is_kept_for_access(edge:forward(1):right():right(), root)
  end
end

local function has_trees(edge)
  math.randomseed(edge:hash("edge"))
  math.random()
  return math.random() < STREET_TREES
end

local function choose(site, list)
  return list[site:pick(#list)]
end

local function chance(site, percent)
  return site:pick(100) <= percent
end

local function between(site, span)
  return span[1] + site:pick(span[2] - span[1] + 1) - 1
end

local function sidewalk(edge, x, starts_crossed, ends_crossed)
  local last = edge:edge_cells() - 1
  local first = 0
  if starts_crossed then
    first = CROSSING + 1
  end
  if ends_crossed then
    last = last - CROSSING - 1
  end
  edge:paint("concrete", { x = x, y = { -1, 0 }, z = { first, last } })
end

local function street_trees(edge)
  local last = edge:edge_cells() - 1
  local planted = { CROSSING + 4, last - CROSSING - 4 }
  local trunk = { every = TREE_SPACING, from = 6, span = 1 }
  edge:paint("oak_leaves", { x = { CURB - 1, CURB + 1 }, y = { 5, 6 }, z = planted }, { every = TREE_SPACING, from = 4, span = 5 })
  edge:paint("oak_leaves", { x = { CURB - 1, CURB + 1 }, y = { 7, 7 }, z = planted }, { every = TREE_SPACING, from = 5, span = 3 })
  edge:paint("oak_leaves", { x = { CURB, CURB }, y = { 8, 8 }, z = planted }, trunk)
  edge:paint("oak_wood", { x = { CURB, CURB }, y = { 1, 5 }, z = planted }, trunk)
end

local function street(edge, root)
  local finish = edge:forward(1)
  local near_start = is_street(edge:right(), root)
  local far_start = is_street(edge:left(), root)
  local near_finish = is_street(finish:right(), root)
  local far_finish = is_street(finish:left(), root)
  local last = edge:edge_cells() - 1
  edge:paint("basalt", { x = ROAD, y = { -1, -1 }, z = { 0, last } })
  sidewalk(edge, SIDEWALK, near_start, near_finish)
  sidewalk(edge, FAR_SIDEWALK, far_start, far_finish)
  if near_start or far_start then
    edge:paint("white_brick", { x = ROAD, y = { -1, -1 }, z = { CROSSING + 1, CROSSING + 2 } })
  end
  if near_finish or far_finish then
    edge:paint("white_brick", { x = ROAD, y = { -1, -1 }, z = { last - CROSSING - 2, last - CROSSING - 1 } })
  end
  if has_trees(edge) then
    street_trees(edge)
  end
end

local function tree(tower, x, y)
  tower:paint("oak_leaves", { x = { x - 2, x + 2 }, y = { y - 1, y + 1 }, z = { 5, 7 } })
  tower:paint("oak_leaves", { x = { x - 1, x + 1 }, y = { y - 2, y + 2 }, z = { 5, 7 } })
  tower:paint("oak_leaves", { x = { x - 1, x + 1 }, y = { y - 1, y + 1 }, z = { 8, 9 } })
  tower:paint("oak_wood", { x = { x, x }, y = { y, y }, z = { 1, 7 } })
end

local function ground_of(part)
  local tower = upright(part.site)
  local _, far = tower:column()
  local x_low = 0
  local y_low = 0
  if part.x_low == STREET then
    x_low = FRONT
  end
  if part.y_low == STREET then
    y_low = FRONT
  end
  return tower, { x = { x_low, far }, y = { y_low, far } }
end

local function pave(parts, material)
  for _, part in ipairs(parts) do
    local tower, area = ground_of(part)
    tower:paint(material, { x = area.x, y = area.y, z = { -1, 0 } })
  end
end

local function plant(parts)
  for _, part in ipairs(parts) do
    local tower, area = ground_of(part)
    if area.x[2] - area.x[1] >= 4 and area.y[2] - area.y[1] >= 4 then
      tree(tower, (area.x[1] + area.x[2] + 1) // 2, (area.y[1] + area.y[2] + 1) // 2)
    end
  end
end

local function parking(parts)
  for _, part in ipairs(parts) do
    local tower, area = ground_of(part)
    tower:paint("basalt", { x = area.x, y = area.y, z = { 0, 0 } })
    for x = area.x[1] + 1, area.x[2], PARKING_SPACING do
      tower:paint("white_brick", { x = { x, x }, y = { area.y[1] + 1, area.y[1] + 3 }, z = { 0, 0 } })
    end
  end
end

local function spec_of(site, kind, types)
  local name = choose(site, types)
  local building = TYPES[name]
  local stories = between(site, { building.STORIES[1], math.min(building.STORIES[2], kind.most) })
  local gap = 0
  if kind.name ~= "corner" and chance(site, ALLEY_PERCENT) then
    gap = 1
  end
  local front = FRONT
  if kind.name ~= "corner" then
    front = FRONT + site:pick(MAX_INSET + 1) - 1
  end
  return { type = name, stories = stories, palette = choose(site, building.PALETTES), front = front, gap = gap }
end

local function route_spec()
  local spec = { front = FRONT, palette = TYPES[ROUTE_SPEC.type].PALETTES[1] }
  for key, value in pairs(ROUTE_SPEC) do
    spec[key] = value
  end
  return spec
end

local function build(parts, spec)
  pave(parts, "concrete")
  TYPES[spec.type].build(parts, spec)
end

local function lot(parts, is_route)
  local site = parts[1].site
  local kind = KINDS[#parts]
  if is_route then
    build(parts, route_spec())
  elseif chance(site, PARK_PERCENT) then
    pave(parts, "grass")
    plant(parts)
  elseif chance(site, PLAZA_PERCENT) then
    pave(parts, "granite")
    plant(parts)
  elseif chance(site, PARKING_PERCENT) then
    parking(parts)
  else
    build(parts, spec_of(site, kind, kind.types))
  end
end

local function part_of(quarter, is_street_before, is_street_after, is_first)
  local x_low = JOINED
  local y_low = JOINED
  if is_street_after then
    x_low = STREET
  end
  if is_street_before then
    y_low = STREET
  end
  local front = nil
  if is_first and is_street_before then
    front = "y_low"
  end
  return { site = quarter, x_low = x_low, y_low = y_low, x_high = BOUNDARY, y_high = BOUNDARY, front = front }
end

local function lots_at(quarters, root)
  local streets = {}
  local islands = {}
  local any = false
  for index = 1, AROUND do
    streets[index] = is_street(quarters[index], root)
    islands[index] = is_island(quarters[index], root)
    any = any or streets[index]
  end
  local is_root = is_root_vertex(quarters[1], root)
  local start = 1
  while start <= AROUND and not streets[start] do
    start = start + 1
  end
  if not any then
    start = 1
  end
  local run = {}
  local is_route = false
  for step = 0, AROUND - 1 do
    local index = (start + step - 1) % AROUND + 1
    local after = index % AROUND + 1
    if not islands[index] then
      run[#run + 1] = part_of(quarters[index], streets[index], streets[after], #run == 0)
      is_route = is_route or (is_root and quarters[index]:hash("face") == root.face)
    end
    if streets[after] or step == AROUND - 1 then
      if #run > 0 then
        lot(run, is_route)
      end
      run = {}
      is_route = false
    end
  end
end

local function is_owner(quarters)
  local mine = quarters[1]:hash("face")
  local index = 2
  while index <= AROUND and quarters[index]:hash("face") < mine do
    index = index + 1
  end
  return index > AROUND
end

local function island(corners)
  local parts = {}
  for index = 1, SIDES do
    parts[index] = { site = corners[index], x_low = STREET, y_low = STREET, x_high = JOINED, y_high = JOINED }
  end
  parts[1].front = "y_low"
  build(parts, spec_of(corners[1], KINDS[#KINDS], ISLAND_TYPES))
end

local function tile(face, root)
  local corners = corners_of(face)
  local mine = face:hash("face")
  for _, edge in ipairs(corners) do
    if is_street(edge, root) and mine > edge:left():hash("face") then
      street(edge, root)
    end
  end
  for _, corner in ipairs(corners) do
    local quarters = quarters_of(corner)
    if is_owner(quarters) then
      lots_at(quarters, root)
    end
  end
  if is_island(face, root) then
    island(corners)
  end
end

return function(site)
  local root = { vertex = site:hash("vertex"), face = site:hash("face") }
  site:tile(tile, root)
  site:right():entrance(SPAWN_SPOT[1], SPAWN_SPOT[2], SPAWN_SPOT[3])
end
