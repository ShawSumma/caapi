module common.material;

import plugins.api.api : Material;

enum uint MATERIAL_COUNT = Material.max + 1;

struct ByteColor {
    ubyte red;
    ubyte green;
    ubyte blue;
}

bool isSeeThrough(Material material) {
    return material == Material.none || material == Material.glass;
}

bool isShownAgainst(Material material, Material beside) {
    return material != Material.none && isSeeThrough(beside) && !(material == Material.glass && beside == Material.glass);
}

bool isGlowing(Material material) {
    return material == Material.lightPanel || material == Material.sunlight || material == Material.lava;
}

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
];
