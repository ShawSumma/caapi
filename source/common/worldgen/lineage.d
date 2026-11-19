module common.worldgen.lineage;

import base.splitmix : SplitMix;

enum uint LINEAGE_SEEDS = 4;
enum ulong ROOT_SALT = 0x77_11D5_EED5;
enum ulong MUTATION_SALT = 0x0B5E_55ED_CA75;
enum ulong PARENT_SALT = 0x9A2E_7A15;
enum float NODE_MUTATION_ODDS = 0.04f;

struct Lineage {
    ulong[LINEAGE_SEEDS] seeds;

    static Lineage ofRoot(ulong worldSalt) {
        Lineage lineage;
        foreach (index; 0 .. LINEAGE_SEEDS) {
            lineage.seeds[index] = SplitMix(ROOT_SALT ^ worldSalt ^ index).next();
        }
        return lineage;
    }
}

Lineage inherited(const(Lineage)[] parents, ulong spice) {
    Lineage lineage;
    foreach (index; 0 .. LINEAGE_SEEDS) {
        size_t pick = cast(size_t)(SplitMix(spice ^ PARENT_SALT ^ index).next() % parents.length);
        lineage.seeds[index] = mutated(parents[pick].seeds[index], spice ^ index, NODE_MUTATION_ODDS);
    }
    return lineage;
}

ulong mutated(ulong seed, ulong spice, float odds) {
    SplitMix roll = SplitMix(spice ^ MUTATION_SALT);
    if (roll.roll() < odds) {
        return SplitMix(seed ^ roll.next()).next();
    } else {
        return seed;
    }
}
