module common.worldgen.generation;

import core.stdc.math : asinhf, atanf, cosf, coshf, fabsf, sinhf, tanf;
import core.stdc.stdlib : abs;
import core.stdc.string : memcpy;
import base.array : Array;
import base.flags : Readiness;
import base.maybe : Maybe;
import base.numbers : RADIANS_PER_DEGREE, clamped, higherOf;
import base.splitmix : SplitMix;
import common.graph : Graph, MAX_PARENTS, NO_SLOT, NodeId, ParentList;
import common.node : ChunkLayout, Materials, Occupancy, Voxels, cellIndex;
import common.view : GraphView;
import common.worldgen.building : Building;
import common.worldgen.climate : COVER_DEPTH, Climate, CubeClimate, NodeClimate, SNOW_WARMTH, SOIL_DEPTH, WATER_LEVEL, groundAt, isDesert, openAt, uniformRock;
import common.worldgen.plane : Plane, PlaneMeasure, chunkPoint, cubePoint;
import common.worldgen.horospheres : Fill, Ground, Grounds, MAX_GROUNDS, ROOT, groundsAt;
import common.worldgen.store : Standing;
import common.worldgen.strokes : Stroke, StrokeForm;
import common.worldgen.structure : calmAt, firstSideAmong, ringFaces;
import geometry.cube : CELL_STEPS;
import geometry.honeycomb : CUBE_GRID_RADIUS, CUBE_RADIUS, Corner, FACE_COUNT, Face, cubeCenter, cubeToNode;
import geometry.lorentz : Mat4, Point, Vec4;
import plugins.api.api : Material;

enum WorldgenKind : ubyte {
    terrain,
    plane,
    structure,
}

enum size_t STRUCTURE_NAME_CAPACITY = 256;
enum string TERRAIN_STRUCTURE = "planet";
enum Material DEFERRED_STAND_IN_MATERIAL = Material.dirt;
enum float BASE_TREE_DENSITY = 0.05f;
enum float WETNESS_PER_TREE_DENSITY = 4.0f;
enum float MIN_TREE_DENSITY = 0.01f;
enum float MAX_TREE_DENSITY = 0.3f;
enum ubyte MIN_TREE_DIMENSION = 4;
enum int CANOPY_RADIUS = 2;
enum int CANOPY_CORNER_SPAN = 3;
enum int SPRUCE_LOWEST_LEAVES = 2;
enum float SPRUCE_WARMTH = -0.2f;
enum float MAPLE_WARMTH = 0.05f;
enum float TROPICAL_WARMTH = 0.25f;
enum float WET = 0.45f;
enum float DRY = -0.05f;
enum ulong SHRUB_ODDS = 8;
enum ulong CHOICE_SHIFT = 8;
enum uint CHUNK_ROLL_SHIFT = 32;
enum float RISER_MARGIN = 1.2f;

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
    return cast(float)(degrees * RADIANS_PER_DEGREE);
}

enum TreeKind : ubyte {
    oak,
    birch,
    spruce,
    bigOak,
    cherry,
    maple,
    willow,
    jungle,
    acacia,
    shrub,
    snag,
    cactus,
}

enum TreeShape : ubyte {
    round,
    cone,
    broad,
    weeping,
    tall,
    flat,
    bush,
    bare,
    column,
}

struct TreeSpecies {
    Material wood;
    Material leaves;
    TreeShape shape;
    ubyte minTrunk;
    ubyte trunkChoices;
    ubyte reach;
}

immutable TreeSpecies[TreeKind.max + 1] TREE_SPECIES = [
    TreeKind.oak: TreeSpecies(Material.oakWood, Material.oakLeaves, TreeShape.round, 4, 2, 2),
    TreeKind.birch: TreeSpecies(Material.birchWood, Material.birchLeaves, TreeShape.round, 5, 2, 2),
    TreeKind.spruce: TreeSpecies(Material.spruceWood, Material.spruceLeaves, TreeShape.cone, 5, 3, 2),
    TreeKind.bigOak: TreeSpecies(Material.oakWood, Material.oakLeaves, TreeShape.broad, 5, 2, 3),
    TreeKind.cherry: TreeSpecies(Material.spruceWood, Material.cherryLeaves, TreeShape.round, 4, 2, 2),
    TreeKind.maple: TreeSpecies(Material.oakWood, Material.mapleLeaves, TreeShape.round, 4, 3, 2),
    TreeKind.willow: TreeSpecies(Material.oakWood, Material.willowLeaves, TreeShape.weeping, 5, 2, 2),
    TreeKind.jungle: TreeSpecies(Material.jungleWood, Material.jungleLeaves, TreeShape.tall, 7, 3, 2),
    TreeKind.acacia: TreeSpecies(Material.acaciaWood, Material.acaciaLeaves, TreeShape.flat, 3, 2, 3),
    TreeKind.shrub: TreeSpecies(Material.oakWood, Material.oakLeaves, TreeShape.bush, 0, 1, 1),
    TreeKind.snag: TreeSpecies(Material.spruceWood, Material.none, TreeShape.bare, 3, 3, 1),
    TreeKind.cactus: TreeSpecies(Material.cactus, Material.none, TreeShape.column, 2, 3, 1),
];

immutable TreeKind[3] WET_TREES = [TreeKind.willow, TreeKind.bigOak, TreeKind.oak];
immutable TreeKind[4] COOL_TREES = [TreeKind.maple, TreeKind.maple, TreeKind.birch, TreeKind.oak];
immutable TreeKind[6] MILD_TREES = [TreeKind.oak, TreeKind.oak, TreeKind.birch, TreeKind.bigOak, TreeKind.cherry, TreeKind.maple];

struct NodeState {
    Plane surface;
    Plane reference;
    NodeClimate climate;

    static NodeState fromParents(ref GraphView view, uint slot) {
        NodeState state = NodeState.uncalmed(view, slot);
        state.climate.calm = view.calmAt(slot);
        return state;
    }

    static NodeState uncalmed(ref GraphView view, uint slot) {
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

struct ChunkStructure {
    const(Building)* building;
    Standing standing;

    bool isKnown() const {
        return standing != Standing.unknown;
    }
}

enum MaterialPass : ubyte {
    deferring,
    resolving,
}

struct ChunkParams {
    const(Building)* building;
    const(Stroke)[] strokes;
    ulong nodeSpice;
    Grounds grounds;
    CubeClimate climate;
    Plane reference;
    float slopeTangent;
    float slopeSecant;
    ChunkLayout layout;
    Corner chunk;
    Standing standing;
    MaterialPass materials;

    bool hasStructure() const {
        return standing == Standing.inside;
    }

    static ChunkParams make(ref GraphView view, uint slot, Corner chunk) {
        ChunkStructure structure = view.chunkStructureAt(slot);
        assert(structure.isKnown);
        NodeState state = view.stateAt(slot);
        return ChunkParams(
            structure.building,
            strokesNear(strokesIn(structure.building), chunk),
            view.idAt(slot).spice(),
            view.groundsAt(slot),
            CubeClimate.around(view, slot, chunk),
            state.reference,
            tanf(view.worldgen.groundTiltRadians()),
            1.0f / cosf(view.worldgen.groundTiltRadians()),
            view.layout,
            chunk,
            structure.standing,
            MaterialPass.deferring,
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
        return index == ROOT && slopeTangent != 0;
    }

    uint rivalsOf(uint index) const {
        float highest = altitudes(index).high;
        uint rivals = 0;
        foreach (other; 0 .. grounds.count) {
            if (other != index && !(altitudes(other).low >= highest)) {
                rivals += 1;
            }
        }
        return rivals;
    }

    float levelFrom(uint index, float height, Point!float point) const {
        if (!isTilted(index)) {
            return height;
        } else {
            float across = asinhf(sinhf(reference.distanceTo(point)) / coshf(height));
            return atanf(sinhf(height)) + slopeTangent * across;
        }
    }

    ValueRange groundRange(uint index) const {
        Point!float middle = chunkPoint(chunk, [0.5f, 0.5f, 0.5f]);
        float center = levelFrom(index, ground(index).surface.distanceTo(middle), middle);
        float radius = CUBE_GRID_RADIUS;
        if (isTilted(index)) {
            radius = radius * slopeSecant;
        }
        return ValueRange(center - radius, center + radius);
    }

    float terrainCeiling(uint index) const {
        if (ground(index).fill == Fill.flat) {
            return 0;
        } else if (climate.lowest.relief < WATER_LEVEL) {
            return higherOf(climate.highest.relief, WATER_LEVEL);
        } else {
            return climate.highest.relief;
        }
    }

    bool isClearOf(uint index) const {
        return ground(index).fill == Fill.none || groundRange(index).low > terrainCeiling(index);
    }

    bool isFullOf(uint index) const {
        float highest = groundRange(index).high;
        final switch (ground(index).fill) {
            case Fill.none:
                return false;
            case Fill.flat:
                return highest < 0;
            case Fill.terrain:
                return isProvenBelowTerrain(highest) && rivalsOf(index) == 0;
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
        return !hasStructure && strokes.length == 0 && isClearOfAll();
    }

    bool isProvenBelowTerrain(float highest) const {
        return climate.lowest.relief > highest;
    }

    Occupancy predictOccupancy() const {
        if (hasStructure || strokes.length > 0) {
            return Occupancy.unknown;
        } else if (isClearOfAll()) {
            return Occupancy.empty;
        } else if (isFullOfAny()) {
            return Occupancy.full;
        } else {
            return Occupancy.unknown;
        }
    }

    bool isUniformlyFilled(Occupancy predicted) const {
        return predicted == Occupancy.empty || (predicted == Occupancy.full && grounds.count == 1);
    }

    Maybe!Material provenUniformRock(ValueRange altitudes) const {
        return uniformRock(climate.lowest.relief - altitudes.high, climate.highest.relief - altitudes.low, climate.lowest, climate.highest);
    }

    GeneratedVoxels generateVoxels(Yield yield = Yield.init) const {
        TerrainGenerator generator = TerrainGenerator(Voxels.filled(Material.none), this, SplitMix(nodeSpice ^ chunk), yield);
        foreach (index; 0 .. grounds.count) {
            final switch (ground(index).fill) {
                case Fill.none:
                    break;
                case Fill.flat:
                    generator.generateFlat(index);
                    break;
                case Fill.terrain:
                    generator.generateTerrain(index);
                    generator.generateTrees(index);
                    break;
            }
        }
        generator.generateStrokes();
        generator.generateStructure();
        generator.voxels.compress(dimension);
        return GeneratedVoxels(generator.voxels, generator.materials);
    }
}

const(Stroke)[] strokesIn(const(Building)* building) {
    if (building is null) {
        return null;
    } else {
        return building.strokes.slice();
    }
}

const(Stroke)[] strokesNear(const(Stroke)[] strokes, Corner chunk) {
    Vec4!float center = cubeCenter(chunk).v;
    size_t index = 0;
    while (index < strokes.length && !strokes[index].isWithin(center, CUBE_RADIUS)) {
        index += 1;
    }
    if (index < strokes.length) {
        return strokes;
    } else {
        return null;
    }
}

struct GeneratedVoxels {
    Voxels voxels;
    Materials materials;
}

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
    Materials materials;
    Readiness cells;
    Mat4!float toNode;
    PlaneMeasure[MAX_GROUNDS] surfaces;
    float[ubyte.max] centers;

    void prepareCells() {
        if (cells == Readiness.pending) {
            toNode = params.chunk.cubeToNode;
            foreach (index; 0 .. params.grounds.count) {
                surfaces[index] = params.ground(index).surface.measure();
            }
            foreach (cell; 0 .. params.dimension) {
                centers[cell] = params.layout.cellCenterAlong(cell);
            }
            cells = Readiness.ready;
        }
    }

    float[3] centerOf(uint x, uint y, uint z) const {
        return [centers[x], centers[y], centers[z]];
    }

    bool isNearest(uint ground, float own, Point!float point) const {
        uint other = 0;
        while (other < params.grounds.count && (other == ground || surfaces[other].distanceTo(point) >= own)) {
            other += 1;
        }
        return other == params.grounds.count;
    }

    void generateTerrain(uint ground) {
        ubyte dimension = params.dimension;
        ValueRange altitudes = params.altitudes(ground);
        if (altitudes.low <= params.terrainCeiling(ground)) {
            Maybe!Material rock = params.provenUniformRock(altitudes);
            uint rivals = params.rivalsOf(ground);
            if (rock.exists && rivals == 0) {
                fillEmpty(rock.value);
            } else if (params.materials == MaterialPass.deferring && !params.hasStructure && params.strokes.length == 0 && params.grounds.count == 1 && params.isProvenBelowTerrain(altitudes.high)) {
                voxels = Voxels.filled(DEFERRED_STAND_IN_MATERIAL);
                materials = Materials.deferred;
            } else {
                prepareCells();
                foreach (x; 0 .. dimension) {
                    foreach (y; 0 .. dimension) {
                        foreach (z; 0 .. dimension) {
                            size_t index = cellIndex(dimension, x, y, z);
                            if (voxels.at(index) == Material.none) {
                                Point!float point = cubePoint(toNode, centerOf(x, y, z));
                                float altitude = surfaces[ground].distanceTo(point);
                                if (rivals == 0 || isNearest(ground, altitude, point)) {
                                    generateTerrainVoxel(ground, [x, y, z], altitude, index);
                                }
                            }
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
            prepareCells();
            foreach (x; 0 .. dimension) {
                foreach (y; 0 .. dimension) {
                    foreach (z; 0 .. dimension) {
                        Point!float point = cubePoint(toNode, centerOf(x, y, z));
                        if (params.levelFrom(ground, surfaces[ground].distanceTo(point), point) < 0) {
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

    void generateStrokes() {
        if (params.strokes.length > 0) {
            ubyte dimension = params.dimension;
            Array!Stroke near;
            Vec4!float center = cubeCenter(params.chunk).v;
            foreach (stroke; params.strokes) {
                if (stroke.isWithin(center, CUBE_RADIUS)) {
                    near.append(stroke);
                }
            }
            prepareCells();
            foreach (x; 0 .. dimension) {
                foreach (y; 0 .. dimension) {
                    foreach (z; 0 .. dimension) {
                        Vec4!float point = cubePoint(toNode, centerOf(x, y, z)).v;
                        size_t index = cellIndex(dimension, x, y, z);
                        Material existing = voxels.at(index);
                        Material material = existing;
                        float roll = cellRoll(index);
                        foreach (ref stroke; near.slice()) {
                            if ((stroke.form == StrokeForm.solid || material == Material.none) && stroke.holds(point, roll)) {
                                material = stroke.material;
                            }
                        }
                        if (material != existing) {
                            voxels.toDense(dimension)[index] = material;
                        }
                    }
                }
                yield.now();
            }
            near.release();
        }
    }

    float cellRoll(size_t index) const {
        return SplitMix(params.nodeSpice ^ (cast(ulong) params.chunk << CHUNK_ROLL_SHIFT) ^ index).roll();
    }

    float depthAt(uint ground, uint[3] cell) const {
        float[3] center = centerOf(cell[0], cell[1], cell[2]);
        return params.climate.at(center).relief - surfaces[ground].distanceTo(cubePoint(toNode, center));
    }

    float riserAt(uint ground, uint[3] cell, float depth) const {
        float most = 0;
        foreach (axis; 0 .. 3) {
            uint[3] beside = cell;
            if (cell[axis] + 1 < params.dimension) {
                beside[axis] += 1;
            } else {
                beside[axis] -= 1;
            }
            most = higherOf(most, fabsf(depthAt(ground, beside) - depth));
        }
        return RISER_MARGIN * most;
    }

    void generateTerrainVoxel(uint ground, uint[3] cell, float altitude, size_t index) {
        Climate here = params.climate.at(centerOf(cell[0], cell[1], cell[2]));
        float depth = here.relief - altitude;
        Material material;
        if (depth >= SOIL_DEPTH) {
            material = groundAt(depth, 0, here);
        } else if (depth >= COVER_DEPTH) {
            material = groundAt(depth, riserAt(ground, cell, depth), here);
        } else if (depth >= 0.0f) {
            material = groundAt(depth, 0, here);
        } else {
            material = openAt(altitude, here);
        }
        if (material != Material.none) {
            voxels.toDense(params.dimension)[index] = material;
        }
    }

    void generateTrees(uint ground) {
        ubyte dimension = params.dimension;
        if (!voxels.isUniform() && dimension > MIN_TREE_DIMENSION) {
            Climate mean = params.climate.mean();
            float density = clamped(BASE_TREE_DENSITY + mean.wetness / WETNESS_PER_TREE_DENSITY, MIN_TREE_DENSITY, MAX_TREE_DENSITY);
            uint interior = dimension - 2;
            uint candidateCount = cast(uint)(cast(float)(interior * interior * interior) * density);
            foreach (_; 0 .. candidateCount) {
                int x = cast(int)(1 + (rng.next() % interior));
                int y = cast(int)(1 + (rng.next() % interior));
                int z = cast(int)(1 + (rng.next() % interior));
                ulong roll = rng.next();
                placeTree(ground, [x, y, z], treeKind(mean.warmth(), mean.wetness, roll));
            }
        }
    }

    void placeTree(uint ground, int[3] base, TreeKind kind) {
        ubyte dimension = params.dimension;
        if (voxels.at(cellIndex(dimension, base[0], base[1], base[2])) == Material.none) {
            int upDirection = params.ground(ground).surface.risingNeighbor(params.chunk, params.layout, base);
            int[3] up = CELL_STEPS[upDirection];
            if (voxels.at(cellIndex(dimension, base[0] + up[0], base[1] + up[1], base[2] + up[2])) == Material.none && isGroundFor(kind,voxels.at(cellIndex(dimension, base[0] - up[0], base[1] - up[1], base[2] - up[2])))) {
                TreeSpecies species = TREE_SPECIES[kind];
                ulong roll = rng.next();
                TreeFrame frame = TreeFrame.fromUp(base, upDirection, cast(int)(species.minTrunk + roll % species.trunkChoices), species.shape, species.reach);
                if (frame.fitsWithin(dimension)) {
                    growTree(frame, species);
                }
            }
        }
    }

    void growTree(TreeFrame frame, TreeSpecies species) {
        int reach = frame.reach;
        foreach (level; 0 .. frame.top + 1) {
            foreach (i; -reach .. reach + 1) {
                foreach (j; -reach .. reach + 1) {
                    if (isWood(species.shape, frame.trunk, level, i, j)) {
                        setIfEmpty(frame.cell(level, i, j), species.wood);
                    }
                }
            }
        }
        foreach (level; 0 .. frame.top + 1) {
            foreach (i; -reach .. reach + 1) {
                foreach (j; -reach .. reach + 1) {
                    if (species.leaves != Material.none && isLeaf(species.shape, frame.trunk, level, i, j)) {
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
    int reach;

    static TreeFrame fromUp(int[3] base, int upDirection, int trunk, TreeShape shape, int reach) {
        size_t axis = upDirection / 2;
        return TreeFrame(base, CELL_STEPS[upDirection], (axis + 1) % 3, (axis + 2) % 3, trunk, trunk + aboveTrunk(shape), reach);
    }

    int[3] cell(int level, int i, int j) const {
        int[3] result = [base[0] + up[0] * level, base[1] + up[1] * level, base[2] + up[2] * level];
        result[across] += i;
        result[along] += j;
        return result;
    }

    bool fitsWithin(ubyte dimension) const {
        return isInChunk(cell(0, -reach, -reach), dimension) && isInChunk(cell(top, reach, reach), dimension);
    }
}

int aboveTrunk(TreeShape shape) {
    final switch (shape) {
        case TreeShape.round:
        case TreeShape.broad:
        case TreeShape.flat:
        case TreeShape.bush:
            return 1;
        case TreeShape.cone:
        case TreeShape.weeping:
        case TreeShape.tall:
        case TreeShape.bare:
            return 0;
        case TreeShape.column:
            return -1;
    }
}

bool isInChunk(int[3] cell, ubyte dimension) {
    return cell[0] >= 0 && cell[0] < dimension && cell[1] >= 0 && cell[1] < dimension && cell[2] >= 0 && cell[2] < dimension;
}

TreeKind treeKind(float warmth, float wetness, ulong roll) {
    ulong choice = roll >> CHOICE_SHIFT;
    if (isDesert(warmth, wetness)) {
        return TreeKind.cactus;
    } else if (warmth < SNOW_WARMTH && choice % 3 == 0) {
        return TreeKind.snag;
    } else if (warmth < SNOW_WARMTH) {
        return TreeKind.spruce;
    } else if (warmth < SPRUCE_WARMTH && choice % 6 == 0) {
        return TreeKind.birch;
    } else if (warmth < SPRUCE_WARMTH) {
        return TreeKind.spruce;
    } else if (roll % SHRUB_ODDS == 0) {
        return TreeKind.shrub;
    } else if (warmth > TROPICAL_WARMTH && wetness > WET && choice % 3 == 0) {
        return TreeKind.bigOak;
    } else if (warmth > TROPICAL_WARMTH && wetness > WET) {
        return TreeKind.jungle;
    } else if (warmth > TROPICAL_WARMTH && wetness < DRY) {
        return TreeKind.acacia;
    } else if (wetness > WET) {
        return WET_TREES[choice % WET_TREES.length];
    } else if (warmth < MAPLE_WARMTH) {
        return COOL_TREES[choice % COOL_TREES.length];
    } else {
        return MILD_TREES[choice % MILD_TREES.length];
    }
}

bool isInTrunk(int trunk, int level, int i, int j) {
    return i == 0 && j == 0 && level < trunk;
}

bool isWood(TreeShape shape, int trunk, int level, int i, int j) {
    final switch (shape) {
        case TreeShape.round:
        case TreeShape.cone:
        case TreeShape.broad:
        case TreeShape.weeping:
        case TreeShape.tall:
        case TreeShape.bush:
            return isInTrunk(trunk, level, i, j);
        case TreeShape.flat:
            return isInTrunk(trunk, level, i, j) || (level == trunk - 1 && i == 1 && j == 0) || (level == trunk && i == 1 && j == 1);
        case TreeShape.bare:
            return isInTrunk(trunk, level, i, j) || (level == trunk - 2 && i == 0 && j == 1) || (level == trunk - 1 && i == -1 && j == 0) || (level == trunk && i == 1 && j == 0);
        case TreeShape.column:
            return isInTrunk(trunk, level, i, j) || (i == 1 && j == 0 && level >= 1 && level <= 2 && level < trunk - 1) || (i == -1 && j == 0 && level >= 2 && level <= 3 && level < trunk - 1);
    }
}

bool isInCanopy(int spread, int span) {
    return spread <= CANOPY_RADIUS && span <= CANOPY_CORNER_SPAN;
}

bool isLeaf(TreeShape shape, int trunk, int level, int i, int j) {
    int spread = chebyshevLength(i, j);
    int span = abs(i) + abs(j);
    int squared = i * i + j * j;
    final switch (shape) {
        case TreeShape.round:
            return roundLeaf(trunk, level, spread, span);
        case TreeShape.cone:
            return spruceLeaf(trunk, level, spread, span);
        case TreeShape.broad:
            return broadLeaf(trunk, level, squared);
        case TreeShape.weeping:
            return weepingLeaf(trunk, level, spread, squared, i + j);
        case TreeShape.tall:
            return tallLeaf(trunk, level, squared);
        case TreeShape.flat:
            return (level == trunk && squared <= 10) || (level == trunk + 1 && squared <= 4);
        case TreeShape.bush:
            return (level == 0 && span <= 1) || (level == 1 && squared <= 2);
        case TreeShape.bare:
        case TreeShape.column:
            return false;
    }
}

bool roundLeaf(int trunk, int level, int spread, int span) {
    if (level == trunk - 2 || level == trunk - 1) {
        return isInCanopy(spread, span);
    } else if (level == trunk) {
        return spread <= 1;
    } else if (level == trunk + 1) {
        return span <= 1;
    } else {
        return false;
    }
}

bool broadLeaf(int trunk, int level, int squared) {
    if (level == trunk - 3 || level == trunk) {
        return squared <= 5;
    } else if (level == trunk - 2 || level == trunk - 1) {
        return squared <= 10;
    } else if (level == trunk + 1) {
        return squared <= 2;
    } else {
        return false;
    }
}

bool weepingLeaf(int trunk, int level, int spread, int squared, int parity) {
    if (level == trunk - 1 || level == trunk) {
        return squared <= 5 - (level - trunk + 1) * 3;
    } else {
        return level >= 1 && level < trunk - 1 && spread == CANOPY_RADIUS && (parity & 1) == 0;
    }
}

bool tallLeaf(int trunk, int level, int squared) {
    if (level == trunk - 2 || level == trunk - 1) {
        return squared <= 5;
    } else if (level == trunk) {
        return squared <= 2;
    } else {
        return level == trunk / 2 && squared == 1;
    }
}

bool spruceLeaf(int trunk, int level, int spread, int span) {
    if (level == trunk + 1) {
        return false;
    } else if (level == trunk) {
        return span == 0;
    } else if (level == trunk - 1) {
        return span <= 1;
    } else if (level >= SPRUCE_LOWEST_LEAVES && (trunk - level) % 2 == 0) {
        return isInCanopy(spread, span);
    } else if (level >= SPRUCE_LOWEST_LEAVES) {
        return span <= 1;
    } else {
        return false;
    }
}

int chebyshevLength(int i, int j) {
    return higherOf(abs(i), abs(j));
}

bool isGroundMaterial(Material material) {
    return material == Material.dirt || material == Material.grass || material == Material.mudGrass || material == Material.lushGrass || material == Material.tanGrass || material == Material.coarseGrass;
}

bool isGroundFor(TreeKind kind, Material material) {
    if (kind == TreeKind.cactus) {
        return material == Material.sand || material == Material.redSand;
    } else if (kind == TreeKind.willow || kind == TreeKind.shrub) {
        return isGroundMaterial(material) || material == Material.mud;
    } else if (kind == TreeKind.snag) {
        return isGroundMaterial(material) || material == Material.snow || material == Material.gravel;
    } else {
        return isGroundMaterial(material);
    }
}
