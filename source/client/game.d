module client.game;

import core.stdc.math : atan2f, ceilf, fabsf, tanhf;
import client.camera : Camera;
import client.streaming : generateNow;
import client.world : LocalWorld, Placement;
import common.array : Array;
import common.character.controller : CharacterInput, CharacterState, MovementMode, Mover, Slide, Stepped;
import common.character.place : ChartCell, Place, Relocated, coordsOf, dominantAxis, gravityUp, initialUp, nearestChartCell, relocated;
import common.coords : Coords;
import common.character.sweep : Capsule, isCapsuleBlocked, isCapsuleOverlappingCell;
import common.character.warp : IDENTITY_WARP, applied, inverted, multiplied, smoothGridDirection, smoothWarp, transposed;
import common.dodeca : Side, faceDirection, faceDistance;
import common.graph : NodeId;
import common.material : Material;
import common.math : MIsometry, MPoint;
import common.node : ChunkSlot, GridSpacing;
import common.position : Position;
import common.settings : CharacterConfig, SimConfig, SimMeters, longestVoxelEdge;
import common.traversal : NearbyNode, NearbyScratch;
import common.vector3 : ZERO_VECTOR, cross, dot, magnitude, minus, negated, plus, rejectAlong, scaled;
import common.worldgen.building : Building;
import common.worldgen.generation : NodeState, Worldgen, WorldgenKind;
import common.worldgen.spawn : clearSpawnPosition, collectChunksNear;

enum float STRUCTURE_SEARCH_RADIUS = 4.0f;
enum float STAIR_SEARCH_RADIUS = 2.0f;
enum float WARP_INNER_METERS = 4.0f;
enum float WARP_OUTER_METERS = 16.0f;
enum float CELL_CENTER_HEIGHT_METERS = 0.5f;
enum float GENERATION_REACH_FACTOR = 2.0f;
enum float SPAWN_EDGE_MARGIN_METERS = 1.5f;
enum int STAIR_CHART_RADIUS = 5;

immutable Material[9] MATERIAL_PALETTE = [
    Material.woodPlanks,
    Material.oakWood,
    Material.oakLeaves,
    Material.greyBrick,
    Material.whiteBrick,
    Material.sandstone,
    Material.marble,
    Material.granite,
    Material.basalt,
];

enum Key : ubyte {
    fwd,
    back,
    left,
    right,
    up,
    down,
    yawLeft,
    yawRight,
    pitchUp,
    pitchDown,
}

enum uint KEY_COUNT = Key.max + 1;

struct FrameInput {
    float yaw = 0;
    float pitch = 0;
    bool[KEY_COUNT] isHeld;
}

float axisValue(bool isHeld) {
    if (isHeld) {
        return 1.0f;
    } else {
        return 0.0f;
    }
}

float[3] unit(float[3] v) {
    return v.scaled(1.0f / v.magnitude);
}

struct StairWaypoint {
    float yawRadians = 0;
    float horizontal = 0;
    float rise = 0;
    bool isFound;
}

struct StairCell {
    MPoint!float point;
    ChunkSlot chunk;
    Coords coords;
}

struct Game {
    LocalWorld world;
    Array!StairCell stairRoute;
    Camera camera;
    Position bodyView;
    CharacterState characterState;
    SimConfig simConfig;
    float simTime = 0;
    float traveled = 0;
    float altitude = 0;
    float cameraVerticalAcceleration = 0;
    float cameraAltitude = 0;
    float cameraVerticalVelocity = 0;
    float[3][3] bodyViewWarp = IDENTITY_WARP;
    uint materialIndex;
    MovementMode mode = MovementMode.walk;
    bool isSettlingWorldgenEachFrame;
    bool hasCameraVerticalVelocity;

    static Game make(Worldgen worldgen, float reachMeters) {
        SimMeters meters;
        SimConfig simConfig = SimConfig.fromMeters(meters);
        Game game;
        game.simConfig = simConfig;
        game.world = LocalWorld.make(meters.chunkSize, worldgen, tanhf(reachMeters * simConfig.metersToAbsolute));
        game.setWarpRadii();
        game.camera = Camera.make(simConfig.character.eyeOffset);
        game.placeAtSpawn();
        return game;
    }

    float bodyReach() const {
        CharacterConfig cfg = simConfig.character;
        return cfg.characterHalfHeight + cfg.characterRadius + cfg.contactSkin;
    }

    float metricBodyReach() const {
        return bodyReach() * longestVoxelEdge(world.graph.layout.dimension, world.graph.layout.spacing);
    }

    Capsule bodyCapsule() const {
        CharacterConfig cfg = simConfig.character;
        return Capsule(characterState.up, cfg.characterRadius, cfg.characterHalfHeight, cfg.contactSkin);
    }

    Position centerPosition(Place place) const {
        return Position(world.graph.idAt(place.chunk.slot), MIsometry!float.fromTranslation(MPoint!float.origin(), place.pointInNode(world.graph.layout)));
    }

    void generateAround(Place place, float metricReach) {
        Array!ChunkSlot chunks = world.graph.collectChunksNear(centerPosition(place), GENERATION_REACH_FACTOR * metricReach);
        foreach (chunk; chunks.slice()) {
            world.graph.generateNow(chunk);
        }
        chunks.release();
    }

    void placeAtSpawn() {
        float metricReach = metricBodyReach();
        Position spawn = world.graph.clearSpawnPosition(metricReach);
        Place place = Place.fromPosition(world.graph, spawn);
        float[3] up = world.graph.initialUp(place);
        place = offSingularEdges(place, up);
        Slide drop;
        while (!drop.hasLanded) {
            generateAround(place, metricReach);
            drop = Mover.make(simConfig.character, world.graph, up).settle(place, bodyReach());
            place = world.graph.relocated(drop.position).place;
            world.graph.ensureNodeStateAt(place.chunk.slot);
            up = world.graph.gravityUp(place, up, 0);
        }
        characterState = CharacterState(place, ZERO_VECTOR, drop.groundNormal, up, true);
        resetView();
        if (world.graph.worldgen.kind == WorldgenKind.structure) {
            camera.turn(yawToward(directionToNode(world.graph.worldgen.structure.base)), 0);
        } else if (world.graph.worldgen.groundTiltRadians() != 0) {
            camera.turn(yawToward(uphillDirection()), 0);
        }
        updateView();
    }

    Place offSingularEdges(Place place, float[3] up) const {
        size_t upAxis = dominantAxis(place.frame.toGrid(up));
        float highest = world.graph.layout.dimension - SPAWN_EDGE_MARGIN_METERS;
        Place result = place;
        foreach (axis; 0 .. 3) {
            if (axis != upAxis && result.grid[axis] > highest) {
                result.grid[axis] = highest;
            }
        }
        return result;
    }

    void resetView() {
        bodyView = centerPosition(characterState.position);
        camera = Camera.make(simConfig.character.eyeOffset);
        altitude = metricAltitude(characterState.position.moved(characterState.up.scaled(-bodyReach() + simConfig.character.characterRadius))) + bodyReach() - simConfig.character.characterRadius;
        followBody();
        camera.level();
        updateView();
        cameraAltitude = altitude + camera.eyeOffset;
        hasCameraVerticalVelocity = false;
    }

    float metricAltitude(Place place) {
        Place at = world.graph.relocated(place).place;
        world.graph.ensureNodeStateAt(at.chunk.slot);
        return world.graph.nodeAt(at.chunk.slot).state.surface.distanceTo(at.pointInNode(world.graph.layout));
    }

    MIsometry!float nodeTransform(NodeId node, float radius) {
        NearbyScratch scratch;
        NearbyNode[] nearby = scratch.collectAll(world.graph, bodyView, radius);
        size_t index = 0;
        while (index < nearby.length && nearby[index].id != node) {
            index += 1;
        }
        assert(index < nearby.length);
        MIsometry!float transform = nearby[index].transform;
        scratch.release();
        return transform;
    }

    float[3] directionToNode(NodeId node) {
        return (bodyView.local.inverse() * nodeTransform(node, STRUCTURE_SEARCH_RADIUS) * MPoint!float.origin()).vec.xyz();
    }

    float[3] uphillDirection() const {
        const(NodeState)* state = world.graph.nodeState(bodyView.node);
        return (bodyView.local.inverse() * state.reference.scaledNormal).xyz().negated;
    }

    float yawToward(float[3] direction) const {
        float[3] forward = camera.forward().rejectAlong(camera.viewUp);
        float[3] level = applied(bodyViewWarp, direction).rejectAlong(camera.viewUp);
        return atan2f(camera.viewUp.dot(forward.cross(level)), forward.dot(level));
    }

    void enterStructure(float metersUp) {
        float[3] up = Side.a.faceDirection.negated;
        float rise = metersUp * simConfig.metersToAbsolute - faceDistance();
        uint stepCount = cast(uint) ceilf(fabsf(rise) / faceDistance());
        Position target = Position(world.graph.worldgen.structure.base, MIsometry!float.identity());
        foreach (_; 0 .. stepCount) {
            target = world.graph.ensureNormalized(Position(target.node, (target.local * MIsometry!float.fromDisplacement(up.scaled(rise / stepCount))).renormalized()));
        }
        placeAt(target, 0);
    }

    bool enterStairs() {
        uint base = world.graph.slotOf(world.graph.worldgen.structure.base);
        Building building = Building.make(world.graph.ensureStructureAt(base), world.graph.nodeAt(base).state.surface, world.graph.layout);
        stairRoute.clear();
        foreach (cell; building.route.slice()) {
            stairRoute.append(StairCell(building.shape.cellCenter(cell), ChunkSlot(base, building.shape.vertexOf(cell)), coordsOf(building.shape.cellOf(cell))));
        }
        if (building.route.length > 0) {
            MPoint!float start = building.shape.cellCenter(building.route.ptr[0]);
            Position center = world.graph.ensureNormalized(Position(world.graph.worldgen.structure.base, MIsometry!float.fromTranslation(MPoint!float.origin(), start)));
            placeAt(center, bodyReach() - simConfig.character.characterRadius - CELL_CENTER_HEIGHT_METERS);
        }
        building.release();
        return stairRoute.length > 0;
    }

    StairWaypoint stairWaypoint(size_t index) {
        if (index < stairRoute.length) {
            Place place = characterState.position;
            float[3][3] jacobian = place.jacobian(world.graph.layout, bodyView.local);
            StairCell cell = stairRoute.ptr[index];
            ChartCell charted = world.graph.nearestChartCell(place, cell.chunk, cell.coords, STAIR_CHART_RADIUS);
            float[3] grid;
            if (charted.isFound) {
                grid = charted.center.minus(place.grid);
            } else {
                MIsometry!float toBase = nodeTransform(world.graph.worldgen.structure.base, STAIR_SEARCH_RADIUS);
                grid = applied(jacobian, (bodyView.local.inverse() * toBase * cell.point).vec.xyz());
            }
            float[3] meters = place.frame.toBody(grid);
            return StairWaypoint(yawToward(applied(inverted(jacobian), grid)), meters.rejectAlong(characterState.up).magnitude, meters.dot(characterState.up), true);
        } else {
            return StairWaypoint.init;
        }
    }

    void placeAt(Position target, float lift) {
        world.graph.ensureNodeState(target.node);
        Place place = Place.fromPosition(world.graph, target);
        float[3] up = world.graph.initialUp(place);
        characterState = CharacterState(world.graph.relocated(place.moved(up.scaled(lift))).place, ZERO_VECTOR, characterState.groundNormal, up, false);
        world.graph.ensureNodeStateAt(characterState.position.chunk.slot);
        resetView();
    }

    void cycleSpacing() {
        setSpacing(cast(GridSpacing)((world.graph.worldgen.spacing + 1) % (GridSpacing.max + 1)));
    }

    void setSpacing(GridSpacing spacing) {
        Worldgen worldgen = world.graph.worldgen;
        worldgen.spacing = spacing;
        Array!Side path = world.graph.sidesToRoot(bodyView.node);
        MPoint!float center = bodyView.local * MPoint!float.origin();
        rebuildWorld(worldgen);
        NodeId node = world.graph.ensureFromRoot(path.slice());
        path.release();
        world.graph.ensureNodeState(node);
        characterState.position.chunk.slot = world.graph.slotOf(node);
        MPoint!float moved = characterState.position.pointInNode(world.graph.layout);
        bodyView = Position(node, (MIsometry!float.fromTranslation(center, moved) * bodyView.local).renormalized());
        liftClear();
        followBody();
        updateView();
    }

    void liftClear() {
        float metricReach = metricBodyReach();
        Relocated lifted = Relocated(characterState.position, MIsometry!float.identity());
        generateAround(lifted.place, metricReach);
        while (world.graph.isCapsuleBlocked(bodyCapsule(), lifted.place)) {
            Relocated next = world.graph.relocated(lifted.place.moved(characterState.up));
            lifted = Relocated(next.place, next.toNode * lifted.toNode);
            altitude += 1;
            generateAround(lifted.place, metricReach);
        }
        characterState.position = lifted.place;
        moveView(lifted.toNode);
    }

    void setWorldgen(Worldgen worldgen) {
        rebuildWorld(worldgen);
        placeAtSpawn();
    }

    void rebuildWorld(Worldgen worldgen) {
        ubyte dimension = world.graph.layout.dimension;
        float reach = world.reach;
        uint epoch = world.epoch;
        world.release();
        stairRoute.clear();
        world = LocalWorld.make(dimension, worldgen, reach);
        world.epoch = epoch + 1;
        setWarpRadii();
    }

    void setWarpRadii() {
        world.warpInner = WARP_INNER_METERS * simConfig.metersToAbsolute;
        world.warpOuter = WARP_OUTER_METERS * simConfig.metersToAbsolute;
    }

    void release() {
        stairRoute.release();
        world.release();
    }

    bool breakBlock() {
        return world.breakBlock();
    }

    bool placeBlock() {
        Placement placement = world.placementTarget();
        if (placement.isFound && !world.graph.isCapsuleOverlappingCell(bodyCapsule(), characterState.position, ChunkSlot(world.graph.slotOf(placement.chunk.node), placement.chunk.vertex), placement.coords)) {
            return world.setVoxel(placement.chunk, placement.coords, MATERIAL_PALETTE[materialIndex]);
        } else {
            return false;
        }
    }

    void look(float yaw, float pitch) {
        camera.turn(-yaw, -pitch);
        updateView();
    }

    MPoint!float pointInView(Place place) const {
        Relocated at = world.graph.relocated(place);
        return bodyView.local.inverse() * (at.toNode.inverse() * at.place.pointInNode(world.graph.layout));
    }

    void followBody() {
        Place place = characterState.position;
        bodyViewWarp = world.graph.smoothWarp(bodyView, simConfig.metersToAbsolute);
        float[3] up = world.graph.smoothGridDirection(bodyView, place.jacobian(world.graph.layout, bodyView.local), place.frame.toGrid(characterState.up));
        MPoint!float eye = pointInView(place.moved(characterState.up.scaled(camera.eyeHeight())));
        camera.follow(bodyView, MIsometry!float.fromTranslation(MPoint!float.origin(), eye), unit(applied(bodyViewWarp, up)));
        camera.levelRoll();
    }

    void moveView(MIsometry!float toNode) {
        MIsometry!float shifted = toNode * bodyView.local;
        MPoint!float center = characterState.position.pointInNode(world.graph.layout);
        bodyView = Position(world.graph.idAt(characterState.position.chunk.slot), (MIsometry!float.fromTranslation(shifted * MPoint!float.origin(), center) * shifted).renormalized());
        world.graph.ensureNodeState(bodyView.node);
    }

    void updateView() {
        world.cameraPosition = camera.orientedPosition();
        float[3][3] rotation = cameraRotation();
        world.viewWarp = multiplied(transposed(rotation), multiplied(bodyViewWarp, rotation));
    }

    float[3][3] cameraRotation() const {
        float[3][3] rotation;
        foreach (column; 0 .. 3) {
            float[3] axis = [0, 0, 0];
            axis[column] = 1;
            float[3] rotated = camera.orientation.rotate(axis);
            foreach (row; 0 .. 3) {
                rotation[row][column] = rotated[row];
            }
        }
        return rotation;
    }

    void step(FrameInput input, float dt) {
        look(input.yaw, input.pitch);
        float moveX = axisValue(input.isHeld[Key.right]) - axisValue(input.isHeld[Key.left]);
        float moveY = axisValue(input.isHeld[Key.up]) - axisValue(input.isHeld[Key.down]);
        float moveZ = axisValue(input.isHeld[Key.back]) - axisValue(input.isHeld[Key.fwd]);
        bool wasOnGround = characterState.isOnGround;
        Stepped stepped = characterState.runStep(simConfig.character, world.graph, characterInput(moveX, moveY, moveZ, input.isHeld[Key.up], input.isHeld[Key.down]), dt);
        traveled += stepped.traveled;
        altitude += stepped.rise;
        moveView(stepped.toNode);
        camera.smoothEyeVertical(groundedRise(wasOnGround, stepped.rise), simConfig.character.stepHeight, dt);
        followBody();
        updateView();
        trackCameraAcceleration(altitude + camera.eyeHeight(), dt);
        world.update(isSettlingWorldgenEachFrame);
        if (isSettlingWorldgenEachFrame) {
            world.streamer.settle(world.graph);
        }
        simTime += dt;
    }

    float[3] viewToBody(float[3] view) const {
        float length = view.magnitude;
        if (length > 0) {
            Place place = characterState.position;
            float[3] grid = applied(place.jacobian(world.graph.layout, bodyView.local), applied(inverted(bodyViewWarp), view));
            float[3] body = place.frame.toBody(grid);
            return body.scaled(length / body.magnitude);
        } else {
            return view;
        }
    }

    CharacterInput characterInput(float moveX, float moveY, float moveZ, bool isUpHeld, bool isDownHeld) const {
        if (mode == MovementMode.noclip) {
            return CharacterInput(viewToBody(camera.orientation.rotate([moveX, moveY, moveZ])), mode, false, false);
        } else if (mode == MovementMode.fly) {
            return CharacterInput(levelMove(moveX, moveZ).plus(characterState.up.scaled(moveY)), mode, false, false);
        } else {
            return CharacterInput(levelMove(moveX, moveZ), mode, isUpHeld, isDownHeld);
        }
    }

    float[3] levelMove(float moveX, float moveZ) const {
        float[3] right = viewToBody(camera.orientation.rotate([1, 0, 0])).rejectAlong(characterState.up);
        float[3] back = viewToBody(camera.orientation.rotate([0, 0, 1])).rejectAlong(characterState.up);
        return right.scaled(moveX / right.magnitude).plus(back.scaled(moveZ / back.magnitude));
    }

    float groundedRise(bool wasOnGround, float rise) const {
        if (wasOnGround && characterState.isOnGround) {
            return rise;
        } else {
            return 0;
        }
    }

    void trackCameraAcceleration(float newCameraAltitude, float dt) {
        float verticalVelocity = (newCameraAltitude - cameraAltitude) / dt;
        if (hasCameraVerticalVelocity) {
            cameraVerticalAcceleration = fabsf((verticalVelocity - cameraVerticalVelocity) / dt);
        } else {
            cameraVerticalAcceleration = 0;
        }
        cameraAltitude = newCameraAltitude;
        cameraVerticalVelocity = verticalVelocity;
        hasCameraVerticalVelocity = true;
    }

    void toggleMode(MovementMode toggled) {
        if (mode == toggled) {
            mode = MovementMode.fly;
        } else {
            mode = toggled;
        }
    }
}
