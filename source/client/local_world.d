module client.local_world;

import core.time : MonoTime;
import std.math : cosh, isNaN;
import client.worldgen_driver : WorldgenDriver, getChunkNeighbor;
import common.collision_math : Ray;
import common.graph : Graph, NodeId;
import common.graph_ray_casting : GraphCastHit, rayCast;
import common.margins : fixMargins, neighborAxisPermutation;
import common.math : MIsometry, MPoint, MVector;
import common.node : Chunk, ChunkId, ChunkState;
import common.proto : Position;
import common.traversal : ensureAndCollectNearby, NearbyNode, NearbyScratch;
import common.voxel_math : ChunkDirection, Coords, CoordSign;
import common.world : Material;

/// The client's view of the world with no GPU state: the graph, the nearby
/// node set around the camera, async chunk generation, and block edits.
/// The renderer reads it; headless runs drive it alone.
struct LocalWorld {
    Graph graph;
    WorldgenDriver worldgenDriver;
    ubyte dimension;
    Position camPos;
    float renderRadius = 4.5f;
    // tanh of the absolute block reach distance.
    float reach = 0;

    NearbyNode[] cachedNodes;
    NearbyScratch nearbyScratch;
    NodeId lastNearbyNode;
    MPoint!float lastNearbyPos;
    bool hasNearby = false;
    uint nearbyVersion = 0;

    // Stage timings of the last update, for the renderer's stage log.
    double ensureMs = 0;
    double driveMs = 0;

    // The nearby set is collected with this much extra radius so it stays
    // valid until the camera has translated NEARBY_PADDING away from the
    // collection point; rotation never invalidates it. Node count grows
    // exponentially with radius in hyperbolic space, so this must stay small:
    // 0.05 costs ~10% more nodes, while e.g. 0.25 would cost ~65% more.
    enum float NEARBY_PADDING = 0.05f;

    static LocalWorld create(ubyte dimension, bool flatWorldgen) {
        LocalWorld w;
        w.dimension = dimension;
        w.graph = Graph.create(dimension);
        w.worldgenDriver = WorldgenDriver.create();
        w.worldgenDriver.flatWorldgen = flatWorldgen;
        w.camPos.node = NodeId.ROOT;
        w.camPos.local = MIsometry!float.translationAlong([0.0f, 1.4f, 0.0f]);
        return w;
    }

    /// Refreshes the nearby set if the camera left its padding, then feeds
    /// chunk generation and integrates finished chunks.
    void update() {
        MonoTime a0 = MonoTime.currTime;
        MPoint!float camPoint = camPos.local * MPoint!float.origin();
        bool camMoved = !hasNearby || camPos.node != lastNearbyNode
            || nearbyScratch.creationCapped
            || -lastNearbyPos.mip(camPoint.vec) > cosh(NEARBY_PADDING);
        if (camMoved) {
            cachedNodes = ensureAndCollectNearby(nearbyScratch, graph, camPos.node, camPos.local,
                renderRadius + NEARBY_PADDING);
            lastNearbyNode = camPos.node;
            lastNearbyPos = camPoint;
            hasNearby = true;
            nearbyVersion++;
        }
        MonoTime a1 = MonoTime.currTime;
        worldgenDriver.drive(cachedNodes, camPos.local, renderRadius, graph, dimension, nearbyVersion);
        MonoTime a2 = MonoTime.currTime;
        ensureMs = (a1 - a0).total!"usecs" / 1000.0;
        driveMs = (a2 - a1).total!"usecs" / 1000.0;
    }

    GraphCastHit castCenterRay() {
        Ray ray = Ray.create(
            MPoint!float.origin(),
            MVector!float(0, 0, -1, 0).normalizedDirection());
        bool oob;
        return rayCast(graph, camPos.node, camPos.local, ray, reach, oob);
    }

    bool breakBlock() {
        GraphCastHit hit = castCenterRay();
        if (isNaN(hit.tanhDistance)) {
            return false;
        }
        return setVoxel(hit.chunk, hit.voxelCoords, Material.Void);
    }

    bool placeBlock(Material material) {
        GraphCastHit hit = castCenterRay();
        if (isNaN(hit.tanhDistance)) {
            return false;
        }
        ChunkId targetChunk = hit.chunk;
        Coords coords = hit.voxelCoords;
        int stepped = coords[hit.faceAxis] + (hit.faceSign == CoordSign.Plus ? 1 : -1);
        if (stepped >= 0 && stepped < dimension) {
            coords[hit.faceAxis] = cast(ubyte) stepped;
        } else {
            // The cell in front of the hit face lies in the neighboring chunk.
            // Chunk neighbors meet mirrored, so the crossing lands on the
            // neighbor's boundary layer for the same direction, with its axes
            // permuted the same way fixMargins matches them up.
            ChunkDirection dir = ChunkDirection(hit.faceAxis, hit.faceSign);
            ChunkId neighbor = getChunkNeighbor(graph, hit.chunk, dir.axis, dir.sign);
            if (neighbor.node == NodeId.init || !graph.contains(neighbor.node)) {
                return false;
            }
            coords[hit.faceAxis] = Coords.boundaryCoord(dimension, dir.sign);
            coords = neighborAxisPermutation(hit.chunk.vertex, dir) * coords;
            targetChunk = neighbor;
        }
        return setVoxel(targetChunk, coords, material);
    }

    /// Write one voxel and keep the margin copies of adjacent chunks in sync
    /// so their surfaces re-extract correctly when a boundary voxel changes.
    bool setVoxel(ChunkId chunkId, Coords coords, Material material) {
        if (!graph.contains(chunkId.node)) {
            return false;
        }
        Chunk* c = &graph[chunkId.node].chunks.values[chunkId.vertex];
        if (c.state != ChunkState.Populated) {
            return false;
        }
        c.voxels.dataMut(dimension)[coords.toIndex(dimension)] = material;
        c.generation++;

        foreach (dir; ChunkDirection.ALL) {
            if (coords[dir.axis] != Coords.boundaryCoord(dimension, dir.sign)) {
                continue;
            }
            ChunkId neighbor = getChunkNeighbor(graph, chunkId, dir.axis, dir.sign);
            if (neighbor.node == NodeId.init || !graph.contains(neighbor.node)) {
                continue;
            }
            Chunk* nc = &graph[neighbor.node].chunks.values[neighbor.vertex];
            if (nc.state != ChunkState.Populated) {
                continue;
            }
            fixMargins(dimension, chunkId.vertex, c.voxels, dir, nc.voxels);
            nc.generation++;
        }
        return true;
    }
}
