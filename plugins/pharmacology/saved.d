module plugins.pharmacology.saved;

import base.array : Array;
import base.flags : Readiness;
import base.units : Time;
import plugins.crafting.crafting : Step, Taken;
import plugins.crafting.inventory : Stack;
import plugins.game.game : CraftKind, Crafting, Game;
import plugins.game.save : Reader, Remap, Section, Writer, putName, takeName;
import plugins.pharmacology.genome : Genome;
import plugins.pharmacology.kinetics : Body;
import plugins.pharmacology.molecule : Molecule;
import plugins.pharmacology.organism : Organism;
import plugins.pharmacology.player : Compound, Pharma, SYNTHESIS, assayAll, pharma;
import plugins.pharmacology.signaling : Signaling;
import plugins.pharmacology.synthesis : syntheses;

enum string SECTION_NAME = "pharmacology";

struct SavedSynthesis {
    Stack held;
    ulong[2] payload;
    Time left;
    uint order;
    Readiness started;
}

void write(ref const Game game, ref Writer writer) {
    const(Pharma)* own = &pharma(game);
    uint count = cast(uint) own.compounds.length;
    writer.put(count);
    writer.putAll(own.compounds.slice());
    writer.put(own.organism.genome);
    writer.put(own.organism.body);
    writer.put(own.organism.signaling);
    uint queued = 0;
    foreach (ref crafting; game.crafts.slice()) {
        if (crafting.work is &SYNTHESIS) {
            queued += 1;
        }
    }
    writer.put(queued);
    foreach (ref crafting; game.crafts.slice()) {
        if (crafting.work is &SYNTHESIS) {
            SavedSynthesis saved = SavedSynthesis(crafting.held, crafting.payload, crafting.left, crafting.order, crafting.started);
            writer.put(saved);
            writer.putName(syntheses()[crafting.index].name);
        }
    }
    writer.put(own.catalog.molecule);
}

void read(ref Game game, const(ubyte)[] bytes, ref const Remap remap) {
    Pharma* own = &pharma(game);
    Reader reader = Reader(bytes);
    Array!Compound held;
    Genome genome;
    Body body;
    Signaling signaling;
    uint count;
    bool whole = reader.take(count);
    uint taken = 0;
    while (whole && taken < count) {
        Compound compound;
        whole = reader.take(compound);
        held.append(compound);
        taken += 1;
    }
    if (whole && reader.take(genome) && reader.take(body) && reader.take(signaling)) {
        own.organism.release();
        own.organism = Organism.make(genome);
        own.organism.body = body;
        own.organism.signaling = signaling;
        own.compounds.clear();
        own.compounds.appendAll(held.slice());
        assayAll(game);
        Molecule desk;
        if (readQueued(game, reader, remap) && reader.take(desk)) {
            own.catalog.molecule = desk;
        }
    }
    held.release();
}

bool readQueued(ref Game game, ref Reader reader, ref const Remap remap) {
    uint count;
    bool whole = reader.take(count);
    uint taken = 0;
    while (whole && taken < count) {
        SavedSynthesis saved;
        const(char)[] name;
        whole = reader.take(saved) && reader.takeName(name);
        if (whole) {
            restoreSynthesis(game, saved, name, remap);
        }
        taken += 1;
    }
    return whole;
}

void restoreSynthesis(ref Game game, ref const SavedSynthesis saved, const(char)[] name, ref const Remap remap) {
    Stack held = remap.stack(saved.held);
    uint index = 0;
    while (index < syntheses().length && syntheses()[index].name != name) {
        index += 1;
    }
    if (index < syntheses().length) {
        game.requeue(Crafting(Taken.init, saved.left, index, CraftKind.work, saved.started, 0, Step.last, &SYNTHESIS, saved.payload, held, saved.order));
    } else if (!held.isEmpty) {
        game.store(held);
    }
}

immutable Section SECTION = Section(SECTION_NAME, &write, &read);
