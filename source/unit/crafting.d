module unit.crafting;

import common.crafting : IdSet, MOST_MAKERS, insights, makersOf, recipes;
import common.items : Item, itemNamed;

uint insightNamed(const(char)[] name) {
    uint index = 0;
    while (insights()[index].name != name) {
        index += 1;
    }
    return index;
}

unittest {
    Item glass = itemNamed("base:glass").value;
    uint[MOST_MAKERS] makers;
    IdSet common;
    uint known = makersOf(glass, common, makers);
    IdSet learned;
    learned.set(insightNamed("base:quenching"));
    uint more = makersOf(glass, learned, makers);
    assert(known == 1 && more == 3 && recipes()[makers[0]].yield == 2);
}
