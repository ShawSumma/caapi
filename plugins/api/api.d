module plugins.api.api;

enum string ENTRY = "mined_plugin_2";

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
    bare,
    upright,
}

enum uint NO_KIND = uint.max;

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

struct Box {
    int[3] low;
    int[3] high;
}

struct Rhythm {
    int every;
    int from;
    int span;
}

struct Spot {
    float x;
    float y;
    float z;
}

struct Column {
    int low;
    int high;
}

struct Pen {
    double[16] frame;
    double[4] ground;
    uint node;
}

struct Risen {
    Site foot;
    int edges;
    int ground;
    int below;
    int balance;
    uint lower;
    int segment;
}

struct Look {
    const(char)* name;
    float[3] fog = [0, 0, 0];
    bool hasFog;
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
}

struct Api {
    void* host;
    const(char)* function(const(Api)* api) failure;
    void function(const(Api)* api, const(char)* message) fail;
    Site function(const(Api)* api, Site site, int edges) forward;
    Site function(const(Api)* api, Site site, Turn turn) turned;
    Column function(const(Api)* api) column;
    int function(const(Api)* api) edgeCells;
    uint function(const(Api)* api, uint count) pick;
    double function(const(Api)* api) random;
    ulong function(const(Api)* api, Site site, SitePart part) hash;
    void function(const(Api)* api, Site site, Material material, Box box, Rhythm rhythm) paint;
    void function(const(Api)* api, Site site, Material material, Box box, Rhythm rhythm) fill;
    void function(const(Api)* api, Site site, Spot spot) stop;
    void function(const(Api)* api, Site site, Spot spot) entrance;
    bool function(const(Api)* api, Site site, Structure structure, const(void)* data, size_t size) place;
    bool function(const(Api)* api, Site site, SitePart part) claim;
    bool function(const(Api)* api, Site site, SitePart part) isClaimed;
    void function(const(Api)* api, Tile tile, const(void)* data, size_t size) tile;
    void function(const(Api)* api, Tile tile, const(void)* data, size_t size) tileEdges;
    uint function(const(Api)* api, double odds, HorosphereForm form, uint tag, Tile tile, const(void)* data, size_t size) horosphere;
    void function(const(Api)* api, Site site, uint kind, uint edges) openHorosphere;
    void function(const(Api)* api, uint kind) rooted;
    void function(const(Api)* api) invertGravity;
    void function(const(Api)* api, double units) fog;
    uint function(const(Api)* api, Site site) rising;
    int function(const(Api)* api, Site site, int most) balance;
    Pen function(const(Api)* api, Site site) pen;
    Pen function(const(Api)* api, Pen pen, double cells) penForward;
    Pen function(const(Api)* api, Pen pen, double yaw, double pitch) penTurn;
    Pen function(const(Api)* api, Pen pen, double degrees) penRoll;
    Pen function(const(Api)* api, Pen pen, double degrees) penLift;
    double function(const(Api)* api, Pen pen) penRise;
    double function(const(Api)* api, Pen pen) penHeight;
    void function(const(Api)* api, Pen pen, Material material, double cells, double fromRadius, double toRadius) limb;
    void function(const(Api)* api, Pen pen, Material material, double radius) leaves;
    bool function(const(Api)* api, const(char)* world, Site site) build;
    void function(const(Api)* api, uint kind, const(Look)* look) look;
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
