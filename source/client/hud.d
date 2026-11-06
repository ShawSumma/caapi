module client.hud;

import core.stdc.math : asinhf, cosf, floorf, powf, sinf, sqrtf;
import base.array : Array;
import base.clock : FrameClock, MILLISECONDS_PER_SECOND;
import base.maybe : Maybe, MaybeIndex;
import base.names : ENUM_NAMES;
import base.numbers : PI, higherOf, lowerOf;
import base.stdio : snprintf;
import base.units : Ratio;
import base.vector3 : Vec3;
import geometry.honeycomb : FACE_COUNT, Face;
import geometry.lorentz : Motion, Vec4;
import common.biology.genome : Receptor;
import common.biology.molecule : Fragment, GRID_CELLS, PROPERTY_COUNT, Property, fragmentAt;
import common.biology.organism : Organism;
import common.biology.signaling : MESSENGER_COUNT, SIGNAL_COUNT, Signaling;
import common.character.controller : MovementMode;
import common.graph : Graph;
import common.inventory : HOTBAR_SLOTS, Inventory;
import common.material : ByteColor, MATERIAL_COLORS;
import common.perception : SIGNAL_NAMES;
import common.position : Position;
import common.traversal : NearbyScratch;
import common.worldgen.generation : Worldgen, WorldgenKind;
import client.camera : Quaternion;
import client.game : BeaconSighting, Game, Preset, Scan, Seed, TRAIL_POINTS;
import client.text : AtlasGlyph, FIRST_CHARACTER, GlyphAtlas, LAST_CHARACTER, WHITE_TEXEL, emPixelsFor, texelOf;
import client.world : LocalWorld;
import plugins.api.api : Material;

enum uint GROWTH_STEPS = 5;
enum size_t MOST_DISK_NODES = 1 << 14;
enum uint MOST_VERTICES = 1 << 18;
enum uint QUAD_VERTICES = 6;
enum uint CIRCLE_SEGMENTS = 48;
enum uint BASE_HEIGHT = 360;
enum float MARGIN = 8;
enum float TEXT_PADDING = 3;
enum float BAR_SHARE = 0.2f;
enum float HOTBAR_SHARE = 0.075f;
enum float BEACON_NEEDLE_SHARE = 0.7f;
enum float SCAN_PLOT_SHARE = 0.12f;
enum uint STRIP_CELLS = 16;
enum uint NIBBLES_PER_SEED_SHOWN = 4;
enum size_t SEEDS_SHOWN = 3;
enum string BENCH_LONGEST_LABEL = "gene 10 ";
enum string BENCH_TITLE = "bench: E crosses, F splices";
enum uint LETTER_COLOR_MULTIPLIER = 0x9E3779B1;
enum uint LETTER_COLOR_FLOOR = 60;
enum uint LETTER_COLOR_MASK = 0x7F;
enum float SCAN_MOST_FRAGMENTS = 9;
enum uint ASSAY_POINTS = 48;
enum float LEAST_ASSAY_DECADE = -3;
enum float ASSAY_DECADES = 4;
enum string SCAN_LONGEST_LABEL = "fragments ";
immutable string[4] SCAN_LABELS = ["fragments", "bulky", "charged", "polar"];
enum float SWATCH_INSET_SHARE = 0.15f;
enum size_t COUNT_LABEL_CAPACITY = 12;
enum float TRACE_SHARE = 0.12f;
enum float BAR_BACK_SHARE = 0.25f;
enum float SIGNAL_RANGE = 1;
enum float TRACE_RANGE = 1.5f;
enum uint TRACE_POINTS = 120;
enum size_t RECEPTOR_LABEL_CAPACITY = 16;
enum string LONGEST_LABEL = "AA bound ";
enum char FIRST_HALF_NAME = 'A';
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
immutable uint[MESSENGER_COUNT] TRACE_COLORS = [GOLD, CYAN, THROWN_COLOR];

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
    uint texel;
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
    string preset = ENUM_NAMES!Preset[game.preset];
    const(char)[] world = worldNameOf(game.world.graph.worldgen);
    final switch (mouse) {
        case MouseCapture.captured:
            snprintf(text.ptr, text.length, "mined - %.*s ([ ]) - %.*s (V) - %.*s (P) - [%u] - Esc to release mouse - FPS %.0f, worst frame %.0fms", cast(int) world.length, world.ptr, cast(int) mode.length, mode.ptr, cast(int) preset.length, preset.ptr, game.inventory.selected + 1, cast(double) meter.fps, cast(double) meter.worstFrameMs);
            break;
        case MouseCapture.released:
            snprintf(text.ptr, text.length, "mined - %.*s ([ ]) - %.*s (V) - %.*s (P) - click to capture mouse - FPS %.0f, worst frame %.0fms", cast(int) world.length, world.ptr, cast(int) mode.length, mode.ptr, cast(int) preset.length, preset.ptr, cast(double) meter.fps, cast(double) meter.worstFrameMs);
            break;
    }
    return text;
}

const(char)[] stateLine(ref const Game game, char[] buffer) {
    string mode = ENUM_NAMES!MovementMode[game.mode];
    string preset = ENUM_NAMES!Preset[game.preset];
    const(char)[] world = worldNameOf(game.world.graph.worldgen);
    int written = snprintf(buffer.ptr, buffer.length, "%.*s   %.*s   %.*s", cast(int) world.length, world.ptr, cast(int) mode.length, mode.ptr, cast(int) preset.length, preset.ptr);
    return buffer[0 .. lowerOf(cast(size_t) higherOf(written, 0), buffer.length - 1)];
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
    GlyphAtlas atlas;
    Ratio[MESSENGER_COUNT][TRACE_POINTS] trace;
    uint traced;
    float width = 0;
    float height = 0;
    float scale = 1;

    void rect(float x, float y, float w, float h, uint color) {
        quad(ScreenPoint(x, y), ScreenPoint(x + w, y), ScreenPoint(x + w, y + h), ScreenPoint(x, y + h), color);
    }

    void quad(ScreenPoint a, ScreenPoint b, ScreenPoint c, ScreenPoint d, uint color) {
        texturedQuad(a, b, c, d, color, [WHITE_TEXEL, WHITE_TEXEL, WHITE_TEXEL, WHITE_TEXEL]);
    }

    void texturedQuad(ScreenPoint a, ScreenPoint b, ScreenPoint c, ScreenPoint d, uint color, uint[4] texels) {
        if (vertices.length + QUAD_VERTICES <= MOST_VERTICES) {
            vertex(a, color, texels[0]);
            vertex(b, color, texels[1]);
            vertex(c, color, texels[2]);
            vertex(c, color, texels[2]);
            vertex(d, color, texels[3]);
            vertex(a, color, texels[0]);
        }
    }

    void vertex(ScreenPoint at, uint color, uint texel) {
        vertices.append(HudVertex(ScreenPoint(2 * at.x / width - 1, 2 * at.y / height - 1), color, texel));
    }

    void text(float x, float top, const(char)[] line, uint color) {
        float pen = floorf(x);
        float baseline = floorf(top) + atlas.ascent;
        foreach (character; line) {
            if (character >= FIRST_CHARACTER && character <= LAST_CHARACTER) {
                AtlasGlyph glyph = atlas.glyphs[character - FIRST_CHARACTER];
                if (glyph.box.width > 0 && glyph.box.height > 0) {
                    float left = pen + glyph.box.left;
                    float upper = baseline + glyph.box.top;
                    float right = left + glyph.box.width;
                    float lower = upper + glyph.box.height;
                    uint atlasRight = glyph.atlasX + glyph.box.width;
                    uint atlasLower = glyph.atlasY + glyph.box.height;
                    texturedQuad(ScreenPoint(left, upper), ScreenPoint(right, upper), ScreenPoint(right, lower), ScreenPoint(left, lower), color, [texelOf(glyph.atlasX, glyph.atlasY), texelOf(atlasRight, glyph.atlasY), texelOf(atlasRight, atlasLower), texelOf(glyph.atlasX, atlasLower)]);
                }
            }
            pen += atlas.advance;
        }
    }

    float textWidth(const(char)[] line) const {
        return cast(float) line.length * atlas.advance;
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
                vertex(center, fill, WHITE_TEXEL);
                vertex(a, fill, WHITE_TEXEL);
                vertex(b, fill, WHITE_TEXEL);
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
        atlas.ensure(emPixelsFor(pixelsHigh));
        if (game.world.cameraNearbyIndex().exists) {
            growth.update(game.world);
            buildPoincareDisk(game);
        }
        buildCompass(game);
        buildState(game);
        buildBody(game);
        buildHotbar(game);
        Maybe!Material aimed = game.world.targetMaterial();
        if (aimed.exists && aimed.value == Material.bench) {
            buildBench(game);
        } else if (game.isScanShown) {
            buildScan(game.scan.value);
        }
    }

    void buildBench(ref const Game game) {
        float margin = MARGIN * scale;
        float padding = TEXT_PADDING * scale;
        float row = atlas.lineHeight + padding;
        float cell = atlas.lineHeight / 2;
        float label = textWidth(BENCH_LONGEST_LABEL);
        size_t genes = game.organism.genome.count;
        size_t seeds = lowerOf(game.seeds.length, cast(size_t) SEEDS_SHOWN);
        float panelWidth = higherOf(label + STRIP_CELLS * cell + 3 * padding, textWidth(BENCH_TITLE) + 2 * padding);
        float left = width - margin - panelWidth;
        float top = 2 * margin + 2 * DISK_SHARE * height;
        rect(left, top, panelWidth, (genes + seeds + 1) * row + 2 * padding, PANEL);
        float x = left + padding;
        float y = top + padding;
        text(x, y, BENCH_TITLE, WHITE);
        y += row;
        foreach (index, ref gene; game.organism.genome.slice()) {
            char[RECEPTOR_LABEL_CAPACITY] buffer;
            int written = snprintf(buffer.ptr, buffer.length, "gene %zu", index + 1);
            text(x, y, buffer[0 .. lowerOf(cast(size_t) higherOf(written, 0), buffer.length - 1)], WHITE);
            foreach (letter; 0 .. lowerOf(cast(uint) gene.length, STRIP_CELLS)) {
                rect(x + label + letter * cell, y, cell - scale, atlas.lineHeight, letterColor(gene.letters[letter]));
            }
            y += row;
        }
        foreach (shown; 0 .. seeds) {
            const(Seed)* seed = &game.seeds.ptr[game.seeds.length - 1 - shown];
            char[RECEPTOR_LABEL_CAPACITY] buffer;
            int written = snprintf(buffer.ptr, buffer.length, "seed %zu", shown + 1);
            text(x, y, buffer[0 .. lowerOf(cast(size_t) higherOf(written, 0), buffer.length - 1)], CYAN);
            foreach (nibble; 0 .. STRIP_CELLS) {
                ulong value = seed.genes.seeds[nibble / NIBBLES_PER_SEED_SHOWN] >> (4 * (nibble % NIBBLES_PER_SEED_SHOWN));
                rect(x + label + nibble * cell, y, cell - scale, atlas.lineHeight, letterColor(cast(ushort)(value & 0xF)));
            }
            y += row;
        }
    }

    void buildScan(ref const Scan scan) {
        float margin = MARGIN * scale;
        float padding = TEXT_PADDING * scale;
        float row = atlas.lineHeight + padding;
        float label = textWidth(SCAN_LONGEST_LABEL);
        float bar = BAR_SHARE * height;
        float plot = SCAN_PLOT_SHARE * height;
        float panelWidth = label + bar + 3 * padding;
        float left = width - margin - panelWidth;
        float top = 2 * margin + 2 * DISK_SHARE * height;
        rect(left, top, panelWidth, 5 * row + plot + 3 * padding, PANEL);
        float x = left + padding;
        float y = top + padding;
        string name = ENUM_NAMES!Material[scan.plant];
        text(x, y, name, WHITE);
        y += row;
        uint[4] counts;
        foreach (cell; 0 .. GRID_CELLS) {
            Fragment fragment = scan.product.fragmentAt(cell);
            if (fragment.isPresent) {
                counts[0] += 1;
                foreach (property; 0 .. PROPERTY_COUNT) {
                    if (fragment.has(cast(Property) property)) {
                        counts[1 + property] += 1;
                    }
                }
            }
        }
        foreach (index, count; counts) {
            text(x, y, SCAN_LABELS[index], WHITE);
            rect(x + label, y, bar, atlas.lineHeight, faded(WHITE, BAR_BACK_SHARE));
            rect(x + label, y, bar * lowerOf(cast(float) count / SCAN_MOST_FRAGMENTS, 1.0f), atlas.lineHeight, GOLD);
            y += row;
        }
        float plotLeft = x;
        float plotTop = y + padding;
        float plotWidth = label + bar;
        rect(plotLeft, plotTop, plotWidth, plot, faded(WHITE, BAR_BACK_SHARE / 2));
        foreach (index; 0 .. scan.receptors) {
            uint color = faded(WHITE, BAR_BACK_SHARE * 2);
            if (scan.efficacy[index].value > 0) {
                color = GOLD;
            } else if (scan.efficacy[index].value < 0) {
                color = CYAN;
            }
            foreach (point; 1 .. ASSAY_POINTS) {
                line(assayPoint(plotLeft, plotTop, plotWidth, plot, point - 1, scan.affinity[index].value), assayPoint(plotLeft, plotTop, plotWidth, plot, point, scan.affinity[index].value), scale, color);
            }
        }
    }

    void buildHotbar(ref const Game game) {
        const(Inventory)* inventory = &game.inventory;
        float side = HOTBAR_SHARE * height;
        float gap = TEXT_PADDING * scale;
        float total = HOTBAR_SLOTS * side + (HOTBAR_SLOTS - 1) * gap;
        float left = floorf((width - total) / 2);
        float top = height - MARGIN * scale - side;
        foreach (slot; 0 .. HOTBAR_SLOTS) {
            float x = left + slot * (side + gap);
            Material material = inventory.hotbar[slot];
            uint count = inventory.counts[material];
            rect(x, top, side, side, PANEL);
            if (material != Material.none && count > 0) {
                ByteColor color = MATERIAL_COLORS[material];
                float inset = side * SWATCH_INSET_SHARE;
                rect(x + inset, top + inset, side - 2 * inset, side - 2 * inset, rgba(color.red, color.green, color.blue, 255));
                char[COUNT_LABEL_CAPACITY] buffer;
                int written = snprintf(buffer.ptr, buffer.length, "%u", count);
                const(char)[] label = buffer[0 .. lowerOf(cast(size_t) higherOf(written, 0), buffer.length - 1)];
                rect(x + side - textWidth(label) - gap, top + side - atlas.lineHeight, textWidth(label), atlas.lineHeight, PANEL);
                text(x + side - textWidth(label) - gap, top + side - atlas.lineHeight, label, WHITE);
            }
            if (slot == inventory.selected) {
                ScreenPoint[4] corners = [ScreenPoint(x, top), ScreenPoint(x + side, top), ScreenPoint(x + side, top + side), ScreenPoint(x, top + side)];
                foreach (index; 0 .. 4) {
                    line(corners[index], corners[(index + 1) % 4], NEEDLE_THICKNESS * scale, GOLD);
                }
            }
        }
    }

    void buildBody(ref const Game game) {
        const(Organism)* organism = &game.organism;
        recordTrace(organism.signaling);
        if (organism.body.count > 0) {
            float margin = MARGIN * scale;
            float padding = TEXT_PADDING * scale;
            float row = atlas.lineHeight + padding;
            float label = textWidth(LONGEST_LABEL);
            float bar = BAR_SHARE * height;
            float traceHeight = TRACE_SHARE * height;
            size_t rows = SIGNAL_COUNT + organism.receptors.length;
            float top = 2 * margin + atlas.lineHeight + 2 * padding;
            float left = margin + padding;
            rect(margin, top, label + bar + 3 * padding, rows * row + traceHeight + 3 * padding, PANEL);
            float y = top + padding;
            Ratio[SIGNAL_COUNT] signals = organism.signaling.signals();
            foreach (signal; 0 .. SIGNAL_COUNT) {
                text(left, y, SIGNAL_NAMES[signal], WHITE);
                centeredBar(left + label, y, bar, atlas.lineHeight, signals[signal].value / SIGNAL_RANGE);
                y += row;
            }
            foreach (index, occupied; organism.occupancy.slice()) {
                const(Receptor)* receptor = &organism.receptors.ptr[index];
                char[RECEPTOR_LABEL_CAPACITY] buffer;
                int written = snprintf(buffer.ptr, buffer.length, "%c%c bound", cast(char)(FIRST_HALF_NAME + receptor.firstHalf), cast(char)(FIRST_HALF_NAME + receptor.secondHalf));
                text(left, y, buffer[0 .. lowerOf(cast(size_t) higherOf(written, 0), buffer.length - 1)], WHITE);
                rect(left + label, y, bar, atlas.lineHeight, faded(WHITE, BAR_BACK_SHARE));
                rect(left + label, y, bar * lowerOf(occupied.value, 1.0f), atlas.lineHeight, CYAN);
                y += row;
            }
            drawTrace(left, y + padding, label + bar, traceHeight);
        }
    }

    void centeredBar(float x, float y, float w, float h, float share) {
        float middle = x + w / 2;
        float reach = w / 2 * lowerOf(higherOf(share, -1.0f), 1.0f);
        rect(x, y, w, h, faded(WHITE, BAR_BACK_SHARE));
        if (reach >= 0) {
            rect(middle, y, reach, h, GOLD);
        } else {
            rect(middle + reach, y, -reach, h, CYAN);
        }
        rect(middle, y, scale, h, WHITE);
    }

    void recordTrace(ref const Signaling signaling) {
        trace[traced % TRACE_POINTS] = signaling.messengers;
        traced += 1;
    }

    void drawTrace(float x, float y, float w, float h) {
        uint shown = lowerOf(traced, TRACE_POINTS);
        foreach (messenger; 0 .. MESSENGER_COUNT) {
            foreach (point; 1 .. shown) {
                ScreenPoint from = tracePoint(x, y, w, h, point - 1, shown, messenger);
                ScreenPoint to = tracePoint(x, y, w, h, point, shown, messenger);
                line(from, to, scale, TRACE_COLORS[messenger]);
            }
        }
    }

    ScreenPoint tracePoint(float x, float y, float w, float h, uint point, uint shown, uint messenger) const {
        uint index = (traced - shown + point) % TRACE_POINTS;
        float level = lowerOf(higherOf(trace[index][messenger].value / TRACE_RANGE, 0.0f), 1.0f);
        return ScreenPoint(x + w * point / (TRACE_POINTS - 1), y + h * (1 - level));
    }

    void buildState(ref const Game game) {
        char[STATUS_CAPACITY] buffer;
        const(char)[] shown = stateLine(game, buffer[]);
        float margin = MARGIN * scale;
        float padding = TEXT_PADDING * scale;
        rect(margin, margin, textWidth(shown) + 2 * padding, atlas.lineHeight + 2 * padding, PANEL);
        text(margin + padding, margin + padding, shown, WHITE);
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
        Maybe!float nearest;
        foreach (beacon; game.beacons.slice()) {
            BeaconSighting sighting = game.sightingOf(beacon);
            float toward = game.yawToward(sighting.direction).value;
            ScreenPoint end = ScreenPoint(center.x - sinf(toward) * radius * BEACON_NEEDLE_SHARE, center.y - cosf(toward) * radius * BEACON_NEEDLE_SHARE);
            line(center, end, NEEDLE_THICKNESS * scale, CYAN);
            if (!nearest.exists || sighting.distance.value < nearest.value) {
                nearest = Maybe!float.of(sighting.distance.value);
            }
        }
        if (nearest.exists) {
            char[COUNT_LABEL_CAPACITY] buffer;
            int written = snprintf(buffer.ptr, buffer.length, "%.1f", cast(double) nearest.value);
            const(char)[] label = buffer[0 .. lowerOf(cast(size_t) higherOf(written, 0), buffer.length - 1)];
            text(center.x - textWidth(label) / 2, center.y - radius - atlas.lineHeight - TEXT_PADDING * scale, label, CYAN);
        }
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
        atlas.release();
    }
}

uint letterColor(ushort letter) {
    uint mixed = cast(uint)(letter * LETTER_COLOR_MULTIPLIER);
    return rgba(LETTER_COLOR_FLOOR + (mixed & LETTER_COLOR_MASK), LETTER_COLOR_FLOOR + ((mixed >> 8) & LETTER_COLOR_MASK), LETTER_COLOR_FLOOR + ((mixed >> 16) & LETTER_COLOR_MASK), 255);
}

ScreenPoint assayPoint(float x, float y, float w, float h, uint point, float affinity) {
    float share = cast(float) point / (ASSAY_POINTS - 1);
    float concentration = powf(10, LEAST_ASSAY_DECADE + share * ASSAY_DECADES);
    float occupied = concentration / (concentration + affinity);
    return ScreenPoint(x + w * share, y + h * (1 - occupied));
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
