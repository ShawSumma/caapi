module common.worldgen.generation;

import core.stdc.math : asinhf, atanf, cosf, coshf, sinhf, tanf;
import core.stdc.stdlib : abs;
import core.stdc.string : memcpy;
import base.array : Array;
import base.numbers : PI, clamped;
import common.graph : Graph, MAX_PARENTS, NO_SLOT, NodeId, ParentList;
import common.material : Material;
import common.node : ChunkLayout, Occupancy, Voxels, cellIndex;
import common.view : GraphView;
import common.worldgen.building : Building;
import common.worldgen.climate : Climate, CubeClimate, NodeClimate, UniformRock, groundAt, uniformRock;
import common.worldgen.plane : Plane;
import common.worldgen.sky : Ground, Grounds, PLANET, groundsAt;
import common.worldgen.structure : firstSideAmong, ringFaces;
import geometry.cube : CELL_STEPS;
import geometry.honeycomb : CUBE_GRID_RADIUS, Corner, FACE_COUNT, Face;

enum WorldgenKind : ubyte {
    terrain,
    plane,
    structure,
}

enum size_t STRUCTURE_NAME_CAPACITY = 256;
enum string TERRAIN_STRUCTURE = "planet";

struct PlaneWorld {
    float tiltRadians;
}

struct StructureWorld {
    char[STRUCTURE_NAME_CAPACITY] text;
    size_t length;

    static StructureWorld fromName(const(char)[] name) {
        assert(name.length <= STRUCTURE_NAME_CAPACITY);
        StructureWorld world = StructureWorld(' ', name.length);
        memcpy(world.text.ptr, name.ptr, name.length);
        return world;
    }

    const(char)[] name() const return {
        return text[0 .. length];
    }
}

struct Worldgen {
    union {
        PlaneWorld plane;
        StructureWorld structure;
    }
    WorldgenKind kind;

    static Worldgen makeTerrain() {
        return Worldgen.init;
    }

    static Worldgen fromPlane(PlaneWorld plane) {
        Worldgen worldgen;
        worldgen.plane = plane;
        worldgen.kind = WorldgenKind.plane;
        return worldgen;
    }

    static Worldgen fromStructure(StructureWorld structure) {
        Worldgen worldgen;
        worldgen.structure = structure;
        worldgen.kind = WorldgenKind.structure;
        return worldgen;
    }

    bool hasPlaneGround() const {
        return kind != WorldgenKind.terrain;
    }

    bool hasStructure() const {
        return kind != WorldgenKind.plane;
    }

    const(char)[] structureName() const return {
        if (kind == WorldgenKind.structure) {
            return structure.name();
        } else {
            return TERRAIN_STRUCTURE;
        }
    }

    float groundTiltRadians() const {
        float tilt = 0;
        final switch (kind) {
            case WorldgenKind.terrain:
            case WorldgenKind.structure:
                break;
            case WorldgenKind.plane:
                tilt = plane.tiltRadians;
                break;
        }
        return tilt;
    }
}

float degreesToRadians(float degrees) {
    return degrees * PI / DEGREES_PER_HALF_TURN;
}

enum TreeKind : ubyte {
    oak,
    birch,
    spruce,
}

struct TreeSpecies {
    Material wood;
    Material leaves;
    ubyte minTrunk;
    ubyte trunkChoices;
}

immutable TreeSpecies[TreeKind.max + 1] TREE_SPECIES = [
    TreeSpecies(Material.oakWood, Material.oakLeaves, 4, 2),
    TreeSpecies(Material.birchWood, Material.birchLeaves, 5, 2),
    TreeSpecies(Material.spruceWood, Material.spruceLeaves, 5, 3),
];

enum Material DEFERRED_STAND_IN_MATERIAL = Material.dirt;
enum float BASE_TREE_DENSITY = 0.05f;
enum float WETNESS_PER_TREE_DENSITY = 4.0f;
enum float MAX_TREE_DENSITY = 0.3f;
enum ubyte MIN_TREE_DIMENSION = 4;
enum int CANOPY_RADIUS = 2;
enum int CANOPY_CORNER_SPAN = 3;
enum int CANOPY_ABOVE_TRUNK = 1;
enum int SPRUCE_LOWEST_LEAVES = 2;
enum float SPRUCE_WARMTH = -0.2f;
enum ulong BIRCH_ODDS = 3;
enum float DEGREES_PER_HALF_TURN = 180.0f;
enum ulong SPLITMIX_INCREMENT = 0x9e3779b97f4a7c15;
enum ulong SPLITMIX_MULTIPLIER_1 = 0xbf58476d1ce4e5b9;
enum ulong SPLITMIX_MULTIPLIER_2 = 0x94d049bb133111eb;
enum ubyte TEST_DIMENSION = 12;

struct SplitMix {
    ulong state;

    ulong next() {
        state += SPLITMIX_INCREMENT;
        ulong z = state;
        z = (z ^ (z >> 30)) * SPLITMIX_MULTIPLIER_1;
        z = (z ^ (z >> 27)) * SPLITMIX_MULTIPLIER_2;
        return z ^ (z >> 31);
    }
}

// What a node knows about the world around it: where the planet's ground lies and a plane across it that tilted
// worlds slope along, both carried from its first parent by reflection, and its climate, drawn from all its parents.
struct NodeState {
    Plane surface;
    Plane reference;
    NodeClimate climate;

    static NodeState fromParents(ref GraphView view, uint slot) {
        ParentList parents = view.parents(slot);
        if (parents.count == 0) {
            return NodeState(Plane.ofFace(Face.f0), Plane.ofFace(firstSideAmong(ringFaces(Face.f0))), NodeClimate.init);
        } else {
            NodeClimate[MAX_PARENTS] climates;
            foreach (index, link; parents.links[0 .. parents.count]) {
                climates[index] = view.stateAt(link.slot).climate;
            }
            NodeState first = view.stateAt(parents.links[0].slot);
            Face side = parents.links[0].side;
            Plane surface = first.surface.reflectAcross(side).snappedToFaces();
            Plane reference = first.reference.reflectAcross(side).snappedToFaces();
            return NodeState(surface, reference, NodeClimate.fromParents(climates[0 .. parents.count], view.idAt(slot).spice()));
        }
    }
}

struct ValueRange {
    float low;
    float high;
}

bool isSameState(NodeState a, NodeState b) {
    bool isSame = isSamePlane(a.surface, b.surface) && isSamePlane(a.reference, b.reference);
    isSame = isSame && a.climate.broad == b.climate.broad && a.climate.local == b.climate.local && a.climate.heat == b.climate.heat;
    return isSame && a.climate.wetness == b.climate.wetness && a.climate.strata == b.climate.strata;
}

bool isSamePlane(Plane a, Plane b) {
    return isSameVector(a.up, b.up) && a.height == b.height;
}

bool isSameVector(float[3] a, float[3] b) {
    return a[0] == b[0] && a[1] == b[1] && a[2] == b[2];
}

unittest {
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.makeTerrain());
    foreach (side; 0 .. FACE_COUNT) {
        uint neighbor = graph.ensureNeighborSlot(graph.anchorSlot, cast(Face) side);
        foreach (outer; 0 .. FACE_COUNT) {
            graph.ensureNeighborSlot(neighbor, cast(Face) outer);
        }
    }
    uint region = graph.slotCount;
    GraphView view = GraphView.over(graph);
    Array!NodeState worked;
    Array!NodeId ids;
    foreach (slot; 0 .. region) {
        foreach (side; 0 .. FACE_COUNT) {
            foreach (outer; 0 .. FACE_COUNT) {
                uint far = view.ensureNeighborSlot(view.ensureNeighborSlot(slot, cast(Face) side), cast(Face) outer);
                worked.append(view.stateAt(far));
                ids.append(view.idAt(far));
            }
        }
    }
    assert(graph.slotCount == region && view.nodes.length > 0);
    size_t index = 0;
    foreach (slot; 0 .. region) {
        foreach (side; 0 .. FACE_COUNT) {
            foreach (outer; 0 .. FACE_COUNT) {
                uint far = graph.ensureNeighborSlot(graph.ensureNeighborSlot(slot, cast(Face) side), cast(Face) outer);
                assert(graph.idAt(far) == ids.ptr[index] && isSameState(*graph.ensureState(far), worked.ptr[index]));
                index += 1;
            }
        }
    }
    view.release();
    worked.release();
    ids.release();
    graph.release();
}

struct ChunkStructure {
    const(Building)* building;
    bool isInStructure;
    bool isKnown = true;
}

struct ChunkParams {
    const(Building)* building;
    ulong nodeSpice;
    Grounds grounds;
    CubeClimate climate;
    Plane reference;
    float slopeTangent;
    float slopeSecant;
    ChunkLayout layout;
    Corner chunk;
    bool hasStructure;
    bool isResolvingMaterials;

    // Another thread's view can only make these once the node's structure is finished, which the caller checks first.
    static ChunkParams make(ref GraphView view, uint slot, Corner chunk) {
        ChunkStructure structure = view.chunkStructureAt(slot);
        assert(structure.isKnown);
        NodeState state = view.stateAt(slot);
        return ChunkParams(
            structure.building,
            view.idAt(slot).spice(),
            view.groundsAt(slot),
            CubeClimate.around(view, slot, chunk),
            state.reference,
            tanf(view.worldgen.groundTiltRadians()),
            1.0f / cosf(view.worldgen.groundTiltRadians()),
            view.layout,
            chunk,
            structure.isInStructure,
            false,
        );
    }

    ubyte dimension() const {
        return layout.dimension;
    }

    ref const(Ground) ground(uint index) const return {
        return grounds.items[index];
    }

    ValueRange altitudes(uint index) const {
        float center = ground(index).surface.distanceToChunk(chunk, [0.5f, 0.5f, 0.5f]);
        return ValueRange(center - CUBE_GRID_RADIUS, center + CUBE_GRID_RADIUS);
    }

    bool isTilted(uint index) const {
        return index == PLANET && slopeTangent != 0;
    }

    float groundLevelAt(uint index, float[3] coord) const {
        float height = ground(index).surface.distanceToChunk(chunk, coord);
        if (!isTilted(index)) {
            return height;
        } else {
            float across = asinhf(sinhf(reference.distanceToChunk(chunk, coord)) / coshf(height));
            return atanf(sinhf(height)) + slopeTangent * across;
        }
    }

    ValueRange groundRange(uint index) const {
        float center = groundLevelAt(index, [0.5f, 0.5f, 0.5f]);
        float radius = CUBE_GRID_RADIUS;
        if (isTilted(index)) {
            radius = radius * slopeSecant;
        }
        return ValueRange(center - radius, center + radius);
    }

    float terrainCeiling(uint index) const {
        if (ground(index).isFlat) {
            return 0;
        } else {
            return climate.highest.relief;
        }
    }

    bool isClearOf(uint index) const {
        return groundRange(index).low > terrainCeiling(index);
    }

    bool isFullOf(uint index) const {
        float highest = groundRange(index).high;
        if (ground(index).isFlat) {
            return highest < 0;
        } else {
            return isProvenBelowTerrain(highest);
        }
    }

    bool isClearOfAll() const {
        uint index = 0;
        while (index < grounds.count && isClearOf(index)) {
            index += 1;
        }
        return index == grounds.count;
    }

    bool isFullOfAny() const {
        uint index = 0;
        while (index < grounds.count && !isFullOf(index)) {
            index += 1;
        }
        return index < grounds.count;
    }

    bool isProvenClear() const {
        return !hasStructure && isClearOfAll();
    }

    bool isProvenBelowTerrain(float highest) const {
        return climate.lowest.relief > highest;
    }

    Occupancy predictOccupancy() const {
        if (hasStructure) {
            return Occupancy.unknown;
        } else if (isClearOfAll()) {
            return Occupancy.empty;
        } else if (isFullOfAny()) {
            return Occupancy.full;
        } else {
            return Occupancy.unknown;
        }
    }

    UniformRock provenUniformRock(ValueRange altitudes) const {
        return uniformRock(climate.lowest.relief - altitudes.high, climate.highest.relief - altitudes.low, climate.lowest, climate.highest);
    }

    GeneratedVoxels generateVoxels(Yield yield = Yield.init) const {
        TerrainGenerator generator = TerrainGenerator(Voxels.filled(Material.none), this, SplitMix(nodeSpice ^ chunk), yield, false);
        foreach (index; 0 .. grounds.count) {
            if (ground(index).isFlat) {
                generator.generateFlat(index);
            } else {
                generator.generateTerrain(index);
                generator.generateTrees(index);
            }
        }
        generator.generateStructure();
        generator.voxels.compress(dimension);
        return GeneratedVoxels(generator.voxels, generator.hasDeferredMaterials);
    }
}

struct GeneratedVoxels {
    Voxels voxels;
    bool hasDeferredMaterials;
}

// Called between slices of a chunk, so the thread generating it can briefly do something more urgent.
struct Yield {
    void function(void* context) call;
    void* context;

    void now() {
        if (call !is null) {
            call(context);
        }
    }
}

struct TerrainGenerator {
    Voxels voxels;
    ChunkParams params;
    SplitMix rng;
    Yield yield;
    bool hasDeferredMaterials;

    // A chunk the ground fills entirely is one rock when the climate allows only one, and otherwise gets a stand-in
    // until a neighbor opens it up, since nobody sees which rock fills it until then.
    void generateTerrain(uint ground) {
        ubyte dimension = params.dimension;
        ValueRange altitudes = params.altitudes(ground);
        if (altitudes.low <= params.terrainCeiling(ground)) {
            UniformRock rock = params.provenUniformRock(altitudes);
            if (rock.isProven) {
                fillEmpty(rock.material);
            } else if (!params.isResolvingMaterials && !params.hasStructure && params.grounds.count == 1 && params.isProvenBelowTerrain(altitudes.high)) {
                voxels = Voxels.filled(DEFERRED_STAND_IN_MATERIAL);
                hasDeferredMaterials = true;
            } else {
                foreach (x; 0 .. dimension) {
                    foreach (y; 0 .. dimension) {
                        foreach (z; 0 .. dimension) {
                            generateTerrainVoxel(ground, params.layout.cellCenter([x, y, z]), cellIndex(dimension, x, y, z));
                        }
                    }
                    yield.now();
                }
            }
        }
    }

    void fillEmpty(Material material) {
        if (voxels.isFilledWith(Material.none)) {
            voxels = Voxels.filled(material);
        } else if (!voxels.isUniform()) {
            ubyte dimension = params.dimension;
            foreach (x; 0 .. dimension) {
                foreach (y; 0 .. dimension) {
                    foreach (z; 0 .. dimension) {
                        setIfEmpty([x, y, z], material);
                    }
                }
            }
        }
    }

    void generateFlat(uint ground) {
        ubyte dimension = params.dimension;
        ValueRange range = params.groundRange(ground);
        if (range.high < 0) {
            fillEmpty(Material.dirt);
        } else if (range.low <= 0) {
            foreach (x; 0 .. dimension) {
                foreach (y; 0 .. dimension) {
                    foreach (z; 0 .. dimension) {
                        if (params.groundLevelAt(ground, params.layout.cellCenter([x, y, z])) < 0) {
                            setIfEmpty([x, y, z], Material.dirt);
                        }
                    }
                }
                yield.now();
            }
        }
    }

    void generateStructure() {
        if (params.hasStructure) {
            ubyte dimension = params.dimension;
            foreach (x; 0 .. dimension) {
                foreach (y; 0 .. dimension) {
                    foreach (z; 0 .. dimension) {
                        size_t index = cellIndex(dimension, x, y, z);
                        Material existing = voxels.at(index);
                        Material material = params.building.materialAt(params.chunk, [x, y, z], existing);
                        if (material != existing) {
                            voxels.toDense(dimension)[index] = material;
                        }
                    }
                }
                yield.now();
            }
        }
    }

    void generateTerrainVoxel(uint ground, float[3] center, size_t index) {
        Climate here = params.climate.at(center);
        float depth = here.relief - params.ground(ground).surface.distanceToChunk(params.chunk, center);
        if (depth >= 0.0f && voxels.at(index) == Material.none) {
            voxels.toDense(params.dimension)[index] = groundAt(depth, here);
        }
    }

    void generateTrees(uint ground) {
        ubyte dimension = params.dimension;
        if (!voxels.isUniform() && dimension > MIN_TREE_DIMENSION) {
            Climate mean = params.climate.mean();
            float density = clamped(BASE_TREE_DENSITY + mean.wetness / WETNESS_PER_TREE_DENSITY, 0.0f, MAX_TREE_DENSITY);
            uint interior = dimension - 2;
            uint candidateCount = cast(uint)(cast(float)(interior * interior * interior) * density);
            foreach (_; 0 .. candidateCount) {
                int x = cast(int)(1 + (rng.next() % interior));
                int y = cast(int)(1 + (rng.next() % interior));
                int z = cast(int)(1 + (rng.next() % interior));
                ulong roll = rng.next();
                placeTree(ground, [x, y, z], treeKind(mean.warmth(), roll));
            }
        }
    }

    void placeTree(uint ground, int[3] base, TreeKind kind) {
        ubyte dimension = params.dimension;
        int upDirection = params.ground(ground).surface.risingNeighbor(params.chunk, params.layout, base);
        int[3] up = CELL_STEPS[upDirection];
        bool isBaseEmpty = voxels.at(cellIndex(dimension, base[0], base[1], base[2])) == Material.none;
        bool isAboveEmpty = voxels.at(cellIndex(dimension, base[0] + up[0], base[1] + up[1], base[2] + up[2])) == Material.none;
        if (isBaseEmpty && isAboveEmpty && isGroundMaterial(voxels.at(cellIndex(dimension, base[0] - up[0], base[1] - up[1], base[2] - up[2])))) {
            TreeSpecies species = TREE_SPECIES[kind];
            ulong roll = rng.next();
            TreeFrame frame = TreeFrame.fromUp(base, upDirection, cast(int)(species.minTrunk + roll % species.trunkChoices));
            if (frame.fitsWithin(dimension)) {
                growTree(frame, kind);
            }
        }
    }

    void growTree(TreeFrame frame, TreeKind kind) {
        TreeSpecies species = TREE_SPECIES[kind];
        foreach (level; 0 .. frame.trunk) {
            setIfEmpty(frame.cell(level, 0, 0), species.wood);
        }
        foreach (level; 0 .. frame.top + 1) {
            foreach (i; -CANOPY_RADIUS .. CANOPY_RADIUS + 1) {
                foreach (j; -CANOPY_RADIUS .. CANOPY_RADIUS + 1) {
                    if (isLeaf(kind, frame.trunk, level, i, j)) {
                        setIfEmpty(frame.cell(level, i, j), species.leaves);
                    }
                }
            }
        }
    }

    void setIfEmpty(int[3] cell, Material material) {
        size_t index = cellIndex(params.dimension, cell[0], cell[1], cell[2]);
        if (voxels.at(index) == Material.none) {
            voxels.toDense(params.dimension)[index] = material;
        }
    }
}

struct TreeFrame {
    int[3] base;
    int[3] up;
    size_t across;
    size_t along;
    int trunk;
    int top;

    static TreeFrame fromUp(int[3] base, int upDirection, int trunk) {
        size_t axis = upDirection / 2;
        return TreeFrame(base, CELL_STEPS[upDirection], (axis + 1) % 3, (axis + 2) % 3, trunk, trunk + CANOPY_ABOVE_TRUNK);
    }

    int[3] cell(int level, int i, int j) const {
        int[3] result = [base[0] + up[0] * level, base[1] + up[1] * level, base[2] + up[2] * level];
        result[across] += i;
        result[along] += j;
        return result;
    }

    bool fitsWithin(ubyte dimension) const {
        return isInChunk(cell(0, -CANOPY_RADIUS, -CANOPY_RADIUS), dimension) && isInChunk(cell(top, CANOPY_RADIUS, CANOPY_RADIUS), dimension);
    }
}

bool isInChunk(int[3] cell, ubyte dimension) {
    return cell[0] >= 0 && cell[0] < dimension && cell[1] >= 0 && cell[1] < dimension && cell[2] >= 0 && cell[2] < dimension;
}

TreeKind treeKind(float warmth, ulong roll) {
    if (warmth < SPRUCE_WARMTH) {
        return TreeKind.spruce;
    } else if (roll % BIRCH_ODDS == 0) {
        return TreeKind.birch;
    } else {
        return TreeKind.oak;
    }
}

bool isLeaf(TreeKind kind, int trunk, int level, int i, int j) {
    int spread = chebyshevLength(i, j);
    int span = abs(i) + abs(j);
    bool isWide = spread <= CANOPY_RADIUS && span <= CANOPY_CORNER_SPAN;
    if (kind == TreeKind.spruce) {
        return spruceLeaf(trunk, level, span, isWide);
    } else if (level == trunk - 2 || level == trunk - 1) {
        return isWide;
    } else if (level == trunk) {
        return spread <= 1;
    } else if (level == trunk + 1) {
        return span <= 1;
    } else {
        return false;
    }
}

bool spruceLeaf(int trunk, int level, int span, bool isWide) {
    if (level == trunk + 1) {
        return false;
    } else if (level == trunk) {
        return span == 0;
    } else if (level == trunk - 1) {
        return span <= 1;
    } else if (level >= SPRUCE_LOWEST_LEAVES && (trunk - level) % 2 == 0) {
        return isWide;
    } else if (level >= SPRUCE_LOWEST_LEAVES) {
        return span <= 1;
    } else {
        return false;
    }
}

int chebyshevLength(int i, int j) {
    if (abs(i) > abs(j)) {
        return abs(i);
    } else {
        return abs(j);
    }
}

bool isGroundMaterial(Material material) {
    return material == Material.dirt || material == Material.grass || material == Material.mudGrass || material == Material.lushGrass || material == Material.tanGrass || material == Material.coarseGrass;
}
