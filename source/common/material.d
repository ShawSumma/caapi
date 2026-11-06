module common.material;

import base.maybe : Maybe;
import plugins.api.api : Material;

enum uint MATERIAL_COUNT = Material.max + 1;
enum uint BITS_PER_WORD = 32;
enum uint MATERIAL_WORDS = (MATERIAL_COUNT + BITS_PER_WORD - 1) / BITS_PER_WORD;

struct ByteColor {
    ubyte red;
    ubyte green;
    ubyte blue;
}

enum HiddenFamily : ubyte {
    mist,
    ember,
    tide,
}

enum uint HIDDEN_FAMILY_COUNT = HiddenFamily.max + 1;

struct MaterialSet {
    uint[MATERIAL_WORDS] words;
}

bool has(MaterialSet set, Material material) {
    return (set.words[material / BITS_PER_WORD] & (1u << (material % BITS_PER_WORD))) != 0;
}

MaterialSet including(MaterialSet set, Material material) {
    MaterialSet made = set;
    made.words[material / BITS_PER_WORD] |= 1u << (material % BITS_PER_WORD);
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

Maybe!HiddenFamily hiddenFamilyOf(Material material) {
    if (material == Material.mistStone || material == Material.mistLight) {
        return Maybe!HiddenFamily.of(HiddenFamily.mist);
    } else if (material == Material.emberStone || material == Material.emberLight) {
        return Maybe!HiddenFamily.of(HiddenFamily.ember);
    } else if (material == Material.tideStone || material == Material.tideLight) {
        return Maybe!HiddenFamily.of(HiddenFamily.tide);
    } else {
        return Maybe!HiddenFamily.init;
    }
}

bool isHidden(Material material) {
    return hiddenFamilyOf(material).exists;
}

bool isSameHiddenFamily(Material material, Material beside) {
    Maybe!HiddenFamily own = hiddenFamilyOf(material);
    Maybe!HiddenFamily other = hiddenFamilyOf(beside);
    return own.exists && other.exists && own.value == other.value;
}

bool isSeeThrough(Material material) {
    return material == Material.none || material == Material.glass || isHidden(material);
}

bool isShownAgainst(Material material, Material beside) {
    return material != Material.none && isSeeThrough(beside) && !(material == Material.glass && beside == Material.glass) && !isSameHiddenFamily(material, beside);
}

bool isOccluding(Material material) {
    return material != Material.none && !isHidden(material);
}

bool isGlowing(Material material) {
    return material == Material.lightPanel || material == Material.sunlight || material == Material.lava || material == Material.mistLight || material == Material.emberLight || material == Material.tideLight || material == Material.beacon;
}

MaterialSet materialsWhere(alias test)() {
    MaterialSet set;
    foreach (index; 0 .. MATERIAL_COUNT) {
        if (test(cast(Material) index)) {
            set = set.including(cast(Material) index);
        }
    }
    return set;
}

bool isPlainSolid(Material material) {
    return material != Material.none && !isHidden(material);
}

MaterialSet[HIDDEN_FAMILY_COUNT] familySets() {
    MaterialSet[HIDDEN_FAMILY_COUNT] sets;
    foreach (index; 0 .. MATERIAL_COUNT) {
        Maybe!HiddenFamily found = hiddenFamilyOf(cast(Material) index);
        if (found.exists) {
            sets[found.value] = sets[found.value].including(cast(Material) index);
        }
    }
    return sets;
}

immutable MaterialSet PLAIN_SOLID = materialsWhere!isPlainSolid();
immutable MaterialSet GLOWING = materialsWhere!isGlowing();
immutable MaterialSet HIDDEN = materialsWhere!isHidden();
immutable MaterialSet[HIDDEN_FAMILY_COUNT] FAMILY_SETS = familySets();

immutable ByteColor[MATERIAL_COUNT] MATERIAL_COLORS = [
    Material.none: ByteColor(0, 0, 0),
    Material.dirt: ByteColor(120, 85, 58),
    Material.sand: ByteColor(219, 203, 150),
    Material.redSand: ByteColor(190, 100, 60),
    Material.silt: ByteColor(160, 140, 110),
    Material.clay: ByteColor(170, 110, 80),
    Material.mud: ByteColor(90, 70, 50),
    Material.sandyLoam: ByteColor(150, 120, 80),
    Material.siltyLoam: ByteColor(130, 105, 75),
    Material.clayLoam: ByteColor(135, 90, 65),
    Material.gravel: ByteColor(135, 130, 125),
    Material.grass: ByteColor(90, 140, 50),
    Material.lushGrass: ByteColor(70, 150, 50),
    Material.coarseGrass: ByteColor(110, 130, 60),
    Material.tanGrass: ByteColor(170, 160, 90),
    Material.mudGrass: ByteColor(90, 110, 50),
    Material.caveGrass: ByteColor(70, 100, 80),
    Material.snow: ByteColor(245, 248, 250),
    Material.ice: ByteColor(180, 215, 240),
    Material.iceSlush: ByteColor(200, 220, 230),
    Material.limestone: ByteColor(200, 195, 175),
    Material.dolomite: ByteColor(210, 205, 190),
    Material.shale: ByteColor(95, 95, 100),
    Material.slate: ByteColor(75, 80, 90),
    Material.sandstone: ByteColor(205, 175, 125),
    Material.redSandstone: ByteColor(170, 80, 55),
    Material.marble: ByteColor(235, 235, 230),
    Material.granite: ByteColor(165, 150, 145),
    Material.diorite: ByteColor(200, 200, 195),
    Material.andesite: ByteColor(130, 130, 130),
    Material.gabbro: ByteColor(60, 60, 60),
    Material.basalt: ByteColor(50, 50, 55),
    Material.olivine: ByteColor(110, 130, 60),
    Material.water: ByteColor(50, 90, 170),
    Material.lava: ByteColor(220, 80, 20),
    Material.oakWood: ByteColor(105, 75, 45),
    Material.oakLeaves: ByteColor(60, 120, 40),
    Material.birchWood: ByteColor(215, 210, 195),
    Material.birchLeaves: ByteColor(125, 175, 70),
    Material.spruceWood: ByteColor(80, 58, 38),
    Material.spruceLeaves: ByteColor(45, 85, 55),
    Material.woodPlanks: ByteColor(180, 140, 90),
    Material.greyBrick: ByteColor(130, 130, 135),
    Material.whiteBrick: ByteColor(220, 220, 215),
    Material.concrete: ByteColor(160, 160, 155),
    Material.steel: ByteColor(115, 120, 130),
    Material.glass: ByteColor(165, 205, 225),
    Material.jungleWood: ByteColor(125, 95, 55),
    Material.jungleLeaves: ByteColor(35, 125, 35),
    Material.acaciaWood: ByteColor(140, 115, 95),
    Material.acaciaLeaves: ByteColor(125, 145, 50),
    Material.cherryLeaves: ByteColor(235, 165, 195),
    Material.mapleLeaves: ByteColor(205, 95, 40),
    Material.willowLeaves: ByteColor(145, 175, 75),
    Material.cactus: ByteColor(70, 130, 60),
    Material.wallpaper: ByteColor(214, 197, 124),
    Material.stainedWallpaper: ByteColor(188, 168, 98),
    Material.carpet: ByteColor(166, 148, 92),
    Material.dampCarpet: ByteColor(132, 118, 72),
    Material.ceilingTile: ByteColor(224, 218, 194),
    Material.lightPanel: ByteColor(252, 250, 236),
    Material.redCarpet: ByteColor(128, 36, 40),
    Material.sunlight: ByteColor(252, 236, 168),
    Material.plaster: ByteColor(218, 208, 186),
    Material.wetConcrete: ByteColor(118, 118, 112),
    Material.mistStone: ByteColor(176, 190, 214),
    Material.mistLight: ByteColor(222, 232, 252),
    Material.emberStone: ByteColor(150, 74, 52),
    Material.emberLight: ByteColor(255, 150, 88),
    Material.tideStone: ByteColor(52, 120, 128),
    Material.tideLight: ByteColor(110, 236, 220),
    Material.beacon: ByteColor(120, 230, 255),
    Material.ironOre: ByteColor(140, 96, 80),
    Material.copperOre: ByteColor(80, 150, 120),
    Material.sulfur: ByteColor(225, 210, 70),
    Material.fern: ByteColor(60, 140, 70),
    Material.flower: ByteColor(210, 120, 200),
    Material.thornbush: ByteColor(150, 130, 70),
    Material.moss: ByteColor(110, 150, 90),
    Material.collector: ByteColor(170, 175, 190),
    Material.bench: ByteColor(150, 110, 80),
];

bool isPlant(Material material) {
    return material == Material.fern || material == Material.flower || material == Material.thornbush || material == Material.moss;
}

Material oreFor(Material rock) {
    if (rock == Material.granite || rock == Material.diorite || rock == Material.andesite || rock == Material.gabbro || rock == Material.basalt || rock == Material.olivine) {
        return Material.ironOre;
    } else if (rock == Material.marble || rock == Material.slate) {
        return Material.copperOre;
    } else if (rock == Material.limestone || rock == Material.dolomite || rock == Material.shale || rock == Material.sandstone || rock == Material.redSandstone) {
        return Material.sulfur;
    } else {
        return Material.none;
    }
}
