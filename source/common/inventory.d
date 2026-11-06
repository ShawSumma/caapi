module common.inventory;

import common.material : MATERIAL_COUNT;
import plugins.api.api : Material;

enum uint HOTBAR_SLOTS = 9;
enum uint STARTER_COUNT = 999;

immutable Material[HOTBAR_SLOTS] STARTER_HOTBAR = [
    Material.woodPlanks,
    Material.oakWood,
    Material.oakLeaves,
    Material.greyBrick,
    Material.whiteBrick,
    Material.sandstone,
    Material.bench,
    Material.collector,
    Material.beacon,
];

struct Inventory {
    uint[MATERIAL_COUNT] counts;
    Material[HOTBAR_SLOTS] hotbar;
    uint selected;

    static Inventory starter() {
        Inventory inventory;
        inventory.hotbar = STARTER_HOTBAR;
        foreach (material; STARTER_HOTBAR) {
            inventory.counts[material] = STARTER_COUNT;
        }
        return inventory;
    }

    Material held() const {
        return hotbar[selected];
    }

    bool select(uint slot) {
        bool changed = slot < HOTBAR_SLOTS && slot != selected;
        if (changed) {
            selected = slot;
        }
        return changed;
    }

    void gain(Material material) {
        counts[material] += 1;
        uint slot = 0;
        while (slot < HOTBAR_SLOTS && hotbar[slot] != material) {
            slot += 1;
        }
        if (slot == HOTBAR_SLOTS) {
            uint empty = 0;
            while (empty < HOTBAR_SLOTS && counts[hotbar[empty]] > 0 && hotbar[empty] != Material.none) {
                empty += 1;
            }
            if (empty < HOTBAR_SLOTS) {
                hotbar[empty] = material;
            }
        }
    }

    bool spend(Material material) {
        if (material != Material.none && counts[material] > 0) {
            counts[material] -= 1;
            return true;
        } else {
            return false;
        }
    }
}
