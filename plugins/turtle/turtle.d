module plugins.turtle.turtle;

import core.stdc.math : atan2, cos, sin;
import plugins.api.api : Api, Box, Column, Material, Pen, Rhythm, Risen, Site, SitePart, Spot, Structure, Turn;

enum double PI = 3.14159265358979323846;
enum int TURN_TREADS = 24;
enum int STAIR_HEADROOM = 4;
enum int TREAD_THICKNESS = 2;
enum uint MOST_ROWS = 48;
enum Rhythm EVERY_HEIGHT = Rhythm(0, 0, 0);
enum int ENDLESS_LOW = int.min;
enum int ENDLESS_HIGH = int.max;
enum uint PERCENT = 100;
enum uint FACE_CORNERS = 5;
enum ulong MIX = 0x2545F4914F6CDD1D;
enum uint MIX_SHIFT = 24;

ulong mixed(ulong hash, ulong salt) {
    return ((hash ^ salt) * MIX) >> MIX_SHIFT;
}

double roll(ulong hash, ulong salt) {
    return (mixed(hash, salt) % PERCENT) / cast(double) PERCENT;
}

Box boxOf(int[2] x, int[2] y, int[2] z) {
    return Box([x[0], y[0], z[0]], [x[1], y[1], z[1]]);
}

int floorDiv(int value, int divisor) {
    int quotient = value / divisor;
    if (value % divisor != 0 && (value < 0) != (divisor < 0)) {
        return quotient - 1;
    } else {
        return quotient;
    }
}

int floorMod(int value, int divisor) {
    int remainder = value % divisor;
    if (remainder < 0) {
        return remainder + divisor;
    } else {
        return remainder;
    }
}

T lowerOf(T)(T a, T b) {
    if (a < b) {
        return a;
    } else {
        return b;
    }
}

T higherOf(T)(T a, T b) {
    if (a > b) {
        return a;
    } else {
        return b;
    }
}

T clamped(T)(T value, T low, T high) {
    if (value < low) {
        return low;
    } else if (value > high) {
        return high;
    } else {
        return value;
    }
}

struct Tread {
    int[2] x;
    int[2] y;
}

int[2] negated(int[2] span) {
    return [-span[1] - 1, -span[0] - 1];
}

Tread treadAround(int inner, int width, int sides, int index) {
    int at = floorMod(index, 4 * (sides + 1));
    int step = at % (sides + 1);
    int depth = 2 * inner / sides;
    int[2] ring = [inner, inner + width - 1];
    Tread tread = Tread(ring, ring);
    if (step > 0) {
        tread.x = [inner - step * depth, inner - (step - 1) * depth - 1];
    }
    foreach (_; 0 .. at / (sides + 1)) {
        tread = Tread(negated(tread.y), tread.x);
    }
    return tread;
}

float middle(int[2] span) {
    return (span[0] + span[1] + 1) / 2.0f;
}

struct Row {
    int y;
    int[2] x;
}

struct Rows {
    Row[MOST_ROWS] items;
    uint count;

    void add(int x, int y) {
        if (count > 0 && items[count - 1].y == y && items[count - 1].x[1] == x - 1) {
            items[count - 1].x[1] = x;
        } else {
            items[count] = Row(y, [x, x]);
            count += 1;
        }
    }

    const(Row)[] slice() const return {
        return items[0 .. count];
    }
}

bool isInRing(int x, int y, double inner, double outer) {
    double across = x + 0.5;
    double along = y + 0.5;
    double squared = across * across + along * along;
    return squared >= inner * inner && squared < outer * outer;
}

Rows ringRows(Column column, double inner, double outer) {
    Rows rows;
    foreach (y; column.low .. column.high + 1) {
        foreach (x; column.low .. column.high + 1) {
            if (isInRing(x, y, inner, outer)) {
                rows.add(x, y);
            }
        }
    }
    return rows;
}

Rows[TURN_TREADS] wedgeRows(Column column, double inner, double outer) {
    Rows[TURN_TREADS] wedges;
    foreach (y; column.low .. column.high + 1) {
        foreach (x; column.low .. column.high + 1) {
            if (isInRing(x, y, inner, outer)) {
                wedges[wedgeAt(x, y)].add(x, y);
            }
        }
    }
    return wedges;
}

int[2] treadSpan(int tread) {
    return [higherOf(0, tread - TREAD_THICKNESS + 1), tread];
}

enum Along : ubyte {
    x,
    y,
}

Box line(Along along, int[2] span, int[2] z) {
    if (along == Along.x) {
        return boxOf(span, [0, 0], z);
    } else {
        return boxOf([0, 0], span, z);
    }
}

void grass(Turtle face) {
    foreach (corner; cornersOf(face)) {
        int far = corner.column().high;
        upright(corner).paint(Material.grass, boxOf([0, far], [0, far], [-1, -1]));
    }
}

void lawn(const(Api)* api, Site face, const(Risen)* risen, const(void)* data) {
    grass(Turtle(api, face));
}

uint wedgeAt(int cellX, int cellY) {
    double turns = atan2(cellY + 0.5, cellX + 0.5) / (2 * PI);
    if (turns < 0) {
        turns += 1;
    }
    return lowerOf(cast(uint)(turns * TURN_TREADS), TURN_TREADS - 1);
}

float[2] onWedge(int tread, double radius) {
    double angle = (floorMod(tread, TURN_TREADS) + 0.5) * 2 * PI / TURN_TREADS;
    return [cast(float)(radius * cos(angle)), cast(float)(radius * sin(angle))];
}

Turtle upright(Turtle site) {
    return site.pitchUp().rollRight();
}

Turtle[FACE_CORNERS] cornersOf(Turtle face) {
    Turtle[FACE_CORNERS] corners;
    Turtle corner = face;
    foreach (index; 0 .. FACE_CORNERS) {
        corners[index] = corner;
        corner = corner.forward(1).right();
    }
    return corners;
}

struct Turtle {
    const(Api)* api;
    Site site;

    Turtle forward(int edges) const {
        return Turtle(api, api.forward(api, site, edges));
    }

    Turtle turned(Turn turn) const {
        return Turtle(api, api.turned(api, site, turn));
    }

    Turtle left() const {
        return turned(Turn.left);
    }

    Turtle right() const {
        return turned(Turn.right);
    }

    Turtle pitchUp() const {
        return turned(Turn.pitchUp);
    }

    Turtle pitchDown() const {
        return turned(Turn.pitchDown);
    }

    Turtle rollLeft() const {
        return turned(Turn.rollLeft);
    }

    Turtle rollRight() const {
        return turned(Turn.rollRight);
    }

    Column column() const {
        return api.column(api);
    }

    void fail(const(char)* message) const {
        api.fail(api, message);
    }

    int edgeCells() const {
        return api.edgeCells(api);
    }

    uint pick(uint count) const {
        return api.pick(api, count);
    }

    bool chance(uint percent) const {
        return api.pick(api, PERCENT) < percent;
    }

    double random() const {
        return api.random(api);
    }

    ulong hash(SitePart part) const {
        return api.hash(api, site, part);
    }

    void paint(Material material, Box area, Rhythm rhythm = EVERY_HEIGHT) const {
        api.paint(api, site, material, area, rhythm);
    }

    void fill(Material material, Box area, Rhythm rhythm = EVERY_HEIGHT) const {
        api.fill(api, site, material, area, rhythm);
    }

    void paintRows(Material material, ref const Rows rows, int[2] z, Rhythm rhythm = EVERY_HEIGHT) const {
        foreach (row; rows.slice()) {
            paint(material, boxOf(row.x, [row.y, row.y], z), rhythm);
        }
    }

    void fillRows(Material material, ref const Rows rows, int[2] z, Rhythm rhythm = EVERY_HEIGHT) const {
        foreach (row; rows.slice()) {
            fill(material, boxOf(row.x, [row.y, row.y], z), rhythm);
        }
    }

    void clearOver(ref const Rows room, int tread) const {
        int low = higherOf(0, tread + 1);
        int high = lowerOf(edgeCells() - 1, tread + STAIR_HEADROOM);
        if (low <= high) {
            paintRows(Material.none, room, [low, high]);
        }
    }

    Turtle columnSite() const {
        return Turtle(api, api.columnSite(api, site));
    }

    void stop(float x, float y, float z) const {
        api.stop(api, site, Spot(x, y, z));
    }

    void entrance(float x, float y, float z) const {
        api.entrance(api, site, Spot(x, y, z));
    }

    bool place(Structure structure, const(void)* data, size_t size) const {
        return api.place(api, site, structure, data, size);
    }

    bool claim(SitePart part) const {
        return api.claim(api, site, part);
    }

    bool isClaimed(SitePart part) const {
        return api.isClaimed(api, site, part);
    }

    int balance(int most) const {
        return api.balance(api, site, most);
    }

    uint rising() const {
        return api.rising(api, site);
    }

    bool build(const(char)* world) const {
        return api.build(api, world, site);
    }

    Drawing pen() const {
        return Drawing(api, api.pen(api, site));
    }
}

struct Drawing {
    const(Api)* api;
    Pen pen;

    Drawing forward(double cells) const {
        return Drawing(api, api.penForward(api, pen, cells));
    }

    Drawing turn(double yaw, double pitch) const {
        return Drawing(api, api.penTurn(api, pen, yaw, pitch));
    }

    Drawing roll(double degrees) const {
        return Drawing(api, api.penRoll(api, pen, degrees));
    }

    Drawing lift(double degrees) const {
        return Drawing(api, api.penLift(api, pen, degrees));
    }

    double rise() const {
        return api.penRise(api, pen);
    }

    double height() const {
        return api.penHeight(api, pen);
    }

    Drawing limb(Material material, double cells, double fromRadius, double toRadius) const {
        api.limb(api, pen, material, cells, fromRadius, toRadius);
        return forward(cells);
    }

    void leaves(Material material, double radius) const {
        api.leaves(api, pen, material, radius);
    }

    double random() const {
        return api.random(api);
    }

    double between(double low, double high) const {
        return low + (high - low) * random();
    }
}
