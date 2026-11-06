module unit.breeding;

import common.biology.breeding : crossed, expressionIn;
import common.biology.wild : WILD_GENES, WildGenes;
import common.worldgen.climate : Climate;
import plugins.api.api : Material;

enum ulong SALT = 0x1234;

unittest {
    WildGenes first = WildGenes([1, 2, 3, 4]);
    WildGenes second = WildGenes([10, 20, 30, 40]);
    WildGenes child = crossed(first, second, SALT, 0);
    foreach (index; 0 .. WILD_GENES) {
        assert(child.seeds[index] == first.seeds[index] || child.seeds[index] == second.seeds[index]);
    }
    WildGenes wild = crossed(first, second, SALT, 1);
    uint unchanged = 0;
    foreach (index; 0 .. WILD_GENES) {
        if (wild.seeds[index] == first.seeds[index] || wild.seeds[index] == second.seeds[index]) {
            unchanged += 1;
        }
    }
    assert(unchanged == 0);
}

unittest {
    Climate wet = Climate(0, 0.2f, 0.9f, 0);
    Climate dry = Climate(0, 0.2f, -0.9f, 0);
    assert(expressionIn(Material.fern, wet) > expressionIn(Material.fern, dry));
    assert(expressionIn(Material.thornbush, dry) > expressionIn(Material.thornbush, wet));
    assert(expressionIn(Material.flower, wet) > 0 && expressionIn(Material.flower, wet) < 1);
}
