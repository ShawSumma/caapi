module common.content.check;

import base.flags : Bits;
import base.stdio : FILE, fprintf;
import common.content.roles : ROLE_COUNT, Role, roleItem;
import common.crafting : Effect, HAND, IdSet, Product, Station, Trigger, doseRoutes, insights, isKnown, recipes, stations, syntheses, upgrades;
import common.items : Item, ItemKind, contentNameOf, itemCount, itemOf, wareCount, wareItem;
import common.material : MaterialSet, has, including, isLiving, materialCount, miningTiers;
import common.worldgen.palette : palette;
import plugins.api.api : Material;

enum uint LEAST_BLOCK_USES = 2;
enum uint LEAST_WARE_USES = 1;
enum uint LIVING_USES = 2;

MaterialSet terrainMaterials() {
    MaterialSet laid;
    foreach (rule; palette.cover.slice()) {
        laid = laid.including(rule.material);
    }
    foreach (rule; palette.soil.slice()) {
        laid = laid.including(rule.material);
    }
    foreach (rule; palette.fluids.slice()) {
        laid = laid.including(rule.material);
    }
    foreach (rule; palette.plants.slice()) {
        laid = laid.including(rule.material);
    }
    foreach (ref band; palette.rocks) {
        foreach (ref wetness; band) {
            foreach (rock; wetness) {
                laid = laid.including(rock);
            }
        }
    }
    foreach (ore; palette.ores.slice()) {
        laid = laid.including(ore);
    }
    foreach (ref tree; palette.trees.slice()) {
        laid = laid.including(tree.wood).including(tree.leaves).including(tree.heart);
    }
    return laid.including(palette.flatFill);
}

struct Reach {
    Bits items;
    Bits recipes;
    Bits worked;
    MaterialSet sources;
    IdSet known;
    uint tier;

    static Reach make(MaterialSet sources) {
        Reach reach;
        reach.items.cover(itemCount());
        reach.recipes.cover(.recipes().length);
        reach.worked.cover(stations().length);
        reach.sources = sources;
        return reach;
    }

    bool hasStation(Station station) const {
        return station == HAND || items.has(itemOf(stations()[station.id].block).id);
    }

    bool hasAny(const(Item)[] options) const {
        uint index = 0;
        while (index < options.length && !items.has(options[index].id)) {
            index += 1;
        }
        return index < options.length;
    }

    bool canMake(uint recipe) const {
        uint need = 0;
        while (need < .recipes()[recipe].needed && hasAny(.recipes()[recipe].needs[need].accepted)) {
            need += 1;
        }
        return known.isKnown(.recipes()[recipe].insight) && hasStation(.recipes()[recipe].station) && need == .recipes()[recipe].needed;
    }

    uint gather() {
        uint opened = 0;
        foreach (id; 1 .. materialCount()) {
            Material material = Material(cast(ubyte) id);
            if (sources.has(material) && miningTiers.ptr[id] <= tier && !items.has(id)) {
                items.set(id);
                opened += 1;
            }
        }
        return opened;
    }

    uint notice() {
        uint opened = 0;
        foreach (index, ref rule; insights()) {
            if (!known.has(cast(uint) index) && ((rule.trigger == Trigger.broke && hasAny(rule.noticed)) || (rule.trigger == Trigger.worked && worked.has(rule.station.id)))) {
                known.set(cast(uint) index);
                opened += 1;
            }
        }
        return opened;
    }

    uint widen() {
        uint opened = gather() + notice();
        foreach (index, ref recipe; .recipes()) {
            if (!recipes.has(index) && canMake(cast(uint) index)) {
                recipes.set(index);
                worked.set(recipe.station.id);
                opened += 1;
                if (recipe.product == Product.item) {
                    items.set(recipe.made.id);
                } else if (upgrades()[recipe.upgrade.id].effect == Effect.mining && upgrades()[recipe.upgrade.id].tier > tier) {
                    tier = upgrades()[recipe.upgrade.id].tier;
                }
            }
        }
        return opened;
    }

    void settle() {
        uint opened = widen();
        while (opened > 0) {
            opened = widen();
        }
    }

    void release() {
        items.release();
        recipes.release();
        worked.release();
    }
}

uint usesOf(Item item) {
    uint uses = 0;
    foreach (ref recipe; recipes()) {
        uint need = 0;
        while (need < recipe.needed && !item.isAmong(recipe.needs[need].accepted)) {
            need += 1;
        }
        if (need < recipe.needed) {
            uses += 1;
        }
    }
    foreach (ref rule; syntheses()) {
        if (rule.reagent == item) {
            uses += 1;
        }
    }
    if (item.kind == ItemKind.block && isLiving(item.block)) {
        uses += LIVING_USES;
    }
    return uses;
}

bool isAmong(Item item, const(Item)[] options) {
    uint index = 0;
    while (index < options.length && options[index] != item) {
        index += 1;
    }
    return index < options.length;
}

bool isMachine(Item item) {
    uint role = 0;
    while (role < ROLE_COUNT && !(roleItem(cast(Role) role) == item && cast(Role) role != Role.mutagen)) {
        role += 1;
    }
    uint station = 0;
    while (station < stations().length && itemOf(stations()[station].block) != item) {
        station += 1;
    }
    return role < ROLE_COUNT || station < stations().length;
}

bool isDevice(Item item) {
    uint index = 0;
    while (index < doseRoutes().length && doseRoutes()[index].device != item) {
        index += 1;
    }
    return index < doseRoutes().length;
}

void reportName(FILE* report, const(char)* what, const(char)[] name) {
    fprintf(report, what, cast(int) name.length, name.ptr);
}

uint checkReach(ref Reach reach, FILE* report) {
    uint problems = 0;
    foreach (index, ref recipe; recipes()) {
        if (!reach.recipes.has(index)) {
            reportName(report, "recipe %.*s is never reachable\n", recipe.name);
            problems += 1;
        }
    }
    foreach (index, ref rule; insights()) {
        if (!reach.known.has(cast(uint) index)) {
            reportName(report, "insight %.*s is never learned\n", rule.name);
            problems += 1;
        }
    }
    foreach (ref rule; syntheses()) {
        if (!reach.hasStation(rule.station) || (rule.reagent.kind != ItemKind.nothing && !reach.items.has(rule.reagent.id))) {
            reportName(report, "synthesis %.*s cannot be worked\n", rule.name);
            problems += 1;
        }
    }
    foreach (id; 1 .. itemCount()) {
        if (!reach.items.has(id)) {
            reportName(report, "%.*s is never in hand\n", contentNameOf(Item(cast(ushort) id)));
            problems += 1;
        }
    }
    return problems;
}

uint checkUses(FILE* report) {
    uint problems = 0;
    foreach (id; 1 .. materialCount()) {
        Item item = itemOf(Material(cast(ubyte) id));
        if (!isMachine(item) && usesOf(item) < LEAST_BLOCK_USES) {
            fprintf(report, "%.*s has %u uses\n", cast(int) contentNameOf(item).length, contentNameOf(item).ptr, usesOf(item));
            problems += 1;
        }
    }
    foreach (ware; 0 .. wareCount()) {
        Item item = wareItem(ware);
        if (!isDevice(item) && usesOf(item) < LEAST_WARE_USES) {
            fprintf(report, "%.*s has %u uses\n", cast(int) contentNameOf(item).length, contentNameOf(item).ptr, usesOf(item));
            problems += 1;
        }
    }
    return problems;
}
