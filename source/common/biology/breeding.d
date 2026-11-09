module common.biology.breeding;

import core.stdc.math : expf;
import base.array : Array;
import base.maybe : Maybe, MaybeIndex;
import base.names : enumNamed;
import base.splitmix : SplitMix;
import common.biology.molecule : Molecule;
import common.biology.organism : complementOf, halfNamed;
import common.biology.pocket : HalfPocket, Pocket, PocketKind, joined;
import common.biology.wild : WILD_GENES, WildGenes, mutated, productFrom;
import common.content.declarations : declare;
import common.content.graph : ContentGraph, targetOf;
import common.material : materialCount, materialOfNode;
import common.worldgen.climate : Climate;
import plugins.api.api : Material;
import plugins.api.content : ContentRef, Holder;

enum ulong CROSS_SALT = 0xC2055_ED;
enum float SUITABILITY_STEEPNESS = 4;
enum float WET_HABIT_WETNESS = 0.45f;
enum float COLD_HABIT_WARMTH = -0.45f;
enum float HABIT_MARGIN = 0.5f;
enum uint MOST_TARGETS = 2;

enum Thrives : ubyte {
    mild,
    cold,
    wet,
    arid,
}

struct Habit {
    Maybe!Molecule core;
    Thrives thrives;
}

__gshared Array!Habit habits;

Habit habitOf(Material plant) {
    return habits.ptr[plant.id];
}

enum string BREEDING_DECLARATIONS = "biology/breeding.decl";

void declareBreeding(ref ContentGraph graph) {
    declare(graph, import(BREEDING_DECLARATIONS), BREEDING_DECLARATIONS);
}

E traitOf(E)(ref const ContentGraph graph, uint node, string key) {
    return enumNamed!E(graph.textAt(ContentRef(node, Holder.node), key)).value;
}

void buildHabits(ref ContentGraph graph) {
    habits.resize(materialCount());
    foreach (ref habit; habits.slice()) {
        habit = Habit.init;
    }
    foreach (index; 0 .. cast(uint) graph.nodes.length) {
        if (graph.isKind(index, "material")) {
            habits.ptr[materialOfNode(graph, index).id] = Habit(coreOf(graph, index), traitOf!Thrives(graph, index, "thrives"));
        }
    }
}

Maybe!Molecule coreOf(ref ContentGraph graph, uint material) {
    MaybeIndex!uint chemistry = targetOf(graph, material, "makes");
    if (!chemistry.exists) {
        return Maybe!Molecule.init;
    } else {
        HalfPocket[MOST_TARGETS] halves;
        uint count = 0;
        uint broken = 0;
        foreach (edge; graph.edgesFrom(chemistry.value)) {
            if (graph.isEdgeKind(edge, "targets")) {
                Maybe!HalfPocket half = halfNamed(graph, graph.edges.ptr[edge].to);
                if (half.exists) {
                    halves[count] = half.value;
                    count += 1;
                } else {
                    broken += 1;
                }
            }
        }
        if (broken > 0) {
            return Maybe!Molecule.init;
        } else {
            HalfPocket far = HalfPocket.init;
            if (count == MOST_TARGETS) {
                far = halves[1];
            }
            Pocket pocket = joined(halves[0], far);
            PocketKind skipped = traitOf!PocketKind(graph, chemistry.value, "skips");
            return Maybe!Molecule.of(complementOf(pocket, skipped));
        }
    }
}

Molecule productOf(Material species, WildGenes genes) {
    return productFrom(habitOf(species).core, genes);
}

WildGenes crossed(WildGenes first, WildGenes second, ulong salt, float mutationOdds) {
    WildGenes child;
    foreach (index; 0 .. WILD_GENES) {
        bool fromFirst = (SplitMix(salt ^ CROSS_SALT ^ index).next() & 1) == 0;
        ulong seed = second.seeds[index];
        if (fromFirst) {
            seed = first.seeds[index];
        }
        child.seeds[index] = mutated(seed, salt ^ index, mutationOdds);
    }
    return child;
}

float suitabilityOf(Material plant, Climate climate) {
    float warmth = climate.warmth();
    final switch (habitOf(plant).thrives) {
        case Thrives.arid:
            return warmth - climate.wetness;
        case Thrives.cold:
            return COLD_HABIT_WARMTH - warmth + HABIT_MARGIN;
        case Thrives.wet:
            return climate.wetness - WET_HABIT_WETNESS + HABIT_MARGIN;
        case Thrives.mild:
            return HABIT_MARGIN - (climate.wetness * climate.wetness + warmth * warmth);
    }
}

float expressionIn(Material plant, Climate climate) {
    return 1 / (1 + expf(-SUITABILITY_STEEPNESS * suitabilityOf(plant, climate)));
}
