module common.biology.organism;

import base.array : Array;
import base.maybe : Maybe;
import base.names : enumNamed;
import base.stdio : printed;
import base.units : Ratio, Time;
import common.biology.genome : Gene, Genome, MOST_GENES, Receptor, assembleReceptors, enzymeGene, enzymesOf, receptorGene;
import common.biology.kinetics : Body, MOST_SPECIES, Route;
import common.biology.metabolism : Enzyme, MotifCell, Operation, Presence, SITE_CELL, metabolize;
import common.biology.molecule : Fragment, GRID_CELLS, Molecule, Property, propertyBit, withFragment;
import common.biology.occupancy : occupanciesOf;
import common.biology.pocket : Binding, BindingCache, HALF_CELLS, HalfPocket, Pocket, PocketCell, PocketKind, TRANSDUCER_COUNT, joined;
import common.biology.signaling : Signaling;
import common.content.declarations : declare;
import common.content.graph : ContentGraph, ENGINE_OWNER, PROBLEM_CAPACITY, targetOf;
import plugins.api.content : ContentRef, Holder;

enum Time BIOLOGY_TICK = Time(0.05f);
enum ubyte BULKY = 1 << Property.bulky;
enum ubyte CHARGED = 1 << Property.charged;
enum ubyte POLAR = 1 << Property.polar;
enum ubyte ALL_PROPERTIES = BULKY | CHARGED | POLAR;

PocketCell wall() {
    return PocketCell(PocketKind.wall, 0, 0, 0);
}

PocketCell open(ubyte wanted) {
    return PocketCell(PocketKind.open, wanted, ALL_PROPERTIES, 0);
}

PocketCell trigger(ubyte transducer) {
    return PocketCell(PocketKind.trigger, 0, 0, transducer);
}

PocketCell brake() {
    return PocketCell(PocketKind.brake, 0, 0, 0);
}

Enzyme enzymeAt(Operation operation, ubyte wanted) {
    Enzyme enzyme;
    enzyme.operation = operation;
    enzyme.motif[SITE_CELL] = MotifCell(wanted, ALL_PROPERTIES, Presence.filled);
    return enzyme;
}

enum string BODY_KIND = "starter-body";
enum string ORGANISM_DECLARATIONS = "biology/organism.decl";
enum string OPEN_PREFIX = "open-";
enum string TRIGGER_PREFIX = "trigger-";
enum char PROPERTY_JOIN = '+';
enum char WORD_GAP = ' ';

__gshared Genome starter;
__gshared Array!Dose starterDoses;

Genome starterGenome() {
    return starter;
}

void declareOrganism(ref ContentGraph graph) {
    declare(graph, import(ORGANISM_DECLARATIONS), ORGANISM_DECLARATIONS);
}

Maybe!ubyte propertiesOf(const(char)[] text) {
    ubyte bits = 0;
    size_t start = 0;
    uint unknown = 0;
    while (start < text.length) {
        size_t end = start;
        while (end < text.length && text[end] != PROPERTY_JOIN) {
            end += 1;
        }
        Maybe!Property property = enumNamed!Property(text[start .. end]);
        if (property.exists) {
            bits |= propertyBit(property.value);
        } else {
            unknown += 1;
        }
        start = end + 1;
    }
    if (unknown > 0) {
        return Maybe!ubyte.init;
    } else {
        return Maybe!ubyte.of(bits);
    }
}

Maybe!PocketCell cellNamed(const(char)[] word) {
    if (word == "wall") {
        return Maybe!PocketCell.of(wall());
    } else if (word == "brake") {
        return Maybe!PocketCell.of(brake());
    } else if (word.length == TRIGGER_PREFIX.length + 1 && word[0 .. TRIGGER_PREFIX.length] == TRIGGER_PREFIX && word[$ - 1] >= '0' && word[$ - 1] < '0' + TRANSDUCER_COUNT) {
        return Maybe!PocketCell.of(trigger(cast(ubyte)(word[$ - 1] - '0')));
    } else if (word.length > OPEN_PREFIX.length && word[0 .. OPEN_PREFIX.length] == OPEN_PREFIX && propertiesOf(word[OPEN_PREFIX.length .. $]).exists) {
        return Maybe!PocketCell.of(open(propertiesOf(word[OPEN_PREFIX.length .. $]).value));
    } else {
        return Maybe!PocketCell.init;
    }
}

Maybe!HalfPocket halfNamed(ref ContentGraph graph, uint node) {
    char[PROBLEM_CAPACITY] buffer;
    const(char)[] text = graph.textAt(ContentRef(node, Holder.node), "cells");
    const(char)[] name = graph.nameOf(node);
    HalfPocket half;
    uint count = 0;
    uint wrong = 0;
    size_t start = 0;
    while (start < text.length) {
        size_t end = start;
        while (end < text.length && text[end] != WORD_GAP) {
            end += 1;
        }
        const(char)[] word = text[start .. end];
        Maybe!PocketCell cell = cellNamed(word);
        if (word.length > 0 && !cell.exists) {
            graph.report(graph.nodes.ptr[node].owner, printed(buffer[], "'%.*s' has the cell '%.*s', which is not wall, brake, trigger-N or open-<properties>", cast(int) name.length, name.ptr, cast(int) word.length, word.ptr));
            wrong += 1;
        } else if (word.length > 0 && count < HALF_CELLS) {
            half.cells[count] = cell.value;
            count += 1;
        } else if (word.length > 0) {
            count += 1;
        }
        start = end + 1;
    }
    if (count != HALF_CELLS) {
        graph.report(graph.nodes.ptr[node].owner, printed(buffer[], "'%.*s' has %u cells, and a receptor half has %u", cast(int) name.length, name.ptr, count, HALF_CELLS));
        wrong += 1;
    }
    if (wrong > 0) {
        return Maybe!HalfPocket.init;
    } else {
        return Maybe!HalfPocket.of(half);
    }
}

void addGene(ref ContentGraph graph, uint body, Gene gene) {
    if (starter.count == MOST_GENES) {
        char[PROBLEM_CAPACITY] buffer;
        const(char)[] name = graph.nameOf(body);
        graph.report(graph.nodes.ptr[body].owner, printed(buffer[], "'%.*s' has more than %u genes", cast(int) name.length, name.ptr, MOST_GENES));
    } else {
        starter.add(gene);
    }
}

void readBody(ref ContentGraph graph, uint body) {
    char[PROBLEM_CAPACITY] buffer;
    foreach (edge; graph.edgesFrom(body)) {
        uint to = graph.edges.ptr[edge].to;
        ContentRef at = ContentRef(to, Holder.node);
        if (graph.isEdgeKind(edge, "halves")) {
            Maybe!HalfPocket half = halfNamed(graph, to);
            if (half.exists) {
                addGene(graph, body, receptorGene(half.value, Ratio(graph.number(at, "expression"))));
            }
        }
    }
    foreach (edge; graph.edgesFrom(body)) {
        uint to = graph.edges.ptr[edge].to;
        ContentRef at = ContentRef(to, Holder.node);
        Maybe!ubyte wants = propertiesOf(graph.textAt(at, "wants"));
        const(char)[] name = graph.nameOf(to);
        if (graph.isEdgeKind(edge, "enzymes") && !wants.exists) {
            graph.report(graph.nodes.ptr[to].owner, printed(buffer[], "'%.*s' wants properties that are not bulky, charged or polar", cast(int) name.length, name.ptr));
        } else if (graph.isEdgeKind(edge, "enzymes")) {
            Enzyme enzyme = enzymeAt(enumNamed!Operation(graph.textAt(at, "operation")).value, wants.value);
            addGene(graph, body, enzymeGene(enzyme, Ratio(graph.number(at, "expression"))));
        }
    }
    foreach (edge; graph.edgesFrom(body)) {
        uint to = graph.edges.ptr[edge].to;
        ContentRef at = ContentRef(to, Holder.node);
        if (graph.isEdgeKind(edge, "doses")) {
            Maybe!HalfPocket half = halfNamed(graph, targetOf(graph, to, "half").value);
            if (half.exists) {
                Pocket pocket = joined(half.value, half.value);
                PocketKind skipped = enumNamed!PocketKind(graph.textAt(at, "skips")).value;
                starterDoses.append(Dose(complementOf(pocket, skipped), Ratio(graph.number(at, "amount")), enumNamed!Route(graph.textAt(at, "route")).value));
            }
        }
    }
}

void buildOrganism(ref ContentGraph graph) {
    starter = Genome.init;
    starterDoses.clear();
    uint bodies = 0;
    foreach (node; 0 .. cast(uint) graph.nodes.length) {
        if (graph.isKind(node, BODY_KIND)) {
            if (bodies == 0) {
                readBody(graph, node);
            }
            bodies += 1;
        }
    }
    if (bodies != 1) {
        char[PROBLEM_CAPACITY] buffer;
        graph.report(graph.intern(ENGINE_OWNER), printed(buffer[], "the mods define %u starter bodies, and the body reads exactly one", bodies));
    }
}

Molecule complementOf(ref const Pocket pocket, PocketKind skipped) {
    Molecule molecule;
    foreach (cell; 0 .. GRID_CELLS) {
        PocketCell place = pocket.cells[cell];
        if (place.kind != PocketKind.wall && place.kind != skipped) {
            molecule = molecule.withFragment(cell, Fragment.of(place.wanted));
        }
    }
    return molecule;
}

struct Dose {
    Molecule molecule;
    Ratio amount;
    Route route;
}


struct Organism {
    Genome genome;
    Array!Receptor receptors;
    Array!Enzyme enzymes;
    Array!Ratio occupancy;
    Array!(Ratio[MOST_SPECIES]) bound;
    Body body;
    Signaling signaling;
    BindingCache cache;
    Ratio[TRANSDUCER_COUNT] activation;
    Time owed;

    static Organism make(Genome chosen) {
        Organism organism;
        organism.genome = chosen;
        assembleReceptors(organism.genome, organism.receptors);
        enzymesOf(organism.genome, organism.enzymes);
        organism.occupancy.resize(organism.receptors.length);
        organism.bound.resize(organism.receptors.length);
        organism.signaling = Signaling.atRest();
        return organism;
    }

    void dose(Dose given) {
        if (body.hasRoomFor(given.molecule)) {
            body.dose(given.molecule, given.amount, given.route);
        }
    }

    void advance(Time elapsed) {
        owed = owed + elapsed;
        while (owed >= BIOLOGY_TICK) {
            tick(BIOLOGY_TICK);
            owed = owed - BIOLOGY_TICK;
        }
    }

    void tick(Time step) {
        metabolize(body, enzymes.slice(), step);
        body.advance(step);
        Ratio[MOST_SPECIES] concentrations;
        Ratio[MOST_SPECIES] affinities;
        Ratio[MOST_SPECIES] occupied;
        Binding[MOST_SPECIES] bindings;
        activation = Ratio(0);
        foreach (index, ref receptor; receptors.slice()) {
            foreach (held; 0 .. body.count) {
                bindings[held] = cache.bindingOf(receptor.pocket, body.species[held].molecule);
                concentrations[held] = body.species[held].blood;
                affinities[held] = bindings[held].affinity;
            }
            occupanciesOf(concentrations[0 .. body.count], affinities[0 .. body.count], occupied[0 .. body.count]);
            float total = 0;
            foreach (held; 0 .. body.count) {
                total += occupied[held].value;
                foreach (transducer; 0 .. TRANSDUCER_COUNT) {
                    activation[transducer] = activation[transducer] + Ratio(receptor.amount.value * occupied[held].value * bindings[held].efficacy[transducer].value);
                }
            }
            occupancy.ptr[index] = Ratio(total);
            foreach (held; 0 .. MOST_SPECIES) {
                bound.ptr[index][held] = Ratio(0);
                if (held < body.count) {
                    bound.ptr[index][held] = occupied[held];
                }
            }
        }
        signaling.advance(activation, step);
    }

    void release() {
        receptors.release();
        enzymes.release();
        occupancy.release();
        bound.release();
        cache.release();
    }
}
