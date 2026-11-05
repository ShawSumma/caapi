module client.hud;

import core.stdc.math : asinhf, cosf, sinf, sqrtf;
import base.array : Array;
import base.clock : FrameClock, MILLISECONDS_PER_SECOND;
import base.maybe : MaybeIndex;
import base.names : ENUM_NAMES;
import base.numbers : PI, higherOf, lowerOf;
import base.stdio : snprintf;
import base.vector3 : Vec3;
import client.camera : Quaternion;
import client.game : Game, TRAIL_POINTS;
import client.world : LocalWorld;
import common.character.controller : MovementMode;
import common.graph : Graph;
import common.position : Position;
import common.traversal : NearbyScratch;
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
enum double STATUS_INTERVAL_SECONDS = 1.0;
enum size_t STATUS_CAPACITY = 256;
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

struct ScreenPoint {
    float x;
    float y;
}

struct HudVertex {
    ScreenPoint at;
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

enum MouseCapture : ubyte {
    released,
    captured,
}

struct FrameMeter {
    double last = 0;
    float fps = 0;
    float worstFrameMs = 0;
    uint frames;

    static FrameMeter startingAt(double now) {
        FrameMeter meter;
        meter.last = now;
        return meter;
    }

    bool tick(double now, ref FrameClock clock) {
        frames += 1;
        bool refreshed = now - last >= STATUS_INTERVAL_SECONDS;
        if (refreshed) {
            fps = cast(float)(frames / (now - last));
            worstFrameMs = cast(float)(clock.worst * MILLISECONDS_PER_SECOND);
            clock.worst = 0;
            frames = 0;
            last = now;
        }
        return refreshed;
    }
}

char[STATUS_CAPACITY] statusLine(ref const Game game, MouseCapture mouse, ref const FrameMeter meter) {
    char[STATUS_CAPACITY] text;
    string mode = ENUM_NAMES!MovementMode[game.mode];
    const(char)[] world = worldNameOf(game.world.graph.worldgen);
    final switch (mouse) {
        case MouseCapture.captured:
            snprintf(text.ptr, text.length, "mined - %.*s ([ ]) - %.*s (V) - [%u] - Esc to release mouse - FPS %.0f, worst frame %.0fms", cast(int) world.length, world.ptr, cast(int) mode.length, mode.ptr, game.materialIndex + 1, cast(double) meter.fps, cast(double) meter.worstFrameMs);
            break;
        case MouseCapture.released:
            snprintf(text.ptr, text.length, "mined - %.*s ([ ]) - %.*s (V) - click to capture mouse - FPS %.0f, worst frame %.0fms", cast(int) world.length, world.ptr, cast(int) mode.length, mode.ptr, cast(double) meter.fps, cast(double) meter.worstFrameMs);
            break;
    }
    return text;
}

struct Growth {
    Array!uint seen;
    Array!uint placeOf;
    Array!uint queue;
    uint[GROWTH_STEPS + 1] within;
    uint generation;
    MaybeIndex!uint countedSlot;
    uint countedVersion;
    uint countedEpoch;
    size_t countedNodes;

    void update(ref const LocalWorld world) {
        MaybeIndex!uint start = world.graph.slotOf(world.cameraPosition.node);
        size_t nodes = world.nearby[world.published].nodes.length;
        if (start != countedSlot || world.nearbyVersion != countedVersion || world.epoch != countedEpoch || nodes > 2 * countedNodes) {
            count(world, start.value);
            countedSlot = start;
            countedVersion = world.nearbyVersion;
            countedEpoch = world.epoch;
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
                        MaybeIndex!uint next = graph.neighborSlot(slot, cast(Face) face);
                        if (next.exists && seen.ptr[next.value] != generation && nearby.indexOf(next.value).exists) {
                            visit(next.value);
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
    ScreenPoint at;
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
        quad(ScreenPoint(x, y), ScreenPoint(x + w, y), ScreenPoint(x + w, y + h), ScreenPoint(x, y + h), color);
    }

    void quad(ScreenPoint a, ScreenPoint b, ScreenPoint c, ScreenPoint d, uint color) {
        if (vertices.length + QUAD_VERTICES <= MOST_VERTICES) {
            vertex(a, color);
            vertex(b, color);
            vertex(c, color);
            vertex(c, color);
            vertex(d, color);
            vertex(a, color);
        }
    }

    void vertex(ScreenPoint at, uint color) {
        vertices.append(HudVertex(ScreenPoint(2 * at.x / width - 1, 2 * at.y / height - 1), color));
    }

    void line(ScreenPoint from, ScreenPoint to, float thickness, uint color) {
        float dx = to.x - from.x;
        float dy = to.y - from.y;
        float length = sqrtf(dx * dx + dy * dy);
        if (length > 0) {
            float nx = -dy / length * thickness * 0.5f;
            float ny = dx / length * thickness * 0.5f;
            quad(ScreenPoint(from.x + nx, from.y + ny), ScreenPoint(to.x + nx, to.y + ny), ScreenPoint(to.x - nx, to.y - ny), ScreenPoint(from.x - nx, from.y - ny), color);
        }
    }

    void circle(ScreenPoint center, float radius, uint fill, uint rim) {
        foreach (segment; 0 .. CIRCLE_SEGMENTS) {
            ScreenPoint a = onCircle(center, radius, segment);
            ScreenPoint b = onCircle(center, radius, segment + 1);
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
        MaybeIndex!uint slot = game.world.graph.slotOf(position.node);
        if (slot.exists) {
            MaybeIndex!uint index = nearby.indexOf(slot.value);
            if (index.exists) {
                markers.append(Marker(nearby.nodes.ptr[index.value].transform * position.local, half, color));
            }
        }
    }

    void build(ref const Game game, uint pixelsWide, uint pixelsHigh) {
        vertices.clear();
        width = pixelsWide;
        height = pixelsHigh;
        scale = higherOf(1u, pixelsHigh / BASE_HEIGHT);
        if (game.world.cameraNearbyIndex().exists) {
            growth.update(game.world);
            buildPoincareDisk(game);
        }
        buildCompass(game);
    }

    void buildCompass(ref const Game game) {
        float radius = COMPASS_SHARE * height;
        ScreenPoint center = ScreenPoint(width - MARGIN * scale - radius, height - MARGIN * scale - radius);
        circle(center, radius, PANEL, RIM);
        float off = game.compassOff().value;
        ScreenPoint ahead = ScreenPoint(center.x, center.y - radius * 0.8f);
        line(center, ahead, scale, faded(WHITE, 0.45f));
        ScreenPoint tip = ScreenPoint(center.x - sinf(off) * radius * 0.92f, center.y - cosf(off) * radius * 0.92f);
        line(center, tip, NEEDLE_THICKNESS * scale, GOLD);
    }

    void buildPoincareDisk(ref const Game game) {
        float radius = DISK_SHARE * height;
        ScreenPoint center = ScreenPoint(width - MARGIN * scale - radius, MARGIN * scale + radius);
        circle(center, radius, PANEL, RIM);
        const(LocalWorld)* world = &game.world;
        const(Graph)* graph = &world.graph;
        const(NearbyScratch)* nearby = &world.nearby[world.published];
        Motion!float level = Quaternion.fromAxisAngle(Vec3!float(1, 0, 0), game.camera.pitch.value).toMotion() * world.cameraInNearbyFrame().inverse();
        const(uint)[] nearest = growth.queue.slice()[0 .. lowerOf(growth.queue.length, MOST_DISK_NODES)];
        disk.resize(nearest.length);
        foreach (index, slot; nearest) {
            disk.ptr[index] = onDisk(level * nearby.nodes.ptr[nearby.indexOf(slot).value].transform.m.column(3));
        }
        foreach (index, slot; nearest) {
            DiskPoint from = disk.ptr[index];
            if (from.share > 0) {
                foreach (face; 0 .. FACE_COUNT) {
                    MaybeIndex!uint next = graph.neighborSlot(slot, cast(Face) face);
                    if (next.exists && next.value > slot && growth.isCounted(next.value) && growth.placeOf.ptr[next.value] < nearest.length && disk.ptr[growth.placeOf.ptr[next.value]].share > 0) {
                        DiskPoint to = disk.ptr[growth.placeOf.ptr[next.value]];
                        line(placed(center, radius, from.at), placed(center, radius, to.at), LINK_THICKNESS * scale, faded(CYAN, lowerOf(from.share, to.share)));
                    }
                }
            }
        }
        line(center, ScreenPoint(center.x, center.y - 4 * scale), NEEDLE_THICKNESS * scale, GOLD);
        rect(center.x - scale, center.y - scale, 2 * scale, 2 * scale, WHITE);
    }

    void release() {
        vertices.release();
        markers.release();
        disk.release();
        growth.release();
    }
}

ScreenPoint onCircle(ScreenPoint center, float radius, uint segment) {
    float angle = segment * 2 * PI / CIRCLE_SEGMENTS;
    return ScreenPoint(center.x + cosf(angle) * radius, center.y + sinf(angle) * radius);
}

ScreenPoint placed(ScreenPoint center, float radius, ScreenPoint at) {
    return ScreenPoint(center.x + at.x * radius, center.y + at.y * radius);
}

DiskPoint onDisk(Vec4!float point) {
    float height = asinhf(point.c[1]);
    float share = 1 - height * height / (DISK_BAND * DISK_BAND);
    if (!(point.c[3] < DISK_FARTHEST_W) || !(share > 0)) {
        return DiskPoint(ScreenPoint(0, 0), 0);
    } else {
        float foot = sqrtf(1 + point.c[1] * point.c[1]);
        float over = 1 / (foot + point.c[3]);
        return DiskPoint(ScreenPoint(point.c[0] * over, point.c[2] * over), share);
    }
}
