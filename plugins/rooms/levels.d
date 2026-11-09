module plugins.rooms.levels;

import plugins.api.api : Material;
import plugins.api.binding : List;
import plugins.connector.connector : Ground;

enum size_t MOST_ROOM_FLOORS = 8;
enum size_t MOST_BIOMES = 8;
enum size_t MOST_LEVELS = 8;

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
    double big;
    double open;
    double hallDoors;
    double boxOdds;
    double skylight;
    double nowhere;
    int boxHeight;
    Vents vents;
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
