module plugins.turtle.turtle;

import core.stdc.math : atan2, cos, sin;
import plugins.api.api : Api, Box, ColumnCell, Extent, KindTag, Material, Pen, Repeat, Rhythm, Risen, Site, SitePart, Span, Spot, Structure, Turn;

enum double PI = 3.14159265358979323846;
enum int TURN_TREADS = 24;
enum int STAIR_HEADROOM = 4;
enum int TREAD_THICKNESS = 2;
enum uint MOST_ROWS = 48;
enum Rhythm EVERY_HEIGHT = Rhythm(0, 0, 0, Repeat.always);
enum uint PERCENT = 100;
enum uint FACE_CORNERS = 5;
enum uint EDGE_FACES = 4;
enum int PORT = 4;
enum ulong MIX = 0x2545F4914F6CDD1D;
enum uint MIX_SHIFT = 24;
enum size_t MOST_HASHES = 1024;

ulong mixed(ulong hash, ulong salt) {
    return ((hash ^ salt) * MIX) >> MIX_SHIFT;
}

double roll(ulong hash, ulong salt) {
    return (mixed(hash, salt) % PERCENT) / cast(double) PERCENT;
}

struct Cell {
    int x;
    int y;
}

struct Offset {
    float x;
    float y;
}

Box boxOf(Span x, Span y, Span z) {
    return Box(ColumnCell(x.low, y.low, z.low), ColumnCell(x.high, y.high, z.high));
}

Box alongLine(Span x, Span y) {
    return Box(ColumnCell(x.low, y.low, 0), ColumnCell(x.high, y.high, 0), Extent.endless);
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
    Span x;
    Span y;
}

Span negated(Span span) {
    return Span(-span.high - 1, -span.low - 1);
}

Tread treadAround(int inner, int width, int sides, int index) {
    int at = floorMod(index, 4 * (sides + 1));
    int step = at % (sides + 1);
    int depth = 2 * inner / sides;
    Span ring = Span(inner, inner + width - 1);
    Tread tread = Tread(ring, ring);
    if (step > 0) {
        tread.x = Span(inner - step * depth, inner - (step - 1) * depth - 1);
    }
    foreach (_; 0 .. at / (sides + 1)) {
        tread = Tread(negated(tread.y), tread.x);
    }
    return tread;
}

float middle(Span span) {
    return (span.low + span.high + 1) / 2.0f;
}

struct Row {
    int y;
    Span x;
}

struct Rows {
    Row[MOST_ROWS] items;
    uint count;

    void add(int x, int y) {
        if (count > 0 && items[count - 1].y == y && items[count - 1].x.high == x - 1) {
            items[count - 1].x.high = x;
        } else {
            items[count] = Row(y, Span(x, x));
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

Rows ringRows(Span column, double inner, double outer) {
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

Rows[TURN_TREADS] wedgeRows(Span column, double inner, double outer) {
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

Span treadSpan(int tread) {
    return Span(higherOf(0, tread - TREAD_THICKNESS + 1), tread);
}

enum Along : ubyte {
    x,
    y,
}

Box line(Along along, Span span, Span z) {
    if (along == Along.x) {
        return boxOf(span, Span(0, 0), z);
    } else {
        return boxOf(Span(0, 0), span, z);
    }
}

void grass(Turtle face, Material material) {
    foreach (corner; cornersOf(face)) {
        Span whole = Span(0, corner.column().high);
        upright(corner).paint(material, boxOf(whole, whole, Span(-1, -1)));
    }
}

void lawn(const(Api)* api, Site face, const(Risen)* risen, const(void)* data) {
    grass(Turtle(api, face), *cast(const(Material)*) data);
}

uint wedgeAt(int cellX, int cellY) {
    double turns = atan2(cellY + 0.5, cellX + 0.5) / (2 * PI);
    if (turns < 0) {
        turns += 1;
    }
    return lowerOf(cast(uint)(turns * TURN_TREADS), TURN_TREADS - 1);
}

Offset onWedge(int tread, double radius) {
    double angle = (floorMod(tread, TURN_TREADS) + 0.5) * 2 * PI / TURN_TREADS;
    return Offset(cast(float)(radius * cos(angle)), cast(float)(radius * sin(angle)));
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

ulong strongestAround(Turtle face) {
    ulong strongest = face.probeHash(SitePart.face);
    foreach (corner; cornersOf(face)) {
        strongest = higherOf(corner.left().probeHash(SitePart.face), strongest);
    }
    return strongest;
}

Turtle settled(Turtle start) {
    Turtle least = start;
    ulong lowest = start.probeHash(SitePart.face);
    Turtle rolled = start;
    foreach (_; 1 .. EDGE_FACES) {
        rolled = rolled.rollRight();
        ulong hash = rolled.probeHash(SitePart.face);
        if (hash < lowest) {
            lowest = hash;
            least = rolled;
        }
    }
    return least;
}

ulong strongestNear(Turtle face) {
    ulong strongest = strongestAround(face);
    foreach (corner; cornersOf(face)) {
        strongest = higherOf(strongestAround(corner.left()), strongest);
    }
    return strongest;
}

struct Hashes {
    ulong[MOST_HASHES] items;
    uint count;

    bool contains(ulong hash) const {
        uint index = 0;
        while (index < count && items[index] != hash) {
            index += 1;
        }
        return index < count;
    }

    void add(ulong hash) {
        if (!contains(hash)) {
            assert(count < MOST_HASHES);
            items[count] = hash;
            count += 1;
        }
    }
}

struct Turtle {
    const(Api)* api;
    Site site;

    Turtle forward(int edges) const {
        return Turtle(api, api.forward(api, site, edges));
    }

    Turtle turn(Turn how) const {
        return Turtle(api, api.turn(api, site, how));
    }

    Turtle left() const {
        return turn(Turn.left);
    }

    Turtle right() const {
        return turn(Turn.right);
    }

    Turtle pitchUp() const {
        return turn(Turn.pitchUp);
    }

    Turtle pitchDown() const {
        return turn(Turn.pitchDown);
    }

    Turtle rollLeft() const {
        return turn(Turn.rollLeft);
    }

    Turtle rollRight() const {
        return turn(Turn.rollRight);
    }

    Span column() const {
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

    int pickBetween(int low, int high) const {
        return low + cast(int) pick(high - low + 1);
    }

    bool rollChance(uint percent) const {
        return api.pick(api, PERCENT) < percent;
    }

    double rollUnit() const {
        return api.random(api);
    }

    ulong probeHash(SitePart part) const {
        return api.probeHash(api, site, part);
    }

    void paint(Material material, Box area, Rhythm rhythm = EVERY_HEIGHT) const {
        api.paint(api, site, material, area, rhythm);
    }

    void fill(Material material, Box area, Rhythm rhythm = EVERY_HEIGHT) const {
        api.fill(api, site, material, area, rhythm);
    }

    void paintRows(Material material, ref const Rows rows, Span z, Rhythm rhythm = EVERY_HEIGHT) const {
        foreach (row; rows.slice()) {
            paint(material, boxOf(row.x, Span(row.y, row.y), z), rhythm);
        }
    }

    void fillRows(Material material, ref const Rows rows, Span z, Rhythm rhythm = EVERY_HEIGHT) const {
        foreach (row; rows.slice()) {
            fill(material, boxOf(row.x, Span(row.y, row.y), z), rhythm);
        }
    }

    void clearOver(ref const Rows room, int tread) const {
        int low = higherOf(0, tread + 1);
        int high = lowerOf(edgeCells() - 1, tread + STAIR_HEADROOM);
        if (low <= high) {
            paintRows(Material.none, room, Span(low, high));
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

    bool probeClaimed(SitePart part) const {
        return api.probeClaimed(api, site, part);
    }

    int probeBalance(int most) const {
        return api.probeBalance(api, site, most);
    }

    KindTag probeRising() const {
        return api.probeRising(api, site);
    }

    bool probePort() const {
        return api.probePort(api, site);
    }

    double probeCrust() const {
        return api.probeCrust(api, site);
    }

    bool build(const(char)* world) const {
        return api.build(api, world, site);
    }

    Drawing openPen() const {
        return Drawing(api, api.openPen(api, site));
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

    double rollUnit() const {
        return api.random(api);
    }

    double pickBetween(double low, double high) const {
        return low + (high - low) * rollUnit();
    }
}
