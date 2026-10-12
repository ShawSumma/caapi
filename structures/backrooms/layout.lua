local kit = require("backrooms.kit")
local levels = require("backrooms.levels")
local town = require("town")

-- Endless rooms and hallways in layers, laid out like the city. Hallways run along the city's streets, on edges of
-- the tiling; the blocks between them are split into rooms. A quarter's walls on its sides are its own, built back
-- to back with the next quarter's, and both take their doorways from the line they share, so they line up. Each
-- face takes its biome on every layer from the strongest of it and its neighbors, so biomes come in clumps. Layers
-- go down into the ground, and stairwells now and then lead from one to the next one down.
local layout = {}

local MIX = 0x2545F4914F6CDD1D
local MIX_SHIFT = 24
local LINE_SALT = 0x2F4A7C15
local STAIR_SALT = 0x6A09E667
local BIOME_SALT = 0x3C6EF372
local LAYER_SALT = 0x9E3779B9
local STAIR_ODDS = 0.08

local function mixed(hash, salt)
  return ((hash ~ salt) * MIX) >> MIX_SHIFT
end

-- A shared wall's doorway, or now and then no wall at all, from the line's own hash. Every shared wall lets through,
-- so every quarter is joined to all its neighbors.
local function line_doors(hash, layer, level)
  math.randomseed(hash ~ LINE_SALT ~ layer)
  if math.random() < level.missing then
    return "open"
  else
    return { math.random(kit.DOOR_LOW, kit.DOOR_HIGH) }
  end
end

-- A quarter's lines are named by the edge they lie on or cross, and by the vertex or the face they belong to.
local function line_hashes(corner)
  local vertex, face = corner:hash("vertex"), corner:hash("face")
  local edge_y, edge_x = corner:hash("edge"), corner:right():hash("edge")
  return { y_low = edge_y ~ vertex, x_low = edge_x ~ vertex, x_high = edge_y ~ face, y_high = edge_x ~ face }
end

local function quarter(corner, root, biomes)
  local vertex, face = corner:hash("vertex"), corner:hash("face")
  local q = {
    tower = town.upright(corner),
    path_y = town.is_street(corner, root),
    path_x = town.is_street(corner:right(), root),
    lobby = vertex == root.vertex,
  }
  q.shaft = q.lobby and root.has_shaft
  local hashes = line_hashes(corner)
  math.randomseed(vertex ~ face ~ STAIR_SALT)
  local stair_from = nil
  if not q.lobby and not q.path_x and math.random() < STAIR_ODDS then
    stair_from = math.random(#levels.LAYERS - 1)
  end
  local frames = {}
  for layer, level in ipairs(levels.LAYERS) do
    local lines = {}
    for side, hash in pairs(hashes) do
      lines[side] = line_doors(hash, layer, level)
    end
    math.randomseed(vertex ~ face ~ layer * LAYER_SALT)
    local has_strip = stair_from == layer or stair_from == layer - 1
    local f = kit.frame(q, layer, level, biomes[layer], has_strip, layer == 1)
    kit.layer(f, lines, level)
    frames[layer] = f
  end
  if stair_from then
    kit.stairs(frames[stair_from + 1], frames[stair_from])
  end
end

-- Paints a face's quarters on every layer. The root names the vertex every hallway near it leads to, which becomes
-- an open lobby, and whether a connector's shaft rises through it.
function layout.tile(face, root)
  local corners = town.corners_of(face)
  local strongest = face:hash("face")
  for _, corner in ipairs(corners) do
    strongest = math.max(strongest, corner:left():hash("face"))
  end
  local biomes = {}
  for layer, level in ipairs(levels.LAYERS) do
    biomes[layer] = level.biomes[mixed(strongest, BIOME_SALT + layer) % #level.biomes + 1]
  end
  for _, corner in ipairs(corners) do
    quarter(corner, root, biomes)
  end
end

return layout
