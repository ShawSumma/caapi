module common.worldgen.palette;

import base.array : Array;
import base.maybe : Maybe, MaybeIndex;
import base.names : enumNamed;
import base.stdio : printed;
import common.content.declarations : declare;
import common.content.graph : ContentGraph, PROBLEM_CAPACITY, targetOf;
import common.material : MaterialSet, has, including, materialCount, materialOfNode;
import common.worldgen.generation : TreeShape;
import plugins.api.api : Material;
import plugins.api.content : ContentRef, Holder;

enum string MATERIAL = "material";
enum string TREE = "tree";
enum string GROUP = "group";
enum uint ROCK_BANDS = 4;
enum uint WETNESS_CLASSES = 3;
enum uint WARMTH_CLASSES = 2;
enum ulong CHOICE_SHIFT = 8;

struct Bounds {
    float low = -float.infinity;
    float high = float.infinity;
}

bool holds(Bounds bounds, float value) {
    return value > bounds.low && value < bounds.high;
}

struct ClimeRule {
    Bounds warmth;
    Bounds wetness;
    Bounds relief;
    double order;
    Material material;

    bool admits(float warmthHere, float wetnessHere, float reliefHere) const {
        return warmth.holds(warmthHere) && wetness.holds(wetnessHere) && relief.holds(reliefHere);
    }
}

enum Draw : ubyte {
    always,
    roll,
    choice,
}

struct TreeRule {
    Bounds warmth;
    Bounds wetness;
    double order;
    uint firstPick;
    uint pickCount;
    uint oneIn;
    Draw draw;

    bool admits(float warmthHere, float wetnessHere, ulong roll) const {
        return warmth.holds(warmthHere) && wetness.holds(wetnessHere) && isDrawn(roll);
    }

    bool isDrawn(ulong roll) const {
        final switch (draw) {
            case Draw.always:
                return true;
            case Draw.roll:
                return roll % oneIn == 0;
            case Draw.choice:
                return (roll >> CHOICE_SHIFT) % oneIn == 0;
        }
    }
}

struct Tree {
    MaterialSet ground;
    Material wood;
    Material leaves;
    Material heart;
    TreeShape shape;
    ubyte minTrunk;
    ubyte trunkChoices;
    ubyte reach;
}

enum Layer : ubyte {
    missing,
    laid,
}

struct Palette {
    Array!ClimeRule cover;
    Array!ClimeRule soil;
    Array!ClimeRule fluids;
    Array!ClimeRule plants;
    Array!TreeRule treeRules;
    Array!uint picks;
    Array!Tree trees;
    Array!MaterialSet plantGrounds;
    Array!Material ores;
    Material[WARMTH_CLASSES][WETNESS_CLASSES][ROCK_BANDS] rocks;
    Layer[WARMTH_CLASSES][WETNESS_CLASSES][ROCK_BANDS] layers;
    Material flatFill;
    Material standIn;
}

__gshared Palette palette;

Material laidBy(const(ClimeRule)[] rules, float warmth, float wetness, float relief) {
    size_t index = 0;
    while (index < rules.length && !rules[index].admits(warmth, wetness, relief)) {
        index += 1;
    }
    if (index < rules.length) {
        return rules[index].material;
    } else if (rules.length > 0) {
        return rules[$ - 1].material;
    } else {
        return Material.none;
    }
}

bool hasTrees() {
    return palette.treeRules.length > 0;
}

uint treeAt(float warmth, float wetness, ulong roll) {
    const(TreeRule)[] rules = palette.treeRules.slice();
    size_t index = 0;
    while (index < rules.length && !rules[index].admits(warmth, wetness, roll)) {
        index += 1;
    }
    if (index == rules.length) {
        index = rules.length - 1;
    }
    ulong choice = roll >> CHOICE_SHIFT;
    return palette.picks.ptr[rules[index].firstPick + cast(uint)(choice % rules[index].pickCount)];
}

ref const(Tree) treeOf(uint tree) {
    return palette.trees.ptr[tree];
}

bool isGroundFor(uint tree, Material material) {
    return palette.trees.ptr[tree].ground.has(material);
}

bool isGroundForPlant(Material plant, Material material) {
    return palette.plantGrounds.ptr[plant.id].has(material);
}

Material oreFor(Material rock) {
    return palette.ores.ptr[rock.id];
}

enum string PALETTE_DECLARATIONS = "worldgen/palette.decl";

void declarePalette(ref ContentGraph graph) {
    declare(graph, import(PALETTE_DECLARATIONS), PALETTE_DECLARATIONS);
}

Material materialAlong(ref const ContentGraph graph, uint node, const(char)[] kind) {
    MaybeIndex!uint target = targetOf(graph, node, kind);
    if (target.exists) {
        return materialOfNode(graph, target.value);
    } else {
        return Material.none;
    }
}

Material laidMaterial(ref const ContentGraph graph, uint node) {
    return materialAlong(graph, node, "lays");
}

Bounds boundsOf(ref const ContentGraph graph, ContentRef at, string above, string below) {
    return Bounds(cast(float) graph.numberOr(at, above, -float.infinity), cast(float) graph.numberOr(at, below, float.infinity));
}

ClimeRule climeRuleOf(ref ContentGraph graph, uint node) {
    ContentRef at = ContentRef(node, Holder.node);
    return ClimeRule(boundsOf(graph, at, "warmth-above", "warmth-below"), boundsOf(graph, at, "wetness-above", "wetness-below"), boundsOf(graph, at, "relief-above", "relief-below"), graph.number(at, "order"), laidMaterial(graph, node));
}

void sortByOrder(T)(T[] rules) {
    foreach (index; 1 .. rules.length) {
        T rule = rules[index];
        size_t at = index;
        while (at > 0 && rules[at - 1].order > rule.order) {
            rules[at] = rules[at - 1];
            at -= 1;
        }
        rules[at] = rule;
    }
}

MaterialSet groundOf(ref const ContentGraph graph, uint node) {
    MaterialSet ground;
    foreach (edge; graph.edgesFrom(node)) {
        uint target = graph.edges.ptr[edge].to;
        if (graph.isEdgeKind(edge, "grows-on") && graph.isKind(target, MATERIAL)) {
            ground = ground.including(materialOfNode(graph, target));
        } else if (graph.isEdgeKind(edge, "grows-on") && graph.isKind(target, GROUP)) {
            foreach (member; graph.edgesFrom(target)) {
                uint inside = graph.edges.ptr[member].to;
                if (graph.isEdgeKind(member, "member") && graph.isKind(inside, MATERIAL)) {
                    ground = ground.including(materialOfNode(graph, inside));
                }
            }
        }
    }
    return ground;
}

Tree treeNodeOf(ref ContentGraph graph, uint node) {
    ContentRef at = ContentRef(node, Holder.node);
    TreeShape shape = enumNamed!TreeShape(graph.textAt(at, "shape")).value;
    return Tree(groundOf(graph, node), materialAlong(graph, node, "wood"), materialAlong(graph, node, "leaves"), materialAlong(graph, node, "heart"), shape, cast(ubyte) graph.number(at, "trunk"), cast(ubyte) graph.number(at, "trunk-choices"), cast(ubyte) graph.number(at, "reach"));
}

Draw drawOf(ref ContentGraph graph, uint node) {
    ContentRef at = ContentRef(node, Holder.node);
    const(char)[] text = graph.textAt(at, "draw");
    bool drawn = graph.numberOf(at, "one-in").exists;
    if (!drawn && text is null) {
        return Draw.always;
    } else if (drawn && text !is null) {
        return enumNamed!Draw(text).value;
    } else {
        char[PROBLEM_CAPACITY] buffer;
        const(char)[] name = graph.nameOf(node);
        graph.report(graph.nodes.ptr[node].owner, printed(buffer[], "the tree rule '%.*s' needs both one-in and draw, or neither", cast(int) name.length, name.ptr));
        return Draw.always;
    }
}

void addTreeRule(ref ContentGraph graph, uint node) {
    ContentRef at = ContentRef(node, Holder.node);
    uint first = cast(uint) palette.picks.length;
    foreach (edge; graph.edgesFrom(node)) {
        if (graph.isEdgeKind(edge, "picks")) {
            palette.picks.append(graph.ordinalOf(graph.edges.ptr[edge].to));
        }
    }
    uint count = cast(uint) palette.picks.length - first;
    palette.treeRules.append(TreeRule(boundsOf(graph, at, "warmth-above", "warmth-below"), boundsOf(graph, at, "wetness-above", "wetness-below"), graph.number(at, "order"), first, count, cast(uint) graph.numberOr(at, "one-in", 0), drawOf(graph, node)));
}

void addRockLayer(ref ContentGraph graph, uint node) {
    ContentRef at = ContentRef(node, Holder.node);
    uint band = cast(uint) graph.number(at, "band");
    uint wetness = cast(uint) graph.number(at, "wetness-class");
    uint warmth = cast(uint) graph.number(at, "warmth-class");
    palette.rocks[band][wetness][warmth] = laidMaterial(graph, node);
    palette.layers[band][wetness][warmth] = Layer.laid;
}

void addMaterialTerrain(ref ContentGraph graph, uint node) {
    Material material = materialOfNode(graph, node);
    palette.plantGrounds.ptr[material.id] = groundOf(graph, node);
    foreach (edge; graph.edgesFrom(node)) {
        if (graph.isEdgeKind(edge, "vein-in")) {
            palette.ores.ptr[materialOfNode(graph, graph.edges.ptr[edge].to).id] = material;
        }
    }
}

uint addTerrain(ref ContentGraph graph, uint node, uint terrains) {
    palette.flatFill = materialAlong(graph, node, "flat-fill");
    palette.standIn = materialAlong(graph, node, "stand-in");
    return terrains + 1;
}

void buildPalette(ref ContentGraph graph, uint owner) {
    palette.plantGrounds.resize(materialCount());
    palette.ores.resize(materialCount());
    foreach (index; 0 .. materialCount()) {
        palette.plantGrounds.ptr[index] = MaterialSet.init;
        palette.ores.ptr[index] = Material.none;
    }
    uint terrains = 0;
    foreach (index; 0 .. cast(uint) graph.nodes.length) {
        if (graph.isKind(index, "cover-rule")) {
            palette.cover.append(climeRuleOf(graph, index));
        } else if (graph.isKind(index, "soil-rule")) {
            palette.soil.append(climeRuleOf(graph, index));
        } else if (graph.isKind(index, "fluid-rule")) {
            palette.fluids.append(climeRuleOf(graph, index));
        } else if (graph.isKind(index, "plant-rule")) {
            palette.plants.append(climeRuleOf(graph, index));
        } else if (graph.isKind(index, "tree-rule")) {
            addTreeRule(graph, index);
        } else if (graph.isKind(index, "rock-layer")) {
            addRockLayer(graph, index);
        } else if (graph.isKind(index, TREE)) {
            palette.trees.append(treeNodeOf(graph, index));
        } else if (graph.isKind(index, MATERIAL)) {
            addMaterialTerrain(graph, index);
        } else if (graph.isKind(index, "terrain")) {
            terrains = addTerrain(graph, index, terrains);
        }
    }
    sortByOrder(palette.cover.slice());
    sortByOrder(palette.soil.slice());
    sortByOrder(palette.fluids.slice());
    sortByOrder(palette.plants.slice());
    sortByOrder(palette.treeRules.slice());
    reportGaps(graph, owner, terrains);
}

void reportGaps(ref ContentGraph graph, uint owner, uint terrains) {
    char[PROBLEM_CAPACITY] buffer;
    if (terrains != 1) {
        graph.report(owner, printed(buffer[], "the mods define %u terrains, and the terrain reads exactly one", terrains));
    }
    if (palette.cover.length == 0 || palette.soil.length == 0 || palette.fluids.length == 0) {
        graph.report(owner, printed(buffer[], "the terrain needs at least one cover, soil and fluid rule"));
    }
    foreach (band; 0 .. ROCK_BANDS) {
        foreach (wetness; 0 .. WETNESS_CLASSES) {
            foreach (warmth; 0 .. WARMTH_CLASSES) {
                if (palette.layers[band][wetness][warmth] == Layer.missing) {
                    graph.report(owner, printed(buffer[], "no mod lays rock in band %u, wetness class %u, warmth class %u", band, wetness, warmth));
                }
            }
        }
    }
}
