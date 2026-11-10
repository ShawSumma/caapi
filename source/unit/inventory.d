module unit.inventory;

import base.array : Array;
import base.maybe : Maybe;
import common.biology.wild : WildGenes;
import common.crafting : IdSet, MOST_MAKERS, Recipe, Shortfall, Taken, canCraft, makersOf, planRecipe, recipes, returnIngredients, takeIngredients;
import common.inventory : Cycle, HOTBAR_SLOTS, Inventory, MOST_STRAINS, SLOT_COUNT, STACK_LIMIT, Section, Sorting, Stack, Strain;
import common.items : Item, ItemKind, itemNamed;
import unit.named : named;

unittest {
    Inventory inventory;
    Item granite = named("base:granite");
    Item dirt = named("base:dirt");
    assert(!inventory.spend(granite, 1));
    assert(inventory.gain(Stack(granite, 1)) == 0);
    assert(inventory.slots[0] == Stack(granite, 1));
    inventory.gain(Stack(dirt, STACK_LIMIT + 3));
    assert(inventory.slots[1] == Stack(dirt, STACK_LIMIT) && inventory.slots[2] == Stack(dirt, 3));
    assert(inventory.countOf(dirt) == STACK_LIMIT + 3);
    assert(inventory.spend(dirt, 4) && inventory.countOf(dirt) == STACK_LIMIT - 1 && inventory.slots[2].isEmpty);
    assert(inventory.spendHeld() && inventory.slots[0].isEmpty && inventory.held().kind == ItemKind.nothing);
}

unittest {
    Inventory inventory;
    foreach (slot; 0 .. SLOT_COUNT) {
        inventory.slots[slot] = Stack(named("base:sand"), STACK_LIMIT);
    }
    assert(inventory.gain(Stack(named("base:sand"), 1)) == 1);
    assert(inventory.gain(Stack(itemNamed("base:iron-bar").value, 5)) == 5);
}

unittest {
    Inventory inventory;
    Stack moving = Stack(named("base:glass"), 5);
    inventory.pour(Section.pack, moving);
    assert(moving.isEmpty && inventory.slots[HOTBAR_SLOTS] == Stack(named("base:glass"), 5));
    inventory.cycle(Cycle.back);
    assert(inventory.selected == HOTBAR_SLOTS - 1);
    inventory.cycle(Cycle.ahead);
    assert(inventory.selected == 0);
}

unittest {
    Inventory inventory;
    Item leaves = named("base:oak-leaves");
    Stack first = Stack.ofLiving(leaves, 2, WildGenes([1, 2, 3, 4]), Sorting.unsorted);
    Stack second = Stack.ofLiving(leaves, 3, WildGenes([5, 6, 7, 8]), Sorting.unsorted);
    Stack known = Stack.ofLiving(leaves, 1, WildGenes([5, 6, 7, 8]), Sorting.sorted);
    Stack plain = Stack(leaves, 4);
    inventory.gain(first);
    inventory.gain(second);
    inventory.gain(plain);
    inventory.gain(first);
    inventory.gain(known);
    assert(inventory.slots[0].count == 7 && inventory.slots[0].strainCount == 2 && inventory.slots[0].sorting == Sorting.unsorted);
    assert(inventory.slots[1] == plain && inventory.slots[2] == known && inventory.slots[3].isEmpty);
    assert(inventory.countOf(leaves) == 12 && inventory.countOfKind(first) == 4 && inventory.countOfKind(second) == 4);
    assert(inventory.spendKind(second) && inventory.slots[2].isEmpty && inventory.countOfKind(second) == 3 && inventory.countOfKind(first) == 4);
    Stack drawn = inventory.slots[0].draw(5);
    assert(drawn.count == 5 && drawn.strainCount == 2 && drawn.strains[0] == Strain(WildGenes([1, 2, 3, 4]), 4) && drawn.strains[1] == Strain(WildGenes([5, 6, 7, 8]), 1));
    assert(inventory.slots[0].count == 2 && inventory.slots[0].strainCount == 1 && inventory.slots[0].front() == Stack.ofLiving(leaves, 1, WildGenes([5, 6, 7, 8]), Sorting.unsorted));
    drawn.pourInto(inventory.slots[0]);
    assert(drawn.isEmpty && inventory.slots[0].count == 7 && inventory.countOfKind(first) == 4);
}

unittest {
    Inventory inventory;
    Item leaves = named("base:oak-leaves");
    foreach (strain; 0 .. MOST_STRAINS + 1) {
        WildGenes genes;
        genes.seeds[0] = strain;
        inventory.gain(Stack.ofLiving(leaves, 1, genes, Sorting.unsorted));
    }
    assert(inventory.slots[0].strainCount == MOST_STRAINS && inventory.slots[0].count == MOST_STRAINS && inventory.slots[1].count == 1 && inventory.slots[2].isEmpty);
}

unittest {
    Inventory inventory;
    assert(!inventory.canCraft(recipes()[0]));
    assert(!inventory.takeIngredients(recipes()[0]).exists);
    inventory.gain(Stack(named("base:spruce-wood"), 1));
    Maybe!Taken taken = inventory.takeIngredients(recipes()[0]);
    assert(taken.exists && inventory.countOf(named("base:spruce-wood")) == 0);
    inventory.returnIngredients(recipes()[0], taken.value);
    assert(inventory.countOf(named("base:spruce-wood")) == 1 && inventory.countOf(named("base:oak-wood")) == 0);
}

unittest {
    Inventory inventory;
    uint[MOST_MAKERS] makers;
    IdSet known;
    makersOf(named("base:furnace"), known, makers);
    const(Recipe)* furnace = &recipes()[makers[0]];
    inventory.gain(Stack(named("base:granite"), 5));
    inventory.gain(Stack(named("base:diorite"), 4));
    Maybe!Taken taken = inventory.takeIngredients(*furnace);
    assert(taken.exists && inventory.countOf(named("base:granite")) + inventory.countOf(named("base:diorite")) == 1);
    inventory.returnIngredients(*furnace, taken.value);
    assert(inventory.countOf(named("base:granite")) == 5 && inventory.countOf(named("base:diorite")) == 4);
}

unittest {
    Inventory stock;
    stock.gain(Stack(named("base:birch-wood"), 2));
    uint[MOST_MAKERS] makers;
    IdSet known;
    makersOf(named("base:workbench"), known, makers);
    uint workbench = makers[0];
    Array!uint plan;
    Shortfall shortfall = planRecipe(stock, workbench, 1, plan, 0, known);
    assert(shortfall.count == 0 && plan.length == 3 && plan.ptr[2] == workbench);
    assert(stock.countOf(named("base:workbench")) == 1 && stock.countOf(named("base:wood-planks")) == 2);
    plan.clear();
    shortfall = planRecipe(stock, workbench, 1, plan, 0, known);
    assert(shortfall.count == 1 && shortfall.label == "wood");
    plan.release();
}
