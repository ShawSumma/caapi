module common.worldgen.palette;

import base.array : Array;
import base.maybe : Maybe, MaybeIndex;
import base.names : enumNamed;
import base.stdio : printed;
import common.content.declarations : declare;
import common.content.graph : ContentGraph, PROBLEM_CAPACITY, targetOf;
import common.material : MaterialSet, has, including, materialCount, materialOfNode;
import plugins.api.api : Form, Material, Part;
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
    Form form;
    ubyte minTrunk;
    ubyte trunkChoices;
    ubyte reach;
}

struct NamedForm {
    const(char)[] name;
    Form form;
}

Part shapeless(int trunk, int level, int across, int along) {
    return Part.none;
}

enum Layer : ubyte {
    missing,
    laid,
}

enum Drift : ubyte {
    broad,
    local,
    heat,
    wetness,
    strata,
    ruggedness,
    shield,
}

enum uint DRIFT_COUNT = Drift.max + 1;
immutable string[DRIFT_COUNT] DRIFT_NAMES = ["broad", "local", "heat", "wetness", "strata", "ruggedness", "shield"];

struct Shape {
    float[DRIFT_COUNT] keep = 0;
    float[DRIFT_COUNT] spread = 0;
    float ruggedThreshold = 0;
    float mountainHeight = 0;
    float lapseRate = 0;
    float coverDepth = 0;
    float soilDepth = 0;
    float waterLevel = 0;
    float warmthClassLimit = 0;
    float[ROCK_BANDS - 1] rockBandDepths = 0;
    float[WETNESS_CLASSES - 1] wetnessClassLimits = 0;
    float baseTreeDensity = 0;
    float wetnessPerTreeDensity = 0;
    float leastTreeDensity = 0;
    float mostTreeDensity = 0;
    float plantDensity = 0;
    float veinOdds = 0;
    float veinFill = 0;
    int veinRadius;
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
    const(char)[] world;
    Shape shape;
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

enum string PALETTE_SOURCE = "common/worldgen/palette.d";
enum string CLIME_FIELDS = `
    warmth-above: number?
    warmth-below: number?
    wetness-above: number?
    wetness-below: number?
    relief-above: number?
    relief-below: number?
    order: number = 0
    lays: one -> material
`;
enum string PALETTE_DECLARATIONS = "kind cover-rule {" ~ CLIME_FIELDS ~ "}\nkind soil-rule {" ~ CLIME_FIELDS ~ "}\nkind fluid-rule {" ~ CLIME_FIELDS ~ "}\nkind plant-rule {" ~ CLIME_FIELDS ~ "}\n" ~ `
kind tree-rule {
    warmth-above: number?
    warmth-below: number?
    wetness-above: number?
    wetness-below: number?
    order: number = 0
    one-in: integer 1..?
    draw: "roll" | "choice"?
    picks: some -> tree
}

kind rock-layer {
    band: integer 0..3
    wetness-class: integer 0..2
    warmth-class: integer 0..1
    lays: one -> material
}

kind tree {
    shape: text
    trunk: integer 0..255 = 0
    trunk-choices: integer 1..255 = 1
    reach: integer 0..255 = 1
    wood: one -> material
    leaves: optional -> material
    heart: optional -> material
    grows-on: many -> material | group
}

kind terrain {
    flat-fill: one -> material
    stand-in: one -> material
    world: text?
    broad-keep: number 0..1
    broad-spread: number 0..
    local-keep: number 0..1
    local-spread: number 0..
    heat-keep: number 0..1
    heat-spread: number 0..
    wetness-keep: number 0..1
    wetness-spread: number 0..
    strata-keep: number 0..1
    strata-spread: number 0..
    ruggedness-keep: number 0..1
    ruggedness-spread: number 0..
    shield-keep: number 0..1
    shield-spread: number 0..
    rugged-threshold: number
    mountain-height: number 0..
    lapse-rate: number
    cover-depth: number 0..
    soil-depth: number 0..
    water-level: number
    warmth-class-limit: number
    rock-band-1: number 0..
    rock-band-2: number 0..
    rock-band-3: number 0..
    wetness-limit-1: number
    wetness-limit-2: number
    base-tree-density: number 0..1
    wetness-per-tree-density: number
    least-tree-density: number 0..1
    most-tree-density: number 0..1
    plant-density: number 0..1
    vein-odds: number 0..1
    vein-fill: number 0..1
    vein-radius: integer 0..
}

extend material {
    grows-on: many -> material | group
    vein-in: many -> material
}
`;

static assert(ROCK_BANDS == 4 && WETNESS_CLASSES == 3 && WARMTH_CLASSES == 2);

void declarePalette(ref ContentGraph graph) {
    declare(graph, PALETTE_DECLARATIONS, PALETTE_SOURCE);
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

Form formOf(ref ContentGraph graph, uint node, const(NamedForm)[] forms) {
    const(char)[] shape = graph.textAt(ContentRef(node, Holder.node), "shape");
    uint index = 0;
    while (index < forms.length && forms[index].name != shape) {
        index += 1;
    }
    if (index < forms.length) {
        return forms[index].form;
    } else {
        char[PROBLEM_CAPACITY] buffer;
        const(char)[] name = graph.nameOf(node);
        graph.report(graph.nodes.ptr[node].owner, printed(buffer[], "the tree '%.*s' has the shape '%.*s', which no plugin registers", cast(int) name.length, name.ptr, cast(int) shape.length, shape.ptr));
        return Form(&shapeless, 0);
    }
}

Tree treeNodeOf(ref ContentGraph graph, uint node, const(NamedForm)[] forms) {
    ContentRef at = ContentRef(node, Holder.node);
    return Tree(groundOf(graph, node), materialAlong(graph, node, "wood"), materialAlong(graph, node, "leaves"), materialAlong(graph, node, "heart"), formOf(graph, node, forms),cast(ubyte) graph.number(at, "trunk"), cast(ubyte) graph.number(at, "trunk-choices"), cast(ubyte) graph.number(at, "reach"));
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

float numberAt(ref const ContentGraph graph, ContentRef at, const(char)[] key) {
    return cast(float) graph.number(at, key);
}

Shape shapeOf(ref const ContentGraph graph, ContentRef at) {
    Shape shape;
    foreach (drift, name; DRIFT_NAMES) {
        char[PROBLEM_CAPACITY] buffer;
        shape.keep[drift] = numberAt(graph, at, printed(buffer[], "%.*s-keep", cast(int) name.length, name.ptr));
        shape.spread[drift] = numberAt(graph, at, printed(buffer[], "%.*s-spread", cast(int) name.length, name.ptr));
    }
    shape.ruggedThreshold = numberAt(graph, at, "rugged-threshold");
    shape.mountainHeight = numberAt(graph, at, "mountain-height");
    shape.lapseRate = numberAt(graph, at, "lapse-rate");
    shape.coverDepth = numberAt(graph, at, "cover-depth");
    shape.soilDepth = numberAt(graph, at, "soil-depth");
    shape.waterLevel = numberAt(graph, at, "water-level");
    shape.warmthClassLimit = numberAt(graph, at, "warmth-class-limit");
    shape.rockBandDepths = [numberAt(graph, at, "rock-band-1"), numberAt(graph, at, "rock-band-2"), numberAt(graph, at, "rock-band-3")];
    shape.wetnessClassLimits = [numberAt(graph, at, "wetness-limit-1"), numberAt(graph, at, "wetness-limit-2")];
    shape.baseTreeDensity = numberAt(graph, at, "base-tree-density");
    shape.wetnessPerTreeDensity = numberAt(graph, at, "wetness-per-tree-density");
    shape.leastTreeDensity = numberAt(graph, at, "least-tree-density");
    shape.mostTreeDensity = numberAt(graph, at, "most-tree-density");
    shape.plantDensity = numberAt(graph, at, "plant-density");
    shape.veinOdds = numberAt(graph, at, "vein-odds");
    shape.veinFill = numberAt(graph, at, "vein-fill");
    shape.veinRadius = cast(int) graph.number(at, "vein-radius");
    return shape;
}

uint addTerrain(ref ContentGraph graph, uint node, uint terrains) {
    ContentRef at = ContentRef(node, Holder.node);
    palette.flatFill = materialAlong(graph, node, "flat-fill");
    palette.standIn = materialAlong(graph, node, "stand-in");
    palette.world = graph.textAt(at, "world");
    palette.shape = shapeOf(graph, at);
    return terrains + 1;
}

void buildPalette(ref ContentGraph graph, uint owner, const(NamedForm)[] forms) {
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
            palette.trees.append(treeNodeOf(graph, index, forms));
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
