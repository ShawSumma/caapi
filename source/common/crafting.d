module common.crafting;

import core.stdc.math : ceilf;
import base.array : Array;
import base.flags : Readiness;
import base.maybe : Maybe, MaybeIndex;
import base.names : enumNamed;
import base.numbers : lowerOf;
import base.stdio : printed;
import base.units : Time;
import common.biology.kinetics : Route;
import common.biology.metabolism : Enzyme, MotifCell, Operation, Presence, SITE_CELL, productOf;
import common.biology.molecule : Fragment, Molecule, Property, propertyBit;
import common.content.declarations : declare;
import common.content.graph : ContentGraph, PROBLEM_CAPACITY, targetOf;
import common.inventory : Inventory, Stack;
import common.items : Item, ItemKind, MATERIAL_KIND, WARE_KIND, WareInfo, itemOfNode, wareTable;
import common.material : ByteColor;
import plugins.api.api : Material;
import plugins.api.content : ContentRef, Holder;

enum uint MOST_INGREDIENTS = 2;
enum uint MOST_OPTIONS = 32;
enum uint MOST_PLAN_DEPTH = 4;
enum uint MOST_MAKERS = 8;
enum uint SET_WORDS = 8;
enum uint BITS_PER_SET_WORD = 32;

struct Station {
    ubyte id;
}

struct Upgrade {
    ubyte id;
}

struct Insight {
    ubyte id;
}

struct Synthesis {
    ubyte id;
}

enum Station HAND = Station(0);

struct IdSet {
    uint[SET_WORDS] words;

    bool has(uint id) const {
        return (words[id / BITS_PER_SET_WORD] & (1u << (id % BITS_PER_SET_WORD))) != 0;
    }

    void set(uint id) {
        words[id / BITS_PER_SET_WORD] |= 1u << (id % BITS_PER_SET_WORD);
    }
}

enum Product : ubyte {
    item,
    upgrade,
}

enum Trigger : ubyte {
    broke,
    worked,
}

enum Effect : ubyte {
    nothing,
    mining,
    assay,
}

enum Reaction : ubyte {
    extract,
    press,
    oxidize,
    conjugate,
    cleave,
    attach,
}

struct Ingredient {
    const(Item)[] options;
    const(char)[] label;
    uint count;

    const(Item)[] accepted() const return {
        return options;
    }
}

struct Recipe {
    Ingredient[MOST_INGREDIENTS] needs;
    Time time;
    const(char)[] name;
    Maybe!Insight insight;
    Item made;
    uint needed;
    uint yield;
    Upgrade upgrade;
    Station station;
    Product product;
}

struct StationInfo {
    const(char)[] name;
    Material block;
}

struct UpgradeInfo {
    const(char)[] name;
    const(char)[] title;
    uint tier;
    Effect effect;
}

struct InsightRule {
    const(char)[] name;
    const(char)[] title;
    const(char)[] notice;
    const(Item)[] noticed;
    Station station;
    Trigger trigger;
}

struct SynthesisRule {
    Time time;
    const(char)[] name;
    const(char)[] title;
    Item reagent;
    Fragment attached;
    Station station;
    Reaction reaction;
}

struct DoseRoute {
    const(char)[] name;
    const(char)[] title;
    Item device;
    uint uses;
    Route route;
}

struct Pending {
    uint first;
    uint count;
}

struct CraftingTables {
    Array!Recipe recipes;
    Array!Item pool;
    Array!StationInfo stations;
    Array!UpgradeInfo upgrades;
    Array!InsightRule insights;
    Array!SynthesisRule syntheses;
    Array!DoseRoute routes;
}

__gshared CraftingTables tables;

const(Recipe)[] recipes() {
    return tables.recipes.slice();
}

const(StationInfo)[] stations() {
    return tables.stations.slice();
}

const(UpgradeInfo)[] upgrades() {
    return tables.upgrades.slice();
}

const(InsightRule)[] insights() {
    return tables.insights.slice();
}

const(SynthesisRule)[] syntheses() {
    return tables.syntheses.slice();
}

const(DoseRoute)[] doseRoutes() {
    return tables.routes.slice();
}

Maybe!Station stationOf(Material material) {
    uint index = 1;
    while (index < tables.stations.length && tables.stations.ptr[index].block != material) {
        index += 1;
    }
    if (index < tables.stations.length) {
        return Maybe!Station.of(Station(cast(ubyte) index));
    } else {
        return Maybe!Station.init;
    }
}

bool isKnown(IdSet known, Maybe!Insight insight) {
    return !insight.exists || known.has(insight.value.id);
}

enum string CRAFTING_DECLARATIONS = "crafting.decl";

void declareCrafting(ref ContentGraph graph) {
    declare(graph, import(CRAFTING_DECLARATIONS), CRAFTING_DECLARATIONS);
}

ContentRef nodeRef(uint node) {
    return ContentRef(node, Holder.node);
}

ContentRef edgeRef(uint edge) {
    return ContentRef(edge, Holder.edge);
}

void buildCrafting(ref ContentGraph graph) {
    buildWares(graph);
    buildStations(graph);
    buildUpgrades(graph);
    Array!Pending pending;
    buildInsights(graph, pending);
    buildRecipes(graph, pending);
    settlePool(pending);
    pending.release();
    buildSyntheses(graph);
    buildRoutes(graph);
}

void buildWares(ref ContentGraph graph) {
    foreach (node, ref record; graph.nodes.slice()) {
        if (graph.isKind(cast(uint) node, WARE_KIND)) {
            ContentRef at = nodeRef(cast(uint) node);
            ByteColor color = ByteColor(cast(ubyte) graph.number(at, "red"), cast(ubyte) graph.number(at, "green"), cast(ubyte) graph.number(at, "blue"));
            wareTable.append(WareInfo(graph.nameOf(cast(uint) node), color));
        }
    }
}

void buildStations(ref ContentGraph graph) {
    foreach (node, ref record; graph.nodes.slice()) {
        if (graph.isKind(cast(uint) node, "station")) {
            MaybeIndex!uint block = targetOf(graph, cast(uint) node, "placed-as");
            Material placed = Material.none;
            if (block.exists) {
                placed = Material(cast(ubyte) graph.ordinalOf(block.value));
            }
            tables.stations.append(StationInfo(graph.nameOf(cast(uint) node), placed));
        }
    }
}

void buildUpgrades(ref ContentGraph graph) {
    foreach (node, ref record; graph.nodes.slice()) {
        if (graph.isKind(cast(uint) node, "upgrade")) {
            ContentRef at = nodeRef(cast(uint) node);
            tables.upgrades.append(UpgradeInfo(graph.nameOf(cast(uint) node), graph.textAt(at, "title"), cast(uint) graph.number(at, "mining-tier"), enumNamed!Effect(graph.textAt(at, "effect")).value));
        }
    }
}

Pending poolMembers(ref ContentGraph graph, uint target) {
    uint first = cast(uint) tables.pool.length;
    Maybe!Item single = itemOfNode(target);
    if (single.exists) {
        tables.pool.append(single.value);
    } else {
        foreach (edge; graph.edgesFrom(target)) {
            if (graph.isEdgeKind(edge, "member")) {
                Maybe!Item member = itemOfNode(graph.edges.ptr[edge].to);
                if (member.exists) {
                    tables.pool.append(member.value);
                }
            }
        }
    }
    uint count = cast(uint) tables.pool.length - first;
    if (count > MOST_OPTIONS) {
        char[PROBLEM_CAPACITY] buffer;
        const(char)[] name = graph.nameOf(target);
        graph.report(graph.nodes.ptr[target].owner, printed(buffer[], "'%.*s' accepts %u items, more than the %u a recipe can take", cast(int) name.length, name.ptr, count, MOST_OPTIONS));
        count = MOST_OPTIONS;
    }
    return Pending(first, count);
}

const(char)[] labelOf(ref const ContentGraph graph, uint target) {
    const(char)[] label = graph.textAt(nodeRef(target), "label");
    if (label is null) {
        return graph.nameOf(target);
    } else {
        return label;
    }
}

void buildInsights(ref ContentGraph graph, ref Array!Pending pending) {
    foreach (node, ref record; graph.nodes.slice()) {
        if (graph.isKind(cast(uint) node, "insight")) {
            ContentRef at = nodeRef(cast(uint) node);
            InsightRule rule = InsightRule(graph.nameOf(cast(uint) node), graph.textAt(at, "title"), graph.textAt(at, "notice"));
            MaybeIndex!uint station = targetOf(graph, cast(uint) node, "noticed-working");
            MaybeIndex!uint noticed = targetOf(graph, cast(uint) node, "noticed-breaking");
            Pending items = Pending(0, 0);
            if (station.exists) {
                rule.station = Station(cast(ubyte) graph.ordinalOf(station.value));
                rule.trigger = Trigger.worked;
            } else if (noticed.exists) {
                items = poolMembers(graph, noticed.value);
                rule.trigger = Trigger.broke;
            }
            pending.append(items);
            tables.insights.append(rule);
        }
    }
}

void buildRecipes(ref ContentGraph graph, ref Array!Pending pending) {
    foreach (node, ref record; graph.nodes.slice()) {
        if (graph.isKind(cast(uint) node, "recipe")) {
            buildRecipe(graph, cast(uint) node, pending);
        }
    }
}

void buildRecipe(ref ContentGraph graph, uint node, ref Array!Pending pending) {
    Recipe recipe;
    recipe.name = graph.nameOf(node);
    recipe.time = Time(cast(float) graph.number(nodeRef(node), "seconds"));
    recipe.station = HAND;
    foreach (edge; graph.edgesFrom(node)) {
        uint target = graph.edges.ptr[edge].to;
        if (graph.isEdgeKind(edge, "at")) {
            recipe.station = Station(cast(ubyte) graph.ordinalOf(target));
        } else if (graph.isEdgeKind(edge, "produces") && graph.isKind(target, "upgrade")) {
            recipe.product = Product.upgrade;
            recipe.upgrade = Upgrade(cast(ubyte) graph.ordinalOf(target));
            recipe.yield = 1;
        } else if (graph.isEdgeKind(edge, "produces")) {
            recipe.product = Product.item;
            recipe.made = itemOfNode(target).value;
            recipe.yield = cast(uint) graph.number(edgeRef(edge), "yield");
        } else if (graph.isEdgeKind(edge, "learned-by")) {
            recipe.insight = Maybe!Insight.of(Insight(cast(ubyte) graph.ordinalOf(target)));
        } else if (graph.isEdgeKind(edge, "consumes")) {
            pending.append(poolMembers(graph, target));
            recipe.needs[recipe.needed] = Ingredient(null, labelOf(graph, target), cast(uint) graph.number(edgeRef(edge), "count"));
            recipe.needed += 1;
        }
    }
    tables.recipes.append(recipe);
}

void settlePool(ref Array!Pending pending) {
    size_t next = 0;
    foreach (ref rule; tables.insights.slice()) {
        Pending items = pending.ptr[next];
        rule.noticed = tables.pool.slice()[items.first .. items.first + items.count];
        next += 1;
    }
    foreach (ref recipe; tables.recipes.slice()) {
        foreach (ref need; recipe.needs[0 .. recipe.needed]) {
            Pending items = pending.ptr[next];
            need.options = tables.pool.slice()[items.first .. items.first + items.count];
            next += 1;
        }
    }
}

Fragment fragmentNamed(const(char)[] name) {
    Maybe!Property property = enumNamed!Property(name);
    if (property.exists) {
        return Fragment.of(propertyBit(property.value));
    } else {
        return Fragment.init;
    }
}

void buildSyntheses(ref ContentGraph graph) {
    foreach (node, ref record; graph.nodes.slice()) {
        if (graph.isKind(cast(uint) node, "synthesis")) {
            ContentRef at = nodeRef(cast(uint) node);
            Reaction reaction = enumNamed!Reaction(graph.textAt(at, "operation")).value;
            SynthesisRule rule = SynthesisRule(Time(cast(float) graph.number(at, "seconds")), graph.nameOf(cast(uint) node), graph.textAt(at, "title"), Item.init, fragmentNamed(graph.textAt(at, "fragment")), HAND, reaction);
            MaybeIndex!uint station = targetOf(graph, cast(uint) node, "at");
            MaybeIndex!uint reagent = targetOf(graph, cast(uint) node, "reagent");
            if (station.exists) {
                rule.station = Station(cast(ubyte) graph.ordinalOf(station.value));
            }
            if (reagent.exists) {
                rule.reagent = itemOfNode(reagent.value).value;
            }
            tables.syntheses.append(rule);
        }
    }
}

void buildRoutes(ref ContentGraph graph) {
    foreach (node, ref record; graph.nodes.slice()) {
        if (graph.isKind(cast(uint) node, "dose-route")) {
            ContentRef at = nodeRef(cast(uint) node);
            DoseRoute made = DoseRoute(graph.nameOf(cast(uint) node), graph.textAt(at, "title"), Item.init, 0, enumNamed!Route(graph.textAt(at, "route")).value);
            foreach (edge; graph.edgesFrom(cast(uint) node)) {
                if (graph.isEdgeKind(edge, "needs-device")) {
                    made.device = itemOfNode(graph.edges.ptr[edge].to).value;
                    made.uses = cast(uint) graph.number(edgeRef(edge), "uses");
                }
            }
            tables.routes.append(made);
        }
    }
}

Enzyme reactionOf(ref const SynthesisRule rule) {
    Enzyme enzyme;
    enzyme.motif[SITE_CELL] = MotifCell(0, 0, Presence.filled);
    final switch (rule.reaction) {
        case Reaction.extract:
        case Reaction.press:
            break;
        case Reaction.oxidize:
            enzyme.operation = Operation.oxidize;
            break;
        case Reaction.conjugate:
            enzyme.operation = Operation.conjugate;
            break;
        case Reaction.cleave:
            enzyme.operation = Operation.cleave;
            break;
        case Reaction.attach:
            enzyme.operation = Operation.attach;
            enzyme.attached = rule.attached;
            enzyme.motif[SITE_CELL] = MotifCell(0, 0, Presence.empty);
            break;
    }
    return enzyme;
}

Maybe!Molecule synthesized(Molecule molecule, Synthesis synthesis) {
    const(SynthesisRule)* rule = &tables.syntheses.ptr[synthesis.id];
    if (rule.reaction == Reaction.press || rule.reaction == Reaction.extract) {
        return Maybe!Molecule.of(molecule);
    } else {
        return reactionOf(*rule).productOf(molecule);
    }
}

bool actsOnCompounds(ref const SynthesisRule rule) {
    return rule.reaction != Reaction.extract;
}

enum CraftKind : ubyte {
    recipe,
    synthesis,
}

struct Taken {
    ushort[MOST_OPTIONS][MOST_INGREDIENTS] counts;
}

struct Crafting {
    Taken taken;
    Molecule molecule;
    Time left;
    uint index;
    CraftKind kind;
    Readiness started;
    Stack pressed;
}

Station stationOf(ref const Crafting crafting) {
    final switch (crafting.kind) {
        case CraftKind.recipe:
            return tables.recipes.ptr[crafting.index].station;
        case CraftKind.synthesis:
            return tables.syntheses.ptr[crafting.index].station;
    }
}

Time timeOf(ref const Crafting crafting) {
    final switch (crafting.kind) {
        case CraftKind.recipe:
            return tables.recipes.ptr[crafting.index].time;
        case CraftKind.synthesis:
            return tables.syntheses.ptr[crafting.index].time;
    }
}

bool canCraft(ref const Inventory inventory, ref const Recipe recipe) {
    uint index = 0;
    while (index < recipe.needed && inventory.countAmong(recipe.needs[index].accepted) >= recipe.needs[index].count) {
        index += 1;
    }
    return index == recipe.needed;
}

Maybe!Taken takeIngredients(ref Inventory inventory, ref const Recipe recipe) {
    if (!inventory.canCraft(recipe)) {
        return Maybe!Taken.init;
    } else {
        Taken taken;
        foreach (need, ref ingredient; recipe.needs[0 .. recipe.needed]) {
            uint left = ingredient.count;
            foreach (option, item; ingredient.accepted) {
                uint spent = lowerOf(left, inventory.countOf(item));
                inventory.spend(item, spent);
                taken.counts[need][option] = cast(ushort) spent;
                left -= spent;
            }
        }
        return Maybe!Taken.of(taken);
    }
}

void returnIngredients(ref Inventory inventory, ref const Recipe recipe, ref const Taken taken) {
    foreach (need, ref ingredient; recipe.needs[0 .. recipe.needed]) {
        foreach (option, item; ingredient.accepted) {
            inventory.gain(Stack(item, taken.counts[need][option]));
        }
    }
}

struct Shortfall {
    const(char)[] label;
    uint count;
}

Inventory projected(ref const Inventory inventory, const(Crafting)[] queue) {
    Inventory stock = inventory;
    foreach (ref crafting; queue) {
        if (crafting.kind == CraftKind.recipe && crafting.started == Readiness.pending) {
            const(Recipe)* recipe = &tables.recipes.ptr[crafting.index];
            foreach (ref need; recipe.needs[0 .. recipe.needed]) {
                stock.spendAmong(need.accepted, need.count);
            }
        }
        if (crafting.kind == CraftKind.recipe && tables.recipes.ptr[crafting.index].product == Product.item) {
            stock.gain(Stack(tables.recipes.ptr[crafting.index].made, tables.recipes.ptr[crafting.index].yield));
        }
    }
    return stock;
}

uint makersOf(Item item, IdSet known, ref uint[MOST_MAKERS] makers) {
    uint count = 0;
    foreach (index, ref recipe; recipes()) {
        if (count < MOST_MAKERS && recipe.product == Product.item && recipe.made == item && known.isKnown(recipe.insight)) {
            uint at = count;
            while (at > 0 && tables.recipes.ptr[makers[at - 1]].yield < recipe.yield) {
                makers[at] = makers[at - 1];
                at -= 1;
            }
            makers[at] = cast(uint) index;
            count += 1;
        }
    }
    return count;
}

Shortfall planNeed(ref Inventory stock, Item item, Shortfall missing, ref Array!uint plan, uint depth, IdSet known) {
    uint[MOST_MAKERS] makers;
    uint count = 0;
    if (depth < MOST_PLAN_DEPTH) {
        count = makersOf(item, known, makers);
    }
    Shortfall reported = missing;
    uint reportedFrom = cast(uint) tables.recipes.length;
    foreach (maker; makers[0 .. count]) {
        Inventory trial = stock;
        size_t mark = plan.length;
        uint batches = cast(uint) ceilf(cast(float) missing.count / tables.recipes.ptr[maker].yield);
        Shortfall inner = planRecipe(trial, maker, batches, plan, depth + 1, known);
        if (inner.count == 0) {
            stock = trial;
            return Shortfall.init;
        }
        plan.length = mark;
        if (maker < reportedFrom) {
            reported = inner;
            reportedFrom = maker;
        }
    }
    return reported;
}

Shortfall planRecipe(ref Inventory stock, uint recipe, uint times, ref Array!uint plan, uint depth, IdSet known) {
    const(Recipe)* chosen = &tables.recipes.ptr[recipe];
    foreach (ref need; chosen.needs[0 .. chosen.needed]) {
        uint wanted = need.count * times;
        uint have = stock.countAmong(need.accepted);
        if (have < wanted) {
            Shortfall inner = planNeed(stock, need.options[0], Shortfall(need.label, wanted - have), plan, depth, known);
            if (inner.count > 0) {
                return inner;
            }
        }
    }
    foreach (ref need; chosen.needs[0 .. chosen.needed]) {
        stock.spendAmong(need.accepted, need.count * times);
    }
    foreach (_; 0 .. times) {
        plan.append(recipe);
    }
    if (chosen.product == Product.item) {
        stock.gain(Stack(chosen.made, chosen.yield * times));
    }
    return Shortfall.init;
}
