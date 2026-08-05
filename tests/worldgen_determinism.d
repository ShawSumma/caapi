module tests.worldgen_determinism;

import core.stdc.stdio : printf;
import common.dodeca : Vertex, CHUNK_BOUNDING_SPHERE_RADIUS;
import common.dodeca : vertexChunkBoundingSphereCenter;
import common.dodeca : vertexCanonicalSides, vertexAdjacentVertices;
import common.graph : Graph, NodeId;
import common.math : MIsometry, MPoint, cosh;
import common.node : Chunk, ChunkId, ChunkState, VoxelData;
import common.traversal : ensureAndCollectNearby, NearbyNode;
import common.worldgen : ChunkParams, generateVoxels;
import common.margins : fixMargins;
import common.voxel_math : ChunkDirection, CoordSign;
import common.world : Material;
import client.worldgen_driver : WorldgenDriver, populateChunk;

// Synchronous driver that matches the original pre-threading behaviour exactly.
int driveSync(
    const(NearbyNode)[] nearby,
    MIsometry!float camLocal,
    float distance,
    ref Graph graph,
    ubyte chunkSize,
    int maxPerFrame,
) {
    float threshold = cosh(distance + CHUNK_BOUNDING_SPHERE_RADIUS);
    MPoint!float startP = camLocal * MPoint!float.origin();
    int generated = 0;

    foreach (ref const NearbyNode nn; nearby) {
        foreach (int vIdx; 0 .. Vertex.max + 1) {
            Vertex vertex = cast(Vertex) vIdx;
            ChunkId chunkId = ChunkId(nn.id, vertex);
            Chunk* c = &graph[nn.id].chunks.values[vertex];
            if (c.state != ChunkState.Fresh) {
                continue;
            }

            MPoint!float chunkCenter = nn.transform * vertexChunkBoundingSphereCenter(vertex);
            if (-startP.mip(chunkCenter.vec) > threshold) {
                continue;
            }

            if (generated >= maxPerFrame) {
                continue;
            }
            ChunkParams params = ChunkParams.create(graph, chunkId);
            VoxelData voxels = generateVoxels(params);
            populateChunk(graph, chunkId, voxels, chunkSize);
            generated = generated + 1;
        }
    }
    return generated;
}

int countPopulated(ref Graph graph, const(NearbyNode)[] nearby) {
    int count = 0;
    foreach (ref const NearbyNode nn; nearby) {
        foreach (int vIdx; 0 .. Vertex.max + 1) {
            Vertex vertex = cast(Vertex) vIdx;
            if (graph[nn.id].chunks.values[vertex].state == ChunkState.Populated) {
                count = count + 1;
            }
        }
    }
    return count;
}

void main() {
    enum ubyte DIM = 12;
    enum float RADIUS = 3.0f;
    enum int MAX_PER_FRAME = 8;
    MIsometry!float cam = MIsometry!float.identity();

    // Synchronous path.
    Graph graphSync = Graph.create(DIM);
    int syncTotal = 0;
    foreach (pass; 0 .. 100_000) {
        NearbyNode[] nearby = ensureAndCollectNearby(graphSync, NodeId.ROOT, cam, RADIUS);
        int gen = driveSync(nearby, cam, RADIUS, graphSync, DIM, MAX_PER_FRAME);
        if (gen == 0) {
            syncTotal = countPopulated(graphSync, nearby);
            writefln("Sync: done after %d passes, %d chunks", pass + 1, syncTotal);
            break;
        }
    }

    // Second sync path, used as a control.
    Graph graphSync2 = Graph.create(DIM);
    foreach (pass; 0 .. 100_000) {
        NearbyNode[] nearby = ensureAndCollectNearby(graphSync2, NodeId.ROOT, cam, RADIUS);
        int gen = driveSync(nearby, cam, RADIUS, graphSync2, DIM, MAX_PER_FRAME);
        if (gen == 0) {
            int pop = countPopulated(graphSync2, nearby);
            writefln("Sync2: done after %d passes, %d chunks", pass + 1, pop);
            break;
        }
    }

    // Async path.
    Graph graphAsync = Graph.create(DIM);
    WorldgenDriver driver = WorldgenDriver.create();
    foreach (pass; 0 .. 100_000) {
        NearbyNode[] nearby = ensureAndCollectNearby(graphAsync, NodeId.ROOT, cam, RADIUS);
        driver.drive(nearby, cam, RADIUS, graphAsync, DIM);
        int pop = countPopulated(graphAsync, nearby);
        if (pop >= syncTotal) {
            writefln("Async: done after %d passes, %d chunks", pass + 1, pop);
            break;
        }
    }

    // Compare sync vs sync2 first
    NearbyNode[] nearbyCtrl = ensureAndCollectNearby(graphSync2, NodeId.ROOT, cam, RADIUS);
    int ctrlMismatches = 0;
    foreach (ref const NearbyNode nn; nearbyCtrl) {
        foreach (int vIdx; 0 .. Vertex.max + 1) {
            Vertex vertex = cast(Vertex) vIdx;
            Chunk* sc = &graphSync[nn.id].chunks.values[vertex];
            Chunk* sc2 = &graphSync2[nn.id].chunks.values[vertex];
            if (sc.state != sc2.state) {
                ctrlMismatches = ctrlMismatches + 1;
                continue;
            }
            if (sc.state != ChunkState.Populated) {
                continue;
            }
            if (sc.voxels.kind != sc2.voxels.kind) {
                ctrlMismatches = ctrlMismatches + 1;
                continue;
            }
            if (sc.voxels.kind == VoxelData.Kind.Solid) {
                if (sc.voxels.solidMaterial != sc2.voxels.solidMaterial) {
                    ctrlMismatches = ctrlMismatches + 1;
                }
            } else {
                if (sc.voxels.denseData != sc2.voxels.denseData) {
                    ctrlMismatches = ctrlMismatches + 1;
                }
            }
        }
    }
    writefln("Control (sync vs sync2): %d mismatches", ctrlMismatches);

    // Compare all chunks.
    NearbyNode[] nearbyRef = ensureAndCollectNearby(graphSync, NodeId.ROOT, cam, RADIUS);
    int mismatches = 0;
    int compared = 0;
    foreach (ref const NearbyNode nn; nearbyRef) {
        foreach (int vIdx; 0 .. Vertex.max + 1) {
            Vertex vertex = cast(Vertex) vIdx;
            Chunk* sc = &graphSync[nn.id].chunks.values[vertex];
            if (sc.state != ChunkState.Populated) {
                continue;
            }
            compared = compared + 1;

            if (!graphAsync.contains(nn.id)) {
                writefln("MISSING node %s", nn.id);
                mismatches = mismatches + 1;
                continue;
            }
            Chunk* ac = &graphAsync[nn.id].chunks.values[vertex];
            if (ac.state != ChunkState.Populated) {
                writefln("UNPOPULATED %s/%s", nn.id, cast(Vertex) vIdx);
                mismatches = mismatches + 1;
                continue;
            }

            if (sc.voxels.kind != ac.voxels.kind) {
                if (mismatches < 20) {
                    writefln(
                        "KIND mismatch %s/%s: %s vs %s",
                        nn.id,
                        cast(Vertex) vIdx,
                        sc.voxels.kind,
                        ac.voxels.kind,
                    );
                }
                mismatches = mismatches + 1;
                continue;
            }

            if (sc.voxels.kind == VoxelData.Kind.Solid) {
                if (sc.voxels.solidMaterial != ac.voxels.solidMaterial) {
                    if (mismatches < 5) {
                        writefln(
                            "SOLID mismatch %s/%s: sync=%s async=%s",
                            nn.id,
                            cast(Vertex) vIdx,
                            sc.voxels.solidMaterial,
                            ac.voxels.solidMaterial,
                        );
                    }
                    mismatches = mismatches + 1;
                }
            } else {
                Material[] sd = sc.voxels.denseData;
                Material[] ad = ac.voxels.denseData;
                if (sd.length != ad.length) {
                    if (mismatches < 5) {
                        writefln(
                            "LENGTH mismatch %s/%s: %d vs %d",
                            nn.id,
                            cast(Vertex) vIdx,
                            sd.length,
                            ad.length,
                        );
                    }
                    mismatches = mismatches + 1;
                    continue;
                }
                int diffCount = 0;
                size_t firstDiff = 0;
                foreach (i; 0 .. sd.length) {
                    if (sd[i] != ad[i]) {
                        if (diffCount == 0) {
                            firstDiff = i;
                        }
                        diffCount = diffCount + 1;
                    }
                }
                if (diffCount > 0) {
                    if (mismatches < 5) {
                        writefln(
                            "DATA mismatch %s/%s: %d diffs, first at [%d] sync=%s async=%s",
                            nn.id,
                            cast(Vertex) vIdx,
                            diffCount,
                            firstDiff,
                            sd[firstDiff],
                            ad[firstDiff],
                        );
                    }
                    mismatches = mismatches + 1;
                }
            }
        }
    }

    if (mismatches == 0) {
        writefln("PASS: all %d chunks match exactly", compared);
    } else {
        writefln("FAIL: %d mismatches out of %d chunks", mismatches, compared);
    }
}
