module plugins.rooms.levels;

import plugins.api.api : Material;

enum HallLayout : ubyte {
    none,
    grid,
    streets,
}

struct Biome {
    Material wall;
    Material floor;
    Material ceiling;
    Material light;
    Material trim;
    Material damp;
    Material stair;
    Material shelf;
    Material boxes;
    const(Material)[] roomFloors;
    double big = 0.25;
    double open = 0;
    double hallDoors = 0.35;
    double boxOdds = 0;
    double skylight = 0;
    double nowhere = 0;
    int boxHeight = 0;
    bool hasVents;
}

struct Hall {
    Material floor = Material.carpet;
    Material ceiling = Material.ceilingTile;
    Material light = Material.lightPanel;
    double skylight = 0;
}

struct Level {
    HallLayout halls;
    int hallWidth;
    int room = 4;
    bool isMaze;
    double solid = 0;
    double missing = 0;
    double rings = 0;
    double chapel = 0;
    double stairs = 0;
    Hall hall;
    const(Biome)[] biomes;
}

immutable Biome OFFICE = {
    wall: Material.wallpaper, floor: Material.carpet, ceiling: Material.ceilingTile, light: Material.lightPanel,
    trim: Material.woodPlanks, damp: Material.dampCarpet, stair: Material.carpet, hasVents: true,
    boxes: Material.wallpaper, boxOdds: 0.15, boxHeight: 4, skylight: 0.2,
};

immutable Biome SODDEN = {
    wall: Material.wallpaper, floor: Material.dampCarpet, ceiling: Material.ceilingTile, light: Material.lightPanel,
    damp: Material.carpet, stair: Material.carpet, hasVents: true, boxes: Material.wallpaper, boxOdds: 0.25,
    boxHeight: 3, skylight: 0.1,
};

immutable Biome STAINED = {
    wall: Material.stainedWallpaper, floor: Material.carpet, ceiling: Material.ceilingTile, light: Material.lightPanel,
    damp: Material.dampCarpet, stair: Material.carpet, hasVents: true, skylight: 0.15,
};

immutable Material[3] PARLOR_FLOORS = [Material.woodPlanks, Material.woodPlanks, Material.carpet];
immutable Material[2] STUDY_FLOORS = [Material.woodPlanks, Material.spruceWood];
immutable Material[3] ATTIC_FLOORS = [Material.spruceWood, Material.carpet, Material.dampCarpet];

immutable Biome PARLOR = {
    wall: Material.plaster, floor: Material.woodPlanks, ceiling: Material.plaster, light: Material.lightPanel,
    trim: Material.spruceWood, big: 0.35, stair: Material.woodPlanks, roomFloors: PARLOR_FLOORS[],
};

immutable Biome STUDY = {
    wall: Material.birchWood, floor: Material.woodPlanks, ceiling: Material.plaster, light: Material.lightPanel,
    trim: Material.spruceWood, big: 0.3, stair: Material.spruceWood, shelf: Material.spruceWood,
    roomFloors: STUDY_FLOORS[],
};

immutable Biome ATTIC = {
    wall: Material.plaster, floor: Material.spruceWood, ceiling: Material.plaster, light: Material.lightPanel,
    trim: Material.woodPlanks, big: 0.4, stair: Material.spruceWood, damp: Material.dampCarpet,
    roomFloors: ATTIC_FLOORS[],
};

immutable Biome BUNKER = {
    wall: Material.concrete, floor: Material.concrete, ceiling: Material.concrete, light: Material.lightPanel,
    stair: Material.concrete, nowhere: 0.15,
};

immutable Biome CELLAR = {
    wall: Material.greyBrick, floor: Material.wetConcrete, ceiling: Material.concrete, light: Material.lightPanel,
    stair: Material.concrete, nowhere: 0.2,
};

immutable Biome SUMP = {
    wall: Material.concrete, floor: Material.wetConcrete, ceiling: Material.wetConcrete, stair: Material.wetConcrete,
    nowhere: 0.25,
};

immutable Biome[3] OFFICES = [OFFICE, SODDEN, STAINED];
immutable Biome[3] HOUSES = [PARLOR, STUDY, ATTIC];
immutable Biome[3] MAZES = [BUNKER, CELLAR, SUMP];

immutable Level OFFICE_LEVEL = {
    halls: HallLayout.grid, hallWidth: 2, solid: 0.6, rings: 0.02, chapel: 0.04, stairs: 0.24,
    hall: Hall(Material.carpet, Material.ceilingTile, Material.lightPanel, 0.25), biomes: OFFICES[],
};

immutable Level HOUSE_LEVEL = {
    missing: 0.03, stairs: 0.24, biomes: HOUSES[],
};

immutable Level MAZE_LEVEL = {
    room: 3, isMaze: true, biomes: MAZES[],
};

immutable Level[3] LAYERS = [OFFICE_LEVEL, HOUSE_LEVEL, MAZE_LEVEL];
