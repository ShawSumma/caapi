module client.hud;

import core.stdc.math : asinhf, cosf, sinf, sqrtf;
import base.array : Array;
import base.numbers : PI, higherOf, lowerOf;
import client.camera : Quaternion;
import client.game : Game, TRAIL_POINTS;
import client.world : LocalWorld;
import common.graph : Graph, NO_SLOT;
import common.position : Position;
import common.traversal : NOT_COLLECTED, NearbyScratch;
import common.worldgen.generation : Worldgen, WorldgenKind;
import geometry.honeycomb : FACE_COUNT, Face;
import geometry.lorentz : Motion, Vec4;

enum uint GROWTH_STEPS = 5;
enum size_t MOST_DISK_NODES = 1 << 14;
enum uint MOST_VERTICES = 1 << 18;
enum uint QUAD_VERTICES = 6;
enum uint CIRCLE_SEGMENTS = 48;
enum uint BASE_HEIGHT = 360;
enum float MARGIN = 8;
enum float DISK_SHARE = 0.2f;
enum float COMPASS_SHARE = 0.085f;
enum float DISK_BAND = 1.2f;
enum float DISK_FARTHEST_W = 200;
enum float NEEDLE_THICKNESS = 1.5f;
enum float LINK_THICKNESS = 0.7f;
enum float BLOCK_HALF = 0.02f;
enum float TRAIL_HALF = 0.005f;
enum uint WHITE = rgba(255, 255, 255, 255);
enum uint PANEL = rgba(12, 16, 26, 150);
enum uint RIM = rgba(225, 225, 215, 210);
enum uint GOLD = rgba(255, 205, 90, 255);
enum uint CYAN = rgba(120, 225, 255, 255);
enum uint THROWN_COLOR = rgba(255, 120, 50, 255);
enum uint TRAIL_COLOR = rgba(255, 215, 110, 255);

uint rgba(uint r, uint g, uint b, uint a) {
    return r | (g << 8) | (b << 16) | (a << 24);
}

uint faded(uint color, float share) {
    return (color & 0x00FFFFFF) | (cast(uint)((color >> 24) * share) << 24);
}

struct HudVertex {
    float[2] at;
    uint color;
    uint unused;
}

struct Marker {
    Motion!float frame;
    float half;
    uint color;
}

const(char)[] worldNameOf(ref const Worldgen worldgen) {
    final switch (worldgen.kind) {
        case WorldgenKind.terrain:
            return "terrain";
        case WorldgenKind.plane:
            return "plane";
        case WorldgenKind.structure:
            return worldgen.structureName();
    }
}

struct Growth {
    Array!uint seen;
    Array!uint placeOf;
    Array!uint queue;
    uint[GROWTH_STEPS + 1] within;
    uint generation;
    uint countedSlot = NO_SLOT;
    uint countedVersion;
    size_t countedNodes;

    void update(ref const LocalWorld world) {
        uint start = world.graph.slotOf(world.cameraPosition.node);
        size_t nodes = world.nearby[world.published].nodes.length;
        if (start != countedSlot || world.nearbyVersion != countedVersion || nodes > 2 * countedNodes) {
            count(world, start);
            countedSlot = start;
            countedVersion = world.nearbyVersion;
            countedNodes = nodes;
        }
    }

    void count(ref const LocalWorld world, uint start) {
        const(Graph)* graph = &world.graph;
        const(NearbyScratch)* nearby = &world.nearby[world.published];
        generation += 1;
        seen.resize(graph.slotCount);
        placeOf.resize(graph.slotCount);
        queue.clear();
        visit(start);
        size_t first = 0;
        foreach (step; 0 .. GROWTH_STEPS + 1) {
            within[step] = cast(uint) queue.length;
            size_t end = queue.length;
            if (step < GROWTH_STEPS) {
                foreach (index; first .. end) {
                    uint slot = queue.ptr[index];
                    foreach (face; 0 .. FACE_COUNT) {
                        uint next = graph.neighborSlot(slot, cast(Face) face);
                        if (next != NO_SLOT && seen.ptr[next] != generation && nearby.indexOf(next) != NOT_COLLECTED) {
                            visit(next);
                        }
                    }
                }
            }
            first = end;
        }
    }

    void visit(uint slot) {
        seen.ptr[slot] = generation;
        placeOf.ptr[slot] = cast(uint) queue.length;
        queue.append(slot);
    }

    bool isCounted(uint slot) const {
        return slot < seen.length && seen.ptr[slot] == generation;
    }

    void release() {
        seen.release();
        placeOf.release();
        queue.release();
    }
}

struct DiskPoint {
    float[2] at;
    float share;
}

struct Hud {
    Array!HudVertex vertices;
    Array!Marker markers;
    Array!DiskPoint disk;
    Growth growth;
    float width = 0;
    float height = 0;
    float scale = 1;

    void rect(float x, float y, float w, float h, uint color) {
        quad([x, y], [x + w, y], [x + w, y + h], [x, y + h], color);
    }

    void quad(float[2] a, float[2] b, float[2] c, float[2] d, uint color) {
        if (vertices.length + QUAD_VERTICES <= MOST_VERTICES) {
            vertex(a, color);
            vertex(b, color);
            vertex(c, color);
            vertex(c, color);
            vertex(d, color);
            vertex(a, color);
        }
    }

    void vertex(float[2] at, uint color) {
        vertices.append(HudVertex([2 * at[0] / width - 1, 2 * at[1] / height - 1], color, 0));
    }

    void line(float[2] from, float[2] to, float thickness, uint color) {
        float dx = to[0] - from[0];
        float dy = to[1] - from[1];
        float length = sqrtf(dx * dx + dy * dy);
        if (length > 0) {
            float nx = -dy / length * thickness * 0.5f;
            float ny = dx / length * thickness * 0.5f;
            quad([from[0] + nx, from[1] + ny], [to[0] + nx, to[1] + ny], [to[0] - nx, to[1] - ny], [from[0] - nx, from[1] - ny], color);
        }
    }

    void circle(float[2] center, float radius, uint fill, uint rim) {
        foreach (segment; 0 .. CIRCLE_SEGMENTS) {
            float[2] a = onCircle(center, radius, segment);
            float[2] b = onCircle(center, radius, segment + 1);
            if (vertices.length + 3 <= MOST_VERTICES) {
                vertex(center, fill);
                vertex(a, fill);
                vertex(b, fill);
            }
            line(a, b, scale, rim);
        }
    }

    void buildMarkers(ref const Game game) {
        markers.clear();
        const(NearbyScratch)* nearby = &game.world.nearby[game.world.published];
        foreach (ref thrown; game.thrown.slice()) {
            addMarker(game, nearby, thrown.position, BLOCK_HALF, THROWN_COLOR);
            foreach (ref point; thrown.trail[0 .. lowerOf(thrown.trailCount, TRAIL_POINTS)]) {
                addMarker(game, nearby, point, TRAIL_HALF, TRAIL_COLOR);
            }
        }
    }

    void addMarker(ref const Game game, const(NearbyScratch)* nearby, Position position, float half, uint color) {
        uint slot = game.world.graph.slotOf(position.node);
        if (slot != NO_SLOT) {
            uint index = nearby.indexOf(slot);
            if (index != NOT_COLLECTED) {
                markers.append(Marker(nearby.nodes.ptr[index].transform * position.local, half, color));
            }
        }
    }

    void build(ref const Game game, uint pixelsWide, uint pixelsHigh) {
        vertices.clear();
        width = pixelsWide;
        height = pixelsHigh;
        scale = higherOf(1u, pixelsHigh / BASE_HEIGHT);
        if (game.world.cameraNearbyIndex() != NOT_COLLECTED) {
            growth.update(game.world);
            buildPoincareDisk(game);
        }
        buildCompass(game);
    }

    void buildCompass(ref const Game game) {
        float radius = COMPASS_SHARE * height;
        float[2] center = [width - MARGIN * scale - radius, height - MARGIN * scale - radius];
        circle(center, radius, PANEL, RIM);
        float off = game.compassOff().value;
        float[2] ahead = [center[0], center[1] - radius * 0.8f];
        line(center, ahead, scale, faded(WHITE, 0.45f));
        float[2] tip = [center[0] - sinf(off) * radius * 0.92f, center[1] - cosf(off) * radius * 0.92f];
        line(center, tip, NEEDLE_THICKNESS * scale, GOLD);
    }

    void buildPoincareDisk(ref const Game game) {
        float radius = DISK_SHARE * height;
        float[2] center = [width - MARGIN * scale - radius, MARGIN * scale + radius];
        circle(center, radius, PANEL, RIM);
        const(LocalWorld)* world = &game.world;
        const(Graph)* graph = &world.graph;
        const(NearbyScratch)* nearby = &world.nearby[world.published];
        Motion!float level = Quaternion.fromAxisAngle([1, 0, 0], game.camera.pitch.value).toMotion() * world.cameraInNearbyFrame().inverse();
        const(uint)[] nearest = growth.queue.slice()[0 .. lowerOf(growth.queue.length, MOST_DISK_NODES)];
        disk.resize(nearest.length);
        foreach (index, slot; nearest) {
            disk.ptr[index] = onDisk(level * nearby.nodes.ptr[nearby.indexOf(slot)].transform.m.column(3));
        }
        foreach (index, slot; nearest) {
            DiskPoint from = disk.ptr[index];
            if (from.share > 0) {
                foreach (face; 0 .. FACE_COUNT) {
                    uint next = graph.neighborSlot(slot, cast(Face) face);
                    if (next != NO_SLOT && next > slot && growth.isCounted(next) && growth.placeOf.ptr[next] < nearest.length && disk.ptr[growth.placeOf.ptr[next]].share > 0) {
                        DiskPoint to = disk.ptr[growth.placeOf.ptr[next]];
                        line(placed(center, radius, from.at), placed(center, radius, to.at), LINK_THICKNESS * scale, faded(CYAN, lowerOf(from.share, to.share)));
                    }
                }
            }
        }
        float[2] eye = center;
        line(eye, [eye[0], eye[1] - 4 * scale], NEEDLE_THICKNESS * scale, GOLD);
        rect(eye[0] - scale, eye[1] - scale, 2 * scale, 2 * scale, WHITE);
    }

    void release() {
        vertices.release();
        markers.release();
        disk.release();
        growth.release();
    }
}

float[2] onCircle(float[2] center, float radius, uint segment) {
    float angle = segment * 2 * PI / CIRCLE_SEGMENTS;
    return [center[0] + cosf(angle) * radius, center[1] + sinf(angle) * radius];
}

float[2] placed(float[2] center, float radius, float[2] at) {
    return [center[0] + at[0] * radius, center[1] + at[1] * radius];
}

DiskPoint onDisk(Vec4!float point) {
    float height = asinhf(point.c[1]);
    float share = 1 - height * height / (DISK_BAND * DISK_BAND);
    if (!(point.c[3] < DISK_FARTHEST_W) || !(share > 0)) {
        return DiskPoint([0, 0], 0);
    } else {
        float foot = sqrtf(1 + point.c[1] * point.c[1]);
        float over = 1 / (foot + point.c[3]);
        return DiskPoint([point.c[0] * over, point.c[2] * over], share);
    }
}
