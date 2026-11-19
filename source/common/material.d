module common.material;

import base.array : Array;
import base.maybe : Maybe, MaybeIndex;
import base.murmur : murmurHash3;
import base.stdio : printed;
import common.content.declarations : declare;
import common.content.graph : ContentGraph, ENGINE_OWNER, PROBLEM_CAPACITY;
import plugins.api.api : MOST_MATERIALS, Material;
import plugins.api.content : ContentRef, Holder;

enum string MATERIAL_KIND = "material";
enum string FAMILY_KIND = "hidden-family";
enum uint MOST_FAMILIES = 8;

enum string MATERIAL_SOURCE = "common/material.d";
enum string MATERIAL_DECLARATIONS = `
kind hidden-family {
}

kind material {
    red: integer 0..255 = 0
    green: integer 0..255 = 0
    blue: integer 0..255 = 0
    grain: number 0.. = 0
    see-through: integer 0..1 = 0
    glows: integer 0..1 = 0
    fluid: integer 0..1 = 0
    hidden-in: optional -> hidden-family
}

kind group {
    member: many -> material
}
`;

void declareMaterials(ref ContentGraph graph) {
    declare(graph, MATERIAL_DECLARATIONS, MATERIAL_SOURCE);
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
}

__gshared Array!(const(char)[]) materialNames;
__gshared Array!ByteColor materialColors;
__gshared Array!float grains;
__gshared Array!ulong nameHashes;
__gshared Array!(MaybeIndex!uint) familyOfMaterial;
__gshared Array!Family families;
__gshared MaterialSet seeThrough;
__gshared MaterialSet glowing;
__gshared MaterialSet hidden;
__gshared MaterialSet plainSolid;
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
    materialColors.append(ByteColor(channelOf(graph, at, "red"), channelOf(graph, at, "green"), channelOf(graph, at, "blue")));
    grains.append(cast(float) graph.number(at, "grain"));
    nameHashes.append(murmurHash3(cast(const(ubyte)[]) graph.nameOf(node)).first);
    familyOfMaterial.append(MaybeIndex!uint.init);
    seeThrough = seeThrough.withTrait(graph, at, material, "see-through");
    glowing = glowing.withTrait(graph, at, material, "glows");
    fluids = fluids.withTrait(graph, at, material, "fluid");
}

MaybeIndex!uint familyNamed(const(char)[] name) {
    uint index = 0;
    while (index < families.length && families.ptr[index].name != name) {
        index += 1;
    }
    if (index < families.length) {
        return MaybeIndex!uint.of(index);
    } else {
        return MaybeIndex!uint.init;
    }
}

void addFamily(ref ContentGraph graph, uint node) {
    if (families.length == MOST_FAMILIES) {
        char[PROBLEM_CAPACITY] buffer;
        const(char)[] name = graph.nameOf(node);
        graph.report(graph.nodes.ptr[node].owner, printed(buffer[], "the hidden family '%.*s' is one more than the %u a body can sense", cast(int) name.length, name.ptr, MOST_FAMILIES));
    } else {
        families.append(Family(graph.nameOf(node), MaterialSet.init));
    }
}

void joinFamily(ref ContentGraph graph, uint node) {
    foreach (edge; graph.edgesFrom(node)) {
        uint family = graph.edges.ptr[edge].to;
        if (graph.isEdgeKind(edge, "hidden-in") && graph.isKind(family, FAMILY_KIND)) {
            MaybeIndex!uint index = familyNamed(graph.nameOf(family));
            if (index.exists) {
                Material material = materialOfNode(graph, node);
                families.ptr[index.value].members = families.ptr[index.value].members.including(material);
                familyOfMaterial.ptr[material.id] = index;
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
