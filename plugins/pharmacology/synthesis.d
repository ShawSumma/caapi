module plugins.pharmacology.synthesis;

import base.array : Array;
import base.maybe : Maybe, MaybeIndex;
import base.names : enumNamed;
import base.units : Time;
import common.content.graph : ContentGraph, targetOf;
import plugins.api.content : ContentRef;
import plugins.crafting.crafting : HAND, Station, edgeRef, nodeRef;
import plugins.crafting.items : Item, itemOfNode;
import plugins.pharmacology.kinetics : Route;
import plugins.pharmacology.metabolism : Enzyme, MotifCell, Operation, Presence, SITE_CELL, productOf;
import plugins.pharmacology.molecule : Fragment, Molecule, Property, propertyBit;

enum string SYNTHESIS_KIND = "synthesis";
enum string ROUTE_KIND = "dose-route";

struct Synthesis {
    ubyte id;
}

enum Reaction : ubyte {
    extract,
    press,
    oxidize,
    conjugate,
    cleave,
    attach,
}

struct SynthesisRule {
    Time time;
    const(char)[] name;
    const(char)[] title;
    Item reagent;
    Fragment attached;
    Station station;
    Reaction reaction;
    float extract;
}

struct DoseRoute {
    const(char)[] name;
    const(char)[] title;
    Item device;
    uint uses;
    Route route;
}

__gshared Array!SynthesisRule synthesisTable;
__gshared Array!DoseRoute routeTable;

const(SynthesisRule)[] syntheses() {
    return synthesisTable.slice();
}

const(DoseRoute)[] doseRoutes() {
    return routeTable.slice();
}

Fragment fragmentNamed(const(char)[] name) {
    Maybe!Property property = enumNamed!Property(name);
    if (property.exists) {
        return Fragment.of(propertyBit(property.value));
    } else {
        return Fragment.init;
    }
}

void buildSyntheses(ref ContentGraph graph) {
    foreach (node, ref record; graph.nodes.slice()) {
        if (graph.isKind(cast(uint) node, SYNTHESIS_KIND)) {
            ContentRef at = nodeRef(cast(uint) node);
            Reaction reaction = enumNamed!Reaction(graph.textAt(at, "operation")).value;
            SynthesisRule rule = SynthesisRule(Time(cast(float) graph.number(at, "seconds")), graph.nameOf(cast(uint) node), graph.textAt(at, "title"), Item.init, fragmentNamed(graph.textAt(at, "fragment")), HAND, reaction, cast(float) graph.number(at, "extract"));
            MaybeIndex!uint station = targetOf(graph, cast(uint) node, "at");
            MaybeIndex!uint reagent = targetOf(graph, cast(uint) node, "reagent");
            if (station.exists) {
                rule.station = Station(cast(ubyte) graph.ordinalOf(station.value));
            }
            if (reagent.exists) {
                rule.reagent = itemOfNode(reagent.value).value;
            }
            synthesisTable.append(rule);
        }
    }
}

void buildRoutes(ref ContentGraph graph) {
    foreach (node, ref record; graph.nodes.slice()) {
        if (graph.isKind(cast(uint) node, ROUTE_KIND)) {
            ContentRef at = nodeRef(cast(uint) node);
            DoseRoute made = DoseRoute(graph.nameOf(cast(uint) node), graph.textAt(at, "title"), Item.init, 0, enumNamed!Route(graph.textAt(at, "route")).value);
            foreach (edge; graph.edgesFrom(cast(uint) node)) {
                if (graph.isEdgeKind(edge, "needs-device")) {
                    made.device = itemOfNode(graph.edges.ptr[edge].to).value;
                    made.uses = cast(uint) graph.number(edgeRef(edge), "uses");
                }
            }
            routeTable.append(made);
        }
    }
}

Enzyme reactionOf(ref const SynthesisRule rule) {
    Enzyme enzyme;
    enzyme.motif[SITE_CELL] = MotifCell(0, 0, Presence.filled);
    final switch (rule.reaction) {
        case Reaction.extract:
        case Reaction.press:
            break;
        case Reaction.oxidize:
            enzyme.operation = Operation.oxidize;
            break;
        case Reaction.conjugate:
            enzyme.operation = Operation.conjugate;
            break;
        case Reaction.cleave:
            enzyme.operation = Operation.cleave;
            break;
        case Reaction.attach:
            enzyme.operation = Operation.attach;
            enzyme.attached = rule.attached;
            enzyme.motif[SITE_CELL] = MotifCell(0, 0, Presence.empty);
            break;
    }
    return enzyme;
}

Maybe!Molecule synthesized(Molecule molecule, Synthesis synthesis) {
    const(SynthesisRule)* rule = &synthesisTable.ptr[synthesis.id];
    if (rule.reaction == Reaction.press || rule.reaction == Reaction.extract) {
        return Maybe!Molecule.of(molecule);
    } else {
        return reactionOf(*rule).productOf(molecule);
    }
}

bool actsOnCompounds(ref const SynthesisRule rule) {
    return rule.reaction != Reaction.extract;
}

MaybeIndex!uint synthesisBy(Reaction reaction) {
    uint index = 0;
    while (index < synthesisTable.length && synthesisTable.ptr[index].reaction != reaction) {
        index += 1;
    }
    if (index < synthesisTable.length) {
        return MaybeIndex!uint.of(index);
    } else {
        return MaybeIndex!uint.init;
    }
}
