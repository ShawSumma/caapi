module unit.breeding;

import common.biology.breeding : crossed, expressionIn;
import common.biology.wild : WILD_GENES, WildGenes;
import common.worldgen.climate : Climate;
import plugins.api.api : Material;
import unit.named : blockNamed;

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
    Material fern = blockNamed("base:fern");
    Material thornbush = blockNamed("base:thornbush");
    Material flower = blockNamed("base:flower");
    assert(expressionIn(fern, wet) > expressionIn(fern, dry));
    assert(expressionIn(thornbush, dry) > expressionIn(thornbush, wet));
    assert(expressionIn(flower, wet) > 0 && expressionIn(flower, wet) < 1);
}
