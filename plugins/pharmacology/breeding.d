module plugins.pharmacology.breeding;

import core.stdc.math : expf;
import base.array : Array;
import base.maybe : Maybe, MaybeIndex;
import base.names : enumNamed;
import base.splitmix : SplitMix;
import common.content.graph : ContentGraph, targetOf;
import common.material : MATERIAL_KIND, MaterialSet, has, materialCount, materialOfNode, withTrait;
import common.worldgen.climate : Climate;
import common.worldgen.lineage : LINEAGE_SEEDS, Lineage, mutated;
import plugins.api.api : Material;
import plugins.api.content : ContentRef, Holder;
import plugins.pharmacology.molecule : Molecule;
import plugins.pharmacology.organism : complementOf, halfNamed;
import plugins.pharmacology.pocket : HalfPocket, Pocket, PocketKind, joined;
import plugins.pharmacology.wild : productFrom;

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
__gshared MaterialSet living;
__gshared MaterialSet plants;

Habit habitOf(Material plant) {
    return habits.ptr[plant.id];
}

bool isLiving(Material material) {
    return living.has(material);
}

bool isPlant(Material material) {
    return plants.has(material);
}

E traitOf(E)(ref const ContentGraph graph, uint node, string key) {
    return enumNamed!E(graph.textAt(ContentRef(node, Holder.node), key)).value;
}

void buildHabits(ref ContentGraph graph) {
    habits.resize(materialCount());
    foreach (ref habit; habits.slice()) {
        habit = Habit.init;
    }
    living = MaterialSet.init;
    plants = MaterialSet.init;
    foreach (index; 0 .. cast(uint) graph.nodes.length) {
        if (graph.isKind(index, MATERIAL_KIND)) {
            Material material = materialOfNode(graph, index);
            ContentRef at = ContentRef(index, Holder.node);
            habits.ptr[material.id] = Habit(coreOf(graph, index), traitOf!Thrives(graph, index, "thrives"));
            living = living.withTrait(graph, at, material, "living");
            plants = plants.withTrait(graph, at, material, "plant");
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
            HalfPocket far = halves[0];
            if (count == MOST_TARGETS) {
                far = halves[1];
            }
            Pocket pocket = joined(halves[0], far);
            PocketKind skipped = traitOf!PocketKind(graph, chemistry.value, "skips");
            return Maybe!Molecule.of(complementOf(pocket, skipped));
        }
    }
}

Molecule productOf(Material species, Lineage genes) {
    return productFrom(habitOf(species).core, genes);
}

Lineage crossed(Lineage first, Lineage second, ulong salt, float mutationOdds) {
    Lineage child;
    foreach (index; 0 .. LINEAGE_SEEDS) {
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
