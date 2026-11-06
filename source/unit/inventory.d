module unit.inventory;

import common.inventory : HOTBAR_SLOTS, Inventory, STARTER_COUNT;
import plugins.api.api : Material;

unittest {
    Inventory inventory;
    assert(!inventory.spend(Material.granite));
    inventory.gain(Material.granite);
    assert(inventory.hotbar[0] == Material.granite && inventory.counts[Material.granite] == 1);
    inventory.gain(Material.dirt);
    assert(inventory.hotbar[1] == Material.dirt);
    assert(inventory.spend(Material.granite) && inventory.counts[Material.granite] == 0);
    inventory.gain(Material.sand);
    assert(inventory.hotbar[0] == Material.sand && inventory.hotbar[1] == Material.dirt);
}

unittest {
    Inventory inventory = Inventory.starter();
    assert(inventory.counts[inventory.held()] == STARTER_COUNT);
    assert(!inventory.select(HOTBAR_SLOTS));
    assert(inventory.select(3) && inventory.selected == 3);
    inventory.gain(Material.dirt);
    assert(inventory.counts[Material.dirt] == 1);
    foreach (slot; 0 .. HOTBAR_SLOTS) {
        assert(inventory.hotbar[slot] != Material.dirt);
    }
}
