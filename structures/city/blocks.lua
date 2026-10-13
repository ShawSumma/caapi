local building = require("buildings.building")
local connector = require("connector")

local blocks = {}

local TYPES = {
  brownstone = require("buildings.brownstone"),
  tenement = require("buildings.tenement"),
  deco = require("buildings.deco"),
  glass = require("buildings.glass"),
  rowhouse = require("buildings.rowhouse"),
  warehouse = require("buildings.warehouse"),
  modern = require("buildings.modern"),
  civic = require("buildings.civic"),
}

local STREET = building.STREET
local JOINED = building.JOINED
local BOUNDARY = building.LOT

local MIX = 0x2545F4914F6CDD1D
local MIX_SHIFT = 24
local PERCENT = 100
local ISLAND_SALT = 0x51ED270B
local DROPPED_SALT = 0x2C1B3C6D
local TREES_SALT = 0x297A2D39
local AROUND = 4
local SIDES = 5
local DROPPED_STREET = 0.5
local ISLAND = 0.05
local STREET_TREES = 0.5
local PARK_PERCENT = 6
local PLAZA_PERCENT = 5
local PARKING_PERCENT = 3
local POND_PERCENT = 50
local FOUNTAIN_PERCENT = 60
local ALLEY_PERCENT = 20
local MAX_INSET = 1
local KINDS = {
  {
    name = "corner",
    types = { "tenement", "tenement", "rowhouse", "rowhouse", "deco", "glass", "modern", "civic" },
    most = 22,
  },
  {
    name = "slab",
    types = { "brownstone", "brownstone", "rowhouse", "tenement", "warehouse", "deco", "glass", "modern" },
    most = 30,
  },
  {
    name = "wide",
    types = { "deco", "glass", "glass", "tenement", "modern", "warehouse", "civic" },
    most = 38,
  },
  {
    name = "around",
    types = { "deco", "glass", "tenement", "modern", "civic" },
    most = 38,
  },
}
local ISLAND_TYPES = { "deco", "glass", "modern", "civic" }
local ROUTE_SPEC = { type = "tenement", stories = 4, gap = 0, route_stories = 2 }

local ROAD = { -2, 1 }
local SIDEWALK = { 2, 3 }
local FAR_SIDEWALK = { -4, -3 }
local FRONT = 4
local CROSSING = 1
local TREE_SPACING = 8
local CURB = SIDEWALK[1]
local PARKING_SPACING = 3
local CITY_GROUND = 1
local CROWN_ROOM = 10

function blocks.mixed(hash, salt)
  return ((hash ~ salt) * MIX) >> MIX_SHIFT
end

function blocks.roll(hash, salt)
  return (blocks.mixed(hash, salt) % PERCENT) / PERCENT
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

local function is_owner(quarters)
  local mine = quarters[1]:hash("face")
  local index = 2
  while index <= AROUND and quarters[index]:hash("face") < mine do
    index = index + 1
  end
  return index > AROUND
end

local function is_foot(corner, sky)
  return corner:hash("vertex") == sky.foot:hash("vertex")
end

local function owns_foot(face, sky)
  local is_found = false
  for _, corner in ipairs(corners_of(face)) do
    is_found = is_found or (is_foot(corner, sky) and is_owner(quarters_of(corner)))
  end
  return is_found
end

blocks.corners_of = corners_of
blocks.quarters_of = quarters_of
blocks.upright = upright
blocks.is_owner = is_owner
blocks.is_foot = is_foot
blocks.owns_foot = owns_foot

local function is_root_vertex(site, root)
  return site:hash("vertex") == root.vertex
end

local function is_island(face, root)
  if blocks.roll(face:hash("face"), ISLAND_SALT) >= ISLAND then
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
    return blocks.roll(edge:hash("edge"), DROPPED_SALT) >= DROPPED_STREET
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

blocks.is_street = is_street

local function has_trees(edge)
  return blocks.roll(edge:hash("edge"), TREES_SALT) < STREET_TREES
end

local function choose(site, list)
  return list[site:pick(#list)]
end

local function chance(site, percent)
  return site:pick(PERCENT) <= percent
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

local function is_roomy(area)
  return area.x[2] - area.x[1] >= 4 and area.y[2] - area.y[1] >= 4
end

local function centre(span)
  return (span[1] + span[2] + 1) // 2
end

local function plant(parts)
  for _, part in ipairs(parts) do
    local tower, area = ground_of(part)
    if is_roomy(area) then
      tree(tower, centre(area.x), centre(area.y))
    end
  end
end

local function fountain(tower, x, y)
  tower:paint("marble", { x = { x - 2, x + 2 }, y = { y - 2, y + 2 }, z = { 1, 1 } })
  tower:paint("water", { x = { x - 1, x + 1 }, y = { y - 1, y + 1 }, z = { 1, 1 } })
  tower:paint("marble", { x = { x, x }, y = { y, y }, z = { 1, 2 } })
  tower:paint("water", { x = { x, x }, y = { y, y }, z = { 3, 3 } })
end

local function fountains(parts)
  for _, part in ipairs(parts) do
    local tower, area = ground_of(part)
    if is_roomy(area) then
      fountain(tower, centre(area.x), centre(area.y))
    end
  end
end

local function ponds(parts)
  for _, part in ipairs(parts) do
    local tower, area = ground_of(part)
    if is_roomy(area) then
      local water = { x = { area.x[1] + 1, area.x[2] - 1 }, y = { area.y[1] + 1, area.y[2] - 1 } }
      tower:paint("water", { x = water.x, y = water.y, z = { -1, 0 } })
      tower:paint("sand", { x = water.x, y = water.y, z = { -2, -2 } })
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
  local chosen = TYPES[name]
  local stories = between(site, { chosen.STORIES[1], math.min(chosen.STORIES[2], kind.most) })
  local gap = 0
  if kind.name ~= "corner" and chance(site, ALLEY_PERCENT) then
    gap = 1
  end
  local front = FRONT
  if kind.name ~= "corner" then
    front = FRONT + site:pick(MAX_INSET + 1) - 1
  end
  return { type = name, stories = stories, palette = choose(site, chosen.PALETTES), front = front, gap = gap }
end

function blocks.fit(site, stories)
  local room = CROWN_ROOM + 1
  return math.min(stories, (site:balance(stories * building.STORY + room) - room) // building.STORY)
end

local function fitted(spec, site, root)
  if root.sky ~= nil then
    spec.stories = blocks.fit(site, spec.stories)
  end
  return spec
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

local function lot(parts, is_route, is_root, root)
  local site = parts[1].site
  local kind = KINDS[#parts]
  if is_root and root.sky ~= nil then
    pave(parts, "granite")
    plant(parts)
  elseif is_route then
    build(parts, route_spec())
  elseif chance(site, PARK_PERCENT) then
    pave(parts, "grass")
    if chance(site, POND_PERCENT) then
      ponds(parts)
    else
      plant(parts)
    end
  elseif chance(site, PLAZA_PERCENT) then
    pave(parts, "granite")
    if chance(site, FOUNTAIN_PERCENT) then
      fountains(parts)
    else
      plant(parts)
    end
  elseif chance(site, PARKING_PERCENT) then
    parking(parts)
  else
    local spec = fitted(spec_of(site, kind, kind.types), site, root)
    if spec.stories >= 1 then
      build(parts, spec)
    else
      pave(parts, "granite")
      plant(parts)
    end
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
  return { site = quarter, x_low = x_low, y_low = y_low, x_high = BOUNDARY, y_high = BOUNDARY, front = front, joins = {} }
end

local function join(run)
  for index, part in ipairs(run) do
    if part.x_low == JOINED then
      local next_index = index % #run + 1
      part.joins.x_low = { lot = next_index, side = "y_low" }
      run[next_index].joins.y_low = { lot = index, side = "x_low" }
    end
  end
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
  if is_root and root.sky ~= nil then
    connector(quarters[1], root.sky, CITY_GROUND, root.is_routed)
  end
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
        join(run)
        lot(run, is_route, is_root, root)
      end
      run = {}
      is_route = false
    end
  end
end

local function island(corners, root)
  local parts = {}
  for index = 1, SIDES do
    parts[index] = { site = corners[index], x_low = STREET, y_low = STREET, x_high = JOINED, y_high = JOINED }
  end
  parts[1].front = "y_low"
  local spec = fitted(spec_of(corners[1], KINDS[#KINDS], ISLAND_TYPES), corners[1], root)
  if spec.stories >= 1 then
    build(parts, spec)
  else
    pave(parts, "granite")
    plant(parts)
  end
end

function blocks.root(site, sky, is_routed)
  return { vertex = site:hash("vertex"), face = site:hash("face"), sky = sky, is_routed = is_routed }
end

function blocks.tile(face, root)
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
    island(corners, root)
  end
end

return blocks
