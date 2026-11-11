module plugins.api.api;

import plugins.api.content : Manifest;

enum string ENTRY = "caapi_plugin_28";

version (WebAssembly) {
    enum string entryOf(string unit) = ENTRY ~ "_" ~ unit;
} else {
    enum string entryOf(string unit) = ENTRY;
}

struct Material {
    ubyte id;

    enum Material none = Material(0);
}

enum uint MOST_MATERIALS = ubyte.max + 1;

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

enum ulong TAG_MIX = 0x2545F4914F6CDD1D;
enum uint TAG_FOLD = 32;

uint tagNamed(const(char)[] name) {
    ulong hash = 0;
    foreach (c; name) {
        hash = (hash ^ c) * TAG_MIX;
    }
    return cast(uint)((hash ^ (hash >> TAG_FOLD)) % uint.max);
}
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
    KindTag tag;
    HorosphereForm form;

    bool hasRisen() const {
        return rising == Rising.risen;
    }
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
    const(char)[] look;
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
    void function(const(Api)* api, KindId kind, const(char)[] look) look;
    void function(const(Api)* api, const(char)[] look) worldLook;
    void function(const(Api)* api, double odds) risingKinds;
    bool function(const(Api)* api, uint index, Site site) landmark;
    void function(const(Api)* api, KindTag ground, const(char)[] look, double depth, double fog) under;
    void function(const(Api)* api, KindTag ground, double edges) crust;
    void function(const(Api)* api, double odds) ports;
    bool function(const(Api)* api, Site site) probePort;
    void function(const(Api)* api, KindTag ground, double edges) thinCrust;
    double function(const(Api)* api, Site site) probeCrust;
    void function(const(Api)* api, KindTag ground, const(char)[] look, double edges, double fog) underCrust;
    void function(const(Api)* api, KindTag ground, double edges) abyss;
    void function(const(Api)* api, double cells) edgeCeiling;
}

struct Registry {
    void* host;
    void function(const(Registry)* registry, const(char)* name, Structure world) add;
    void function(const(Registry)* registry, const(char)* name, const(RisingKind)* kind) addKind;
    void function(const(Registry)* registry, const(char)* name, Structure landmark) addLandmark;
    void function(const(Registry)* registry, const(Manifest)* manifest) declare;
    void function(const(Registry)* registry, const(char)* name, Structure structure) addDebug;
}

alias Entry = void function(const(Registry)* registry);
