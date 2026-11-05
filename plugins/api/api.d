module plugins.api.api;

enum string ENTRY = "mined_plugin_8";

version (WebAssembly) {
    enum string entryOf(string unit) = ENTRY ~ "_" ~ unit;
} else {
    enum string entryOf(string unit) = ENTRY;
}

enum Material : ubyte {
    none,
    dirt,
    sand,
    redSand,
    silt,
    clay,
    mud,
    sandyLoam,
    siltyLoam,
    clayLoam,
    gravel,
    grass,
    lushGrass,
    coarseGrass,
    tanGrass,
    mudGrass,
    caveGrass,
    snow,
    ice,
    iceSlush,
    limestone,
    dolomite,
    shale,
    slate,
    sandstone,
    redSandstone,
    marble,
    granite,
    diorite,
    andesite,
    gabbro,
    basalt,
    olivine,
    water,
    lava,
    oakWood,
    oakLeaves,
    birchWood,
    birchLeaves,
    spruceWood,
    spruceLeaves,
    woodPlanks,
    greyBrick,
    whiteBrick,
    concrete,
    steel,
    glass,
    jungleWood,
    jungleLeaves,
    acaciaWood,
    acaciaLeaves,
    cherryLeaves,
    mapleLeaves,
    willowLeaves,
    cactus,
    wallpaper,
    stainedWallpaper,
    carpet,
    dampCarpet,
    ceilingTile,
    lightPanel,
    redCarpet,
    sunlight,
    plaster,
    wetConcrete,
}

enum Turn : ubyte {
    left,
    right,
    pitchUp,
    pitchDown,
    rollLeft,
    rollRight,
}

enum SitePart : ubyte {
    vertex,
    face,
    edge,
}

enum HorosphereForm : ubyte {
    terrain,
    solid,
    bare,
    upright,
    sunken,
}

struct MaybeIndex(Indexed) {
    uint bits;

    static MaybeIndex of(uint value) {
        assert(value != uint.max);
        return MaybeIndex(value + 1);
    }

    bool exists() const {
        return bits != 0;
    }

    uint value() const {
        assert(exists);
        return bits - 1;
    }
}

struct Tagged;

alias KindTag = MaybeIndex!Tagged;
alias KindId = MaybeIndex!RisingKind;

struct Site {
    int level;
    uint node;
    ubyte corner;
    ubyte xSide;
    ubyte ySide;
    byte xSign;
    byte ySign;
    byte zSign;
}

enum Extent : ubyte {
    bounded,
    endless,
}

struct ColumnCell {
    int x;
    int y;
    int z;

    ref inout(int) opIndex(size_t axis) inout return {
        if (axis == 0) {
            return x;
        } else if (axis == 1) {
            return y;
        } else {
            assert(axis == 2);
            return z;
        }
    }
}

struct Box {
    ColumnCell low;
    ColumnCell high;
    Extent extent;
}

enum Repeat : ubyte {
    rhythmic,
    always,
}

struct Rhythm {
    int every;
    int from;
    int span;
    Repeat repeat;
}

struct Spot {
    float x;
    float y;
    float z;
}

struct Span {
    int low;
    int high;
}

struct Pen {
    double[16] frame;
    double[4] ground;
    uint node;
}

enum Rising : ubyte {
    root,
    risen,
}

struct Risen {
    Site foot;
    int edges;
    int ground;
    int balance;
    KindTag lower;
    int segment;
    Rising rising;

    bool hasRisen() const {
        return rising == Rising.risen;
    }
}

enum Tint : ubyte {
    sky,
    fog,
}

struct Color {
    float red;
    float green;
    float blue;
}

struct Look {
    const(char)* name;
    Color fog = Color(0, 0, 0);
    Tint tint;
}

alias Structure = void function(const(Api)* api, Site site, const(void)* data);
alias Tile = void function(const(Api)* api, Site face, const(Risen)* risen, const(void)* data);

struct RisingKind {
    double share;
    HorosphereForm form;
    uint tag;
    Tile tile;
    const(void)* data;
    size_t size;
    Look look;
    uint under;
}

struct Api {
    void* host;
    const(char)* function(const(Api)* api) failure;
    void function(const(Api)* api, const(char)* message) fail;
    Site function(const(Api)* api, Site site, int edges) forward;
    Site function(const(Api)* api, Site site, Turn turn) turn;
    Span function(const(Api)* api) column;
    int function(const(Api)* api) edgeCells;
    uint function(const(Api)* api, uint count) pick;
    double function(const(Api)* api) random;
    ulong function(const(Api)* api, Site site, SitePart part) probeHash;
    void function(const(Api)* api, Site site, Material material, Box box, Rhythm rhythm) paint;
    void function(const(Api)* api, Site site, Material material, Box box, Rhythm rhythm) fill;
    void function(const(Api)* api, Site site, Spot spot) stop;
    void function(const(Api)* api, Site site, Spot spot) entrance;
    bool function(const(Api)* api, Site site, Structure structure, const(void)* data, size_t size) place;
    bool function(const(Api)* api, Site site, SitePart part) claim;
    bool function(const(Api)* api, Site site, SitePart part) probeClaimed;
    void function(const(Api)* api, Tile tile, const(void)* data, size_t size) tile;
    void function(const(Api)* api, Tile tile, const(void)* data, size_t size) tileEdges;
    KindId function(const(Api)* api, double odds, HorosphereForm form, uint tag, Tile tile, const(void)* data, size_t size) horosphere;
    KindId function(const(Api)* api, double odds, uint under, uint tag, Tile tile, const(void)* data, size_t size) sunken;
    void function(const(Api)* api, Site site, KindId kind, uint edges) openHorosphere;
    Site function(const(Api)* api, Site site) columnSite;
    void function(const(Api)* api, Site site) flatten;
    void function(const(Api)* api, KindId kind) rooted;
    void function(const(Api)* api) invertGravity;
    void function(const(Api)* api, double units) fog;
    KindTag function(const(Api)* api, Site site) probeRising;
    int function(const(Api)* api, Site site, int most) probeBalance;
    Pen function(const(Api)* api, Site site) openPen;
    Pen function(const(Api)* api, Pen pen, double cells) penForward;
    Pen function(const(Api)* api, Pen pen, double yaw, double pitch) penTurn;
    Pen function(const(Api)* api, Pen pen, double degrees) penRoll;
    Pen function(const(Api)* api, Pen pen, double degrees) penLift;
    double function(const(Api)* api, Pen pen) penRise;
    double function(const(Api)* api, Pen pen) penHeight;
    void function(const(Api)* api, Pen pen, Material material, double cells, double fromRadius, double toRadius) limb;
    void function(const(Api)* api, Pen pen, Material material, double radius) leaves;
    bool function(const(Api)* api, const(char)* world, Site site) build;
    void function(const(Api)* api, KindId kind, const(Look)* look) look;
    void function(const(Api)* api, const(Look)* look) worldLook;
    void function(const(Api)* api, double odds) risingKinds;
    bool function(const(Api)* api, uint index, Site site) landmark;
}

struct Registry {
    void* host;
    void function(const(Registry)* registry, const(char)* name, Structure world) add;
    void function(const(Registry)* registry, const(char)* name, const(RisingKind)* kind) addKind;
    void function(const(Registry)* registry, const(char)* name, Structure landmark) addLandmark;
}

alias Entry = void function(const(Registry)* registry);
