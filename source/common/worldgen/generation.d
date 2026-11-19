module common.worldgen.generation;

import core.stdc.math : asinhf, atanf, cosf, coshf, fabsf, sinh, sinhf, tanf;
import core.stdc.string : memcpy;
import base.array : Array;
import base.flags : Readiness;
import base.maybe : Maybe;
import base.murmur : murmurHash3;
import base.numbers : RADIANS_PER_DEGREE, clamped, higherOf, lowerOf;
import base.splitmix : SplitMix;
import base.vector3 : Vec3;
import common.graph : Graph, MOST_PARENTS, NodeId, ParentList;
import common.neighbors : isInside;
import common.node : ChunkLayout, Materials, Occupancy, Voxels, cellIndex;
import common.view : GraphView;
import common.worldgen.building : Building;
import common.worldgen.climate : Climate, CubeClimate, NodeClimate, UNDERSIDE_SWING, groundAt, openAt, underAt, uniformRock;
import common.worldgen.horospheres : Fill, FlatLines, Ground, Grounds, MOST_FLAT_LINES, MOST_GROUNDS, MeasuredLine, crustAt, ensureGrounds, ensureHorospheresAt, flatLinesNear, reliefShareAway, undersideOf;
import common.worldgen.lineage : Lineage, inherited;
import common.worldgen.palette : Shape, Tree, hasTrees, isGroundFor, isGroundForPlant, laidBy, oreFor, palette, treeAt, treeOf;
import common.worldgen.plane : Plane, PlaneMeasure, chunkPoint, cubePoint;
import common.worldgen.store : Standing;
import common.worldgen.strokes : Stroke, StrokeForm;
import common.worldgen.structure : calmAt, firstSideAmong, ringFaces;
import geometry.cube : CELL_STEPS;
import geometry.honeycomb : CUBE_GRID_RADIUS, CUBE_RADIUS, Corner, FACE_COUNT, Face, cubeCenter, cubeToNode;
import geometry.lorentz : Mat4, Point, Vec4;
import plugins.api.api : Material, Part;

enum WorldgenKind : ubyte {
    terrain,
    plane,
    structure,
}

enum size_t STRUCTURE_NAME_CAPACITY = 256;
enum ubyte LEAST_TREE_DIMENSION = 4;
enum uint CHUNK_ROLL_SHIFT = 32;
enum float RISER_MARGIN = 1.2f;
enum float CLEAR_MARGIN = 1e-3f;
enum uint BASE_GROUND = 0;
enum ulong VEIN_SALT = 0x5EA1_0E5D_7A11_C0DE;
enum ulong PLANT_SALT = 0x91A7_5EED;
enum float UNKNOWN_SHARE = -1;

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
        final switch (kind) {
            case WorldgenKind.terrain:
                return palette.world.length > 0;
            case WorldgenKind.plane:
                return false;
            case WorldgenKind.structure:
                return true;
        }
    }

    const(char)[] structureName() const return {
        if (kind == WorldgenKind.structure) {
            return structure.name();
        } else {
            return palette.world;
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

struct NodeState {
    Plane surface;
    Maybe!Plane reference;
    NodeClimate climate;
    Lineage lineage;

    static NodeState fromParents(ref GraphView view, uint slot) {
        NodeState state = NodeState.uncalmed(view, slot);
        state.climate.calm = view.calmAt(slot);
        return state;
    }

    static NodeState uncalmed(ref GraphView view, uint slot) {
        ParentList parents = view.parents(slot);
        if (parents.count == 0) {
            const(char)[] name = view.worldgen.structureName();
            Maybe!Plane reference;
            if (view.worldgen.groundTiltRadians() != 0) {
                reference = Maybe!Plane.of(Plane.ofFace(firstSideAmong(ringFaces(Face.first))));
            }
            return NodeState(Plane.ofFace(Face.first), reference, NodeClimate.init, Lineage.ofRoot(murmurHash3(cast(const(ubyte)[]) name).first));
        } else {
            NodeClimate[MOST_PARENTS] climates;
            Lineage[MOST_PARENTS] lineages;
            foreach (index, link; parents.links[0 .. parents.count]) {
                NodeState parent = view.ensureState(link.slot);
                climates[index] = parent.climate;
                lineages[index] = parent.lineage;
            }
            NodeState first = view.ensureState(parents.links[0].slot);
            Face side = parents.links[0].side;
            Plane surface = first.surface.reflectAcross(side).snappedToFaces();
            Maybe!Plane reference;
            if (first.reference.exists) {
                reference = Maybe!Plane.of(first.reference.value.reflectAcross(side).snappedToFaces());
            }
            ulong spice = view.idAt(slot).spice();
            return NodeState(surface, reference, NodeClimate.fromParents(climates[0 .. parents.count], spice), inherited(lineages[0 .. parents.count], spice));
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
    FlatLines flats;
    CubeClimate climate;
    Maybe!Plane reference;
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
        ChunkStructure structure = view.ensureChunkStructure(slot);
        assert(structure.isKnown);
        NodeState state = view.ensureState(slot);
        FlatLines flats = flatLinesNear(view.horospheres, view.ensureHorospheresAt(slot), cubeCenter(chunk));
        CubeClimate climate = CubeClimate.ensureAround(view, slot, chunk);
        if (flats.count > 0) {
            climate = climate.reachingFlat();
        }
        return ChunkParams(
            structure.building,
            strokesNear(strokesIn(structure.building), chunk),
            view.idAt(slot).spice(),
            view.ensureGrounds(slot),
            flats,
            climate,
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
        float center = ground(index).surface.distanceToChunk(chunk, Vec3!float(0.5f, 0.5f, 0.5f));
        return ValueRange(center - CUBE_GRID_RADIUS, center + CUBE_GRID_RADIUS);
    }

    bool isTilted(uint index) const {
        return index == BASE_GROUND && slopeTangent != 0;
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
            float across = asinhf(sinhf(reference.value.distanceTo(point)) / coshf(height));
            return atanf(sinhf(height)) + slopeTangent * across;
        }
    }

    ValueRange groundRange(uint index) const {
        Point!float middle = chunkPoint(chunk, Vec3!float(0.5f, 0.5f, 0.5f));
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
        } else if (climate.lowest.relief < palette.shape.waterLevel) {
            return higherOf(climate.highest.relief, palette.shape.waterLevel);
        } else {
            return climate.highest.relief;
        }
    }

    float thickestCrust(uint index) const {
        return higherOf(crustAt(ground(index).crust, climate.lowest.shield), crustAt(ground(index).crust, climate.highest.shield));
    }

    float thinnestCrust(uint index) const {
        return lowerOf(crustAt(ground(index).crust, climate.lowest.shield), crustAt(ground(index).crust, climate.highest.shield));
    }

    bool isBelowCrust(uint index) const {
        return altitudes(index).high < -(thickestCrust(index) + UNDERSIDE_SWING * climate.highest.relief);
    }

    bool isWithinCrust(uint index) const {
        return altitudes(index).low > -(thinnestCrust(index) + UNDERSIDE_SWING * climate.lowest.relief);
    }

    bool isClearOf(uint index) const {
        return ground(index).fill == Fill.none || groundRange(index).low > terrainCeiling(index) || isBelowCrust(index);
    }

    bool isFullOf(uint index) const {
        float highest = groundRange(index).high;
        final switch (ground(index).fill) {
            case Fill.none:
                return false;
            case Fill.flat:
                return highest < 0 && isWithinCrust(index);
            case Fill.terrain:
                return isProvenBelowTerrain(highest) && rivalsOf(index) == 0 && isWithinCrust(index);
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
        Occupancy predicted = Occupancy.unknown;
        if (!hasStructure && strokes.length == 0) {
            if (isClearOfAll()) {
                predicted = Occupancy.empty;
            } else if (isFullOfAny()) {
                predicted = Occupancy.full;
            }
        }
        return predicted;
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
                    generator.generateVeins();
                    break;
                case Fill.terrain:
                    generator.generateTerrain(index);
                    generator.generateVeins();
                    generator.generateTrees(index);
                    generator.generatePlants(index);
                    break;
            }
        }
        generator.generateStrokes();
        generator.generateStructure();
        generator.voxels.compress(dimension);
        generator.shares.release();
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
    PlaneMeasure[MOST_GROUNDS] surfaces;
    MeasuredLine[MOST_FLAT_LINES] flats;
    Array!float shares;
    float[ubyte.max] centers;

    void prepareCells() {
        if (cells == Readiness.pending) {
            toNode = params.chunk.cubeToNode;
            foreach (index; 0 .. params.grounds.count) {
                surfaces[index] = params.ground(index).surface.measure();
            }
            foreach (index; 0 .. params.flats.count) {
                flats[index] = MeasuredLine.of(params.flats.lines[index]);
            }
            if (params.flats.count > 0) {
                shares.resize(cast(size_t) params.dimension * params.dimension * params.dimension);
                shares.slice()[] = UNKNOWN_SHARE;
            }
            foreach (cell; 0 .. params.dimension) {
                centers[cell] = params.layout.cellCenterAlong(cell);
            }
            cells = Readiness.ready;
        }
    }

    float reliefShareAt(Vec3!uint cell) {
        if (params.flats.count == 0) {
            return 1;
        } else {
            size_t index = cellIndex(params.dimension, cell.x, cell.y, cell.z);
            if (shares.ptr[index] == UNKNOWN_SHARE) {
                Point!float point = cubePoint(toNode, centerOf(cell.x, cell.y, cell.z));
                float share = 1;
                foreach (ref line; flats[0 .. params.flats.count]) {
                    share = lowerOf(share, reliefShareAway(line.distanceTo(point)));
                }
                shares.ptr[index] = share;
            }
            return shares.ptr[index];
        }
    }

    Vec3!float centerOf(uint x, uint y, uint z) const {
        return Vec3!float(centers[x], centers[y], centers[z]);
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
        if (altitudes.low <= params.terrainCeiling(ground) && !params.isBelowCrust(ground)) {
            Maybe!Material rock = params.provenUniformRock(altitudes);
            uint rivals = params.rivalsOf(ground);
            bool whole = params.isWithinCrust(ground);
            if (rock.exists && rivals == 0 && whole) {
                fillEmpty(rock.value);
            } else if (params.materials == MaterialPass.deferring && !params.hasStructure && params.strokes.length == 0 && rivals == 0 && whole && params.isProvenBelowTerrain(altitudes.high)) {
                voxels = Voxels.filled(palette.standIn);
                materials = Materials.deferred;
            } else {
                prepareCells();
                double sinhClear = sinh(higherOf(params.climate.highest.relief, palette.shape.waterLevel) + CLEAR_MARGIN);
                foreach (x; 0 .. dimension) {
                    foreach (y; 0 .. dimension) {
                        foreach (z; 0 .. dimension) {
                            size_t index = cellIndex(dimension, x, y, z);
                            if (voxels.at(index) == Material.none) {
                                Point!float point = cubePoint(toNode, centerOf(x, y, z));
                                if (!(surfaces[ground].sinhDistanceTo(point) > sinhClear)) {
                                    float altitude = surfaces[ground].distanceTo(point);
                                    if (rivals == 0 || isNearest(ground, altitude, point)) {
                                        generateTerrainVoxel(ground, Vec3!uint(x, y, z), altitude, index);
                                    }
                                }
                            }
                        }
                    }
                    yield.now();
                }
            }
        }
    }

    void generateVeins() {
        if (materials != Materials.deferred && !voxels.isFilledWith(Material.none)) {
            SplitMix veins = SplitMix(params.nodeSpice ^ (cast(ulong) params.chunk << CHUNK_ROLL_SHIFT) ^ VEIN_SALT);
            int radius = palette.shape.veinRadius;
            if (veins.roll() < palette.shape.veinOdds) {
                ubyte dimension = params.dimension;
                Vec3!int center = Vec3!int(cast(int)(veins.next() % dimension), cast(int)(veins.next() % dimension), cast(int)(veins.next() % dimension));
                Material rock = voxels.at(cellIndex(dimension, center.x, center.y, center.z));
                Material ore = oreFor(rock);
                if (ore != Material.none) {
                    foreach (x; higherOf(center.x - radius, 0) .. lowerOf(center.x + radius + 1, cast(int) dimension)) {
                        foreach (y; higherOf(center.y - radius, 0) .. lowerOf(center.y + radius + 1, cast(int) dimension)) {
                            foreach (z; higherOf(center.z - radius, 0) .. lowerOf(center.z + radius + 1, cast(int) dimension)) {
                                size_t index = cellIndex(dimension, x, y, z);
                                int dx = x - center.x;
                                int dy = y - center.y;
                                int dz = z - center.z;
                                if (dx * dx + dy * dy + dz * dz <= radius * radius && voxels.at(index) == rock && SplitMix(params.nodeSpice ^ VEIN_SALT ^ (cast(ulong) params.chunk << CHUNK_ROLL_SHIFT) ^ index).roll() < palette.shape.veinFill) {
                                    voxels.toDense(dimension)[index] = ore;
                                }
                            }
                        }
                    }
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
                        setIfEmpty(Vec3!int(x, y, z), material);
                    }
                }
            }
        }
    }

    void generateFlat(uint ground) {
        ubyte dimension = params.dimension;
        ValueRange range = params.groundRange(ground);
        Maybe!Material rock = uniformRock(-range.high, -range.low, params.climate.lowest, params.climate.highest);
        bool buried = range.high < 0 && params.isWithinCrust(ground);
        if (buried && -range.low < palette.shape.soilDepth) {
            fillEmpty(palette.flatFill);
        } else if (buried && rock.exists) {
            fillEmpty(rock.value);
        } else if (buried && params.materials == MaterialPass.deferring && !params.hasStructure && params.strokes.length == 0 && voxels.isFilledWith(Material.none)) {
            voxels = Voxels.filled(palette.standIn);
            materials = Materials.deferred;
        } else if (range.low <= 0 && !params.isBelowCrust(ground)) {
            prepareCells();
            foreach (x; 0 .. dimension) {
                foreach (y; 0 .. dimension) {
                    foreach (z; 0 .. dimension) {
                        Point!float point = cubePoint(toNode, centerOf(x, y, z));
                        float altitude = surfaces[ground].distanceTo(point);
                        float level = params.levelFrom(ground, altitude, point);
                        Climate here = climateOfCell(Vec3!uint(x, y, z));
                        if (level < 0 && altitude > -undersideOf(params.ground(ground).crust, here)) {
                            setIfEmpty(Vec3!int(x, y, z), underAt(-level, here));
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
                        Material material = params.building.materialAt(params.chunk, Vec3!int(x, y, z), existing);
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

    Climate climateOfCell(Vec3!uint cell) {
        Climate here = params.climate.at(centerOf(cell.x, cell.y, cell.z));
        here.relief = here.relief * reliefShareAt(cell);
        return here;
    }

    float depthAt(uint ground, Vec3!uint cell) {
        return climateOfCell(cell).relief - surfaces[ground].distanceTo(cubePoint(toNode, centerOf(cell.x, cell.y, cell.z)));
    }

    float riserAt(uint ground, Vec3!uint cell, float depth) {
        float most = 0;
        foreach (axis; 0 .. 3) {
            Vec3!uint beside = cell;
            if (cell[axis] + 1 < params.dimension) {
                beside[axis] += 1;
            } else {
                beside[axis] -= 1;
            }
            most = higherOf(most, fabsf(depthAt(ground, beside) - depth));
        }
        return RISER_MARGIN * most;
    }

    void generateTerrainVoxel(uint ground, Vec3!uint cell, float altitude, size_t index) {
        Climate here = climateOfCell(cell);
        float depth = here.relief - altitude;
        Material material;
        if (!(altitude > -undersideOf(params.ground(ground).crust, here))) {
            material = Material.none;
        } else if (depth >= palette.shape.coverDepth && depth < palette.shape.soilDepth) {
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
        if (!voxels.isUniform() && dimension > LEAST_TREE_DIMENSION && hasTrees()) {
            Climate mean = params.climate.mean();
            Shape shape = palette.shape;
            float density = clamped(shape.baseTreeDensity + mean.wetness / shape.wetnessPerTreeDensity, shape.leastTreeDensity, shape.mostTreeDensity);
            uint interior = dimension - 2;
            uint candidateCount = cast(uint)(cast(float)(interior * interior * interior) * density);
            foreach (_; 0 .. candidateCount) {
                int x = cast(int)(1 + (rng.next() % interior));
                int y = cast(int)(1 + (rng.next() % interior));
                int z = cast(int)(1 + (rng.next() % interior));
                ulong roll = rng.next();
                placeTree(ground, Vec3!int(x, y, z), treeAt(mean.warmth(), mean.wetness, roll));
            }
        }
    }

    void generatePlants(uint ground) {
        ubyte dimension = params.dimension;
        if (!voxels.isUniform() && dimension > LEAST_TREE_DIMENSION && palette.plants.length > 0) {
            Climate mean = params.climate.mean();
            Material plant = palette.plants.slice().laidBy(mean.warmth(), mean.wetness, mean.relief);
            uint interior = dimension - 2;
            uint candidateCount = cast(uint)(cast(float)(interior * interior * interior) * palette.shape.plantDensity);
            SplitMix plants = SplitMix(params.nodeSpice ^ (cast(ulong) params.chunk << CHUNK_ROLL_SHIFT) ^ PLANT_SALT);
            prepareCells();
            foreach (_; 0 .. candidateCount) {
                Vec3!int base = Vec3!int(cast(int)(1 + plants.next() % interior), cast(int)(1 + plants.next() % interior), cast(int)(1 + plants.next() % interior));
                if (voxels.at(cellIndex(dimension, base.x, base.y, base.z)) == Material.none && reliefShareAt(Vec3!uint(base.x, base.y, base.z)) > 0) {
                    Vec3!int up = CELL_STEPS[params.ground(ground).surface.risingNeighbor(params.chunk, params.layout, base)];
                    Material below = voxels.at(cellIndex(dimension, base.x - up.x, base.y - up.y, base.z - up.z));
                    if (voxels.at(cellIndex(dimension, base.x + up.x, base.y + up.y, base.z + up.z)) == Material.none && isGroundForPlant(plant, below)) {
                        voxels.toDense(dimension)[cellIndex(dimension, base.x, base.y, base.z)] = plant;
                    }
                }
            }
        }
    }

    void placeTree(uint ground, Vec3!int base, uint kind) {
        ubyte dimension = params.dimension;
        prepareCells();
        if (voxels.at(cellIndex(dimension, base.x, base.y, base.z)) == Material.none && reliefShareAt(Vec3!uint(base.x, base.y, base.z)) > 0) {
            int upDirection = params.ground(ground).surface.risingNeighbor(params.chunk, params.layout, base);
            Vec3!int up = CELL_STEPS[upDirection];
            if (voxels.at(cellIndex(dimension, base.x + up.x, base.y + up.y, base.z + up.z)) == Material.none && isGroundFor(kind, voxels.at(cellIndex(dimension, base.x - up.x, base.y - up.y, base.z - up.z)))) {
                Tree species = treeOf(kind);
                ulong roll = rng.next();
                TreeFrame frame = TreeFrame.fromUp(base, upDirection, cast(int)(species.minTrunk + roll % species.trunkChoices), species.form.above, species.reach);
                if (frame.fitsWithin(dimension)) {
                    growTree(frame, species);
                }
            }
        }
    }

    void growTree(TreeFrame frame, ref const Tree species) {
        int reach = frame.reach;
        Material[Part.max + 1] grown = [Part.none: Material.none, Part.wood: species.wood, Part.heart: species.heart, Part.leaves: species.leaves];
        foreach (level; 0 .. frame.top + 1) {
            foreach (i; -reach .. reach + 1) {
                foreach (j; -reach .. reach + 1) {
                    Material material = grown[species.form.shape(frame.trunk, level, i, j)];
                    if (material != Material.none) {
                        setIfEmpty(frame.cell(level, i, j), material);
                    }
                }
            }
        }
    }

    void setIfEmpty(Vec3!int cell, Material material) {
        size_t index = cellIndex(params.dimension, cell.x, cell.y, cell.z);
        if (voxels.at(index) == Material.none) {
            voxels.toDense(params.dimension)[index] = material;
        }
    }
}

struct TreeFrame {
    Vec3!int base;
    Vec3!int up;
    size_t across;
    size_t along;
    int trunk;
    int top;
    int reach;

    static TreeFrame fromUp(Vec3!int base, int upDirection, int trunk, int above, int reach) {
        size_t axis = upDirection / 2;
        return TreeFrame(base, CELL_STEPS[upDirection], (axis + 1) % 3, (axis + 2) % 3, trunk, trunk + above, reach);
    }

    Vec3!int cell(int level, int i, int j) const {
        Vec3!int result = Vec3!int(base.x + up.x * level, base.y + up.y * level, base.z + up.z * level);
        result[across] += i;
        result[along] += j;
        return result;
    }

    bool fitsWithin(ubyte dimension) const {
        return isInside(dimension, cell(0, -reach, -reach)) && isInside(dimension, cell(top, reach, reach));
    }
}
