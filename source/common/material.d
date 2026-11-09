module common.material;

import base.array : Array;
import base.maybe : Maybe, MaybeIndex;
import base.murmur : murmurHash3;
import base.stdio : printed;
import common.content.declarations : declare;
import common.content.graph : ContentGraph, ENGINE_OWNER, PROBLEM_CAPACITY;
import common.items : materialNames;
import common.perception : CHANNEL_NAMES, Channel;
import plugins.api.api : MOST_MATERIALS, Material;
import plugins.api.content : ContentRef, Holder;

enum string MATERIAL_KIND = "material";
enum string FAMILY_KIND = "hidden-family";
enum string CHANNEL_KIND = "channel";

enum string MATERIAL_DECLARATIONS = "material.decl";

void declareMaterials(ref ContentGraph graph) {
    declare(graph, import(MATERIAL_DECLARATIONS), MATERIAL_DECLARATIONS);
}

Material materialOfNode(ref const ContentGraph graph, uint node) {
    return Material(cast(ubyte) graph.ordinalOf(node));
}

enum uint BITS_PER_WORD = 32;
enum uint MATERIAL_WORDS = MOST_MATERIALS / BITS_PER_WORD;

uint materialCount() {
    return cast(uint) materialNames.length;
}

struct ByteColor {
    ubyte red;
    ubyte green;
    ubyte blue;
}

struct MaterialSet {
    uint[MATERIAL_WORDS] words;
}

struct Family {
    const(char)[] name;
    MaterialSet members;
    Channel channel;
}

__gshared Array!float breakSeconds;
__gshared Array!uint miningTiers;
__gshared Array!ByteColor materialColors;
__gshared Array!float grains;
__gshared Array!ulong nameHashes;
__gshared Array!(MaybeIndex!uint) familyOfMaterial;
__gshared Array!Family families;
__gshared MaterialSet seeThrough;
__gshared MaterialSet glowing;
__gshared MaterialSet hidden;
__gshared MaterialSet plainSolid;
__gshared MaterialSet living;
__gshared MaterialSet plants;
__gshared MaterialSet fluids;

bool has(MaterialSet set, Material material) {
    return (set.words[material.id / BITS_PER_WORD] & (1u << (material.id % BITS_PER_WORD))) != 0;
}

MaterialSet including(MaterialSet set, Material material) {
    MaterialSet made = set;
    made.words[material.id / BITS_PER_WORD] |= 1u << (material.id % BITS_PER_WORD);
    return made;
}

MaterialSet joined(MaterialSet set, MaterialSet other) {
    MaterialSet made = set;
    foreach (index; 0 .. MATERIAL_WORDS) {
        made.words[index] |= other.words[index];
    }
    return made;
}

MaterialSet within(MaterialSet set, MaterialSet other) {
    MaterialSet made = set;
    foreach (index; 0 .. MATERIAL_WORDS) {
        made.words[index] &= other.words[index];
    }
    return made;
}

bool isEmpty(MaterialSet set) {
    uint index = 0;
    while (index < MATERIAL_WORDS && set.words[index] == 0) {
        index += 1;
    }
    return index == MATERIAL_WORDS;
}

MaterialSet without(MaterialSet set, MaterialSet other) {
    MaterialSet made = set;
    foreach (index; 0 .. MATERIAL_WORDS) {
        made.words[index] &= ~other.words[index];
    }
    return made;
}

ulong nameHashOf(Material material) {
    return nameHashes.ptr[material.id];
}

MaybeIndex!uint hiddenFamilyOf(Material material) {
    return familyOfMaterial.ptr[material.id];
}

bool isHidden(Material material) {
    return hidden.has(material);
}

bool isSameHiddenFamily(Material material, Material beside) {
    MaybeIndex!uint own = hiddenFamilyOf(material);
    MaybeIndex!uint other = hiddenFamilyOf(beside);
    return own.exists && other.exists && own.value == other.value;
}

bool isSeeThrough(Material material) {
    return material == Material.none || seeThrough.has(material) || hidden.has(material);
}

bool isShownAgainst(Material material, Material beside) {
    return material != Material.none && isSeeThrough(beside) && !(seeThrough.has(material) && material == beside) && !isSameHiddenFamily(material, beside);
}

bool isOccluding(Material material) {
    return material != Material.none && !hidden.has(material);
}

bool isGlowing(Material material) {
    return glowing.has(material);
}

bool isPlant(Material material) {
    return plants.has(material);
}

bool isLiving(Material material) {
    return living.has(material);
}

MaterialSet withTrait(MaterialSet set, ref const ContentGraph graph, ContentRef at, Material material, string trait) {
    if (graph.number(at, trait) != 0) {
        return set.including(material);
    } else {
        return set;
    }
}

ubyte channelOf(ref const ContentGraph graph, ContentRef at, string key) {
    return cast(ubyte) graph.number(at, key);
}

void addMaterial(ref ContentGraph graph, uint node) {
    ContentRef at = ContentRef(node, Holder.node);
    Material material = materialOfNode(graph, node);
    materialNames.append(graph.nameOf(node));
    breakSeconds.append(cast(float) graph.number(at, "break-seconds"));
    miningTiers.append(cast(uint) graph.number(at, "mining-tier"));
    materialColors.append(ByteColor(channelOf(graph, at, "red"), channelOf(graph, at, "green"), channelOf(graph, at, "blue")));
    grains.append(cast(float) graph.number(at, "grain"));
    nameHashes.append(murmurHash3(cast(const(ubyte)[]) graph.nameOf(node)).first);
    familyOfMaterial.append(MaybeIndex!uint.init);
    seeThrough = seeThrough.withTrait(graph, at, material, "see-through");
    glowing = glowing.withTrait(graph, at, material, "glows");
    living = living.withTrait(graph, at, material, "living");
    plants = plants.withTrait(graph, at, material, "plant");
    fluids = fluids.withTrait(graph, at, material, "fluid");
}

MaybeIndex!uint channelNamed(const(char)[] name) {
    uint index = 0;
    while (index < CHANNEL_NAMES.length && CHANNEL_NAMES[index] != name) {
        index += 1;
    }
    if (index < CHANNEL_NAMES.length) {
        return MaybeIndex!uint.of(index);
    } else {
        return MaybeIndex!uint.init;
    }
}

void addFamily(ref ContentGraph graph, uint node) {
    MaybeIndex!uint channel;
    foreach (edge; graph.edgesFrom(node)) {
        if (graph.isEdgeKind(edge, "revealed-by") && graph.isKind(graph.edges.ptr[edge].to, CHANNEL_KIND)) {
            channel = channelNamed(graph.nameOf(graph.edges.ptr[edge].to));
        }
    }
    if (!channel.exists) {
        char[PROBLEM_CAPACITY] buffer;
        const(char)[] name = graph.nameOf(node);
        graph.report(graph.nodes.ptr[node].owner, printed(buffer[], "the hidden family '%.*s' is revealed by no channel perception has", cast(int) name.length, name.ptr));
    } else {
        families.append(Family(graph.nameOf(node), MaterialSet.init, cast(Channel) channel.value));
    }
}

void joinFamily(ref ContentGraph graph, uint node) {
    foreach (edge; graph.edgesFrom(node)) {
        uint family = graph.edges.ptr[edge].to;
        if (graph.isEdgeKind(edge, "hidden-in") && graph.isKind(family, FAMILY_KIND)) {
            uint index = 0;
            while (index < families.length && families.ptr[index].name != graph.nameOf(family)) {
                index += 1;
            }
            if (index < families.length) {
                Material material = materialOfNode(graph, node);
                families.ptr[index].members = families.ptr[index].members.including(material);
                familyOfMaterial.ptr[material.id] = MaybeIndex!uint.of(index);
                hidden = hidden.including(material);
            }
        }
    }
}

void buildMaterials(ref ContentGraph graph) {
    uint count = graph.countOf(MATERIAL_KIND);
    if (count > MOST_MATERIALS) {
        char[PROBLEM_CAPACITY] buffer;
        graph.report(graph.intern(ENGINE_OWNER), printed(buffer[], "the mods define %u materials, and a voxel holds at most %u", count, MOST_MATERIALS));
    } else {
        foreach (index; 0 .. cast(uint) graph.nodes.length) {
            if (graph.isKind(index, MATERIAL_KIND)) {
                addMaterial(graph, index);
            } else if (graph.isKind(index, FAMILY_KIND)) {
                addFamily(graph, index);
            }
        }
        foreach (index; 0 .. cast(uint) graph.nodes.length) {
            if (graph.isKind(index, MATERIAL_KIND)) {
                joinFamily(graph, index);
            }
        }
        foreach (index; 1 .. materialCount()) {
            if (!hidden.has(Material(cast(ubyte) index))) {
                plainSolid = plainSolid.including(Material(cast(ubyte) index));
            }
        }
    }
}
