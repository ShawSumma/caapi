module client.save;

import core.stdc.stdio : FILE, fclose, fopen, fread, fseek, ftell, fwrite, SEEK_END, SEEK_SET;
import core.stdc.string : memcpy, strncpy;
import base.array : Array;
import base.maybe : Maybe;
import base.units : Length;
import client.game : Beacon, Game, Seed;
import client.hud : worldNameOf;
import common.biology.genome : Genome;
import common.biology.kinetics : Body;
import common.biology.organism : Organism;
import common.biology.signaling : Signaling;
import common.edits : BlockRecord, CellEdit, ChunkEdits;
import common.graph : Graph, NodeId, ParentList, ROOT_NODE;
import common.inventory : Inventory;
import common.node : ChunkId;
import common.position : Position;
import geometry.honeycomb : Corner, Face;
import geometry.lorentz : Motion;
import plugins.api.api : ENTRY;

enum uint SAVE_MAGIC = 0x6D696E65;
enum uint SAVE_FORMAT = 3;
enum uint MOST_SAVED_SEEDS = 1 << 10;
enum uint WORLDGEN_VERSION = 3;
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

struct SaveData {
    SaveHeader header;
    Array!Face path;
    Motion!float local;
    Inventory inventory;
    Genome genome;
    Body body;
    Signaling signaling;
    Array!SavedEdits chunks;
    Array!CellEdit cells;
    Array!BlockRecord records;
    Array!SavedBeacon beacons;
    Array!Face beaconPaths;
    Array!Seed seeds;

    void release() {
        seeds.release();
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

void writeGame(ref const Game game, ref Writer writer) {
    SaveHeader header = headerFor(game);
    writer.put(header);
    Array!Face path;
    Position body = game.characterState.position;
    pathFromRoot(game.world.graph, game.world.graph.slotOf(body.node).value, path);
    uint faces = cast(uint) path.length;
    writer.put(faces);
    writer.putAll(path.slice());
    writer.put(body.local);
    path.release();
    writer.put(game.inventory);
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
    uint seedCount = cast(uint) game.seeds.length;
    writer.put(seedCount);
    writer.putAll(game.seeds.slice());
}

const(char)* readGame(const(ubyte)[] bytes, ref const Game game, ref SaveData data) {
    Reader reader = Reader(bytes);
    if (!reader.take(data.header) || data.header.magic != SAVE_MAGIC) {
        return "is not a mined save";
    } else if (data.header.format != SAVE_FORMAT) {
        return "was written by another save format";
    } else if (data.header.worldgen != WORLDGEN_VERSION) {
        return "was written for another version of world generation, so its edits would not line up";
    } else if (data.header.entry != headerFor(game).entry) {
        return "was written for another plugin interface version";
    } else if (data.header.world != headerFor(game).world) {
        return "belongs to another world";
    } else {
        return readBody(reader, data);
    }
}

const(char)* readBody(ref Reader reader, ref SaveData data) {
    if (!readPath(reader, data)) {
        return "is cut short in the body's place";
    } else if (!reader.take(data.local) || !reader.take(data.inventory) || !reader.take(data.genome) || !reader.take(data.body) || !reader.take(data.signaling)) {
        return "is cut short before the edits";
    } else if (!readEdits(reader, data)) {
        return "is cut short in the edits";
    } else if (!readBeacons(reader, data)) {
        return "is cut short in the beacons";
    } else if (!readSeeds(reader, data)) {
        return "is cut short in the seeds";
    } else {
        return null;
    }
}

bool readSeeds(ref Reader reader, ref SaveData data) {
    uint count;
    bool counted = reader.take(count) && count <= MOST_SAVED_SEEDS;
    if (counted) {
        foreach (_; 0 .. count) {
            Seed seed;
            if (!reader.take(seed)) {
                return false;
            }
            data.seeds.append(seed);
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
    game.organism.release();
    game.organism = Organism.make(data.genome);
    game.organism.body = data.body;
    game.organism.signaling = data.signaling;
    game.seeds.clear();
    game.seeds.appendAll(data.seeds.slice());
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

bool writeFile(const(char)* path, const(ubyte)[] bytes) {
    FILE* file = fopen(path, "wb");
    if (file is null) {
        return false;
    } else {
        size_t written = fwrite(bytes.ptr, 1, bytes.length, file);
        fclose(file);
        return written == bytes.length;
    }
}

Maybe!(Array!ubyte) readFile(const(char)* path) {
    FILE* file = fopen(path, "rb");
    if (file is null) {
        return Maybe!(Array!ubyte).init;
    } else {
        fseek(file, 0, SEEK_END);
        long size = ftell(file);
        fseek(file, 0, SEEK_SET);
        Array!ubyte bytes;
        bytes.resize(cast(size_t) size);
        size_t read = fread(bytes.ptr, 1, bytes.length, file);
        fclose(file);
        if (read != bytes.length) {
            bytes.release();
            return Maybe!(Array!ubyte).init;
        } else {
            return Maybe!(Array!ubyte).of(bytes);
        }
    }
}
