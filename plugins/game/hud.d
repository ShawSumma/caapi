module plugins.game.hud;

import core.stdc.math : asinhf, cosf, fabsf, floorf, sinf, sqrtf;
import base.array : Array;
import base.clock : FrameClock, MILLISECONDS_PER_SECOND;
import base.maybe : Maybe, MaybeIndex;
import base.names : ENUM_NAMES;
import base.numbers : PI, clamped, higherOf, lowerOf;
import base.splitmix : SplitMix;
import base.stdio : printed, snprintf;
import base.units : Ratio, Time;
import base.vector3 : Vec3;
import geometry.honeycomb : FACE_COUNT, Face;
import geometry.lorentz : Motion, Vec4;
import common.character.controller : MovementMode;
import common.graph : Graph;
import common.material : ByteColor, families, materialNames;
import common.perception : CHANNEL_COUNT, Channel, MOST_SENSES, presets;
import common.position : Position;
import common.traversal : NearbyScratch;
import common.worldgen.generation : Worldgen, WorldgenKind;
import common.worldgen.lineage : Lineage;
import client.camera : Quaternion;
import client.drawing : HudVertex, MOST_VERTICES, Marker, ScreenPoint;
import client.text : AtlasGlyph, FIRST_CHARACTER, GlyphAtlas, LAST_CHARACTER, WHITE_TEXEL, emPixelsFor, texelOf;
import client.world : LocalWorld;
import plugins.api.api : Material;
import plugins.crafting.crafting : Product, Recipe, Station, recipes, stations, upgrades;
import plugins.crafting.inventory : Cycle, HOTBAR_SLOTS, Inventory, Stack;
import plugins.crafting.items : Item, ItemKind, colorOf, contentNameOf, itemOf;
import plugins.game.bindings : Action, Rules;
import plugins.game.game : AimKind, BeaconSighting, CraftKind, Crafting, Game, MOST_NOTES, Mineable, NOTE_SECONDS, Note, NoteKind, Screen, TRAIL_POINTS, UiAction, requiredTierOf, stationOf, timeOf, toolFor;
import plugins.game.input : Controls, keyLabel;
import plugins.game.screens : buildScreen;

enum uint GROWTH_STEPS = 5;
enum size_t MOST_DISK_NODES = 1 << 14;
enum uint QUAD_VERTICES = 6;
enum uint CIRCLE_SEGMENTS = 48;
enum uint BASE_HEIGHT = 360;
enum float MARGIN = 8;
enum float TEXT_PADDING = 3;
enum float COLUMN_SHARE = 0.5f;
enum float BAR_SHARE = 0.2f;
enum float HOTBAR_SHARE = 0.07f;
enum float BEACON_NEEDLE_SHARE = 0.7f;
enum uint EFFECT_COLUMNS = 18;
enum float SWATCH_INSET_SHARE = 0.15f;
enum size_t COUNT_LABEL_CAPACITY = 12;
enum float BAR_BACK_SHARE = 0.25f;
enum size_t LINE_CAPACITY = 128;
enum uint MOST_NOTE_LINES = 3;
enum size_t NAME_CAPACITY = 32;
enum float DISK_SHARE = 0.13f;
enum float COMPASS_SHARE = 0.07f;
enum float DISK_BAND = 1.2f;
enum float DISK_FARTHEST_W = 200;
enum float NEEDLE_THICKNESS = 1.5f;
enum float LINK_THICKNESS = 0.7f;
enum float BLOCK_HALF = 0.02f;
enum float TRAIL_HALF = 0.005f;
enum float THREAD_HALF = 0.003f;
enum double STATUS_INTERVAL_SECONDS = 1.0;
enum size_t STATUS_CAPACITY = 256;
enum Time NOTE_FADE = Time(1);
enum float MINING_RING_SHARE = 0.03f;
enum float BACKDROP_SHARE = 0.5f;
enum float EFFECT_SHOWN = 0.05f;
enum float EFFECT_FULL = 1;
enum string SENSING = "sensing";
enum uint STRIP_CELLS = 16;
enum uint NIBBLES_PER_SEED_SHOWN = 4;
enum uint LETTER_COLOR_MULTIPLIER = 0x9E3779B1;
enum uint MARK_COLOR_FLOOR = 60;
enum uint MARK_COLOR_MASK = 0x7F;
enum float BUNDLE_BAND_SHARE = 0.5f;
enum uint WHITE = rgba(255, 255, 255, 255);
enum uint BLACK = rgba(0, 0, 0, 255);
enum uint PANEL = rgba(12, 16, 26, 190);
enum uint SOLID = rgba(18, 22, 32, 245);
enum uint RAISED = rgba(48, 56, 74, 235);
enum uint RIM = rgba(225, 225, 215, 210);
enum uint GOLD = rgba(255, 205, 90, 255);
enum uint CYAN = rgba(120, 225, 255, 255);
enum uint RED = rgba(240, 110, 90, 255);
enum uint DIM = rgba(170, 175, 185, 255);
enum uint THROWN_COLOR = rgba(255, 120, 50, 255);
enum uint TRAIL_COLOR = rgba(255, 215, 110, 255);

struct Display {
    Ratio function(ref const Game game) busy;
    bool function(ref Hud hud, ref const Game game, ref const Controls controls, const(char)[] name) target;
    const(char)[] function(ref const Game game, ref const Stack stack, char[] buffer) strain;
    bool function(ref Hud hud, ref const Game game, Box content, Station station) station;
    void function(ref Hud hud, ref const Game game, ref Panel panel, uint slot) surroundings;
}

__gshared Array!Display displays;

uint rgba(uint r, uint g, uint b, uint a) {
    return r | (g << 8) | (b << 16) | (a << 24);
}

uint faded(uint color, float share) {
    return (color & 0x00FFFFFF) | (cast(uint)((color >> 24) * share) << 24);
}

uint swatchOf(Item item) {
    ByteColor color = colorOf(item);
    return rgba(color.red, color.green, color.blue, 255);
}

uint markColor(uint mixed) {
    return rgba(MARK_COLOR_FLOOR + (mixed & MARK_COLOR_MASK), MARK_COLOR_FLOOR + ((mixed >> 8) & MARK_COLOR_MASK), MARK_COLOR_FLOOR + ((mixed >> 16) & MARK_COLOR_MASK), 255);
}

uint letterColor(ushort letter) {
    return markColor(cast(uint)(letter * LETTER_COLOR_MULTIPLIER));
}

uint strainColor(Lineage genes) {
    ulong mixed = 0;
    foreach (seed; genes.seeds) {
        mixed = SplitMix(mixed ^ seed).next();
    }
    return markColor(cast(uint) mixed);
}

void geneStrip(ref Hud hud, float x, float y, float cell, Lineage genes) {
    foreach (nibble; 0 .. STRIP_CELLS) {
        ulong value = genes.seeds[nibble / NIBBLES_PER_SEED_SHOWN] >> (4 * (nibble % NIBBLES_PER_SEED_SHOWN));
        hud.rect(x + nibble * cell, y, cell - hud.scale, hud.atlas.lineHeight, letterColor(cast(ushort)(value & 0xF)));
    }
}

const(char)[] spacedName(const(char)[] name, char[] buffer) {
    size_t length = 0;
    foreach (character; name) {
        if (character >= 'A' && character <= 'Z') {
            buffer[length] = ' ';
            buffer[length + 1] = cast(char)(character - 'A' + 'a');
            length += 2;
        } else {
            buffer[length] = character;
            length += 1;
        }
    }
    return buffer[0 .. length];
}

const(char)[] materialName(Material material, char[] buffer) {
    return displayName(materialNames.ptr[material.id], buffer);
}

const(char)[] displayName(const(char)[] name, char[] buffer) {
    size_t start = 0;
    while (start < name.length && name[start] != ':') {
        start += 1;
    }
    if (start < name.length) {
        start += 1;
    } else {
        start = 0;
    }
    size_t length = lowerOf(name.length - start, buffer.length);
    foreach (index; 0 .. length) {
        char character = name[start + index];
        if (character == '-') {
            character = ' ';
        }
        buffer[index] = character;
    }
    return buffer[0 .. length];
}

const(char)[] itemName(Item item, char[] buffer) {
    final switch (item.kind) {
        case ItemKind.nothing:
            return printed(buffer, "nothing");
        case ItemKind.block:
        case ItemKind.ware:
            return displayName(contentNameOf(item), buffer);
    }
}

const(char)[] stackName(ref const Game game, Stack stack, char[] buffer) {
    char[NAME_CAPACITY] storage;
    char[NAME_CAPACITY] strainStorage;
    const(char)[] name = itemName(stack.item, storage[]);
    const(char)[] strain;
    foreach (ref display; displays.slice()) {
        if (stack.strainCount > 0 && strain.length == 0) {
            strain = display.strain(game, stack, strainStorage[]);
        }
    }
    if (stack.isBundle) {
        return printed(buffer, "%.*s, a bundle of %u kinds", cast(int) name.length, name.ptr, stack.strainCount);
    } else if (strain.length > 0) {
        return printed(buffer, "%.*s, %.*s", cast(int) name.length, name.ptr, cast(int) strain.length, strain.ptr);
    } else {
        return printed(buffer, "%.*s", cast(int) name.length, name.ptr);
    }
}

const(char)[] craftLabel(ref const Crafting crafting, char[] buffer) {
    char[NAME_CAPACITY] storage;
    final switch (crafting.kind) {
        case CraftKind.recipe:
            const(Recipe)* recipe = &recipes()[crafting.index];
            final switch (recipe.product) {
                case Product.item:
                    const(char)[] name = itemName(recipe.made, storage[]);
                    return printed(buffer, "%u %.*s", recipe.yield, cast(int) name.length, name.ptr);
                case Product.upgrade:
                    const(char)[] upgrade = upgrades()[recipe.upgrade.id].title;
                    return printed(buffer, "%.*s", cast(int) upgrade.length, upgrade.ptr);
            }
        case CraftKind.work:
            return crafting.work.label(crafting, buffer);
    }
}

uint craftSwatch(ref const Crafting crafting) {
    if (crafting.kind == CraftKind.recipe && recipes()[crafting.index].product == Product.item) {
        return swatchOf(recipes()[crafting.index].made);
    } else {
        return CYAN;
    }
}

const(char)[] stationName(Station station, char[] buffer) {
    Maybe!Item block = blockItemOf(station);
    if (block.exists) {
        return itemName(block.value, buffer);
    } else {
        return printed(buffer, "hand");
    }
}

Maybe!Item blockItemOf(Station station) {
    Material block = stations()[station.id].block;
    if (block == Material.none) {
        return Maybe!Item.init;
    } else {
        return Maybe!Item.of(itemOf(block));
    }
}

const(char)[] describe(ref const Note note, char[] buffer) {
    char[NAME_CAPACITY] storage;
    char[NAME_CAPACITY] itemStorage;
    const(char)[] name = materialName(note.material, storage[]);
    const(char)[] item = itemName(note.item, itemStorage[]);
    int length = cast(int) name.length;
    int itemLength = cast(int) item.length;
    int labelLength = cast(int) note.label.length;
    char[NAME_CAPACITY] familyStorage;
    final switch (note.kind) {
        case NoteKind.revealed:
            const(char)[] appearing = displayName(families.ptr[note.family].name, familyStorage[]);
            return printed(buffer, "%.*s blocks appear", cast(int) appearing.length, appearing.ptr);
        case NoteKind.faded:
            const(char)[] fading = displayName(families.ptr[note.family].name, familyStorage[]);
            return printed(buffer, "%.*s blocks fade", cast(int) fading.length, fading.ptr);
        case NoteKind.inventoryFull:
            return printed(buffer, "inventory full, lost %.0f %.*s", cast(double) note.amount, itemLength, item.ptr);
        case NoteKind.crafted:
            return printed(buffer, "+%.0f %.*s", cast(double) note.amount, itemLength, item.ptr);
        case NoteKind.upgraded:
            return printed(buffer, "you now have a %.*s", labelLength, note.label.ptr);
        case NoteKind.missingIngredients:
            const(char)[] missing = displayName(note.label, familyStorage[]);
            return printed(buffer, "need %.0f more %.*s", cast(double) note.amount, cast(int) missing.length, missing.ptr);
        case NoteKind.needsTier:
            return printed(buffer, "%.*s needs %.*s", length, name.ptr, labelLength, note.label.ptr);
        case NoteKind.upgradeQueued:
            return printed(buffer, "the %.*s is already yours or queued", labelLength, note.label.ptr);
        case NoteKind.learned:
            return printed(buffer, "noticed: %.*s (journal)", labelLength, note.label.ptr);
        case NoteKind.written:
            return note.written();
        case NoteKind.told:
            return printed(buffer, "%.*s", labelLength, note.label.ptr);
        case NoteKind.woke:
            return printed(buffer, "you fell past the bottom of the world and woke again, %.0f things lost", cast(double) note.amount);
    }
}

struct Effect {
    float share;
    string label;
    MaybeIndex!uint family;
}

immutable string[2][CHANNEL_COUNT] EFFECT_WORDS = [
    Channel.walkSpeed: ["faster", "slower"],
    Channel.gravity: ["heavier", "lighter"],
    Channel.jumpHeight: ["higher jumps", "lower jumps"],
    Channel.fieldOfView: ["wider view", "narrower view"],
    Channel.fog: ["hazier", "clearer air"],
    Channel.eyeOffset: ["outside yourself", "outside yourself"],
    Channel.warp: ["swaying", "swaying"],
    Channel.colorTurn0: ["colors shifted", "colors shifted"],
    Channel.colorTurn1: ["colors shifted", "colors shifted"],
    Channel.colorTurn2: ["colors shifted", "colors shifted"],
    Channel.colorTurn3: ["colors shifted", "colors shifted"],
    Channel.colorTurn4: ["colors shifted", "colors shifted"],
    Channel.colorTurn5: ["colors shifted", "colors shifted"],
    Channel.afterimage: ["trails", "trails"],
    Channel.fineDetail: ["sharper", "blurred"],
    Channel.coarseDetail: ["stark", "washed out"],
];

uint effectsOf(ref const Game game, Effect[] effects) {
    uint count = 0;
    foreach (index; 0 .. CHANNEL_COUNT) {
        float level = game.perception.level[index].value;
        if (fabsf(level) > EFFECT_SHOWN && count < effects.length) {
            string label = EFFECT_WORDS[index][0];
            if (level < 0) {
                label = EFFECT_WORDS[index][1];
            }
            uint same = 0;
            while (same < count && effects[same].label != label) {
                same += 1;
            }
            if (same < count) {
                effects[same].share = higherOf(effects[same].share, fabsf(level) / EFFECT_FULL);
            } else {
                effects[count] = Effect(fabsf(level) / EFFECT_FULL, label);
                count += 1;
            }
        }
    }
    foreach (index; 0 .. cast(uint) families.length) {
        float level = game.perception.reveal[index].value;
        if (fabsf(level) > EFFECT_SHOWN && count < effects.length) {
            effects[count] = Effect(fabsf(level) / EFFECT_FULL, SENSING, MaybeIndex!uint.of(index));
            count += 1;
        }
    }
    return count;
}

const(char)[] effectLabel(ref const Effect effect, char[] buffer) {
    if (effect.family.exists) {
        char[NAME_CAPACITY] storage;
        const(char)[] sensed = displayName(families.ptr[effect.family.value].name, storage[]);
        return printed(buffer, "%.*s %.*s", cast(int) effect.label.length, effect.label.ptr, cast(int) sensed.length, sensed.ptr);
    } else {
        return effect.label;
    }
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

enum Anchor : ubyte {
    topLeft,
    topRight,
    bottomLeft,
    bottomRight,
}

enum uint ANCHOR_COUNT = Anchor.max + 1;

bool isTop(Anchor anchor) {
    return anchor == Anchor.topLeft || anchor == Anchor.topRight;
}

bool isLeft(Anchor anchor) {
    return anchor == Anchor.topLeft || anchor == Anchor.bottomLeft;
}

Anchor facing(Anchor anchor) {
    final switch (anchor) {
        case Anchor.topLeft:
            return Anchor.bottomLeft;
        case Anchor.topRight:
            return Anchor.bottomRight;
        case Anchor.bottomLeft:
            return Anchor.topLeft;
        case Anchor.bottomRight:
            return Anchor.topRight;
    }
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
    const(char)[] world = worldNameOf(game.world.graph.worldgen);
    string rules = ENUM_NAMES!Rules[game.rules];
    final switch (mouse) {
        case MouseCapture.captured:
            snprintf(text.ptr, text.length, "caapi - %.*s - %.*s - Esc opens the menu - %.0f fps",cast(int) world.length, world.ptr, cast(int) rules.length, rules.ptr, cast(double) meter.fps);
            break;
        case MouseCapture.released:
            snprintf(text.ptr, text.length, "caapi - %.*s - %.*s - click to play - %.0f fps", cast(int) world.length, world.ptr, cast(int) rules.length, rules.ptr, cast(double) meter.fps);
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

struct Panel {
    float x;
    float y;
    float row;
    float width;
    uint left;
    uint skip;
    uint cut;

    bool takes(uint rows) {
        if (skip > 0) {
            skip -= lowerOf(skip, rows);
            return false;
        } else if (cut == 0 && left >= rows) {
            return true;
        } else {
            cut += rows;
            return false;
        }
    }

    void advance() {
        y += row;
        left -= 1;
    }
}

struct Box {
    float x;
    float y;
    float w;
    float h;

    bool holds(ScreenPoint point) const {
        return point.x >= x && point.x < x + w && point.y >= y && point.y < y + h;
    }
}

struct Hotspot {
    Box box;
    UiAction action;
}

enum Column : ubyte {
    first,
    second,
}

enum uint COLUMN_COUNT = Column.max + 1;
enum uint WHEEL_ROWS = 3;

struct Scrolled {
    Box box = Box(0, 0, 0, 0);
    uint above;
    uint below;
}

struct Hud {
    Array!HudVertex vertices;
    Array!Marker markers;
    Array!DiskPoint disk;
    Array!Hotspot hotspots;
    Growth growth;
    GlyphAtlas atlas;
    float[ANCHOR_COUNT] used = 0;
    Scrolled[COLUMN_COUNT] scrolled;
    ScreenPoint cursor = ScreenPoint(0, 0);
    float width = 0;
    float height = 0;
    float scale = 1;
    Screen shownScreen;
    uint shownSheet;

    void rect(float x, float y, float w, float h, uint color) {
        quad(ScreenPoint(x, y), ScreenPoint(x + w, y), ScreenPoint(x + w, y + h), ScreenPoint(x, y + h), color);
    }

    void outline(Box box, float thickness, uint color) {
        rect(box.x, box.y, box.w, thickness, color);
        rect(box.x, box.y + box.h - thickness, box.w, thickness, color);
        rect(box.x, box.y, thickness, box.h, color);
        rect(box.x + box.w - thickness, box.y, thickness, box.h, color);
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

    const(char)[] fitting(const(char)[] line, float room) const {
        size_t characters = cast(size_t) higherOf(floorf(room / atlas.advance), 0.0f);
        return line[0 .. lowerOf(line.length, characters)];
    }

    void clippedText(float x, float top, float room, const(char)[] line, uint color) {
        text(x, top, fitting(line, room), color);
    }

    void put(ref const Panel panel, float offset, const(char)[] line, uint color) {
        clippedText(panel.x + offset, panel.y, panel.width - offset, line, color);
    }

    float textWidth(const(char)[] line) const {
        return cast(float) line.length * atlas.advance;
    }

    float columns(uint characters) const {
        return cast(float) characters * atlas.advance;
    }

    float margin() const {
        return MARGIN * scale;
    }

    float padding() const {
        return TEXT_PADDING * scale;
    }

    float rowHeight() const {
        return atlas.lineHeight + padding();
    }

    float columnLimit() const {
        return width * COLUMN_SHARE - 1.5f * margin();
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

    void arc(ScreenPoint center, float radius, float share, float thickness, uint color) {
        uint segments = cast(uint)(CIRCLE_SEGMENTS * clamped(share, 0.0f, 1.0f));
        foreach (segment; 0 .. segments) {
            line(onArc(center, radius, segment), onArc(center, radius, segment + 1), thickness, color);
        }
    }

    ScreenPoint place(Anchor anchor, float w, float h) {
        float x = width - margin() - w;
        if (anchor.isLeft) {
            x = margin();
        }
        float y = height - margin() - used[anchor] - h;
        if (anchor.isTop) {
            y = margin() + used[anchor];
        }
        used[anchor] += h + margin();
        return ScreenPoint(x, y);
    }

    uint rowsFree(Anchor anchor) const {
        float free = height - margin() - used[anchor] - used[anchor.facing] - 2 * padding();
        return cast(uint) higherOf(floorf(free / rowHeight()), 0.0f);
    }

    Panel openPanel(Anchor anchor, float wanted, uint rows) {
        float w = lowerOf(wanted, columnLimit() - 2 * padding());
        uint shown = lowerOf(rows, rowsFree(anchor));
        float h = shown * rowHeight() + padding();
        ScreenPoint at = place(anchor, w + 2 * padding(), h);
        rect(at.x, at.y, w + 2 * padding(), h, PANEL);
        return Panel(at.x + padding(), at.y + padding(), rowHeight(), w, shown);
    }

    void row(ref Panel panel, const(char)[] shown, uint color) {
        if (panel.takes(1)) {
            put(panel, 0, shown, color);
            panel.advance();
        }
    }

    uint rowsIn(Box box) const {
        return cast(uint) higherOf(floorf(box.h / rowHeight()), 0.0f);
    }

    float scrollBar() const {
        return 2 * scale;
    }

    Panel scrollPanel(Box box, Column column) const {
        return Panel(box.x, box.y, rowHeight(), box.w - scrollBar() - padding(), rowsIn(box), scrolled[column].above);
    }

    void closeScroll(ref const Panel panel, Box box, Column column) {
        Scrolled* kept = &scrolled[column];
        kept.box = box;
        kept.above -= panel.skip;
        kept.below = panel.cut;
        uint shown = rowsIn(box);
        if (shown > 0 && kept.above + kept.below > 0) {
            uint total = kept.above + shown + kept.below;
            float x = box.x + box.w - scrollBar();
            rect(x, box.y, scrollBar(), box.h, faded(WHITE, BAR_BACK_SHARE));
            rect(x, box.y + box.h * kept.above / total, scrollBar(), box.h * shown / total, RIM);
        }
    }

    void wheel(Cycle direction) {
        foreach (ref kept; scrolled) {
            if (kept.box.holds(cursor)) {
                final switch (direction) {
                    case Cycle.back:
                        kept.above -= lowerOf(kept.above, WHEEL_ROWS);
                        break;
                    case Cycle.ahead:
                        kept.above += lowerOf(kept.below, WHEEL_ROWS);
                        break;
                }
            }
        }
    }

    void fillBar(float x, float y, float w, float share, uint color) {
        rect(x, y, w, atlas.lineHeight, faded(WHITE, BAR_BACK_SHARE));
        rect(x, y, w * clamped(share, 0.0f, 1.0f), atlas.lineHeight, color);
    }

    bool isUnderCursor(Box box) const {
        return box.holds(cursor);
    }

    void hotspot(Box box, UiAction action) {
        hotspots.append(Hotspot(box, action));
    }

    void button(Box box, const(char)[] label, Maybe!UiAction action) {
        uint color = DIM;
        uint fill = PANEL;
        if (action.exists) {
            color = WHITE;
            fill = RAISED;
            hotspot(box, action.value);
        }
        rect(box.x, box.y, box.w, box.h, fill);
        if (action.exists && isUnderCursor(box)) {
            outline(box, scale, GOLD);
        }
        clippedText(box.x + padding(), box.y + (box.h - atlas.lineHeight) / 2, box.w - 2 * padding(), label, color);
    }

    void pointAt(float x, float y) {
        cursor = ScreenPoint(x, y);
    }

    Maybe!UiAction actionAt() const {
        size_t index = hotspots.length;
        while (index > 0 && !hotspots.ptr[index - 1].box.holds(cursor)) {
            index -= 1;
        }
        if (index > 0) {
            return Maybe!UiAction.of(hotspots.ptr[index - 1].action);
        } else {
            return Maybe!UiAction.init;
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
        foreach (ref point; game.thread.beads.slice()) {
            addMarker(game, nearby, point, THREAD_HALF, GOLD);
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

    void build(ref const Game game, ref const Controls controls, ref const FrameMeter meter, uint pixelsWide, uint pixelsHigh) {
        vertices.clear();
        hotspots.clear();
        used[] = 0;
        foreach (ref kept; scrolled) {
            kept.box = Box(0, 0, 0, 0);
            if (game.screen != shownScreen || game.sheet != shownSheet) {
                kept.above = 0;
            }
        }
        shownScreen = game.screen;
        shownSheet = game.sheet;
        width = pixelsWide;
        height = pixelsHigh;
        scale = higherOf(1u, pixelsHigh / BASE_HEIGHT);
        atlas.ensure(emPixelsFor(pixelsHigh));
        float band = buildHotbar(game, controls);
        buildCompass(game, band);
        buildPoincareDisk(game);
        if (game.screen == Screen.none) {
            buildMiningRing(game);
            buildMode(game);
            buildEffects(game);
            buildTarget(game, controls);
            buildCrafting(game);
            buildNotes(game, MOST_NOTES);
        } else {
            rect(0, 0, width, height, faded(BLACK, BACKDROP_SHARE));
            float noteRow = rowHeight() + padding() + margin();
            buildScreen(this, game, controls, meter, Box(margin(), margin(), width - 2 * margin(), height - band - noteRow - 2 * margin()));
            buildNotes(game, 1);
            buildCarried(game);
        }
    }

    void buildMiningRing(ref const Game game) {
        float share = game.miningShare().value;
        foreach (ref display; displays.slice()) {
            share = higherOf(share, display.busy(game).value);
        }
        if (share > 0) {
            ScreenPoint center = ScreenPoint(width / 2, height / 2);
            float radius = MINING_RING_SHARE * height;
            arc(center, radius, 1, 2 * scale, faded(BLACK, 0.4f));
            arc(center, radius, share, 2 * scale, WHITE);
        }
    }

    void buildMode(ref const Game game) {
        if (game.rules == Rules.creative) {
            char[LINE_CAPACITY] buffer;
            string mode = ENUM_NAMES!MovementMode[game.mode];
            const(char)[] preset = presets.ptr[game.preset].name;
            const(char)[] world = worldNameOf(game.world.graph.worldgen);
            const(char)[] line = printed(buffer[], "creative: %.*s, %.*s, %.*s", cast(int) world.length, world.ptr, cast(int) mode.length, mode.ptr, cast(int) preset.length, preset.ptr);
            Panel panel = openPanel(Anchor.topLeft, textWidth(line), 1);
            row(panel, line, DIM);
        }
    }

    void buildEffects(ref const Game game) {
        Effect[MOST_SENSES] effects;
        char[LINE_CAPACITY] buffer;
        uint count = effectsOf(game, effects[]);
        if (count > 0) {
            float label = columns(EFFECT_COLUMNS);
            Panel panel = openPanel(Anchor.topLeft, label + BAR_SHARE * height / 2, count);
            float bar = higherOf(panel.width - label, 0.0f);
            foreach (ref effect; effects[0 .. count]) {
                if (panel.takes(1)) {
                    put(panel, 0, effectLabel(effect, buffer[]), WHITE);
                    fillBar(panel.x + label, panel.y, bar, effect.share, CYAN);
                    panel.advance();
                }
            }
        }
    }

    void buildTarget(ref const Game game, ref const Controls controls) {
        char[NAME_CAPACITY] storage;
        char[LINE_CAPACITY] buffer;
        const(char)[] name = materialName(game.aim.material, storage[]);
        const(char)[] use = keyLabel(controls.bindings.keys[Action.use].slice());
        uint drawn = 0;
        foreach (ref display; displays.slice()) {
            if (game.aim.kind != AimKind.nothing && drawn == 0 && display.target(this, game, controls, name)) {
                drawn += 1;
            }
        }
        if (drawn == 0) {
            final switch (game.aim.kind) {
                case AimKind.nothing:
                    break;
                case AimKind.block:
                    if (game.mineableOf(game.aim.material) == Mineable.tooHard) {
                        const(char)[] tool = toolFor(requiredTierOf(game.aim.material));
                        targetLines(name, printed(buffer[], "needs %.*s", cast(int) tool.length, tool.ptr));
                    } else {
                        targetLines(name, null);
                    }
                    break;
                case AimKind.usable:
                    targetLines(name, printed(buffer[], "%.*s: open", cast(int) use.length, use.ptr));
                    break;
                case AimKind.readable:
                    targetLines(name, printed(buffer[], "%.*s: read", cast(int) use.length, use.ptr));
                    break;
            }
        }
    }

    void targetLines(const(char)[] name, const(char)[] hint) {
        uint rows = 1;
        if (hint.length > 0) {
            rows = 2;
        }
        Panel panel = openPanel(Anchor.topRight, higherOf(textWidth(name), textWidth(hint)), rows);
        row(panel, name, WHITE);
        if (hint.length > 0) {
            row(panel, hint, DIM);
        }
    }

    void buildCrafting(ref const Game game) {
        if (game.crafts.length > 0 && rowsFree(Anchor.bottomLeft) > 0) {
            char[LINE_CAPACITY] storage;
            char[LINE_CAPACITY] buffer;
            MaybeIndex!uint active = game.activeCraft();
            const(Crafting)* shownCraft = &game.crafts.ptr[0];
            if (active.exists) {
                shownCraft = &game.crafts.ptr[active.value];
            }
            const(char)[] name = craftLabel(*shownCraft, storage[]);
            const(char)[] shown;
            if (active.exists) {
                shown = printed(buffer[], "making %.*s, %zu in the queue", cast(int) name.length, name.ptr, game.crafts.length);
            } else if (game.isStationReady(stationOf(*shownCraft))) {
                shown = printed(buffer[], "%.*s waits for ingredients", cast(int) name.length, name.ptr);
            } else {
                char[NAME_CAPACITY] place;
                const(char)[] station = stationName(stationOf(*shownCraft), place[]);
                shown = printed(buffer[], "%.*s waits for you at a %.*s", cast(int) name.length, name.ptr, cast(int) station.length, station.ptr);
            }
            shown = fitting(shown, columnLimit() - 2 * padding());
            float w = higherOf(textWidth(shown), columns(EFFECT_COLUMNS));
            ScreenPoint at = place(Anchor.bottomLeft, w + 2 * padding(), rowHeight() + 2 * padding());
            rect(at.x, at.y, w + 2 * padding(), rowHeight() + 2 * padding(), PANEL);
            float done = 1 - (shownCraft.left / timeOf(*shownCraft)).value;
            rect(at.x, at.y + rowHeight() + padding(), (w + 2 * padding()) * clamped(done, 0.0f, 1.0f), padding(), GOLD);
            uint color = WHITE;
            if (!active.exists) {
                color = DIM;
            }
            text(at.x + padding(), at.y + padding(), shown, color);
        }
    }

    void buildNotes(ref const Game game, size_t most) {
        char[LINE_CAPACITY] buffer;
        size_t index = game.notes.length;
        size_t drawn = 0;
        while (index > 0 && drawn < most) {
            index -= 1;
            const(Note)* note = &game.notes.ptr[index];
            Time age = game.time - note.at;
            if (age < NOTE_SECONDS) {
                const(char)[][MOST_NOTE_LINES] lines;
                uint count = wrapLines(describe(*note, buffer[]), charactersIn(columnLimit() - 2 * padding()), lines);
                if (rowsFree(Anchor.bottomLeft) >= count) {
                    drawn += 1;
                    float share = clamped(((NOTE_SECONDS - age) / NOTE_FADE).value, 0.0f, 1.0f);
                    float wide = 0;
                    foreach (line; lines[0 .. count]) {
                        wide = higherOf(wide, textWidth(line));
                    }
                    float high = count * rowHeight() + padding();
                    ScreenPoint at = place(Anchor.bottomLeft, wide + 2 * padding(), high);
                    rect(at.x, at.y, wide + 2 * padding(), high, faded(PANEL, share));
                    foreach (row, line; lines[0 .. count]) {
                        text(at.x + padding(), at.y + padding() + row * rowHeight(), line, faded(WHITE, share));
                    }
                }
            }
        }
    }

    size_t charactersIn(float room) const {
        return cast(size_t) higherOf(floorf(room / atlas.advance), 1.0f);
    }

    void buildCarried(ref const Game game) {
        if (!game.carried.isEmpty) {
            float side = hotbarSide();
            stackCell(Box(cursor.x - side / 2, cursor.y - side / 2, side, side), game.carried, faded(PANEL, 0));
        }
    }

    void stackCell(Box box, Stack stack, uint fill) {
        rect(box.x, box.y, box.w, box.h, fill);
        if (!stack.isEmpty) {
            float inset = box.w * SWATCH_INSET_SHARE;
            rect(box.x + inset, box.y + inset, box.w - 2 * inset, box.h - 2 * inset, swatchOf(stack.item));
            if (stack.isBundle) {
                float wide = (box.w - 2 * inset) / stack.strainCount;
                foreach (index, ref run; stack.strains[0 .. stack.strainCount]) {
                    rect(box.x + inset + index * wide, box.y + inset, wide - scale, (box.h - 2 * inset) * BUNDLE_BAND_SHARE, strainColor(run.genes));
                }
            }
            if (stack.count > 1) {
                char[COUNT_LABEL_CAPACITY] buffer;
                const(char)[] label = fitting(printed(buffer[], "%u", stack.count), box.w);
                rect(box.x + box.w - textWidth(label), box.y + box.h - atlas.lineHeight, textWidth(label), atlas.lineHeight, PANEL);
                text(box.x + box.w - textWidth(label), box.y + box.h - atlas.lineHeight, label, WHITE);
            }
        }
    }

    float hotbarSide() const {
        return lowerOf(HOTBAR_SHARE * height, (width - 2 * margin() - (HOTBAR_SLOTS - 1) * padding()) / HOTBAR_SLOTS);
    }

    float hotbarWidth() const {
        return HOTBAR_SLOTS * hotbarSide() + (HOTBAR_SLOTS - 1) * padding();
    }

    float buildHotbar(ref const Game game, ref const Controls controls) {
        const(Inventory)* inventory = &game.inventory;
        float side = hotbarSide();
        float gap = padding();
        float total = hotbarWidth();
        float left = floorf((width - total) / 2);
        float top = height - margin() - side;
        foreach (slot; 0 .. HOTBAR_SLOTS) {
            Box box = Box(left + slot * (side + gap), top, side, side);
            stackCell(box, inventory.slots[slot], PANEL);
            const(char)[] key = fitting(keyLabel(controls.bindings.keys[Action.slot1 + slot].slice()), side / 2);
            text(box.x + gap, box.y, key, faded(WHITE, 0.6f));
            if (slot == inventory.selected) {
                outline(box, NEEDLE_THICKNESS * scale, GOLD);
            }
        }
        char[LINE_CAPACITY] storage;
        Item held = inventory.held();
        float label = top - rowHeight() - 2 * padding();
        if (held.kind != ItemKind.nothing && game.screen == Screen.none) {
            const(char)[] name = fitting(stackName(game, inventory.slots[inventory.selected], storage[]), total);
            float w = textWidth(name) + 2 * padding();
            float x = floorf((width - w) / 2);
            rect(x, label, w, rowHeight() + padding(), PANEL);
            text(x + padding(), label + padding(), name, WHITE);
        }
        float band = height - label;
        used[Anchor.bottomLeft] = band;
        return band;
    }

    void buildCompass(ref const Game game, float band) {
        float radius = COMPASS_SHARE * height;
        float hotbarRight = (width + hotbarWidth()) / 2;
        if (width - margin() - 2 * radius < hotbarRight + margin()) {
            used[Anchor.bottomRight] = band;
        }
        ScreenPoint corner = place(Anchor.bottomRight, 2 * radius, 2 * radius);
        ScreenPoint center = ScreenPoint(corner.x + radius, corner.y + radius);
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
            const(char)[] label = printed(buffer[], "%.1f", cast(double) nearest.value);
            float wide = textWidth(label) + 2 * padding();
            ScreenPoint at = place(Anchor.bottomRight, wide, atlas.lineHeight);
            rect(center.x - wide / 2, at.y, wide, atlas.lineHeight, PANEL);
            text(center.x - textWidth(label) / 2, at.y, label, CYAN);
        }
    }

    void buildPoincareDisk(ref const Game game) {
        float radius = lowerOf(DISK_SHARE * height, columnLimit() / 2);
        ScreenPoint corner = place(Anchor.topRight, 2 * radius, 2 * radius);
        ScreenPoint center = ScreenPoint(corner.x + radius, corner.y + radius);
        circle(center, radius, PANEL, RIM);
        if (game.world.cameraNearbyIndex().exists) {
            growth.update(game.world);
            drawDiskNodes(game, center, radius);
        }
        line(center, ScreenPoint(center.x, center.y - 4 * scale), NEEDLE_THICKNESS * scale, GOLD);
        rect(center.x - scale, center.y - scale, 2 * scale, 2 * scale, WHITE);
    }

    void drawDiskNodes(ref const Game game, ScreenPoint center, float radius) {
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
                        uint color = CYAN;
                        if (game.isExplored(graph.idAt(slot)) && game.isExplored(graph.idAt(next.value))) {
                            color = GOLD;
                        }
                        line(placed(center, radius, from.at), placed(center, radius, to.at), LINK_THICKNESS * scale, faded(color, lowerOf(from.share, to.share)));
                    }
                }
            }
        }
    }

    void release() {
        vertices.release();
        markers.release();
        disk.release();
        hotspots.release();
        growth.release();
        atlas.release();
    }
}

size_t lineEnd(const(char)[] text, size_t start, size_t room) {
    size_t end = lowerOf(start + room, text.length);
    if (end == text.length) {
        return end;
    } else {
        size_t space = end;
        while (space > start && text[space] != ' ') {
            space -= 1;
        }
        if (space > start) {
            return space;
        } else {
            return end;
        }
    }
}

size_t nextLineStart(const(char)[] text, size_t end) {
    size_t start = end;
    while (start < text.length && text[start] == ' ') {
        start += 1;
    }
    return start;
}

uint wrapLines(const(char)[] text, size_t room, ref const(char)[][MOST_NOTE_LINES] lines) {
    uint count = 0;
    size_t start = 0;
    while (start < text.length && count < MOST_NOTE_LINES) {
        size_t end = lineEnd(text, start, room);
        lines[count] = text[start .. end];
        count += 1;
        start = nextLineStart(text, end);
    }
    return count;
}

ScreenPoint onCircle(ScreenPoint center, float radius, uint segment) {
    float angle = segment * 2 * PI / CIRCLE_SEGMENTS;
    return ScreenPoint(center.x + cosf(angle) * radius, center.y + sinf(angle) * radius);
}

ScreenPoint onArc(ScreenPoint center, float radius, uint segment) {
    float angle = segment * 2 * PI / CIRCLE_SEGMENTS;
    return ScreenPoint(center.x + sinf(angle) * radius, center.y - cosf(angle) * radius);
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
