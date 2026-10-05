module common.worldgen.building;

import common.array : Array;
import common.coords : CELL_NEIGHBOR_OFFSETS, Coords;
import common.dodeca : SIDE_COUNT, Side, VERTEX_COUNT, Vertex, adjacentVertices, canonicalSides, chunkAxisPermutations, chunkToNode, opposite;
import common.material : Material;
import common.math : MPoint, MVector;
import common.node : ChunkLayout;
import common.worldgen.plane : Plane;
import common.worldgen.tower : NodeStructure, TOWER_PALETTES, TowerPalette, TowerSymbol, faceBit;

enum int STORY_LAYERS = 4;
enum int FLOOR_LAYER = 0;
enum int WINDOW_LAYER = 2;
enum int HEADROOM_BLOCKS = 3;
enum int MAX_CLEARANCE_CELLS = 8;
enum int NO_CLEARANCE = -1;
enum int PRISM_WIDTH = 7;
enum int CORE_WIDTH = 8;
enum int SPIRE_WIDTH = 2;
enum int WINDOW_PERIOD = 2;
enum uint PORTAL_VERTEX_RANK = 0;
enum int PORTAL_INSET = 1;
enum int PORTAL_WALL_INSET = 2;
enum int EDGE_COST_PER_CELL = 4;
enum long GRAVITY_FLIP_COST = 1L << 32;
enum long UNREACHED_COST = long.max;
enum ubyte FAR_FROM_WALL = ubyte.max;
enum int PORTAL_NEIGHBOR_SHIFT = -1;
enum uint DOOR_VERTEX_RANK = 1;
enum int DOOR_EDGE_OFFSET = 1;
enum int DOOR_WIDTH = 2;
enum int DOOR_SILL = 0;
enum int DOOR_HEIGHT = 2;
enum int NO_CELL = -1;
enum int SOURCE_PARENT = -1;

enum Stamp : ubyte {
    none,
    air,
    solid,
}

struct BuildingShape {
    Plane surface;
    ushort prisms;
    ushort outgoing;
    ChunkLayout layout;
    Side down;
    TowerPalette palette;
    bool isFoundation;
    bool hasDoor;
    bool hasSpire;

    static BuildingShape make(NodeStructure structure, Plane surface, ChunkLayout layout) {
        return BuildingShape(
            surface,
            structure.incoming | structure.outgoing,
            structure.outgoing,
            layout,
            structure.part.down,
            TOWER_PALETTES[structure.part.palette],
            structure.part.symbol == TowerSymbol.foundation,
            structure.part.symbol == TowerSymbol.base,
            structure.part.isGrowing() && structure.outgoing == 0,
        );
    }

    Material materialAt(Vertex vertex, int[3] cell, Material existing) const {
        if (!isInBuilding(vertex, cell)) {
            return spireMaterial(vertex, cell, existing);
        } else if (isFoundation) {
            return palette.wall;
        } else if (isWall(vertex, cell)) {
            return wallMaterial(vertex, cell);
        } else if (isStoryLayer(vertex, cell, FLOOR_LAYER)) {
            return palette.floor;
        } else {
            return Material.none;
        }
    }

    ubyte dimension() const {
        return layout.dimension;
    }

    size_t prismAxis(Vertex vertex, int[3] cell) const {
        size_t axis = 0;
        while (axis < 3 && !(isPrism(vertex, cell, axis) && cell[axis] < innerEdge())) {
            axis += 1;
        }
        return axis;
    }

    bool isStoryLayer(Vertex vertex, int[3] cell, int storyLayer) const {
        size_t axis = prismAxis(vertex, cell);
        if (axis < 3) {
            return storyLayerOf(vertex.canonicalSides[axis] == down, cell[axis]) == storyLayer;
        } else {
            uint rising = surface.risingNeighbor(vertex, layout, cell);
            return storyLayerOf(CELL_NEIGHBOR_OFFSETS[rising][rising / 2] > 0, cell[rising / 2]) == storyLayer;
        }
    }

    int storyLayerOf(bool isRisingWithCoord, int coord) const {
        if (isRisingWithCoord) {
            return (coord + 1) % STORY_LAYERS;
        } else {
            return (STORY_LAYERS - coord % STORY_LAYERS) % STORY_LAYERS;
        }
    }

    int innerEdge() const {
        return dimension - PRISM_WIDTH;
    }

    bool isPrism(Vertex vertex, int[3] cell, size_t axis) const {
        return (prisms & faceBit(vertex.canonicalSides[axis])) != 0 && cell[(axis + 1) % 3] >= innerEdge() && cell[(axis + 2) % 3] >= innerEdge();
    }

    bool isCore(int[3] cell) const {
        int coreEdge = dimension - CORE_WIDTH;
        return prisms != 0 && cell[0] >= coreEdge && cell[1] >= coreEdge && cell[2] >= coreEdge;
    }

    bool isInBuilding(Vertex vertex, int[3] cell) const {
        return isCore(cell) || isPrism(vertex, cell, 0) || isPrism(vertex, cell, 1) || isPrism(vertex, cell, 2);
    }

    bool isNeighborInBuilding(Vertex vertex, int[3] cell, uint direction) const {
        int neighbor = neighborIndex(cellIndex(vertex, cell), direction);
        return neighbor == NO_CELL || isInBuilding(vertexOf(neighbor), cellOf(neighbor));
    }

    uint outsideDirection(Vertex vertex, int[3] cell) const {
        uint direction = 0;
        while (direction < CELL_NEIGHBOR_OFFSETS.length && isNeighborInBuilding(vertex, cell, direction)) {
            direction += 1;
        }
        return direction;
    }

    bool isWall(Vertex vertex, int[3] cell) const {
        return outsideDirection(vertex, cell) < CELL_NEIGHBOR_OFFSETS.length;
    }

    Material wallMaterial(Vertex vertex, int[3] cell) const {
        if (isDoor(vertex, cell) || isWindow(vertex, cell)) {
            return Material.none;
        } else {
            return palette.wall;
        }
    }

    bool isWindow(Vertex vertex, int[3] cell) const {
        uint outside = outsideDirection(vertex, cell);
        uint rising = surface.risingNeighbor(vertex, layout, cell);
        bool isOffSeam = cell[0] < dimension - 1 && cell[1] < dimension - 1 && cell[2] < dimension - 1;
        return isOffSeam && outside / 2 != rising / 2 && (cell[0] + cell[1] + cell[2]) % WINDOW_PERIOD == 1 && isStoryLayer(vertex, cell, WINDOW_LAYER);
    }

    bool isDoor(Vertex vertex, int[3] cell) const {
        FaceFrame frame = FaceFrame.make(down, DOOR_VERTEX_RANK);
        return hasDoor && vertex == frame.vertex && cell[frame.across] == innerEdge() && cell[frame.along] >= dimension - DOOR_EDGE_OFFSET - DOOR_WIDTH && cell[frame.along] < dimension - DOOR_EDGE_OFFSET && cell[frame.axis] >= DOOR_SILL && cell[frame.axis] < DOOR_SILL + DOOR_HEIGHT;
    }

    Material spireMaterial(Vertex vertex, int[3] cell, Material existing) const {
        size_t axis = sideAxis(vertex, down.opposite);
        bool isSpire = hasSpire && axis < 3 && cell[(axis + 1) % 3] >= dimension - SPIRE_WIDTH && cell[(axis + 2) % 3] >= dimension - SPIRE_WIDTH && cell[axis] >= dimension / 2 && cell[axis] < innerEdge();
        if (isSpire) {
            return palette.spire;
        } else {
            return existing;
        }
    }

    int cellsPerChunk() const {
        return dimension * dimension * dimension;
    }

    int cellIndex(Vertex vertex, int[3] cell) const {
        return vertex * cellsPerChunk() + (cell[0] * dimension + cell[1]) * dimension + cell[2];
    }

    Vertex vertexOf(int index) const {
        return cast(Vertex)(index / cellsPerChunk());
    }

    int[3] cellOf(int index) const {
        int linear = index % cellsPerChunk();
        return [linear / (dimension * dimension), linear / dimension % dimension, linear % dimension];
    }

    int neighborIndex(int index, uint direction) const {
        Vertex vertex = vertexOf(index);
        int[3] offset = CELL_NEIGHBOR_OFFSETS[direction];
        int[3] cell = cellOf(index);
        int[3] neighbor = [cell[0] + offset[0], cell[1] + offset[1], cell[2] + offset[2]];
        size_t axis = direction / 2;
        if (neighbor[axis] < 0) {
            return NO_CELL;
        } else if (neighbor[axis] < dimension) {
            return cellIndex(vertex, neighbor);
        } else {
            neighbor[axis] = dimension - 1;
            Coords across = vertex.chunkAxisPermutations[axis].apply(Coords([cast(ubyte) neighbor[0], cast(ubyte) neighbor[1], cast(ubyte) neighbor[2]]));
            return cellIndex(vertex.adjacentVertices[axis], [across.data[0], across.data[1], across.data[2]]);
        }
    }

    uint carriedDirection(int from, int to, uint crossing, uint direction) const {
        if (to == NO_CELL || vertexOf(to) == vertexOf(from)) {
            return direction;
        } else {
            uint crossingAxis = crossing / 2;
            uint axis = direction / 2;
            uint mapped = vertexOf(from).chunkAxisPermutations[crossingAxis].axes[axis];
            return directionIndex(mapped, (direction % 2 == 1) != (axis == crossingAxis));
        }
    }

    bool isInteriorAt(int index) const {
        return index == NO_CELL || (isInBuilding(vertexOf(index), cellOf(index)) && !isWall(vertexOf(index), cellOf(index)));
    }

    bool isInBuildingAt(int index) const {
        return index == NO_CELL || isInBuilding(vertexOf(index), cellOf(index));
    }

    MPoint!float cellCenter(int index) const {
        float[3] center = layout.cellCenter(cellOf(index));
        return (vertexOf(index).chunkToNode * MVector!float([center[0], center[1], center[2], 1.0f])).normalizedPoint();
    }

    int aboveAt(int index) const {
        return neighborIndex(index, surface.risingNeighbor(vertexOf(index), layout, cellOf(index)));
    }

    int portal(Side face, int alongShift) const {
        FaceFrame frame = FaceFrame.make(face, PORTAL_VERTEX_RANK);
        int[3] cell;
        cell[frame.axis] = 0;
        cell[frame.along] = dimension - PORTAL_INSET + alongShift;
        cell[frame.across] = innerEdge() + PORTAL_WALL_INSET;
        return cellIndex(frame.vertex, cell);
    }

    int doorStep() const {
        FaceFrame frame = FaceFrame.make(down, DOOR_VERTEX_RANK);
        int[3] cell;
        cell[frame.axis] = DOOR_SILL;
        cell[frame.along] = dimension - DOOR_EDGE_OFFSET - DOOR_WIDTH;
        cell[frame.across] = innerEdge() + 1;
        return cellIndex(frame.vertex, cell);
    }
}

struct Building {
    Array!Stamp stamps;
    Array!int route;
    BuildingShape shape;
    uint reached;
    uint flips;
    uint edgeDistance;
    ushort connected;

    static Building make(NodeStructure structure, Plane surface, ChunkLayout layout) {
        Building building = Building(Array!Stamp.init, Array!int.init, BuildingShape.make(structure, surface, layout), 0, 0, 0, 0);
        if (!building.shape.isFoundation && building.shape.prisms != 0) {
            building.planStairs();
        }
        return building;
    }

    void release() {
        stamps.release();
        route.release();
    }

    Material materialAt(Vertex vertex, int[3] cell, Material existing) const {
        Stamp stamp = stampAt(vertex, cell);
        if (stamp == Stamp.solid) {
            return shape.palette.floor;
        } else if (stamp == Stamp.air) {
            return Material.none;
        } else {
            return shape.materialAt(vertex, cell, existing);
        }
    }

    Stamp stampAt(Vertex vertex, int[3] cell) const {
        if (stamps.length == 0) {
            return Stamp.none;
        } else {
            return stamps.ptr[shape.cellIndex(vertex, cell)];
        }
    }

    void planStairs() {
        stamps.resize(VERTEX_COUNT * shape.cellsPerChunk());
        StairSearch search = StairSearch.make(shape, stamps.ptr);
        int source = entry(search);
        foreach (index; 0 .. SIDE_COUNT) {
            Side face = cast(Side) index;
            int target = shape.portal(face, 0);
            if ((shape.outgoing & faceBit(face)) != 0) {
                search.run(source);
                if (search.settled > reached) {
                    reached = search.settled;
                }
                if (search.isReached(target)) {
                    connected |= faceBit(face);
                    stampPath(search, target);
                    if (search.isVerticalCrossing(face)) {
                        stampSolid(shape.portal(face, PORTAL_NEIGHBOR_SHIFT));
                    }
                }
            }
        }
        search.release();
    }

    int entry(ref StairSearch search) {
        if (shape.hasDoor) {
            return shape.doorStep();
        } else if (search.isVerticalCrossing(shape.down)) {
            int lowerHead = shape.portal(shape.down, 0);
            foreach (height; 0 .. search.clearance(lowerHead) + 1) {
                stampAir(search.raised(lowerHead, height));
            }
            return shape.portal(shape.down, PORTAL_NEIGHBOR_SHIFT);
        } else {
            return shape.portal(shape.down, 0);
        }
    }

    void stampPath(ref StairSearch search, int target) {
        Array!int path;
        int cell = target;
        while (cell != SOURCE_PARENT) {
            path.append(cell);
            cell = search.parentOf(cell);
        }
        if (search.flipsTo(target) > flips) {
            flips = search.flipsTo(target);
        }
        foreach (step; path.slice()) {
            if (search.wallDistances.ptr[step] > edgeDistance) {
                edgeDistance = search.wallDistances.ptr[step];
            }
            foreach (height; 0 .. search.clearance(step) + 1) {
                stampAir(search.raised(step, height));
            }
        }
        foreach (step; path.slice()) {
            stampSolid(search.below(step));
        }
        foreach (step; path.slice()) {
            int depth = 2;
            int fill = search.sunk(step, depth);
            while (fill != NO_CELL && stamps.ptr[fill] == Stamp.none && shape.isInteriorAt(fill) && !shape.isStoryLayer(shape.vertexOf(fill), shape.cellOf(fill), FLOOR_LAYER)) {
                stamps.ptr[fill] = Stamp.solid;
                depth += 1;
                fill = search.sunk(step, depth);
            }
        }
        foreach (step; path.slice()) {
            foreach (height; 0 .. search.clearance(step) + 1) {
                stampAirBeside(search.column(step, height), height == 0);
            }
        }
        if (route.length == 0) {
            foreach_reverse (step; path.slice()) {
                route.append(step);
            }
        }
        path.release();
    }

    void stampAirBeside(Straight column, bool isTread) {
        if (column.cell != NO_CELL) {
            foreach (direction; 0 .. cast(uint) CELL_NEIGHBOR_OFFSETS.length) {
                int side = shape.neighborIndex(column.cell, direction);
                if (direction / 2 != column.heading / 2 && side != NO_CELL && shape.isInteriorAt(side)) {
                    stampAir(side);
                    if (isTread) {
                        stampTread(shape.neighborIndex(side, shape.carriedDirection(column.cell, side, direction, column.heading ^ 1)));
                    }
                }
            }
        }
    }

    void stampTread(int cell) {
        if (cell != NO_CELL && shape.isInteriorAt(cell)) {
            stampSolid(cell);
        }
    }

    void stampAir(int cell) {
        if (cell != NO_CELL && stamps.ptr[cell] == Stamp.none) {
            stamps.ptr[cell] = Stamp.air;
        }
    }

    void stampSolid(int cell) {
        if (cell != NO_CELL && stamps.ptr[cell] == Stamp.none) {
            stamps.ptr[cell] = Stamp.solid;
        }
    }
}

struct HeapEntry {
    long cost;
    int cell;
}

struct CostHeap {
    Array!HeapEntry entries;

    bool isEmpty() const {
        return entries.length == 0;
    }

    void push(HeapEntry entry) {
        entries.append(entry);
        size_t index = entries.length - 1;
        while (index > 0 && entries.ptr[(index - 1) / 2].cost > entries.ptr[index].cost) {
            swap(index, (index - 1) / 2);
            index = (index - 1) / 2;
        }
    }

    HeapEntry pop() {
        HeapEntry top = entries.ptr[0];
        entries.ptr[0] = entries.ptr[entries.length - 1];
        entries.resize(entries.length - 1);
        size_t index = 0;
        size_t child = smallerChild(index);
        while (child < entries.length && entries.ptr[child].cost < entries.ptr[index].cost) {
            swap(index, child);
            index = child;
            child = smallerChild(index);
        }
        return top;
    }

    size_t smallerChild(size_t index) const {
        size_t left = 2 * index + 1;
        if (left + 1 < entries.length && entries.ptr[left + 1].cost < entries.ptr[left].cost) {
            return left + 1;
        } else {
            return left;
        }
    }

    void swap(size_t a, size_t b) {
        HeapEntry held = entries.ptr[a];
        entries.ptr[a] = entries.ptr[b];
        entries.ptr[b] = held;
    }
}

struct StairSearch {
    Array!long costs;
    Array!int parents;
    Array!byte risings;
    Array!ubyte wallDistances;
    CostHeap heap;
    const(BuildingShape)* shape;
    const(Stamp)* stamps;
    uint settled;

    static StairSearch make(ref const BuildingShape shape, const(Stamp)* stamps) {
        StairSearch search = StairSearch(Array!long.init, Array!int.init, Array!byte.init, Array!ubyte.init, CostHeap.init, &shape, stamps, 0);
        size_t cellCount = VERTEX_COUNT * shape.cellsPerChunk();
        search.parents.resize(cellCount);
        search.costs.resize(cellCount);
        search.risings.resize(cellCount);
        search.measureWallDistances();
        return search;
    }

    void release() {
        parents.release();
        costs.release();
        risings.release();
        wallDistances.release();
        heap.entries.release();
    }

    bool isLateral(int cell, uint direction) {
        return direction / 2 != risingAt(cell) / 2;
    }

    bool isBesideWall(int cell) {
        uint direction = 0;
        while (direction < CELL_NEIGHBOR_OFFSETS.length && shape.isInteriorAt(shape.neighborIndex(cell, direction))) {
            direction += 1;
        }
        return direction < CELL_NEIGHBOR_OFFSETS.length;
    }

    void measureWallDistances() {
        wallDistances.resize(parents.length);
        Array!int frontier;
        foreach (cell; 0 .. cast(int) parents.length) {
            if (shape.isInteriorAt(cell) && isBesideWall(cell)) {
                frontier.append(cell);
            } else {
                wallDistances.ptr[cell] = FAR_FROM_WALL;
            }
        }
        size_t front = 0;
        while (front < frontier.length) {
            int cell = frontier.ptr[front];
            foreach (direction; 0 .. cast(uint) CELL_NEIGHBOR_OFFSETS.length) {
                int neighbor = shape.neighborIndex(cell, direction);
                if (neighbor != NO_CELL && wallDistances.ptr[neighbor] == FAR_FROM_WALL && shape.isInteriorAt(neighbor) && wallDistances.ptr[cell] + 1 < FAR_FROM_WALL) {
                    wallDistances.ptr[neighbor] = cast(ubyte)(wallDistances.ptr[cell] + 1);
                    frontier.append(neighbor);
                }
            }
            front += 1;
        }
        frontier.release();
    }

    int stepCost(int cell) {
        return 1 + EDGE_COST_PER_CELL * wallDistances.ptr[cell];
    }

    int risingAt(int cell) {
        if (risings.ptr[cell] == 0) {
            risings.ptr[cell] = cast(byte)(shape.surface.risingNeighbor(shape.vertexOf(cell), shape.layout, shape.cellOf(cell)) + 1);
        }
        return risings.ptr[cell] - 1;
    }

    int below(int cell) {
        if (cell == NO_CELL) {
            return NO_CELL;
        } else {
            return shape.neighborIndex(cell, risingAt(cell) ^ 1);
        }
    }

    Straight straightFrom(int cell, uint direction, int count) {
        Straight straight = Straight(cell, direction);
        int steps = 0;
        while (steps < count && straight.cell != NO_CELL) {
            int next = shape.neighborIndex(straight.cell, straight.heading);
            straight = Straight(next, shape.carriedDirection(straight.cell, next, straight.heading, straight.heading));
            steps += 1;
        }
        return straight;
    }

    Straight column(int walk, int height) {
        if (walk == NO_CELL) {
            return Straight(NO_CELL, 0);
        } else {
            return straightFrom(walk, risingAt(walk), height);
        }
    }

    int raised(int cell, int height) {
        return column(cell, height).cell;
    }

    int sunk(int walk, int depth) {
        return straightFrom(walk, risingAt(walk) ^ 1, depth).cell;
    }

    int clearance(int walk) {
        int height = 0;
        while (height < MAX_CLEARANCE_CELLS && isOpen(raised(walk, height)) && height + 1 < HEADROOM_BLOCKS) {
            height += 1;
        }
        int cell = raised(walk, height);
        if (height < MAX_CLEARANCE_CELLS && (cell == NO_CELL || isOpen(cell))) {
            return height;
        } else {
            return NO_CLEARANCE;
        }
    }

    bool isOpen(int cell) {
        return cell != NO_CELL && shape.isInteriorAt(cell) && stamps[cell] != Stamp.solid;
    }

    bool isWalkable(int cell) {
        int support = below(cell);
        return cell != NO_CELL && clearance(cell) != NO_CLEARANCE && shape.isInBuildingAt(support) && (support == NO_CELL || stamps[support] != Stamp.air);
    }

    bool isVerticalCrossing(Side face) {
        return risingAt(shape.portal(face, 0)) / 2 == FaceFrame.make(face, PORTAL_VERTEX_RANK).axis;
    }

    bool isReached(int cell) {
        return parents.ptr[cell] != 0;
    }

    int parentOf(int cell) {
        int parent = parents.ptr[cell];
        if (parent == SOURCE_PARENT) {
            return SOURCE_PARENT;
        } else {
            return parent - 1;
        }
    }

    void relax(int cell, int parent, long extraCost) {
        if (cell != NO_CELL) {
            long cost = costs.ptr[parent] + stepCost(cell) + extraCost;
            if (cost < costs.ptr[cell] && isWalkable(cell) && isClearOfPath(cell, parent)) {
                parents.ptr[cell] = parent + 1;
                costs.ptr[cell] = cost;
                heap.push(HeapEntry(cost, cell));
            }
        }
    }

    bool isInClearance(int walk, int cell) {
        int top = clearance(walk);
        int height = 0;
        while (height <= top && raised(walk, height) != cell) {
            height += 1;
        }
        return cell != NO_CELL && height <= top;
    }

    Column columnBelow(int walk) {
        Column column;
        int current = sunk(walk, 1);
        while (column.count < column.cells.length && current != NO_CELL) {
            column.cells[column.count] = current;
            column.count += 1;
            current = sunk(walk, column.count + 1);
        }
        return column;
    }

    Column columnAbove(int cell, int top) {
        Column column;
        foreach (height; 0 .. top + 1) {
            column.cells[column.count] = raised(cell, height);
            column.count += 1;
        }
        return column;
    }

    bool isConflicting(int ancestor, ref const Column underSupport, int support, ref const Column overWalk) {
        bool isSupportInClearance = underSupport.contains(ancestor) && isInClearance(ancestor, support);
        return isSupportInClearance || overWalk.contains(below(ancestor));
    }

    bool isClearOfPath(int walk, int parent) {
        int support = below(walk);
        Column underSupport = columnBelow(walk);
        Column overWalk = columnAbove(walk, clearance(walk));
        int ancestor = parent;
        while (ancestor != SOURCE_PARENT && !isConflicting(ancestor, underSupport, support, overWalk)) {
            ancestor = parentOf(ancestor);
        }
        return ancestor == SOURCE_PARENT;
    }

    void run(int source) {
        size_t cellCount = parents.length;
        parents.clear();
        parents.resize(cellCount);
        foreach (cell; 0 .. cellCount) {
            costs.ptr[cell] = UNREACHED_COST;
        }
        heap.entries.clear();
        settled = 0;
        if (isWalkable(source)) {
            parents.ptr[source] = SOURCE_PARENT;
            costs.ptr[source] = 0;
            heap.push(HeapEntry(0, source));
        }
        while (!heap.isEmpty()) {
            HeapEntry entry = heap.pop();
            if (entry.cost == costs.ptr[entry.cell]) {
                settled += 1;
                expand(entry.cell);
            }
        }
    }

    void expand(int cell) {
        uint rising = risingAt(cell);
        foreach (direction; 0 .. cast(uint) CELL_NEIGHBOR_OFFSETS.length) {
            int neighbor = shape.neighborIndex(cell, direction);
            if (isLateral(cell, direction) && neighbor != NO_CELL) {
                long flip = flipCost(neighbor, shape.carriedDirection(cell, neighbor, direction, rising));
                relax(neighbor, cell, flip);
                relax(shape.neighborIndex(neighbor, risingAt(neighbor)), cell, flip);
            }
        }
    }

    long flipCost(int cell, uint carriedRising) {
        if (risingAt(cell) == carriedRising) {
            return 0;
        } else {
            return GRAVITY_FLIP_COST;
        }
    }

    uint flipsTo(int cell) const {
        return cast(uint)(costs.ptr[cell] / GRAVITY_FLIP_COST);
    }
}

struct Straight {
    int cell;
    uint heading;
}

struct Column {
    int[MAX_CLEARANCE_CELLS + 1] cells;
    int count;

    bool contains(int cell) const {
        int index = 0;
        while (index < count && cells[index] != cell) {
            index += 1;
        }
        return cell != NO_CELL && index < count;
    }
}

struct FaceFrame {
    Vertex vertex;
    size_t axis;
    size_t along;
    size_t across;

    static FaceFrame make(Side face, uint rank) {
        uint seen = 0;
        uint index = 0;
        while (index < VERTEX_COUNT && !(sideAxis(cast(Vertex) index, face) < 3 && seen == rank)) {
            if (sideAxis(cast(Vertex) index, face) < 3) {
                seen += 1;
            }
            index += 1;
        }
        Vertex vertex = cast(Vertex) index;
        size_t axis = sideAxis(vertex, face);
        return FaceFrame(vertex, axis, (axis + 1) % 3, (axis + 2) % 3);
    }
}

uint directionIndex(uint axis, bool isPositive) {
    if (isPositive) {
        return 2 * axis + 1;
    } else {
        return 2 * axis;
    }
}

size_t sideAxis(Vertex vertex, Side side) {
    size_t axis = 0;
    while (axis < 3 && vertex.canonicalSides[axis] != side) {
        axis += 1;
    }
    return axis;
}
