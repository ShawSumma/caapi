module plugins.carve.carve;

import core.stdc.math : asin, floor, sin, sqrt;
import plugins.api.api : Material, SitePart, Span;
import plugins.turtle.turtle : Drawing, MIX, PI, Turtle, boxOf;

enum uint WAY_COUNT = 6;
enum double RADIANS_PER_DEGREE = PI / 180;
enum double QUARTER_TURN = 90;
enum double HALF_TURN = 180;
enum uint MOST_ROW = 24;
enum uint MOST_RUNS = MOST_ROW * MOST_ROW;
enum uint UNIT_STEPS = 1 << 24;
enum uint UNIT_SHIFT = 40;
enum ulong LATTICE_X = MIX;
enum ulong LATTICE_Y = MIX * MIX;
enum ulong LATTICE_Z = MIX * MIX * MIX;
enum uint FOLD_SHIFT = 31;

struct Vec {
    double x = 0;
    double y = 0;
    double z = 0;
}

Vec plus(Vec a, Vec b) {
    return Vec(a.x + b.x, a.y + b.y, a.z + b.z);
}

Vec minus(Vec a, Vec b) {
    return Vec(a.x - b.x, a.y - b.y, a.z - b.z);
}

Vec scaled(Vec a, double k) {
    return Vec(a.x * k, a.y * k, a.z * k);
}

double dot(Vec a, Vec b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

double squared(Vec a) {
    return a.dot(a);
}

double length(Vec a) {
    return sqrt(a.squared);
}

Vec normalized(Vec a) {
    return a.scaled(1 / a.length);
}

Vec rejected(Vec a, Vec unit) {
    return a.minus(unit.scaled(a.dot(unit)));
}

Vec mixed(Vec a, Vec b, double share) {
    return a.scaled(1 - share).plus(b.scaled(share));
}

Vec combined(Vec a, Vec b, Vec c, Vec weights) {
    return a.scaled(weights.x).plus(b.scaled(weights.y)).plus(c.scaled(weights.z));
}

ulong hashed(ulong hash, ulong salt) {
    ulong value = (hash ^ salt) * MIX;
    value ^= value >> FOLD_SHIFT;
    value *= MIX;
    value ^= value >> FOLD_SHIFT;
    return value;
}

double unitOf(ulong hash, ulong salt) {
    return (hashed(hash, salt) >> UNIT_SHIFT) / cast(double) UNIT_STEPS;
}

double between(ulong hash, ulong salt, double low, double high) {
    return low + (high - low) * unitOf(hash, salt);
}

ulong latticeHash(ulong seed, long x, long y, long z) {
    return hashed(seed ^ (x * LATTICE_X) ^ (y * LATTICE_Y) ^ (z * LATTICE_Z), seed);
}

double smoothed(double share) {
    return share * share * (3 - 2 * share);
}

double noiseAt(ulong seed, Vec at, double scale) {
    Vec cell = at.scaled(1 / scale);
    double fx = floor(cell.x);
    double fy = floor(cell.y);
    double fz = floor(cell.z);
    long ix = cast(long) fx;
    long iy = cast(long) fy;
    long iz = cast(long) fz;
    double sx = smoothed(cell.x - fx);
    double sy = smoothed(cell.y - fy);
    double sz = smoothed(cell.z - fz);
    double total = 0;
    foreach (corner; 0 .. 8) {
        long dx = corner & 1;
        long dy = (corner >> 1) & 1;
        long dz = (corner >> 2) & 1;
        double weight = weightOf(sx, dx) * weightOf(sy, dy) * weightOf(sz, dz);
        total += weight * ((latticeHash(seed, ix + dx, iy + dy, iz + dz) >> UNIT_SHIFT) / cast(double) UNIT_STEPS);
    }
    return total;
}

double weightOf(double share, long side) {
    if (side == 0) {
        return 1 - share;
    } else {
        return share;
    }
}

enum Way : ubyte {
    zPlus,
    zMinus,
    xPlus,
    xMinus,
    yPlus,
    yMinus,
}

immutable Way[WAY_COUNT] WAYS = [Way.zPlus, Way.zMinus, Way.xPlus, Way.xMinus, Way.yPlus, Way.yMinus];

immutable Vec[WAY_COUNT] AXES = [
    Way.zPlus: Vec(0, 0, 1),
    Way.zMinus: Vec(0, 0, -1),
    Way.xPlus: Vec(1, 0, 0),
    Way.xMinus: Vec(-1, 0, 0),
    Way.yPlus: Vec(0, 1, 0),
    Way.yMinus: Vec(0, -1, 0),
];

struct Basis {
    Vec x;
    Vec y;
    Vec z;
}

immutable Basis[WAY_COUNT] ALONG_AXES = [
    Way.zPlus: Basis(Vec(1, 0, 0), Vec(0, 1, 0), Vec(0, 0, 1)),
    Way.zMinus: Basis(Vec(1, 0, 0), Vec(0, -1, 0), Vec(0, 0, -1)),
    Way.xPlus: Basis(Vec(0, 0, -1), Vec(0, 1, 0), Vec(1, 0, 0)),
    Way.xMinus: Basis(Vec(0, 0, 1), Vec(0, 1, 0), Vec(-1, 0, 0)),
    Way.yPlus: Basis(Vec(1, 0, 0), Vec(0, 0, -1), Vec(0, 1, 0)),
    Way.yMinus: Basis(Vec(1, 0, 0), Vec(0, 0, 1), Vec(0, -1, 0)),
];

Vec axisOf(Way way) {
    return AXES[way];
}

Vec fromAlong(Way way, Vec inAlong) {
    Basis basis = ALONG_AXES[way];
    return combined(basis.x, basis.y, basis.z, inAlong);
}

Way opposite(Way way) {
    final switch (way) {
        case Way.zPlus:
            return Way.zMinus;
        case Way.zMinus:
            return Way.zPlus;
        case Way.xPlus:
            return Way.xMinus;
        case Way.xMinus:
            return Way.xPlus;
        case Way.yPlus:
            return Way.yMinus;
        case Way.yMinus:
            return Way.yPlus;
    }
}

Turtle along(Turtle frame, Way way) {
    final switch (way) {
        case Way.zPlus:
            return frame;
        case Way.zMinus:
            return frame.pitchUp().pitchUp();
        case Way.xPlus:
            return frame.right();
        case Way.xMinus:
            return frame.left();
        case Way.yPlus:
            return frame.pitchUp();
        case Way.yMinus:
            return frame.pitchDown();
    }
}

Turtle unturned(Turtle frame, Way way) {
    final switch (way) {
        case Way.zPlus:
            return frame;
        case Way.zMinus:
            return frame.pitchUp().pitchUp();
        case Way.xPlus:
            return frame.left();
        case Way.xMinus:
            return frame.right();
        case Way.yPlus:
            return frame.pitchDown();
        case Way.yMinus:
            return frame.pitchUp();
    }
}

Turtle carried(Turtle frame, Way way) {
    return unturned(along(frame, way).forward(1), way);
}

Drawing aimed(Drawing pen, Way way) {
    final switch (way) {
        case Way.zPlus:
            return pen;
        case Way.zMinus:
            return pen.turn(HALF_TURN, 0);
        case Way.xPlus:
            return pen.turn(QUARTER_TURN, 0);
        case Way.xMinus:
            return pen.turn(-QUARTER_TURN, 0);
        case Way.yPlus:
            return pen.turn(0, QUARTER_TURN);
        case Way.yMinus:
            return pen.turn(0, -QUARTER_TURN);
    }
}

Drawing unaimed(Drawing pen, Way way) {
    final switch (way) {
        case Way.zPlus:
            return pen;
        case Way.zMinus:
            return pen.turn(-HALF_TURN, 0);
        case Way.xPlus:
            return pen.turn(-QUARTER_TURN, 0);
        case Way.xMinus:
            return pen.turn(QUARTER_TURN, 0);
        case Way.yPlus:
            return pen.turn(0, -QUARTER_TURN);
        case Way.yMinus:
            return pen.turn(0, QUARTER_TURN);
    }
}

Drawing penCarried(Drawing pen, Way way, double cells) {
    return unaimed(aimed(pen, way).forward(cells), way);
}

double sineOf(double degrees) {
    return sin(degrees * RADIANS_PER_DEGREE);
}

double degreesOf(double sine) {
    double held = sine;
    if (held > 1) {
        held = 1;
    } else if (held < -1) {
        held = -1;
    }
    return asin(held) / RADIANS_PER_DEGREE;
}

Vec upOf(Drawing pen) {
    Vec up = Vec(sineOf(pen.turn(QUARTER_TURN, 0).rise()), sineOf(pen.turn(0, QUARTER_TURN).rise()), sineOf(pen.rise()));
    return up.normalized;
}

ulong edgeHash(Turtle frame, Way way) {
    return along(frame, way).probeHash(SitePart.edge);
}

struct Triad {
    Vec[3] axes;
    Way[3] ways;
}

Triad triadAt(Turtle frame) {
    ulong[WAY_COUNT] hashes;
    foreach (way; WAYS) {
        hashes[way] = edgeHash(frame, way);
    }
    Triad triad;
    Way[3] taken;
    foreach (index; 0 .. 3) {
        Way best = Way.zPlus;
        ulong least = ulong.max;
        foreach (way; WAYS) {
            if (hashes[way] <= least && !isTakenLine(taken[0 .. index], way)) {
                least = hashes[way];
                best = way;
            }
        }
        taken[index] = best;
        triad.ways[index] = best;
        triad.axes[index] = axisOf(best);
    }
    return triad;
}

bool isTakenLine(const(Way)[] taken, Way way) {
    foreach (other; taken) {
        if (other == way || opposite(other) == way) {
            return true;
        }
    }
    return false;
}

bool isOwnedBy(ref const Triad triad, Way own) {
    return triad.ways[0] == own || opposite(triad.ways[0]) == own;
}

Vec physicalOf(ref const Triad triad, Vec chart) {
    return Vec(chart.dot(triad.axes[0]), chart.dot(triad.axes[1]), chart.dot(triad.axes[2]));
}

Vec chartOf(ref const Triad triad, Vec physical) {
    return combined(triad.axes[0], triad.axes[1], triad.axes[2], physical);
}

struct Slab {
    Turtle frame;
    Span x;
    Span y;
    Span z;
}

Slab slabAt(Turtle frame, Way own) {
    Span column = frame.column();
    int cells = column.high + 1;
    if (own == Way.zPlus) {
        return Slab(frame, column, column, Span(0, cells - 1));
    } else {
        return Slab(frame, column, column, Span(-cells, -1));
    }
}

Vec centerOf(int x, int y, int z) {
    return Vec(x + 0.5, y + 0.5, z + 0.5);
}

enum Painting : ubyte {
    kept,
    painted,
}

struct Choice {
    Material material;
    Painting painting;

    static Choice keep() {
        return Choice(Material.none, Painting.kept);
    }

    static Choice of(Material material) {
        return Choice(material, Painting.painted);
    }
}

struct Run {
    Span x;
    int y;
    int zLow;
    Material material;
}

struct Runs {
    Run[MOST_RUNS] items;
    uint count;

    void add(Run run) {
        assert(count < MOST_RUNS);
        items[count] = run;
        count += 1;
    }
}

bool isBefore(ref const Run a, ref const Run b) {
    return a.y < b.y || (a.y == b.y && a.x.low < b.x.low);
}

void flush(Turtle frame, ref const Run run, int zHigh) {
    frame.paint(run.material, boxOf(run.x, Span(run.y, run.y), Span(run.zLow, zHigh)));
}

void emit(alias choose)(Slab slab) {
    int width = slab.x.high - slab.x.low + 1;
    assert(width <= MOST_ROW && slab.y.high - slab.y.low < MOST_ROW);
    Runs open;
    Runs fresh;
    Runs next;
    Choice[MOST_ROW] row;
    foreach (z; slab.z.low .. slab.z.high + 1) {
        fresh.count = 0;
        foreach (y; slab.y.low .. slab.y.high + 1) {
            foreach (index; 0 .. width) {
                row[index] = choose(centerOf(slab.x.low + index, y, z));
            }
            int start = 0;
            while (start < width) {
                int end = start;
                while (end + 1 < width && isSame(row[end + 1], row[start])) {
                    end += 1;
                }
                if (row[start].painting == Painting.painted) {
                    fresh.add(Run(Span(slab.x.low + start, slab.x.low + end), y, z, row[start].material));
                }
                start = end + 1;
            }
        }
        next.count = 0;
        uint index = 0;
        foreach (made; fresh.items[0 .. fresh.count]) {
            while (index < open.count && isBefore(open.items[index], made)) {
                flush(slab.frame, open.items[index], z - 1);
                index += 1;
            }
            if (index < open.count && open.items[index].y == made.y && open.items[index].x.low == made.x.low) {
                if (open.items[index].x.high == made.x.high && open.items[index].material == made.material) {
                    next.add(open.items[index]);
                } else {
                    flush(slab.frame, open.items[index], z - 1);
                    next.add(made);
                }
                index += 1;
            } else {
                next.add(made);
            }
        }
        while (index < open.count) {
            flush(slab.frame, open.items[index], z - 1);
            index += 1;
        }
        foreach (kept; 0 .. next.count) {
            open.items[kept] = next.items[kept];
        }
        open.count = next.count;
    }
    foreach (left; open.items[0 .. open.count]) {
        flush(slab.frame, left, slab.z.high);
    }
}

bool isSame(Choice a, Choice b) {
    return a.painting == b.painting && (a.painting == Painting.kept || a.material == b.material);
}
