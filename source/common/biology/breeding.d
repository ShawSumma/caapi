module common.biology.breeding;

import core.stdc.math : expf;
import base.splitmix : SplitMix;
import common.biology.wild : WILD_GENES, WildGenes, mutated;
import common.worldgen.climate : Climate, SNOW_WARMTH, isDesert;
import plugins.api.api : Material;

enum ulong CROSS_SALT = 0xC2055_ED;
enum float SUITABILITY_STEEPNESS = 4;
enum float WET_FOR_FERN = 0.45f;

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
    if (plant == Material.thornbush) {
        return warmth - climate.wetness;
    } else if (plant == Material.moss) {
        return SNOW_WARMTH - warmth + 0.5f;
    } else if (plant == Material.fern) {
        return climate.wetness - WET_FOR_FERN + 0.5f;
    } else {
        return 0.5f - (climate.wetness * climate.wetness + warmth * warmth);
    }
}

float expressionIn(Material plant, Climate climate) {
    return 1 / (1 + expf(-SUITABILITY_STEEPNESS * suitabilityOf(plant, climate)));
}
