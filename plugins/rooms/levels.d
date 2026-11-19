module plugins.rooms.levels;

import plugins.api.api : Material;
import plugins.api.binding : List, Weighted;
import plugins.connector.connector : Ground;

enum size_t MOST_ROOM_FLOORS = 8;
enum size_t MOST_BIOMES = 8;
enum size_t MOST_LEVELS = 8;
enum size_t MOST_RARE = 8;
enum size_t MOST_USES = 8;
enum size_t MOST_PLANS = 8;

enum HallLayout : ubyte {
    none,
    grid,
    streets,
}

enum Vents : ubyte {
    none,
    some,
}

enum LevelKind : ubyte {
    rooms,
    maze,
}

enum Field : ubyte {
    grandeur,
    wetness,
    age,
    darkness,
}

enum uint FIELD_COUNT = Field.max + 1;

struct Bounds {
    double above;
    double below;
}

enum Opening : ubyte {
    rooms,
    pillars,
    pool,
    court,
}

struct PlanRow {
    Opening plan;
    int pillarEvery;
}

struct Use {
    Material material;
    double odds;
    int height;
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
    List!(Material, MOST_ROOM_FLOORS) roomFloors;
    List!(Use, MOST_USES) uses;
    List!(Weighted!PlanRow, MOST_PLANS) plans;
    double big;
    double open;
    double hallDoors;
    double boxOdds;
    double skylight;
    double nowhere;
    double well;
    double grandeurAbove;
    double grandeurBelow;
    double wetnessAbove;
    double wetnessBelow;
    double ageAbove;
    double ageBelow;
    double darknessAbove;
    double darknessBelow;
    double weight;
    int boxHeight;
    Vents vents;

    Bounds boundsOf(Field field) const {
        final switch (field) {
            case Field.grandeur:
                return Bounds(grandeurAbove, grandeurBelow);
            case Field.wetness:
                return Bounds(wetnessAbove, wetnessBelow);
            case Field.age:
                return Bounds(ageAbove, ageBelow);
            case Field.darkness:
                return Bounds(darknessAbove, darknessBelow);
        }
    }
}

enum Rarity : ubyte {
    rings,
    chapel,
    pillars,
    pool,
    court,
}

struct Rare {
    Rarity plan;
    int oneIn;
}

struct Hall {
    Material floor;
    Material ceiling;
    Material light;
    double skylight;
}

struct Level {
    HallLayout halls;
    int hallWidth;
    int room;
    LevelKind kind;
    double solid;
    double missing;
    double rings;
    double chapel;
    double stairs;
    Hall hall;
    List!(Biome, MOST_BIOMES) biomes;
    List!(Rare, MOST_RARE) rare;

    bool isMaze() const {
        return kind == LevelKind.maze;
    }
}

struct Rooms {
    Ground ground;
    Material vent;
    Material roof;
    Material window;
    Material sunlight;
    Material mural;
    Material muralLine;
    Material water;
    Material lawn;
    Material trunk;
    Material leaves;
    Material sign;
    List!(Level, MOST_LEVELS) levels;
}

__gshared Rooms rooms;

struct Tuning {
    double ventOdds;
    double dampOdds;
    double skirtingOdds;
    double mazeLoopOdds;
    double mazeRoomOdds;
    double mazeLightOdds;
    double gridDropped;
    double secondPassageOdds;
}

__gshared Tuning tuning;
