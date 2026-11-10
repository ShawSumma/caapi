module client.save;

import core.stdc.string : memcpy, strncpy;
import base.array : Array;
import base.maybe : Maybe, MaybeIndex;
import base.flags : Readiness;
import base.units : Length, Time;
import client.game : Beacon, Compound, Game, MOST_COMPOUNDS, RAW_PER_DOSE, slotFor;
import common.crafting : CraftKind, Crafting, IdSet, Reaction, SynthesisRule, insights, recipes, returnIngredients, syntheses, upgrades;
import common.items : Item, ItemKind, contentNameOf, itemCount, itemNamed;
import client.hud : worldNameOf;
import common.biology.genome : Genome;
import common.biology.kinetics : Body;
import common.biology.organism : Organism;
import common.biology.signaling : Signaling;
import common.edits : BlockRecord, CellEdit, ChunkEdits;
import common.graph : Graph, NodeId, ParentList, ROOT_NODE;
import common.inventory : Inventory, Stack;
import common.node : ChunkId;
import common.position : Position;
import geometry.honeycomb : Corner, Face;
import geometry.lorentz : Motion;
import plugins.api.api : ENTRY, Material;

enum uint SAVE_MAGIC = 0x63616170;
enum uint SAVE_FORMAT = 10;
enum uint MOST_SAVED_NAMES = 1 << 16;
enum uint MOST_NAME_BYTES = 1 << 10;
enum uint WORLDGEN_VERSION = 4;
enum size_t ENTRY_CAPACITY = 32;
enum size_t WORLD_NAME_CAPACITY = 64;
enum uint MOST_PATH_FACES = 1 << 16;

struct SaveHeader {
    uint magic;
    uint format;
    uint worldgen;
    char[ENTRY_CAPACITY] entry;
    char[WORLD_NAME_CAPACITY] world;
}

struct SavedEdits {
    NodeId node;
    uint cells;
    uint records;
    Corner corner;
}

struct SavedBeacon {
    uint faces;
    uint cell;
    Corner corner;
}

struct Writer {
    Array!ubyte bytes;

    void put(T)(ref const T value) {
        bytes.appendAll((cast(const(ubyte)*) &value)[0 .. T.sizeof]);
    }

    void putAll(T)(const(T)[] values) {
        bytes.appendAll((cast(const(ubyte)*) values.ptr)[0 .. T.sizeof * values.length]);
    }
}

struct Reader {
    const(ubyte)[] bytes;
    size_t at;

    bool take(T)(ref T value) {
        if (at + T.sizeof > bytes.length) {
            return false;
        } else {
            memcpy(&value, bytes.ptr + at, T.sizeof);
            at += T.sizeof;
            return true;
        }
    }
}

struct Remap {
    Array!ushort items;
    Array!(MaybeIndex!uint) upgrades;
    Array!(MaybeIndex!uint) insights;

    Item item(Item saved) const {
        if (saved.id < items.length) {
            return Item(items.ptr[saved.id]);
        } else {
            return Item.init;
        }
    }

    Material material(Material saved) const {
        Item found = item(Item(saved.id));
        if (found.kind == ItemKind.block) {
            return found.block;
        } else {
            return Material.none;
        }
    }

    void release() {
        items.release();
        upgrades.release();
        insights.release();
    }
}

IdSet remapped(IdSet saved, const(MaybeIndex!uint)[] map) {
    IdSet made;
    foreach (index, now; map) {
        if (saved.has(cast(uint) index) && now.exists) {
            made.set(now.value);
        }
    }
    return made;
}

void putName(ref Writer writer, const(char)[] name) {
    uint length = cast(uint) name.length;
    writer.put(length);
    writer.putAll(name);
}

void putNames(T)(ref Writer writer, const(T)[] rows) {
    uint count = cast(uint) rows.length;
    writer.put(count);
    foreach (ref row; rows) {
        writer.putName(row.name);
    }
}

void putNameTables(ref Writer writer) {
    uint count = itemCount();
    writer.put(count);
    foreach (id; 0 .. count) {
        writer.putName(contentNameOf(Item(cast(ushort) id)));
    }
    writer.putNames(upgrades());
    writer.putNames(insights());
}

bool takeName(ref Reader reader, ref const(char)[] name) {
    uint length;
    if (!reader.take(length) || length > MOST_NAME_BYTES || reader.at + length > reader.bytes.length) {
        return false;
    } else {
        name = cast(const(char)[]) reader.bytes[reader.at .. reader.at + length];
        reader.at += length;
        return true;
    }
}

bool takeRows(T)(ref Reader reader, const(T)[] rows, ref Array!(MaybeIndex!uint) map) {
    uint count;
    if (!reader.take(count) || count > MOST_SAVED_NAMES) {
        return false;
    } else {
        foreach (_; 0 .. count) {
            const(char)[] name;
            if (!reader.takeName(name)) {
                return false;
            }
            uint index = 0;
            while (index < rows.length && rows[index].name != name) {
                index += 1;
            }
            if (index < rows.length) {
                map.append(MaybeIndex!uint.of(index));
            } else {
                map.append(MaybeIndex!uint.init);
            }
        }
        return true;
    }
}

bool takeNameTables(ref Reader reader, ref Remap remap) {
    uint count;
    if (!reader.take(count) || count > MOST_SAVED_NAMES) {
        return false;
    } else {
        foreach (_; 0 .. count) {
            const(char)[] name;
            if (!reader.takeName(name)) {
                return false;
            }
            Maybe!Item found = itemNamed(name);
            if (found.exists) {
                remap.items.append(found.value.id);
            } else {
                remap.items.append(Item.init.id);
            }
        }
        return reader.takeRows(upgrades(), remap.upgrades) && reader.takeRows(insights(), remap.insights);
    }
}

void remapData(ref SaveData data, ref const Remap remap) {
    foreach (ref stack; data.inventory.slots) {
        Item now = remap.item(stack.item);
        if (now.kind == ItemKind.nothing) {
            stack = Stack.init;
        } else {
            stack.item = now;
        }
    }
    data.owned = data.owned.remapped(remap.upgrades.slice());
    data.noticed = data.noticed.remapped(remap.insights.slice());
    foreach (ref edit; data.cells.slice()) {
        edit.material = remap.material(edit.material);
    }
}

struct SaveData {
    SaveHeader header;
    Array!Face path;
    Motion!float local;
    Inventory inventory;
    IdSet owned;
    IdSet noticed;
    Time time;
    Array!Compound compounds;
    Genome genome;
    Body body;
    Signaling signaling;
    Array!SavedEdits chunks;
    Array!CellEdit cells;
    Array!BlockRecord records;
    Array!SavedBeacon beacons;
    Array!Face beaconPaths;

    void release() {
        compounds.release();
        path.release();
        chunks.release();
        cells.release();
        records.release();
        beacons.release();
        beaconPaths.release();
    }
}

SaveHeader headerFor(ref const Game game) {
    SaveHeader header = SaveHeader(SAVE_MAGIC, SAVE_FORMAT, WORLDGEN_VERSION);
    strncpy(header.entry.ptr, ENTRY.ptr, ENTRY_CAPACITY - 1);
    const(char)[] world = worldNameOf(game.world.graph.worldgen);
    size_t length = world.length;
    if (length > WORLD_NAME_CAPACITY - 1) {
        length = WORLD_NAME_CAPACITY - 1;
    }
    memcpy(header.world.ptr, world.ptr, length);
    return header;
}

void pathFromRoot(ref const Graph graph, uint slot, ref Array!Face path) {
    path.clear();
    uint at = slot;
    while (graph.idAt(at) != ROOT_NODE) {
        ParentList list = graph.parents(at);
        path.append(list.links[0].side);
        at = list.links[0].slot;
    }
    foreach (index; 0 .. path.length / 2) {
        Face swapped = path.ptr[index];
        path.ptr[index] = path.ptr[path.length - 1 - index];
        path.ptr[path.length - 1 - index] = swapped;
    }
}

void refund(ref const Crafting crafting, ref Inventory kept, ref Array!Compound compounds) {
    final switch (crafting.kind) {
        case CraftKind.recipe:
            kept.returnIngredients(recipes()[crafting.index], crafting.taken);
            break;
        case CraftKind.synthesis:
            const(SynthesisRule)* rule = &syntheses()[crafting.index];
            if (rule.reagent.kind != ItemKind.nothing) {
                kept.gain(Stack(rule.reagent, 1));
            }
            final switch (rule.reaction) {
                case Reaction.extract:
                    kept.gain(crafting.pressed);
                    break;
                case Reaction.press:
                    compounds.ptr[compounds.slotFor(crafting.molecule)].raw += RAW_PER_DOSE;
                    break;
                case Reaction.oxidize:
                case Reaction.conjugate:
                case Reaction.cleave:
                case Reaction.attach:
                    compounds.ptr[compounds.slotFor(crafting.molecule)].doses += 1;
                    break;
            }
            break;
    }
}

void writeGame(ref const Game game, ref Writer writer) {
    SaveHeader header = headerFor(game);
    writer.put(header);
    writer.putNameTables();
    Array!Face path;
    Position body = game.characterState.position;
    pathFromRoot(game.world.graph, game.world.graph.slotOf(body.node).value, path);
    uint faces = cast(uint) path.length;
    writer.put(faces);
    writer.putAll(path.slice());
    writer.put(body.local);
    path.release();
    Inventory kept = game.inventory;
    Array!Compound compounds;
    compounds.appendAll(game.compounds.slice());
    foreach (ref crafting; game.crafts.slice()) {
        if (crafting.started == Readiness.ready) {
            refund(crafting, kept, compounds);
        }
    }
    if (!game.carried.isEmpty) {
        kept.gain(game.carried);
    }
    writer.put(kept);
    writer.put(game.owned);
    writer.put(game.noticed);
    writer.put(game.time);
    uint compoundCount = cast(uint) compounds.length;
    writer.put(compoundCount);
    writer.putAll(compounds.slice());
    compounds.release();
    writer.put(game.organism.genome);
    writer.put(game.organism.body);
    writer.put(game.organism.signaling);
    uint counted = 0;
    foreach (ref const chunk, ref const edits; game.world.graph.edits.chunks) {
        counted += 1;
    }
    writer.put(counted);
    foreach (ref const chunk, ref const edits; game.world.graph.edits.chunks) {
        SavedEdits saved = SavedEdits(chunk.node, cast(uint) edits.cells.length, cast(uint) edits.records.length, chunk.corner);
        writer.put(saved);
        writer.putAll(edits.cells.slice());
        writer.putAll(edits.records.slice());
    }
    uint beaconCount = cast(uint) game.beacons.length;
    writer.put(beaconCount);
    Array!Face beaconPath;
    foreach (beacon; game.beacons.slice()) {
        pathFromRoot(game.world.graph, game.world.graph.slotOf(beacon.chunk.node).value, beaconPath);
        SavedBeacon saved = SavedBeacon(cast(uint) beaconPath.length, beacon.cell, beacon.chunk.corner);
        writer.put(saved);
        writer.putAll(beaconPath.slice());
    }
    beaconPath.release();
}

const(char)* readGame(const(ubyte)[] bytes, ref const Game game, ref SaveData data) {
    Reader reader = Reader(bytes);
    if (!reader.take(data.header) || data.header.magic != SAVE_MAGIC) {
        return "is not a caapi save";
    } else if (data.header.format != SAVE_FORMAT) {
        return "was written by another save format";
    } else if (data.header.worldgen != WORLDGEN_VERSION) {
        return "was written for another version of world generation, so its edits would not line up";
    } else if (data.header.entry != headerFor(game).entry) {
        return "was written for another plugin interface version";
    } else if (data.header.world != headerFor(game).world) {
        return "belongs to another world";
    } else {
        Remap remap;
        const(char)* problem = "is cut short in its names";
        if (reader.takeNameTables(remap)) {
            problem = readBody(reader, data);
        }
        if (problem is null) {
            remapData(data, remap);
        }
        remap.release();
        return problem;
    }
}

const(char)* readBody(ref Reader reader, ref SaveData data) {
    if (!readPath(reader, data)) {
        return "is cut short in the body's place";
    } else if (!reader.take(data.local) || !reader.take(data.inventory) || !reader.take(data.owned) || !reader.take(data.noticed) || !reader.take(data.time)) {
        return "is cut short in the inventory";
    } else if (!readCompounds(reader, data)) {
        return "is cut short in the compounds";
    } else if (!reader.take(data.genome) || !reader.take(data.body) || !reader.take(data.signaling)) {
        return "is cut short before the edits";
    } else if (!readEdits(reader, data)) {
        return "is cut short in the edits";
    } else if (!readBeacons(reader, data)) {
        return "is cut short in the beacons";
    } else {
        return null;
    }
}

bool readCompounds(ref Reader reader, ref SaveData data) {
    uint count;
    bool counted = reader.take(count) && count <= MOST_COMPOUNDS;
    if (counted) {
        foreach (_; 0 .. count) {
            Compound compound;
            if (!reader.take(compound)) {
                return false;
            }
            data.compounds.append(compound);
        }
    }
    return counted;
}

bool readBeacons(ref Reader reader, ref SaveData data) {
    uint count;
    bool counted = reader.take(count);
    if (counted) {
        foreach (_; 0 .. count) {
            SavedBeacon saved;
            if (!reader.take(saved) || saved.faces > MOST_PATH_FACES) {
                return false;
            }
            data.beacons.append(saved);
            foreach (face; 0 .. saved.faces) {
                Face along;
                if (!reader.take(along)) {
                    return false;
                }
                data.beaconPaths.append(along);
            }
        }
    }
    return counted;
}

bool readPath(ref Reader reader, ref SaveData data) {
    uint faces;
    bool counted = reader.take(faces) && faces <= MOST_PATH_FACES;
    if (counted) {
        data.path.resize(faces);
        foreach (index; 0 .. faces) {
            if (!reader.take(data.path.ptr[index])) {
                return false;
            }
        }
    }
    return counted;
}

bool readEdits(ref Reader reader, ref SaveData data) {
    uint chunkCount;
    bool counted = reader.take(chunkCount);
    if (counted) {
        foreach (_; 0 .. chunkCount) {
            SavedEdits saved;
            if (!reader.take(saved)) {
                return false;
            }
            data.chunks.append(saved);
            foreach (cell; 0 .. saved.cells) {
                CellEdit edit;
                if (!reader.take(edit)) {
                    return false;
                }
                data.cells.append(edit);
            }
            foreach (record; 0 .. saved.records) {
                BlockRecord kept;
                if (!reader.take(kept)) {
                    return false;
                }
                data.records.append(kept);
            }
        }
    }
    return counted;
}

void applyEdits(ref Game game, ref const SaveData data) {
    size_t cell = 0;
    size_t record = 0;
    foreach (saved; data.chunks.slice()) {
        ChunkId chunk = ChunkId(saved.node, saved.corner);
        foreach (_; 0 .. saved.cells) {
            CellEdit edit = data.cells.ptr[cell];
            game.world.graph.edits.record(chunk, edit.cell, edit.material);
            cell += 1;
        }
        foreach (_; 0 .. saved.records) {
            game.world.graph.edits.keepRecord(chunk, data.records.ptr[record]);
            record += 1;
        }
    }
}

uint replayed(ref Graph graph, const(Face)[] path) {
    uint slot = graph.slotOf(ROOT_NODE).value;
    foreach (face; path) {
        slot = graph.ensureNeighborSlot(slot, face);
    }
    return slot;
}

void applyState(ref Game game, ref const SaveData data) {
    game.inventory = data.inventory;
    game.owned = data.owned;
    game.noticed = data.noticed;
    game.time = data.time;
    game.organism.release();
    game.organism = Organism.make(data.genome);
    game.organism.body = data.body;
    game.organism.signaling = data.signaling;
    game.compounds.clear();
    game.compounds.appendAll(data.compounds.slice());
    game.assayAll();
    size_t first = 0;
    foreach (saved; data.beacons.slice()) {
        uint beaconSlot = replayed(game.world.graph, data.beaconPaths.slice()[first .. first + saved.faces]);
        first += saved.faces;
        game.world.graph.reference(beaconSlot);
        game.beacons.append(Beacon(ChunkId(game.world.graph.idAt(beaconSlot), saved.corner), saved.cell));
    }
    uint slot = replayed(game.world.graph, data.path.slice());
    game.placeAt(Position(game.world.graph.idAt(slot), data.local), Length(0));
}

