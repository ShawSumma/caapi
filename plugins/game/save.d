module plugins.game.save;

import core.stdc.string : memcpy, strncpy;
import base.array : Array;
import base.maybe : Maybe, MaybeIndex;
import base.flags : Readiness;
import base.units : Length, Time;
import common.edits : BlockRecord, CellEdit, ChunkEdits;
import common.graph : Graph, NodeId, ParentList, ROOT_NODE;
import common.node : ChunkId;
import common.position : Position;
import geometry.honeycomb : Corner, Face;
import geometry.lorentz : Motion;
import plugins.api.api : ENTRY, Material;
import plugins.crafting.crafting : IdSet, Job, Recipe, Step, Taken, insights, recipes, upgrades;
import plugins.crafting.inventory : Inventory, SLOT_COUNT, Stack, isAmong;
import plugins.crafting.items : Item, ItemKind, contentNameOf, itemCount, itemNamed;
import plugins.game.game : Beacon, CraftKind, Crafting, Game, MOST_FOOTHOLDS;
import plugins.game.hud : worldNameOf;

enum uint SAVE_MAGIC = 0x63616170;
enum uint SAVE_FORMAT = 13;
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

struct SavedFoothold {
    uint faces;
    Motion!float local;
}

struct SavedJob {
    uint id;
    uint stacks;
}

struct SavedStep {
    Time left;
    uint recipe;
    uint job;
    uint order;
    uint taken;
    Readiness started;
    Step step;
}

struct SavedTaken {
    Item item;
    ushort count;
    ubyte need;
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

struct Section {
    const(char)[] name;
    void function(ref const Game game, ref Writer writer) write;
    void function(ref Game game, const(ubyte)[] bytes, ref const Remap remap) read;
}

__gshared Array!Section sections;

struct Remap {
    Array!ushort items;
    Array!(MaybeIndex!uint) upgrades;
    Array!(MaybeIndex!uint) insights;
    Array!(MaybeIndex!uint) recipes;

    Item item(Item saved) const {
        if (saved.id < items.length) {
            return Item(items.ptr[saved.id]);
        } else {
            return Item.init;
        }
    }

    Stack stack(Stack saved) const {
        Stack made = saved;
        made.item = item(saved.item);
        if (made.item.kind == ItemKind.nothing) {
            return Stack.init;
        } else {
            return made;
        }
    }

    MaybeIndex!uint recipe(uint saved) const {
        if (saved < recipes.length) {
            return recipes.ptr[saved];
        } else {
            return MaybeIndex!uint.init;
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
        recipes.release();
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
    writer.putNames(recipes());
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
        return reader.takeRows(upgrades(), remap.upgrades) && reader.takeRows(insights(), remap.insights) && reader.takeRows(recipes(), remap.recipes);
    }
}

void remapData(ref SaveData data) {
    foreach (ref stack; data.inventory.slots) {
        stack = data.remap.stack(stack);
    }
    data.carried = data.remap.stack(data.carried);
    foreach (ref job; data.jobs.slice()) {
        foreach (ref stack; job.held.slots) {
            stack = data.remap.stack(stack);
        }
    }
    foreach (ref taken; data.taken.slice()) {
        taken.item = data.remap.item(taken.item);
    }
    data.owned = data.owned.remapped(data.remap.upgrades.slice());
    data.noticed = data.noticed.remapped(data.remap.insights.slice());
    foreach (ref edit; data.cells.slice()) {
        edit.material = data.remap.material(edit.material);
    }
}

struct SaveData {
    SaveHeader header;
    Remap remap;
    Array!Face path;
    Motion!float local;
    Inventory inventory;
    Stack carried;
    IdSet owned;
    IdSet noticed;
    Time time;
    uint lastJob;
    uint lastQueued;
    Array!Job jobs;
    Array!SavedStep steps;
    Array!SavedTaken taken;
    Array!SavedEdits chunks;
    Array!CellEdit cells;
    Array!BlockRecord records;
    Array!SavedBeacon beacons;
    Array!Face beaconPaths;
    Array!SavedFoothold footholds;
    Array!Face footholdPaths;
    Array!ubyte extra;

    void release() {
        remap.release();
        extra.release();
        path.release();
        jobs.release();
        steps.release();
        taken.release();
        chunks.release();
        cells.release();
        records.release();
        beacons.release();
        beaconPaths.release();
        footholds.release();
        footholdPaths.release();
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

void putJobs(ref Writer writer, ref const Game game) {
    writer.put(game.lastJob);
    uint count = cast(uint) game.jobs.length;
    writer.put(count);
    foreach (ref job; game.jobs.slice()) {
        SavedJob saved = SavedJob(job.id, 0);
        foreach (ref stack; job.held.slots) {
            if (!stack.isEmpty) {
                saved.stacks += 1;
            }
        }
        writer.put(saved);
        foreach (ref stack; job.held.slots) {
            if (!stack.isEmpty) {
                writer.put(stack);
            }
        }
    }
}

void putStep(ref Writer writer, ref const Crafting crafting) {
    const(Recipe)* recipe = &recipes()[crafting.index];
    Array!SavedTaken taken;
    foreach (need, ref ingredient; recipe.needs[0 .. recipe.needed]) {
        foreach (option, item; ingredient.accepted) {
            if (crafting.taken.counts[need][option] > 0) {
                taken.append(SavedTaken(item, crafting.taken.counts[need][option], cast(ubyte) need));
            }
        }
    }
    SavedStep saved = SavedStep(crafting.left, crafting.index, crafting.job, crafting.order, cast(uint) taken.length, crafting.started, crafting.step);
    writer.put(saved);
    writer.putAll(taken.slice());
    taken.release();
}

void putSteps(ref Writer writer, ref const Game game) {
    writer.put(game.lastQueued);
    uint count = 0;
    foreach (ref crafting; game.crafts.slice()) {
        if (crafting.kind == CraftKind.recipe) {
            count += 1;
        }
    }
    writer.put(count);
    foreach (ref crafting; game.crafts.slice()) {
        if (crafting.kind == CraftKind.recipe) {
            writer.putStep(crafting);
        }
    }
}

void putSections(ref Writer writer, ref const Game game) {
    uint count = cast(uint) sections.length;
    writer.put(count);
    foreach (ref section; sections.slice()) {
        Writer part;
        section.write(game, part);
        uint length = cast(uint) part.bytes.length;
        writer.putName(section.name);
        writer.put(length);
        writer.putAll(part.bytes.slice());
        part.bytes.release();
    }
}

bool takeSection(ref Reader reader, ref const(char)[] name, ref const(ubyte)[] bytes) {
    uint length;
    if (!reader.takeName(name) || !reader.take(length) || reader.at + length > reader.bytes.length) {
        return false;
    } else {
        bytes = reader.bytes[reader.at .. reader.at + length];
        reader.at += length;
        return true;
    }
}

bool readSections(ref Reader reader, ref SaveData data) {
    size_t start = reader.at;
    uint count;
    bool whole = reader.take(count);
    uint taken = 0;
    while (whole && taken < count) {
        const(char)[] name;
        const(ubyte)[] bytes;
        whole = reader.takeSection(name, bytes);
        taken += 1;
    }
    if (whole) {
        data.extra.appendAll(reader.bytes[start .. reader.at]);
    }
    return whole;
}

void applySections(ref Game game, ref const SaveData data) {
    Reader reader = Reader(data.extra.slice());
    uint count;
    reader.take(count);
    foreach (_; 0 .. count) {
        const(char)[] name;
        const(ubyte)[] bytes;
        reader.takeSection(name, bytes);
        foreach (ref section; sections.slice()) {
            if (section.name == name) {
                section.read(game, bytes, data.remap);
            }
        }
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
    writer.put(game.inventory);
    writer.put(game.carried);
    writer.put(game.owned);
    writer.put(game.noticed);
    writer.put(game.time);
    writer.putJobs(game);
    writer.putSteps(game);
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
    uint footholdCount = game.footholds.count;
    writer.put(footholdCount);
    Array!Face footholdPath;
    foreach (place; game.footholds.places[0 .. game.footholds.count]) {
        pathFromRoot(game.world.graph, game.world.graph.slotOf(place.node).value, footholdPath);
        SavedFoothold saved = SavedFoothold(cast(uint) footholdPath.length, place.local);
        writer.put(saved);
        writer.putAll(footholdPath.slice());
    }
    footholdPath.release();
    writer.putSections(game);
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
        const(char)* problem = "is cut short in its names";
        if (reader.takeNameTables(data.remap)) {
            problem = readBody(reader, data);
        }
        if (problem is null) {
            remapData(data);
        }
        return problem;
    }
}

const(char)* readBody(ref Reader reader, ref SaveData data) {
    if (!readPath(reader, data)) {
        return "is cut short in the body's place";
    } else if (!reader.take(data.local) || !reader.take(data.inventory) || !reader.take(data.carried) || !reader.take(data.owned) || !reader.take(data.noticed) || !reader.take(data.time)) {
        return "is cut short in the inventory";
    } else if (!readJobs(reader, data) || !readSteps(reader, data)) {
        return "is cut short in the crafting queue";
    } else if (!readEdits(reader, data)) {
        return "is cut short in the edits";
    } else if (!readBeacons(reader, data)) {
        return "is cut short in the beacons";
    } else if (!readFootholds(reader, data)) {
        return "is cut short in the places to wake";
    } else if (!readSections(reader, data)) {
        return "is cut short in what the mods saved";
    } else {
        return null;
    }
}

bool readJobs(ref Reader reader, ref SaveData data) {
    uint count;
    bool counted = reader.take(data.lastJob) && reader.take(count);
    if (counted) {
        foreach (_; 0 .. count) {
            SavedJob saved;
            if (!reader.take(saved) || saved.stacks > SLOT_COUNT) {
                return false;
            }
            Job job = Job(saved.id);
            foreach (slot; 0 .. saved.stacks) {
                if (!reader.take(job.held.slots[slot])) {
                    return false;
                }
            }
            data.jobs.append(job);
        }
    }
    return counted;
}

bool readSteps(ref Reader reader, ref SaveData data) {
    uint count;
    bool counted = reader.take(data.lastQueued) && reader.take(count);
    if (counted) {
        foreach (_; 0 .. count) {
            SavedStep saved;
            if (!reader.take(saved)) {
                return false;
            }
            data.steps.append(saved);
            foreach (part; 0 .. saved.taken) {
                SavedTaken taken;
                if (!reader.take(taken)) {
                    return false;
                }
                data.taken.append(taken);
            }
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

bool readFootholds(ref Reader reader, ref SaveData data) {
    uint count;
    bool counted = reader.take(count) && count <= MOST_FOOTHOLDS;
    if (counted) {
        foreach (_; 0 .. count) {
            SavedFoothold saved;
            if (!reader.take(saved) || saved.faces > MOST_PATH_FACES) {
                return false;
            }
            data.footholds.append(saved);
            foreach (face; 0 .. saved.faces) {
                Face along;
                if (!reader.take(along)) {
                    return false;
                }
                data.footholdPaths.append(along);
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

bool isTakenBy(ref const Recipe recipe, SavedTaken taken) {
    return taken.need < recipe.needed && taken.item.isAmong(recipe.needs[taken.need].accepted);
}

bool isReadBack(ref const SaveData data, ref const SavedStep saved, size_t first) {
    MaybeIndex!uint index = data.remap.recipe(saved.recipe);
    if (!index.exists) {
        return false;
    } else {
        size_t part = first;
        while (part < first + saved.taken && isTakenBy(recipes()[index.value], data.taken.ptr[part])) {
            part += 1;
        }
        return part == first + saved.taken;
    }
}

bool isLost(uint job, const(uint)[] lost) {
    size_t index = 0;
    while (index < lost.length && lost[index] != job) {
        index += 1;
    }
    return index < lost.length;
}

Taken takenOf(ref const Recipe recipe, const(SavedTaken)[] parts) {
    Taken taken;
    foreach (ref part; parts) {
        uint option = 0;
        while (recipe.needs[part.need].accepted[option] != part.item) {
            option += 1;
        }
        taken.counts[part.need][option] = part.count;
    }
    return taken;
}

void restoreQueue(ref Game game, ref const SaveData data, ref Array!uint lost) {
    size_t first = 0;
    foreach (ref saved; data.steps.slice()) {
        if (!isReadBack(data, saved, first)) {
            lost.append(saved.job);
        }
        first += saved.taken;
    }
    foreach (ref job; data.jobs.slice()) {
        if (!isLost(job.id, lost.slice())) {
            game.jobs.append(job);
        }
    }
    first = 0;
    foreach (ref saved; data.steps.slice()) {
        if (!isLost(saved.job, lost.slice())) {
            uint index = data.remap.recipe(saved.recipe).value;
            Crafting crafting = Crafting(takenOf(recipes()[index], data.taken.slice()[first .. first + saved.taken]), saved.left, index, CraftKind.recipe, saved.started, saved.job, saved.step);
            crafting.order = saved.order;
            game.requeue(crafting);
        }
        first += saved.taken;
    }
    game.lastJob = data.lastJob;
    game.lastQueued = data.lastQueued;
}

void returnLost(ref Game game, ref const SaveData data, const(uint)[] lost) {
    foreach (ref job; data.jobs.slice()) {
        if (isLost(job.id, lost)) {
            foreach (ref stack; job.held.slots) {
                if (!stack.isEmpty) {
                    game.store(stack);
                }
            }
        }
    }
    size_t first = 0;
    foreach (ref saved; data.steps.slice()) {
        if (isLost(saved.job, lost)) {
            foreach (ref part; data.taken.slice()[first .. first + saved.taken]) {
                if (part.item.kind != ItemKind.nothing) {
                    game.store(Stack(part.item, part.count));
                }
            }
        }
        first += saved.taken;
    }
}

void applyState(ref Game game, ref const SaveData data) {
    game.inventory = data.inventory;
    game.owned = data.owned;
    game.noticed = data.noticed;
    game.time = data.time;
    Array!uint lost;
    restoreQueue(game, data, lost);
    applySections(game, data);
    returnLost(game, data, lost.slice());
    lost.release();
    if (!data.carried.isEmpty) {
        game.store(data.carried);
    }
    size_t first = 0;
    foreach (saved; data.beacons.slice()) {
        uint beaconSlot = replayed(game.world.graph, data.beaconPaths.slice()[first .. first + saved.faces]);
        first += saved.faces;
        game.world.graph.reference(beaconSlot);
        game.beacons.append(Beacon(ChunkId(game.world.graph.idAt(beaconSlot), saved.corner), saved.cell));
    }
    size_t start = 0;
    foreach (saved; data.footholds.slice()) {
        uint footholdSlot = replayed(game.world.graph, data.footholdPaths.slice()[start .. start + saved.faces]);
        start += saved.faces;
        game.world.graph.reference(footholdSlot);
        game.footholds.places[game.footholds.count] = Position(game.world.graph.idAt(footholdSlot), saved.local);
        game.footholds.count += 1;
    }
    uint slot = replayed(game.world.graph, data.path.slice());
    game.placeAt(Position(game.world.graph.idAt(slot), data.local), Length(0));
}

