local town = require("town")

-- An endless office of low yellow rooms and hallways under a metal ceiling. Every quarter of the ground is a square
-- of cells with walls on a lattice every few cells, so rooms are small and walls meet across quarters. A wall on an
-- edge of the tiling is painted by only one of the two quarters beside it, so neither has to agree with the other on
-- doors. Some edges are Great Paths: the rooms beside them open into one wide hallway, and since the tiling's edges
-- run on in straight lines, so do the hallways wherever neighboring edges are paths too.
local backrooms = {}

local FLOOR = 0
local ROOM = { 1, 3 }
local CEILING = 4
local SLAB = 5
local LINES = { 4, 8 }
local POSTS = { 0, 4, 8 }
local BAND_POSTS = { 4, 8 }
local SEGMENTS = { { 1, 3 }, { 5, 7 }, { 9, 11 } }
local LIGHTS = { 2, 6, 10 }
local AWAY = { 1, 3, 5, 7, 9 }
local SHAFT = 3
local PATH_PERCENT = 25
local PATH_SALT = 0x5DEECE66D
local MIX = 0x2545F4914F6CDD1D
local MIX_SHIFT = 40
local CLOSED_ODDS = 0.3
local OPEN_ODDS = 0.2
local MERGE_ODDS = 0.15
local SKIRTING_ODDS = 0.5
local SKYLIGHT_ODDS = 0.1
local VENT_ODDS = 0.12
local STAIN_ODDS = 0.2
local DAMP_PATCHES = 2
local DAMP_ODDS = 0.4
local MOST_BOXES = 2
local PARTITION_ODDS = 0.5
local PARTITION = { 1, 2 }
local PILLARS = { 1, 5, 9 }
local RINGS = { { 1, 10 }, { 4, 7 } }
local PIT = { 1, 10 }
local PIT_DEPTH = 4
local PODIUMS = 7
local HANGING = 3
local LOFT_STEPS = 5
local LOFT_WALLS = { 6, 8 }
local LOFT_ROOF = 9
local LOFT_SLAB = 10
local PLANS = {
  { name = "rooms", weight = 45 },
  { name = "hall", weight = 20 },
  { name = "office", weight = 10 },
  { name = "pillars", weight = 8 },
  { name = "loft", weight = 8 },
  { name = "chapel", weight = 5 },
  { name = "doors", weight = 4 },
}
local ODD_PLANS = { loft = true, chapel = true, doors = true }

local function percent(hash, salt)
  return (((hash ~ salt) * MIX) >> MIX_SHIFT) % 100
end

-- Whether the edge a turtle faces along is a Great Path; every quarter beside that edge asks the same edge.
local function is_path(turtle)
  return percent(turtle:hash("edge"), PATH_SALT) < PATH_PERCENT
end

local function line_cells(axis, k, span, z)
  if axis == "x" then
    return { x = { k, k }, y = span, z = z }
  else
    return { x = span, y = { k, k }, z = z }
  end
end

local function random_kind()
  local roll = math.random()
  if roll < CLOSED_ODDS then
    return "closed"
  elseif roll < 1 - OPEN_ODDS then
    return "door"
  else
    return "open"
  end
end

local function random_kinds()
  return { random_kind(), random_kind(), random_kind() }
end

-- A wall along the line where the axis's coordinate is k: posts where lines cross, then each segment between posts
-- closed, open, or closed but for a door in its middle. Closed segments may get a vent near the ceiling or a stain.
local function wall(q, axis, k, kinds, posts)
  for _, post in ipairs(posts) do
    q.tower:paint(q.wall, line_cells(axis, k, { post, post }, ROOM))
  end
  for index, span in ipairs(SEGMENTS) do
    local kind = kinds[index]
    if kind ~= "open" then
      local middle = span[1] + 1
      q.tower:paint(q.wall, line_cells(axis, k, span, ROOM))
      if q.skirting then
        q.tower:paint("wood_planks", line_cells(axis, k, span, { ROOM[1], ROOM[1] }))
      end
      if kind == "door" then
        q.tower:paint("air", line_cells(axis, k, { middle, middle }, ROOM))
      elseif math.random() < VENT_ODDS then
        q.tower:paint("steel", line_cells(axis, k, { middle, middle }, { ROOM[2], ROOM[2] }))
      elseif math.random() < STAIN_ODDS then
        q.tower:paint("stained_wallpaper", line_cells(axis, k, span, { ROOM[1] + 1, ROOM[2] }))
      end
    end
  end
end

-- Lines crossing a Great Path's hallway leave it open, posts and all.
local function interior(q, axis, k, kinds)
  local is_band = (axis == "x" and q.path_y) or (axis == "y" and q.path_x)
  local posts = POSTS
  if is_band then
    kinds[1] = "open"
    posts = BAND_POSTS
  end
  wall(q, axis, k, kinds, posts)
end

-- The wall on an edge of the tiling: gone along a Great Path, and open beside the vertex wherever a Great Path runs
-- across it there, so the hallway carries on through.
local function edge_wall(q, axis, is_path_edge, is_crossed)
  local kinds = random_kinds()
  if is_path_edge then
    kinds = { "open", "open", "open" }
  end
  if is_crossed or q.is_lobby then
    kinds[1] = "open"
  end
  if q.is_lobby then
    kinds[2] = "open"
  end
  local posts = POSTS
  if is_path_edge then
    posts = {}
  elseif q.is_lobby then
    posts = { 8 }
  end
  wall(q, axis, 0, kinds, posts)
end

-- The lobby around the connector leaves the shaft's corner of each quarter to the connector.
local function areas(q)
  if q.is_lobby then
    return { { x = { SHAFT + 1, q.far }, y = { 0, q.far } }, { x = { 0, SHAFT }, y = { SHAFT + 1, q.far } } }
  else
    return { { x = { 0, q.far }, y = { 0, q.far } } }
  end
end

local function is_shaft(q, x, y)
  return q.is_lobby and x <= SHAFT and y <= SHAFT
end

local function shell(q)
  for _, area in ipairs(areas(q)) do
    q.tower:paint(q.floor, { x = area.x, y = area.y, z = { FLOOR, FLOOR } })
    q.tower:paint("air", { x = area.x, y = area.y, z = ROOM })
    q.tower:paint("ceiling_tile", { x = area.x, y = area.y, z = { CEILING, CEILING } })
    q.tower:paint("steel", { x = area.x, y = area.y, z = { SLAB, SLAB } })
  end
  local skylight = math.random() < SKYLIGHT_ODDS
  for _, x in ipairs(LIGHTS) do
    for _, y in ipairs(LIGHTS) do
      if not is_shaft(q, x, y) then
        q.tower:paint("light_panel", { x = { x, x }, y = { y, y }, z = { CEILING, CEILING } })
      end
    end
  end
  if skylight then
    local x, y = LIGHTS[math.random(#LIGHTS)], LIGHTS[math.random(#LIGHTS)]
    if not is_shaft(q, x, y) then
      q.tower:paint("glass", { x = { x, x }, y = { y, y }, z = { CEILING, SLAB } })
    end
  end
  if q.floor == "carpet" then
    for _ = 1, DAMP_PATCHES do
      if math.random() < DAMP_ODDS then
        local x, y = math.random(0, q.far - 1), math.random(0, q.far - 1)
        if not is_shaft(q, x, y) and not is_shaft(q, x + 1, y + 1) then
          q.tower:paint("damp_carpet", { x = { x, x + 1 }, y = { y, y + 1 }, z = { FLOOR, FLOOR } })
        end
      end
    end
  end
end

-- Solid boxes of drywall standing against walls for no reason, kept off the cells doors open onto.
local function boxes(q)
  for _ = 1, math.random(0, MOST_BOXES) do
    local k = LINES[math.random(#LINES)] + (math.random(2) == 1 and 1 or -1)
    local along = AWAY[math.random(#AWAY)]
    local top = ROOM[1] + math.random(0, ROOM[2] - ROOM[1])
    local box = { x = { k, k }, y = { along, along }, z = { ROOM[1], top } }
    if math.random(2) == 1 then
      box = { x = { along, along }, y = { k, k }, z = box.z }
    end
    q.tower:paint(q.wall, box)
  end
end

local function rooms(q)
  for _, k in ipairs(LINES) do
    for _, axis in ipairs({ "x", "y" }) do
      if math.random() >= MERGE_ODDS then
        interior(q, axis, k, random_kinds())
      end
    end
  end
  boxes(q)
end

-- A hallway between the two middle lines, with rooms off it on either side.
local function hall(q)
  local along = "x"
  local across = "y"
  if math.random(2) == 1 then
    along, across = "y", "x"
  end
  for _, k in ipairs(LINES) do
    interior(q, across, k, random_kinds())
    local kinds = random_kinds()
    kinds[2] = "open"
    interior(q, along, k, kinds)
  end
  boxes(q)
end

-- One room with posts where the walls would cross and half-height partitions along some of the lines.
local function office(q)
  for _, x in ipairs(LINES) do
    for _, y in ipairs(LINES) do
      q.tower:paint(q.wall, { x = { x, x }, y = { y, y }, z = ROOM })
    end
  end
  for _, k in ipairs(LINES) do
    for _, axis in ipairs({ "x", "y" }) do
      local is_band = (axis == "x" and q.path_y) or (axis == "y" and q.path_x)
      for index, span in ipairs(SEGMENTS) do
        if not (is_band and index == 1) and math.random() < PARTITION_ODDS then
          q.tower:paint(q.wall, line_cells(axis, k, span, PARTITION))
        end
      end
    end
  end
  boxes(q)
end

-- A wide room with a steel floor and a grid of pillars, any of them left out where a hallway runs.
local function pillars(q)
  for _, x in ipairs(PILLARS) do
    for _, y in ipairs(PILLARS) do
      local is_in_band = (q.path_y and y <= SEGMENTS[1][2]) or (q.path_x and x <= SEGMENTS[1][2])
      if not is_in_band then
        q.tower:paint(q.wall, { x = { x, x }, y = { y, y }, z = ROOM })
      end
    end
  end
end

-- Walls inside walls: each ring has one door, and the last holds a room barely big enough to stand in.
local function doors(q)
  for _, ring in ipairs(RINGS) do
    local low, high = ring[1], ring[2]
    q.tower:paint(q.wall, { x = { low, high }, y = { low, high }, z = ROOM })
    q.tower:paint("air", { x = { low + 1, high - 1 }, y = { low + 1, high - 1 }, z = ROOM })
    local at = math.random(low + 1, high - 1)
    local side = math.random(4)
    local door = { x = { low, low }, y = { at, at }, z = ROOM }
    if side == 2 then
      door = { x = { high, high }, y = { at, at }, z = ROOM }
    elseif side == 3 then
      door = { x = { at, at }, y = { low, low }, z = ROOM }
    elseif side == 4 then
      door = { x = { at, at }, y = { high, high }, z = ROOM }
    end
    q.tower:paint("air", door)
  end
end

-- A room sunk into the ground, full of podiums of every height rising from its floor and hanging from its ceiling,
-- lit by a skylight, with steps down along one side.
local function chapel(q)
  local floor = FLOOR - PIT_DEPTH - 1
  q.tower:paint(q.wall, { x = { 0, q.far }, y = { 0, q.far }, z = { floor, FLOOR - 1 } })
  q.tower:paint("air", { x = PIT, y = PIT, z = { floor + 1, FLOOR } })
  q.tower:paint(q.floor, { x = PIT, y = PIT, z = { floor, floor } })
  for step = 1, PIT_DEPTH do
    q.tower:paint(q.wall, { x = { PIT[1] + step - 1, PIT[1] + step - 1 }, y = { PIT[1], PIT[1] + 1 }, z = { floor + 1, FLOOR - step } })
  end
  for _ = 1, PODIUMS do
    local x, y = math.random(PIT[1] + 2, PIT[2] - 1), math.random(PIT[1] + 3, PIT[2] - 1)
    local size = math.random(0, 1)
    q.tower:paint(q.wall, { x = { x - size, x }, y = { y - size, y }, z = { floor + 1, floor + math.random(1, PIT_DEPTH + 1) } })
  end
  for _ = 1, HANGING do
    local x, y = math.random(PIT[1] + 1, PIT[2]), math.random(PIT[1] + 1, PIT[2])
    q.tower:paint(q.wall, { x = { x, x }, y = { y, y }, z = { CEILING - math.random(1, 2), CEILING - 1 } })
  end
  local middle = (PIT[1] + PIT[2]) // 2
  q.tower:paint("glass", { x = { middle, middle + 1 }, y = { middle, middle + 1 }, z = { CEILING, SLAB } })
end

-- Steps up through the ceiling to a loft on top of it, walled, windowed and roofed over.
local function loft(q)
  local well = { x = { 1, LOFT_STEPS - 1 }, y = { 1, 2 } }
  q.tower:paint("carpet", { x = { 1, q.far - 1 }, y = { 1, q.far - 1 }, z = { SLAB, SLAB } })
  q.tower:paint("air", { x = well.x, y = well.y, z = { CEILING, SLAB } })
  for step = 1, LOFT_STEPS do
    q.tower:paint("wood_planks", { x = { step, step }, y = well.y, z = { ROOM[1], step } })
  end
  local walls = { x = { 0, q.far }, y = { 0, q.far }, z = LOFT_WALLS }
  q.tower:paint(q.wall, walls)
  q.tower:paint("air", { x = { 1, q.far - 1 }, y = { 1, q.far - 1 }, z = LOFT_WALLS })
  local sill = LOFT_WALLS[1] + 1
  q.tower:paint("glass", { x = { 0, 0 }, y = { 1, q.far - 1 }, z = { sill, sill } })
  q.tower:paint("glass", { x = { q.far, q.far }, y = { 1, q.far - 1 }, z = { sill, sill } })
  q.tower:paint("ceiling_tile", { x = { 0, q.far }, y = { 0, q.far }, z = { LOFT_ROOF, LOFT_ROOF } })
  q.tower:paint("steel", { x = { 0, q.far }, y = { 0, q.far }, z = { LOFT_SLAB, LOFT_SLAB } })
  q.tower:paint("light_panel", { x = { 6, 6 }, y = { 6, 6 }, z = { LOFT_ROOF, LOFT_ROOF } })
end

local BUILDERS = {
  rooms = rooms,
  hall = hall,
  office = office,
  pillars = pillars,
  loft = loft,
  chapel = chapel,
  doors = doors,
}

local function plan_of(q)
  local total = 0
  for _, plan in ipairs(PLANS) do
    total = total + plan.weight
  end
  local roll = math.random(total)
  local index = 1
  while roll > PLANS[index].weight do
    roll = roll - PLANS[index].weight
    index = index + 1
  end
  local name = PLANS[index].name
  if ODD_PLANS[name] and (q.path_x or q.path_y) then
    return "rooms"
  else
    return name
  end
end

local function quarter(corner, root)
  local mine = corner:hash("face")
  local q = {
    tower = town.upright(corner),
    is_lobby = root.foot ~= nil and corner:hash("vertex") == root.foot,
    owns_y = mine > corner:left():hash("face"),
    owns_x = mine > corner:right():hash("face"),
    path_y = is_path(corner),
    path_x = is_path(corner:right()),
    wall = "wallpaper",
    floor = "carpet",
  }
  local _, far = q.tower:column()
  q.far = far
  local crossed_y = is_path(corner:right()) or is_path(corner:left())
  local crossed_x = q.path_y or is_path(corner:right():right())
  math.randomseed(corner:hash("vertex") ~ mine)
  q.skirting = math.random() < SKIRTING_ODDS
  local plan = "lobby"
  if not q.is_lobby then
    plan = plan_of(q)
  end
  if plan == "pillars" or plan == "doors" then
    q.floor = "steel"
  end
  shell(q)
  if q.owns_y then
    edge_wall(q, "y", q.path_y, crossed_y)
  end
  if q.owns_x then
    edge_wall(q, "x", q.path_x, crossed_x)
  end
  if BUILDERS[plan] then
    BUILDERS[plan](q)
  end
end

-- Paints a face's quarters. The root names the foot vertex of a sky's connector, whose quarters become a lobby.
function backrooms.tile(face, root)
  for _, corner in ipairs(town.corners_of(face)) do
    quarter(corner, root)
  end
end

return backrooms
