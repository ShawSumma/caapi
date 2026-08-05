module common.world;

// Block materials.
//
// DESIGN.md records that materials were rejected as a concept: a voxel is five
// channels at three levels each, and the element it names is not derived from
// its colour. This enum is what worldgen still writes, so it is vestigial and
// wants replacing rather than extending.
enum Material : ushort {
    Void = 0,
    Dirt = 1,
    Sand = 2,
    Silt = 3,
    Clay = 4,
    Mud = 5,
    SandyLoam = 6,
    SiltyLoam = 7,
    ClayLoam = 8,
    RedSand = 9,
    Limestone = 10,
    Shale = 11,
    Dolomite = 12,
    Sandstone = 13,
    RedSandstone = 14,
    Marble = 15,
    Slate = 16,
    Granite = 17,
    Diorite = 18,
    Andesite = 19,
    Gabbro = 20,
    Basalt = 21,
    Olivine = 22,
    Water = 23,
    Lava = 24,
    Wood = 25,
    Leaves = 26,
    WoodPlanks = 27,
    GreyBrick = 28,
    WhiteBrick = 29,
    Ice = 30,
    IceSlush = 31,
    Gravel = 32,
    Snow = 33,
    CoarseGrass = 34,
    TanGrass = 35,
    LushGrass = 36,
    MudGrass = 37,
    Grass = 38,
    CaveGrass = 39,
}

Material materialFromU16(ushort value) {
    if (value > Material.max) {
        return Material.Void;
    }
    return cast(Material) value;
}
