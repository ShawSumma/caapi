module plugins.pharmacology.player;

import core.stdc.math : fabsf, roundf;
import core.stdc.stdlib : free, malloc;
import base.array : Array;
import base.clock : MILLISECONDS_PER_SECOND;
import base.flags : Readiness;
import base.maybe : Maybe, MaybeIndex;
import base.names : ENUM_NAMES;
import base.numbers : higherOf, lowerOf;
import base.splitmix : SplitMix;
import base.stdio : printed;
import base.units : Rate, Ratio, Time;
import common.edits : BlockRecord, RecordTag;
import common.graph : Graph;
import common.material : nameHashOf;
import common.node : ChunkId, cellIndex;
import common.perception : Perception;
import common.raycast.graph : GraphCastHit;
import common.worldgen.horospheres : Fill, ROOT;
import common.worldgen.lineage : Lineage;
import common.worldgen.plane : Plane;
import common.worldgen.structure : edgeLength;
import geometry.cube : Cell;
import plugins.api.api : Material;
import plugins.crafting.crafting : Station, Step, Taken;
import plugins.crafting.inventory : Inventory, SLOT_COUNT, Sorting, Stack, isSameKind;
import plugins.crafting.items : Item, ItemKind, itemOf;
import plugins.game.bindings : ActionInfo, Extra, Rules;
import plugins.game.game : AimKind, CraftKind, Crafting, Extension, Game, NOTE_CAPACITY, Screen, Work;
import plugins.game.hud : itemName, materialName;
import plugins.pharmacology.air : ASH_GAS, AirMix, GAS_COUNT, GAS_MOLECULES, GAS_NAMES, airOf;
import plugins.pharmacology.breeding : crossed, expressionIn, isLiving, isPlant, productOf;
import plugins.pharmacology.drives : felt;
import plugins.pharmacology.genome : Genome, MOST_GENES, enzymeGene;
import plugins.pharmacology.kinetics : Body, Route;
import plugins.pharmacology.catalog : cycledAt, toggledConjugation;
import plugins.pharmacology.machines : benchBlock, catalogBlock, collectorBlock, grantsAssay, mutagenItem;
import plugins.pharmacology.metabolism : Enzyme, Operation;
import plugins.pharmacology.molecule : Molecule;
import plugins.pharmacology.organism : Dose, Organism, starterDoses, starterGenome;
import plugins.pharmacology.pocket : Binding;
import plugins.pharmacology.signaling : SIGNAL_COUNT, Signaling;
import plugins.pharmacology.synthesis : DoseRoute, Reaction, Synthesis, SynthesisRule, doseRoutes, syntheses, synthesized;
import plugins.pharmacology.wild : FIRST_ENZYME_GENE, cellGenes, enzymeFromSeed, speciesGenes;

enum uint MOST_SCANNED_RECEPTORS = 16;
enum Ratio PLANT_DOSE = Ratio(1);
enum uint CELL_HASH_SHIFT = 40;
enum Time MOST_COLLECTED_SECONDS = Time(120);
enum Rate COLLECTION_RATE = Rate(0.02f);
enum Ratio SEALED_GAIN = Ratio(3);
enum float SEALED_DEPTH_EDGES = 1.9f;
enum Time GROWN_SECONDS = Time(60);
enum float MOST_EXTRA_YIELD = 2;
enum Time EAT_TIME = Time(1.5f);
enum float BASE_BREEDING_MUTATION = 0.05f;
enum float ASH_BREEDING_MUTATION = 0.3f;
enum float MUTAGEN_BREEDING_MUTATION = 0.3f;
enum ulong BREEDING_SALT = 0xB4EED;
enum Ratio DOSE_SIZE = Ratio(1);
enum uint CHOSEN_PLANTS = 2;
enum size_t NAME_CAPACITY = 32;
enum uint NAME_SYLLABLES = 3;
enum string CONSONANTS = "bdfgklmnprstvz";
enum string VOWELS = "aeiou";
enum ulong MOLECULE_NAME_SALT = 0x4E_A3E5;
enum string DOSED = "dosed";

enum RecordTag COLLECTOR_RECORD = RecordTag(1);
enum RecordTag PLANTED_RECORD = RecordTag(2);
enum RecordTag PLACED_LIVING_RECORD = RecordTag(3);

enum Told : uint {
    planted,
    plantedWild,
    ate,
    ateUnknown,
    nothingToEat,
    noGenes,
    spliced,
    genomeFull,
    noPlant,
    needPlants,
    crossed,
    crossedWithMutagen,
    breathed,
    dosed,
    harvested,
    extracted,
    synthesized,
    unchanged,
    noDose,
    noTestDose,
    needsDevice,
    bodyFull,
    cannotPay,
    unripeHarvest,
}

immutable string[Route.max + 1] ROUTE_WORDS = [
    Route.injected: "into the blood",
    Route.inhaled: "breathed in",
    Route.ingested: "swallowed",
];

enum Ripeness : ubyte {
    wild,
    growing,
    ripe,
}

enum Sight : ubyte {
    nothing,
    living,
    collector,
    bench,
}

struct Compound {
    Molecule molecule;
    Ratio[MOST_SCANNED_RECEPTORS] affinity;
    Ratio[MOST_SCANNED_RECEPTORS] efficacy;
    float raw = 0;
    float doses = 0;
    uint receptors;
}

uint slotFor(ref Array!Compound compounds, Molecule molecule) {
    uint index = 0;
    while (index < compounds.length && compounds.ptr[index].molecule != molecule) {
        index += 1;
    }
    if (index == compounds.length) {
        Compound made;
        made.molecule = molecule;
        compounds.append(made);
    }
    return index;
}

struct LivingGenes {
    Lineage genes;
    Time left;
    Material species;
    Ripeness growth;
}

struct Eating {
    Stack food;
    Time spent;
    uint slot;
}

enum Bite : ubyte {
    none,
    fresh,
    held,
}

struct LivingReading {
    Molecule product;
    Ratio[MOST_SCANNED_RECEPTORS] affinity;
    Ratio[MOST_SCANNED_RECEPTORS] efficacy;
    Time left;
    Ratio fit;
    uint receptors;
    Material species;
    Ripeness growth;
}

struct Pharma {
    Organism organism;
    Array!Compound compounds;
    LivingReading living;
    Ratio[GAS_COUNT] gathered;
    Ratio mutation;
    Ratio[GAS_COUNT] machineAir;
    Ratio machineFill;
    Compound catalog;
    Maybe!Eating eating;
    MaybeIndex!uint[CHOSEN_PLANTS] chosen;
    MaybeIndex!uint chosenCompound;
    uint doses;
    Sight sight;
    Bite bite;
}

__gshared uint guest;
__gshared uint benchScreen;
__gshared uint collectorScreen;
__gshared uint catalogScreen;

ref inout(Pharma) pharma(ref inout Game game) {
    return *cast(inout(Pharma)*) game.guests[guest];
}

ref inout(Organism) organism(ref inout Game game) {
    return pharma(game).organism;
}

ref inout(Array!Compound) compounds(ref inout Game game) {
    return pharma(game).compounds;
}

ref inout(Maybe!Eating) eating(ref inout Game game) {
    return pharma(game).eating;
}

ref inout(MaybeIndex!uint[CHOSEN_PLANTS]) chosen(ref inout Game game) {
    return pharma(game).chosen;
}

ref inout(MaybeIndex!uint) chosenCompound(ref inout Game game) {
    return pharma(game).chosenCompound;
}

const(char)[] moleculeName(Molecule molecule, char[] buffer) {
    uint gas = 0;
    while (gas < GAS_COUNT && GAS_MOLECULES[gas] != molecule) {
        gas += 1;
    }
    if (gas < GAS_COUNT) {
        return GAS_NAMES[gas];
    } else {
        ulong mixed = SplitMix(molecule.packed[0] ^ SplitMix(molecule.packed[1] ^ MOLECULE_NAME_SALT).next()).next();
        foreach (syllable; 0 .. NAME_SYLLABLES) {
            buffer[2 * syllable] = CONSONANTS[mixed % CONSONANTS.length];
            mixed /= CONSONANTS.length;
            buffer[2 * syllable + 1] = VOWELS[mixed % VOWELS.length];
            mixed /= VOWELS.length;
        }
        return buffer[0 .. 2 * NAME_SYLLABLES];
    }
}

bool isLivingItem(Item item) {
    return item.kind == ItemKind.block && isLiving(item.block);
}

bool isPlantItem(Item item) {
    return item.kind == ItemKind.block && isPlant(item.block);
}

void attach(ref Game game) {
    Pharma* made = cast(Pharma*) malloc(Pharma.sizeof);
    *made = Pharma.init;
    made.organism = Organism.make(starterGenome());
    game.guests[guest] = made;
}

void detach(ref Game game) {
    Pharma* own = &pharma(game);
    own.organism.release();
    own.compounds.release();
    free(own);
    game.guests[guest] = null;
}

void startOver(ref Game game) {
    Pharma* own = &pharma(game);
    own.compounds.clear();
    own.chosenCompound = MaybeIndex!uint.init;
    own.chosen[] = MaybeIndex!uint.init;
    own.eating = Maybe!Eating.init;
    own.organism.release();
    own.organism = Organism.make(starterGenome());
    own.doses = 0;
}

void bite(ref Game game) {
    pharma(game).bite = Bite.fresh;
}

void letGo(ref Game game) {
    pharma(game).bite = Bite.none;
}

void step(ref Game game, Time dt) {
    Pharma* own = &pharma(game);
    own.sight = Sight.nothing;
    own.organism.advance(dt);
    if (own.bite != Bite.none && game.screen == Screen.none) {
        chew(game, dt);
        own.bite = Bite.held;
    } else {
        own.eating = Maybe!Eating.init;
        if (own.bite == Bite.held) {
            own.bite = Bite.fresh;
        }
    }
    if (game.screen == Screen.machine && game.machineScreen == collectorScreen) {
        own.machineAir = machineGathered(game);
        own.machineFill = machineFilled(game);
    }
    if (game.screen == Screen.machine && game.machineScreen == catalogScreen) {
        assay(game, own.catalog);
    }
}

void cycleCatalogCell(ref Game game, uint cell) {
    Compound* draft = &pharma(game).catalog;
    draft.molecule = cycledAt(draft.molecule, cell);
}

void toggleCatalogConjugation(ref Game game, uint index) {
    Compound* draft = &pharma(game).catalog;
    draft.molecule = toggledConjugation(draft.molecule);
}

Perception feel(ref const Game game, Perception base) {
    Ratio[SIGNAL_COUNT] signals = pharma(game).organism.signaling.signals();
    return felt(base, signals[]);
}

void gained(ref Game game, ref const Stack stack) {
    if (stack.strainCount > 0) {
        sortLiving(game);
    }
}

void upgraded(ref Game game) {
    assayAll(game);
    sortLiving(game);
}

void woke(ref Game game) {
    pharma(game).eating = Maybe!Eating.init;
}

bool hasAssay(ref const Game game) {
    return game.rules == Rules.creative || grantsAssay(game.owned);
}

MaybeIndex!uint compoundIndexOf(ref const Game game, Molecule molecule) {
    const(Pharma)* own = &pharma(game);
    uint index = 0;
    while (index < own.compounds.length && own.compounds.ptr[index].molecule != molecule) {
        index += 1;
    }
    if (index < own.compounds.length) {
        return MaybeIndex!uint.of(index);
    } else {
        return MaybeIndex!uint.init;
    }
}

bool isKnownProduct(ref const Game game, Molecule molecule) {
    return hasAssay(game) || compoundIndexOf(game, molecule).exists;
}

bool isKnownStrain(ref const Game game, Item item, Lineage genes) {
    return isKnownProduct(game, productOf(item.block, genes));
}

bool hasKnownStrain(ref const Game game, ref const Stack stack) {
    uint index = 0;
    while (index < stack.strainCount && !(stack.sorting == Sorting.unsorted && isKnownStrain(game, stack.item, stack.strains[index].genes))) {
        index += 1;
    }
    return index < stack.strainCount;
}

void sortLiving(ref Game game) {
    foreach (slot; 0 .. SLOT_COUNT) {
        if (hasKnownStrain(game, game.inventory.slots[slot])) {
            Inventory before = game.inventory;
            uint stranded = sortStack(game, slot);
            if (stranded > 0) {
                game.inventory = before;
            }
        }
    }
}

uint sortStack(ref Game game, uint slot) {
    Stack mixed = game.inventory.slots[slot];
    game.inventory.slots[slot] = Stack.init;
    uint stranded = 0;
    foreach (ref run; mixed.strains[0 .. mixed.strainCount]) {
        if (!isKnownStrain(game, mixed.item, run.genes)) {
            Stack unknown = Stack.ofLiving(mixed.item, run.count, run.genes, Sorting.unsorted);
            unknown.pourInto(game.inventory.slots[slot]);
        }
    }
    foreach (ref run; mixed.strains[0 .. mixed.strainCount]) {
        if (isKnownStrain(game, mixed.item, run.genes)) {
            Stack known = Stack.ofLiving(mixed.item, run.count, run.genes, Sorting.sorted);
            game.inventory.joinWithin(0, SLOT_COUNT, known);
            if (game.inventory.slots[slot].isEmpty) {
                known.pourInto(game.inventory.slots[slot]);
            }
            stranded += game.inventory.gain(known);
        }
    }
    return stranded;
}

Molecule moleculeOf(ref const Crafting crafting) {
    return Molecule(crafting.payload);
}

bool isPressing(uint synthesis) {
    return syntheses()[synthesis].reaction == Reaction.press;
}

bool isExtracting(uint synthesis) {
    return syntheses()[synthesis].reaction == Reaction.extract;
}

MaybeIndex!uint extractionAt(Station station) {
    uint index = 0;
    while (index < syntheses().length && !(isExtracting(index) && syntheses()[index].station == station)) {
        index += 1;
    }
    if (index < syntheses().length) {
        return MaybeIndex!uint.of(index);
    } else {
        return MaybeIndex!uint.init;
    }
}

const(char)[] synthesisName(ref const Crafting crafting) {
    return syntheses()[crafting.index].name;
}

Station synthesisStation(ref const Crafting crafting) {
    return syntheses()[crafting.index].station;
}

Time synthesisTime(ref const Crafting crafting) {
    return syntheses()[crafting.index].time;
}

const(char)[] synthesisLabel(ref const Crafting crafting, char[] buffer) {
    char[NAME_CAPACITY] storage;
    const(char)[] label = syntheses()[crafting.index].title;
    const(char)[] subject = moleculeName(moleculeOf(crafting), storage[]);
    if (!crafting.held.isEmpty) {
        subject = itemName(crafting.held.item, storage[]);
    }
    return printed(buffer, "%.*s %.*s", cast(int) label.length, label.ptr, cast(int) subject.length, subject.ptr);
}

void finishSynthesis(ref Game game, ref const Crafting crafting) {
    char[NOTE_CAPACITY] buffer;
    char[NAME_CAPACITY] storage;
    char[NAME_CAPACITY] itemStorage;
    if (isExtracting(crafting.index)) {
        float gained = syntheses()[crafting.index].extract;
        keepCompound(game, moleculeOf(crafting), gained, 0);
        const(char)[] molecule = moleculeName(moleculeOf(crafting), storage[]);
        const(char)[] item = itemName(crafting.held.item, itemStorage[]);
        game.write(Told.extracted, printed(buffer[], "+%.1f %.*s extract from the %.*s", cast(double) gained, cast(int) molecule.length, molecule.ptr, cast(int) item.length, item.ptr));
    } else {
        Molecule product = synthesized(moleculeOf(crafting), Synthesis(cast(ubyte) crafting.index)).value;
        keepCompound(game, product, 0, 1);
        const(char)[] molecule = moleculeName(product, storage[]);
        game.write(Told.synthesized, printed(buffer[], "made a dose of %.*s", cast(int) molecule.length, molecule.ptr));
    }
}

void refundSynthesis(ref Game game, ref const Crafting crafting) {
    const(SynthesisRule)* rule = &syntheses()[crafting.index];
    if (rule.reagent.kind != ItemKind.nothing) {
        game.store(Stack(rule.reagent, 1));
    }
    if (isExtracting(crafting.index)) {
        game.store(crafting.held);
    } else if (isPressing(crafting.index)) {
        keepCompound(game, moleculeOf(crafting), rule.extract, 0);
    } else {
        keepCompound(game, moleculeOf(crafting), 0, 1);
    }
}

immutable Work SYNTHESIS = Work(&synthesisName, &synthesisStation, &synthesisTime, &finishSynthesis, &refundSynthesis, &synthesisLabel);

Crafting synthesisOf(uint synthesis, Molecule molecule, Stack pressed) {
    return Crafting(Taken.init, syntheses()[synthesis].time, synthesis, CraftKind.work, Readiness.pending, 0, Step.last, &SYNTHESIS, molecule.packed, pressed);
}

bool isPressable(ref const Game game, uint slot) {
    Stack stack = game.inventory.slots[slot];
    return !stack.isEmpty && isLivingItem(stack.item) && stack.genes.exists;
}

bool pressLiving(ref Game game, uint slot) {
    MaybeIndex!uint rule = extractionAt(game.workstation);
    if (!rule.exists || slot >= SLOT_COUNT) {
        return false;
    } else if (!isPressable(game, slot)) {
        tellNoGenes(game, game.inventory.slots[slot].item);
        return false;
    } else {
        Stack pressed = game.inventory.slots[slot].front();
        game.inventory.spendKind(pressed);
        game.queue(synthesisOf(rule.value, productOf(pressed.item.block, pressed.genes.value), pressed));
        return true;
    }
}

void tellNoGenes(ref Game game, Item item) {
    char[NOTE_CAPACITY] buffer;
    char[NAME_CAPACITY] storage;
    const(char)[] name = itemName(item, storage[]);
    game.write(Told.noGenes, printed(buffer[], "this %.*s has no genes of its own until it is set down somewhere", cast(int) name.length, name.ptr));
}

bool canPay(ref const Game game, ref const Crafting crafting) {
    MaybeIndex!uint found = compoundIndexOf(game, moleculeOf(crafting));
    const(SynthesisRule)* rule = &syntheses()[crafting.index];
    if (!found.exists) {
        return false;
    } else if (rule.reagent.kind != ItemKind.nothing && game.inventory.countOf(rule.reagent) == 0) {
        return false;
    } else if (isPressing(crafting.index)) {
        return game.compounds.ptr[found.value].raw >= rule.extract;
    } else {
        return game.compounds.ptr[found.value].doses >= 1;
    }
}

void pay(ref Game game, ref const Crafting crafting) {
    const(SynthesisRule)* rule = &syntheses()[crafting.index];
    if (rule.reagent.kind != ItemKind.nothing) {
        game.inventory.spend(rule.reagent, 1);
    }
    if (isPressing(crafting.index)) {
        game.compounds.ptr[compoundIndexOf(game, moleculeOf(crafting)).value].raw -= rule.extract;
    } else {
        game.compounds.ptr[compoundIndexOf(game, moleculeOf(crafting)).value].doses -= 1;
    }
}

bool synthesize(ref Game game, Synthesis synthesis) {
    char[NOTE_CAPACITY] buffer;
    char[NAME_CAPACITY] storage;
    char[NAME_CAPACITY] itemStorage;
    if (!game.chosenCompound.exists) {
        return false;
    } else {
        Molecule molecule = game.compounds.ptr[game.chosenCompound.value].molecule;
        Maybe!Molecule product = synthesized(molecule, synthesis);
        Crafting made = synthesisOf(synthesis.id, molecule, Stack.init);
        const(char)[] name = moleculeName(molecule, storage[]);
        Item reagent = syntheses()[synthesis.id].reagent;
        if (!product.exists || (!isPressing(synthesis.id) && product.value == molecule)) {
            game.write(Told.unchanged, printed(buffer[], "that would not change %.*s", cast(int) name.length, name.ptr));
            return false;
        } else if (!canPay(game, made) && reagent.kind == ItemKind.nothing) {
            game.write(Told.cannotPay, printed(buffer[], "not enough %.*s to hand for that", cast(int) name.length, name.ptr));
            return false;
        } else if (!canPay(game, made)) {
            const(char)[] item = itemName(reagent, itemStorage[]);
            game.write(Told.cannotPay, printed(buffer[], "that takes a %.*s and a dose of %.*s", cast(int) item.length, item.ptr, cast(int) name.length, name.ptr));
            return false;
        } else {
            pay(game, made);
            game.queue(made);
            return true;
        }
    }
}

void keepCompound(ref Game game, Molecule molecule, float raw, float doses) {
    MaybeIndex!uint found = compoundIndexOf(game, molecule);
    uint index = game.compounds.slotFor(molecule);
    game.compounds.ptr[index].raw += raw;
    game.compounds.ptr[index].doses += doses;
    if (!found.exists) {
        assay(game, game.compounds.ptr[index]);
        sortLiving(game);
    }
}

void assay(ref Game game, ref Compound compound) {
    Organism* body = &game.organism;
    compound.receptors = 0;
    if (hasAssay(game)) {
        compound.receptors = cast(uint) lowerOf(body.receptors.length, cast(size_t) MOST_SCANNED_RECEPTORS);
        foreach (index; 0 .. compound.receptors) {
            Binding binding = body.cache.bindingOf(body.receptors.ptr[index].pocket, compound.molecule);
            compound.affinity[index] = binding.affinity;
            float efficacy = 0;
            foreach (transducer; binding.efficacy) {
                efficacy += transducer.value;
            }
            compound.efficacy[index] = Ratio(efficacy);
        }
    }
}

void assayAll(ref Game game) {
    foreach (ref compound; game.compounds.slice()) {
        assay(game, compound);
    }
}

void tellDosed(ref Game game, Molecule molecule, Route route) {
    char[NOTE_CAPACITY] buffer;
    char[NAME_CAPACITY] storage;
    const(char)[] name = moleculeName(molecule, storage[]);
    string how = ROUTE_WORDS[route];
    game.write(Told.dosed, printed(buffer[], "took a dose of %.*s, %.*s", cast(int) name.length, name.ptr, cast(int) how.length, how.ptr));
}

bool takeDose(ref Game game, uint routeIndex) {
    char[NOTE_CAPACITY] buffer;
    char[NAME_CAPACITY] storage;
    const(DoseRoute)* route = &doseRoutes()[routeIndex];
    if (!game.chosenCompound.exists || game.compounds.ptr[game.chosenCompound.value].doses < 1) {
        game.write(Told.noDose, "no doses of that; press some extract first");
        return false;
    } else if (!game.organism.body.hasRoomFor(game.compounds.ptr[game.chosenCompound.value].molecule)) {
        game.write(Told.bodyFull, "your body holds too many compounds; wait for some to clear");
        return false;
    } else if (route.device.kind != ItemKind.nothing && game.inventory.countOf(route.device) < higherOf(route.uses, 1u)) {
        const(char)[] device = itemName(route.device, storage[]);
        game.write(Told.needsDevice, printed(buffer[], "you need the %.*s for that", cast(int) device.length, device.ptr));
        return false;
    } else {
        if (route.device.kind != ItemKind.nothing && route.uses > 0) {
            game.inventory.spend(route.device, route.uses);
        }
        Compound* compound = &game.compounds.ptr[game.chosenCompound.value];
        game.organism.dose(Dose(compound.molecule, DOSE_SIZE, route.route));
        compound.doses -= 1;
        tellDosed(game, compound.molecule, route.route);
        game.happen(DOSED, route.name);
        return true;
    }
}

void doseNext(ref Game game) {
    Pharma* own = &pharma(game);
    if (starterDoses.length == 0) {
        game.write(Told.noTestDose, "no mod defines a test dose");
    } else {
        Dose given = starterDoses.ptr[own.doses % starterDoses.length];
        own.organism.dose(given);
        own.doses += 1;
        tellDosed(game, given.molecule, given.route);
    }
}

bool broke(ref Game game, ChunkId chunk, uint cell, Material broken) {
    Maybe!LivingGenes genes = livingGenesAt(game, chunk, cell, broken);
    if (genes.exists) {
        harvest(game, genes.value, game.world.graph.slotOf(chunk.node).value);
    }
    if (broken == collectorBlock || isLiving(broken)) {
        game.world.graph.edits.dropRecord(chunk, cell);
    }
    return genes.exists;
}

void harvest(ref Game game, LivingGenes genes, uint slot) {
    char[NOTE_CAPACITY] buffer;
    char[NAME_CAPACITY] storage;
    const(char)[] name = materialName(genes.species, storage[]);
    uint count = 1;
    final switch (genes.growth) {
        case Ripeness.wild:
            break;
        case Ripeness.growing:
            game.write(Told.unripeHarvest, printed(buffer[], "the %.*s was not ripe: only the plant back", cast(int) name.length, name.ptr));
            break;
        case Ripeness.ripe:
            count += cast(uint) roundf(MOST_EXTRA_YIELD * expressionIn(genes.species, game.world.graph.stateAt(slot).climate.climate()));
            game.write(Told.harvested, printed(buffer[], "the ripe %.*s gave %.0f", cast(int) name.length, name.ptr, cast(double) count));
            break;
    }
    game.store(Stack.ofLiving(itemOf(genes.species), count, genes.genes, Sorting.unsorted));
}

Maybe!LivingGenes livingGenesAt(ref Game game, ChunkId chunk, uint cell, Material species) {
    uint slot = game.world.graph.slotOf(chunk.node).value;
    BlockRecord* record = game.world.graph.edits.recordAt(chunk, cell);
    if (!isLiving(species) || !game.world.graph.nodeAt(slot).hasState) {
        return Maybe!LivingGenes.init;
    } else if (record !is null && record.tag == PLANTED_RECORD) {
        Time left = GROWN_SECONDS - (game.time - record.placed);
        Ripeness growth = Ripeness.growing;
        if (left <= Time(0)) {
            growth = Ripeness.ripe;
            left = Time(0);
        }
        return Maybe!LivingGenes.of(LivingGenes(record.lineage, left, species, growth));
    } else if (record !is null && record.tag == PLACED_LIVING_RECORD) {
        return Maybe!LivingGenes.of(LivingGenes(record.lineage, Time(0), species, Ripeness.wild));
    } else {
        return Maybe!LivingGenes.of(LivingGenes(wildGenesAt(game, chunk, cell, species), Time(0), species, Ripeness.wild));
    }
}

Lineage wildGenesAt(ref const Game game, ChunkId chunk, uint cell, Material species) {
    Lineage genes = speciesGenes(game.world.graph.stateAt(game.world.graph.slotOf(chunk.node).value).lineage, nameHashOf(species));
    if (isPlant(species)) {
        return cellGenes(genes, chunk.node.spice() ^ (cast(ulong) chunk.corner << CELL_HASH_SHIFT) ^ cell);
    } else {
        return genes;
    }
}

Maybe!LivingReading livingReadingAt(ref Game game, ChunkId chunk, uint cell, Material species) {
    Maybe!LivingGenes genes = livingGenesAt(game, chunk, cell, species);
    if (!genes.exists) {
        return Maybe!LivingReading.init;
    } else {
        Organism* body = &game.organism;
        uint slot = game.world.graph.slotOf(chunk.node).value;
        LivingReading reading;
        reading.product = productOf(genes.value.species, genes.value.genes);
        reading.left = genes.value.left;
        reading.fit = Ratio(expressionIn(genes.value.species, game.world.graph.stateAt(slot).climate.climate()));
        reading.species = genes.value.species;
        reading.growth = genes.value.growth;
        if (hasAssay(game)) {
            reading.receptors = cast(uint) lowerOf(body.receptors.length, cast(size_t) MOST_SCANNED_RECEPTORS);
        }
        foreach (index; 0 .. reading.receptors) {
            Binding binding = body.cache.bindingOf(body.receptors.ptr[index].pocket, reading.product);
            reading.affinity[index] = binding.affinity;
            float efficacy = 0;
            foreach (transducer; binding.efficacy) {
                efficacy += transducer.value;
            }
            reading.efficacy[index] = Ratio(efficacy);
        }
        return Maybe!LivingReading.of(reading);
    }
}

Ratio mutationOddsAt(ref const Game game, uint slot) {
    float odds = BASE_BREEDING_MUTATION;
    if (game.world.graph.nodeAt(slot).hasState) {
        odds += ASH_BREEDING_MUTATION * airOf(game.world.graph.stateAt(slot).climate.climate()).fractions[ASH_GAS].value;
    }
    if (game.inventory.countOf(mutagenItem) > 0) {
        odds += MUTAGEN_BREEDING_MUTATION;
    }
    return Ratio(odds);
}

Ratio[GAS_COUNT] gatheredBy(ref const Game game, ref const BlockRecord record, uint slot) {
    Ratio[GAS_COUNT] gathered;
    if (game.world.graph.nodeAt(slot).hasState) {
        float elapsed = lowerOf((game.time - record.placed).value, MOST_COLLECTED_SECONDS.value);
        AirMix air = airOf(game.world.graph.stateAt(slot).climate.climate());
        float gain = sealedGainAt(game.world.graph, slot).value;
        foreach (gas; 0 .. GAS_COUNT) {
            gathered[gas] = Ratio(air.fractions[gas].value * COLLECTION_RATE.value * elapsed * gain);
        }
    }
    return gathered;
}

Ratio sealedGainAt(ref const Graph graph, uint slot) {
    Plane nearest = graph.stateAt(slot).surface;
    Fill fill = graph.horospheres.fillOf(ROOT);
    if (graph.horospheres.hasHorospheresAt(slot)) {
        foreach (near; graph.horospheres.horospheresAt(slot)) {
            if (!graph.horospheres.isUpright(near.horosphere) && fabsf(near.plane.height) < fabsf(nearest.height)) {
                nearest = near.plane;
                fill = graph.horospheres.fillOf(near.horosphere);
            }
        }
    }
    if (fill == Fill.flat && nearest.height < -SEALED_DEPTH_EDGES * edgeLength(graph.layout).value) {
        return SEALED_GAIN;
    } else {
        return Ratio(1);
    }
}

void aim(ref Game game, ref const GraphCastHit hit, Material target) {
    Pharma* own = &pharma(game);
    Cell coords = hit.voxelCoords;
    uint cell = cast(uint) cellIndex(game.world.graph.layout.dimension, coords.x, coords.y, coords.z);
    uint slot = game.world.graph.slotOf(hit.chunk.node).value;
    BlockRecord* record = game.world.graph.edits.recordAt(hit.chunk, cell);
    Maybe!LivingReading reading = livingReadingAt(game, hit.chunk, cell, target);
    if (reading.exists) {
        own.living = reading.value;
        own.sight = Sight.living;
    } else if (target == collectorBlock && record !is null) {
        own.gathered = gatheredBy(game, *record, slot);
        own.sight = Sight.collector;
        game.aim.kind = AimKind.usable;
    } else if (target == benchBlock) {
        own.mutation = mutationOddsAt(game, slot);
        own.sight = Sight.bench;
        game.aim.kind = AimKind.usable;
    }
}

bool isBreedable(ref const Game game, uint slot) {
    Stack stack = game.inventory.slots[slot];
    return !stack.isEmpty && isPlantItem(stack.item) && stack.genes.exists;
}

bool isChosenBreedable(ref const Game game, uint index) {
    return game.chosen[index].exists && isBreedable(game, game.chosen[index].value);
}

void chooseFirstPlants(ref Game game) {
    Pharma* own = &pharma(game);
    own.chosen[] = MaybeIndex!uint.init;
    uint marked = 0;
    foreach (slot; 0 .. SLOT_COUNT) {
        if (marked < CHOSEN_PLANTS && isBreedable(game, slot)) {
            own.chosen[marked] = MaybeIndex!uint.of(slot);
            marked += 1;
        }
    }
}

void choose(ref Game game, uint slot) {
    Pharma* own = &pharma(game);
    MaybeIndex!uint picked = MaybeIndex!uint.of(slot);
    if (slot < SLOT_COUNT && isBreedable(game, slot)) {
        if (own.chosen[0] == picked) {
            own.chosen[0] = own.chosen[1];
            own.chosen[1] = MaybeIndex!uint.init;
        } else if (own.chosen[1] == picked) {
            own.chosen[1] = MaybeIndex!uint.init;
        } else if (!own.chosen[0].exists) {
            own.chosen[0] = picked;
        } else {
            own.chosen[1] = picked;
        }
    }
}

void chooseCompound(ref Game game, uint index) {
    Pharma* own = &pharma(game);
    if (index < own.compounds.length) {
        own.chosenCompound = MaybeIndex!uint.of(index);
    }
}

bool crossChosen(ref Game game) {
    char[NOTE_CAPACITY] buffer;
    char[NAME_CAPACITY] storage;
    char[NAME_CAPACITY] itemStorage;
    Pharma* own = &pharma(game);
    MaybeIndex!uint bench = game.world.graph.slotOf(game.machine.node);
    if (!isChosenBreedable(game, 0) || !isChosenBreedable(game, 1) || !bench.exists) {
        game.write(Told.needPlants, "mark two plants to cross");
        return false;
    } else {
        Ratio odds = mutationOddsAt(game, bench.value);
        bool spent = game.inventory.spend(mutagenItem, 1);
        Stack first = game.inventory.slots[own.chosen[0].value];
        Stack second = game.inventory.slots[own.chosen[1].value];
        ulong salt = BREEDING_SALT ^ (cast(ulong)(game.time.value * MILLISECONDS_PER_SECOND) << 8) ^ first.count;
        game.inventory.spendFrom(own.chosen[0].value);
        game.store(Stack.ofLiving(first.item, 1, crossed(first.genes.value, second.genes.value, salt, odds.value), Sorting.unsorted));
        const(char)[] name = materialName(first.item.block, storage[]);
        if (spent) {
            const(char)[] mutagen = itemName(mutagenItem, itemStorage[]);
            game.write(Told.crossedWithMutagen, printed(buffer[], "one %.*s became a cross, %.*s used, mutation %.0f%%", cast(int) name.length, name.ptr, cast(int) mutagen.length, mutagen.ptr, cast(double) odds.value * 100));
        } else {
            game.write(Told.crossed, printed(buffer[], "one %.*s became a cross, mutation %.0f%%", cast(int) name.length, name.ptr, cast(double) odds.value * 100));
        }
        return true;
    }
}

bool spliceChosen(ref Game game) {
    char[NOTE_CAPACITY] buffer;
    Pharma* own = &pharma(game);
    if (!isChosenBreedable(game, 0)) {
        game.write(Told.noPlant, "mark a plant first");
        return false;
    } else if (own.organism.genome.count == MOST_GENES) {
        game.write(Told.genomeFull, "your genome is full");
        return false;
    } else {
        Stack source = game.inventory.slots[own.chosen[0].value];
        game.inventory.spendFrom(own.chosen[0].value);
        Genome genome = own.organism.genome;
        Enzyme enzyme = enzymeFromSeed(source.genes.value.seeds[FIRST_ENZYME_GENE]);
        genome.add(enzymeGene(enzyme, Ratio(1)));
        string operation = ENUM_NAMES!Operation[enzyme.operation];
        game.write(Told.spliced, printed(buffer[], "spliced in a %.*s enzyme", cast(int) operation.length, operation.ptr));
        Body body = own.organism.body;
        Signaling signaling = own.organism.signaling;
        own.organism.release();
        own.organism = Organism.make(genome);
        own.organism.body = body;
        own.organism.signaling = signaling;
        assayAll(game);
        return true;
    }
}

bool use(ref Game game, Material target) {
    if (target == benchBlock) {
        chooseFirstPlants(game);
        game.openMachine(benchScreen);
        return true;
    } else if (target == collectorBlock) {
        game.openMachine(collectorScreen);
        return true;
    } else if (target == catalogBlock) {
        game.openMachine(catalogScreen);
        return true;
    } else {
        return false;
    }
}

bool breatheMachine(ref Game game) {
    Pharma* own = &pharma(game);
    BlockRecord* record = game.world.graph.edits.recordAt(game.machine, game.machineCell);
    MaybeIndex!uint slot = game.world.graph.slotOf(game.machine.node);
    if (record is null || !slot.exists || !game.world.graph.nodeAt(slot.value).hasState) {
        return false;
    } else {
        Ratio[GAS_COUNT] gathered = gatheredBy(game, *record, slot.value);
        foreach (gas; 0 .. GAS_COUNT) {
            own.organism.dose(Dose(GAS_MOLECULES[gas], gathered[gas], Route.inhaled));
        }
        record.placed = game.time;
        game.write(Told.breathed, "breathed in the collected air");
        return true;
    }
}

Ratio machineFilled(ref Game game) {
    BlockRecord* record = game.world.graph.edits.recordAt(game.machine, game.machineCell);
    if (record is null) {
        return Ratio(0);
    } else {
        return Ratio(lowerOf((game.time - record.placed).value, MOST_COLLECTED_SECONDS.value) / MOST_COLLECTED_SECONDS.value);
    }
}

Ratio[GAS_COUNT] machineGathered(ref Game game) {
    BlockRecord* record = game.world.graph.edits.recordAt(game.machine, game.machineCell);
    MaybeIndex!uint slot = game.world.graph.slotOf(game.machine.node);
    if (record is null || !slot.exists) {
        Ratio[GAS_COUNT] nothing;
        return nothing;
    } else {
        return gatheredBy(game, *record, slot.value);
    }
}

Maybe!Eating startEating(ref Game game, Stack food) {
    if (food.isEmpty || !isLivingItem(food.item)) {
        game.write(Told.nothingToEat, "hold something living to eat it");
        return Maybe!Eating.init;
    } else if (!food.genes.exists) {
        tellNoGenes(game, food.item);
        return Maybe!Eating.init;
    } else if (!game.organism.body.hasRoomFor(productOf(food.item.block, food.genes.value))) {
        game.write(Told.bodyFull, "your body holds too many compounds; wait for some to clear");
        return Maybe!Eating.init;
    } else {
        return Maybe!Eating.of(Eating(food, Time(0), game.inventory.selected));
    }
}

void chew(ref Game game, Time dt) {
    Pharma* own = &pharma(game);
    Stack food = game.inventory.slots[game.inventory.selected];
    if (own.eating.exists && own.eating.value.slot == game.inventory.selected && !food.isEmpty && food.isSameKind(own.eating.value.food)) {
        own.eating.value.spent = own.eating.value.spent + dt;
        if (own.eating.value.spent >= EAT_TIME) {
            swallow(game, food);
            own.eating = Maybe!Eating.init;
        }
    } else if (own.bite == Bite.fresh) {
        own.eating = startEating(game, food);
    } else {
        own.eating = Maybe!Eating.init;
    }
}

void swallow(ref Game game, Stack food) {
    char[NOTE_CAPACITY] buffer;
    char[NAME_CAPACITY] storage;
    char[NAME_CAPACITY] itemStorage;
    game.inventory.spendFrom(game.inventory.selected);
    Molecule product = productOf(food.item.block, food.genes.value);
    const(char)[] item = itemName(food.item, itemStorage[]);
    if (isKnownProduct(game, product)) {
        const(char)[] molecule = moleculeName(product, storage[]);
        string how = ROUTE_WORDS[Route.ingested];
        game.write(Told.ate, printed(buffer[], "ate the %.*s: %.*s, %.*s", cast(int) item.length, item.ptr, cast(int) molecule.length, molecule.ptr, cast(int) how.length, how.ptr));
    } else {
        game.write(Told.ateUnknown, printed(buffer[], "ate the %.*s", cast(int) item.length, item.ptr));
    }
    game.organism.dose(Dose(product, PLANT_DOSE, Route.ingested));
}

Ratio eatingShare(ref const Game game) {
    const(Pharma)* own = &pharma(game);
    if (!own.eating.exists) {
        return Ratio(0);
    } else {
        return Ratio(lowerOf((own.eating.value.spent / EAT_TIME).value, 1.0f));
    }
}

void placed(ref Game game, ChunkId chunk, uint cell, Stack stack) {
    Material block = stack.item.block;
    if (block == collectorBlock) {
        game.world.graph.edits.keepRecord(chunk, BlockRecord(Lineage.init, game.time, cell, COLLECTOR_RECORD));
    } else if (isLiving(block)) {
        placeLiving(game, chunk, cell, stack);
    }
}

void placeLiving(ref Game game, ChunkId chunk, uint cell, Stack stack) {
    char[NOTE_CAPACITY] buffer;
    char[NAME_CAPACITY] storage;
    Material block = stack.item.block;
    const(char)[] name = materialName(block, storage[]);
    Lineage genes = wildGenesAt(game, chunk, cell, block);
    if (stack.genes.exists) {
        genes = stack.genes.value;
    }
    if (isPlant(block) && stack.genes.exists) {
        game.world.graph.edits.keepRecord(chunk, BlockRecord(genes, game.time, cell, PLANTED_RECORD));
        game.write(Told.planted, printed(buffer[], "planted a %.*s, ripe in %.0fs", cast(int) name.length, name.ptr, cast(double) GROWN_SECONDS.value));
    } else if (isPlant(block)) {
        game.world.graph.edits.keepRecord(chunk, BlockRecord(genes, game.time, cell, PLANTED_RECORD));
        game.write(Told.plantedWild, printed(buffer[], "planted a %.*s with no genes of its own; it took this place's, ripe in %.0fs", cast(int) name.length, name.ptr, cast(double) GROWN_SECONDS.value));
    } else {
        game.world.graph.edits.keepRecord(chunk, BlockRecord(genes, game.time, cell, PLACED_LIVING_RECORD));
    }
}

immutable Extension EXTENSION = Extension(&attach, &detach, &startOver, &step, &feel, &broke, &placed, &use, &aim, &gained, &upgraded, &woke);

immutable Extra EAT = Extra("eat", ActionInfo("eat what you hold (hold)", "f", Rules.survival), &bite, &letGo);
immutable Extra DOSE = Extra("dose", ActionInfo("take a test dose", "o", Rules.creative), &doseNext, null);
