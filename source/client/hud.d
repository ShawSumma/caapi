module client.hud;

import core.stdc.math : asinhf, cosf, sinf, sqrtf;
import core.stdc.stdio : snprintf;
import core.stdc.string : strlen;
import base.array : Array;
import base.numbers : PI, higherOf, lowerOf;
import client.camera : Quaternion;
import client.font : GLYPH_ADVANCE, GLYPH_HEIGHT, GLYPH_WIDTH, isLit;
import client.game : Game, TRAIL_POINTS;
import client.world : LocalWorld;
import common.graph : Graph, NO_SLOT;
import common.position : Position;
import common.traversal : NOT_COLLECTED, NearbyScratch;
import common.worldgen.generation : Worldgen, WorldgenKind;
import geometry.honeycomb : FACE_COUNT, Face;
import geometry.lorentz : Motion, Vec4;
import plugins.api.api : Look;

enum uint GROWTH_STEPS = 5;
enum size_t MOST_DISK_NODES = 1 << 14;
enum uint MOST_VERTICES = 1 << 18;
enum uint QUAD_VERTICES = 6;
enum uint CIRCLE_SEGMENTS = 48;
enum uint BASE_HEIGHT = 360;
enum float MARGIN = 8;
enum float LINE_GAP = 2;
enum float DISK_SHARE = 0.2f;
enum float COMPASS_SHARE = 0.085f;
enum float DISK_BAND = 1.2f;
enum float DISK_FARTHEST_W = 200;
enum float NEEDLE_THICKNESS = 1.5f;
enum float LINK_THICKNESS = 0.7f;
enum float RADIANS_TO_DEGREES = 180 / PI;
enum float BLOCK_HALF = 0.02f;
enum float TRAIL_HALF = 0.005f;
enum size_t TEXT_CAPACITY = 256;
enum uint WHITE = rgba(255, 255, 255, 255);
enum uint SOFT_WHITE = rgba(235, 235, 225, 235);
enum uint SHADOW = rgba(0, 0, 0, 170);
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

    void update(ref const LocalWorld world) {
        uint start = world.graph.slotOf(world.cameraPosition.node);
        if (start != countedSlot || world.nearbyVersion != countedVersion) {
            count(world, start);
            countedSlot = start;
            countedVersion = world.nearbyVersion;
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

    void clearOverlay() {
        vertices.clear();
    }

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

    void glyphs(float x, float y, float size, const(char)[] text, uint color) {
        foreach (index, letter; text) {
            foreach (column; 0 .. GLYPH_WIDTH) {
                foreach (row; 0 .. GLYPH_HEIGHT) {
                    if (isLit(letter, column, row)) {
                        rect(x + (index * GLYPH_ADVANCE + column) * size, y + row * size, size, size, color);
                    }
                }
            }
        }
    }

    void text(float x, float y, float size, const(char)[] written, uint color) {
        glyphs(x + size, y + size, size, written, SHADOW);
        glyphs(x, y, size, written, color);
    }

    float wrapped(float x, float y, float size, float widest, const(char)[] written, uint color) {
        size_t perLine = cast(size_t)(widest / (GLYPH_ADVANCE * size));
        const(char)[] rest = written;
        float at = y;
        while (rest.length > 0) {
            size_t end = lowerOf(rest.length, perLine);
            if (end < rest.length) {
                while (end > 1 && rest[end] != ' ') {
                    end -= 1;
                }
            }
            text(x, at, size, rest[0 .. end], color);
            at += (GLYPH_HEIGHT + LINE_GAP) * size;
            rest = rest[end .. $];
            if (rest.length > 0 && rest[0] == ' ') {
                rest = rest[1 .. $];
            }
        }
        return at;
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

    void build(ref const Game game, uint pixelsWide, uint pixelsHigh, float fps) {
        vertices.clear();
        width = pixelsWide;
        height = pixelsHigh;
        scale = higherOf(1u, pixelsHigh / BASE_HEIGHT);
        if (game.world.hasNearby && game.world.cameraNearbyIndex() != NOT_COLLECTED) {
            growth.update(game.world);
            buildPoincareDisk(game);
            buildCompass(game);
            buildCaption(game, fps);
            buildGrowth();
        }
    }

    void buildCaption(ref const Game game, float fps) {
        const(Look)* look = game.world.lookAtCamera();
        const(char)[] name = worldNameOf(game.world.graph.worldgen);
        if (look.name !is null) {
            name = look.name[0 .. strlen(look.name)];
        }
        float x = MARGIN * scale;
        float y = MARGIN * scale;
        text(x, y, 2 * scale, name, WHITE);
        y += (GLYPH_HEIGHT + LINE_GAP) * 2 * scale;
        float widest = width - 2 * x - 2.4f * DISK_SHARE * height;
        if (look.caption !is null) {
            y = wrapped(x, y, scale, widest, look.caption[0 .. strlen(look.caption)], SOFT_WHITE);
        }
        if (fps > 0) {
            char[TEXT_CAPACITY] written;
            int length = snprintf(written.ptr, written.length, "%.0f fps", cast(double) fps);
            text(x, y, scale, written[0 .. length], SOFT_WHITE);
        }
    }

    void buildGrowth() {
        char[TEXT_CAPACITY] steps;
        char[TEXT_CAPACITY] cells;
        int stepsLength = snprintf(steps.ptr, steps.length, "steps away");
        int cellsLength = snprintf(cells.ptr, cells.length, "cells within");
        foreach (step; 1 .. GROWTH_STEPS + 1) {
            stepsLength += snprintf(steps.ptr + stepsLength, steps.length - stepsLength, "%8u", step);
            cellsLength += snprintf(cells.ptr + cellsLength, cells.length - cellsLength, "%8u", growth.within[step]);
        }
        float x = MARGIN * scale;
        float rowHeight = (GLYPH_HEIGHT + LINE_GAP) * scale;
        float y = height - MARGIN * scale - 3 * rowHeight;
        text(x, y, scale, steps[0 .. stepsLength], SOFT_WHITE);
        text(x, y + rowHeight, scale, cells[0 .. cellsLength], GOLD);
        text(x, y + 2 * rowHeight, scale, "T throw  C reset compass  H hide", SOFT_WHITE);
    }

    void buildCompass(ref const Game game) {
        float radius = COMPASS_SHARE * height;
        float[2] center = [width - MARGIN * scale - radius, height - MARGIN * scale - radius - GLYPH_HEIGHT * scale];
        circle(center, radius, PANEL, RIM);
        float off = game.compassOff().value;
        float[2] ahead = [center[0], center[1] - radius * 0.8f];
        line(center, ahead, scale, faded(WHITE, 0.45f));
        float[2] tip = [center[0] - sinf(off) * radius * 0.92f, center[1] - cosf(off) * radius * 0.92f];
        line(center, tip, NEEDLE_THICKNESS * scale, GOLD);
        char[TEXT_CAPACITY] written;
        int length = snprintf(written.ptr, written.length, "compass %+.0f", cast(double)(off * RADIANS_TO_DEGREES));
        text(center[0] - length * GLYPH_ADVANCE * scale / 2, center[1] + radius + LINE_GAP * scale, scale, written[0 .. length], GOLD);
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

// The foot of a point on the level plane through the eye, in the Poincare disk of that plane. Height above the plane
// fades a node out, so the disk shows the layer the viewer walks in and not every storey above it.
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

unittest {
    DiskPoint here = onDisk(Vec4!float([0, 0, 0, 1]));
    assert(here.at[0] == 0 && here.at[1] == 0 && here.share == 1);
    DiskPoint far = onDisk(Vec4!float([99.995f, 0, 0, 100]));
    assert(far.at[0] > 0.97f && far.at[0] < 1.0f);
    assert(onDisk(Vec4!float([0, 50, 0, 50])).share == 0);
    assert(onDisk(Vec4!float([500, 0, 0, 500])).share == 0);
}
