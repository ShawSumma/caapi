module unit.inventory;

import base.array : Array;
import base.maybe : Maybe;
import common.biology.wild : WildGenes;
import common.crafting : IdSet, MOST_MAKERS, Recipe, Shortfall, Taken, canCraft, makersOf, planRecipe, recipes, returnIngredients, takeIngredients;
import common.inventory : Cycle, HOTBAR_SLOTS, Inventory, SLOT_COUNT, STACK_LIMIT, Section, Stack, isSameKind;
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
    inventory.slots[0] = Stack(named("base:glass"), 5);
    assert(inventory.gainInto(Section.pack, inventory.slots[0]) == 0);
    assert(inventory.slots[HOTBAR_SLOTS] == Stack(named("base:glass"), 5));
    inventory.cycle(Cycle.back);
    assert(inventory.selected == HOTBAR_SLOTS - 1);
    inventory.cycle(Cycle.ahead);
    assert(inventory.selected == 0);
}

unittest {
    Inventory inventory;
    Item leaves = named("base:oak-leaves");
    Stack first = Stack(leaves, 2, Maybe!WildGenes.of(WildGenes([1, 2, 3, 4])));
    Stack second = Stack(leaves, 3, Maybe!WildGenes.of(WildGenes([5, 6, 7, 8])));
    Stack plain = Stack(leaves, 4);
    inventory.gain(first);
    inventory.gain(second);
    inventory.gain(plain);
    inventory.gain(first);
    assert(inventory.slots[0].isSameKind(first) && inventory.slots[0].count == 4);
    assert(inventory.slots[1].isSameKind(second) && inventory.slots[2].isSameKind(plain) && inventory.slots[3].isEmpty);
    assert(inventory.countOf(leaves) == 11 && inventory.countOfKind(second) == 3);
    assert(inventory.spendKind(second) && inventory.countOfKind(second) == 2 && inventory.countOfKind(first) == 4);
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
