module common.worldgen.blueprint;

import common.array : Array;
import common.dodeca : Side, Vertex;
import common.graph : Graph;
import common.material : Material;
import common.worldgen.structure : CanonicalSite, ColumnSpot, LineTransform, SiteFrame, canonicalOf, edgeCells;

enum size_t MAX_MATERIALS = ubyte.max;

struct Paint {
    ubyte material;
    bool isIntoAirOnly;
}

struct CellBox {
    int[3] low;
    int[3] high;

    static CellBox make(int acrossLow, int acrossHigh, int alongLow, int alongHigh, int heightLow, int heightHigh) {
        return CellBox([acrossLow, alongLow, heightLow], [acrossHigh, alongHigh, heightHigh]);
    }

    bool contains(int[3] cell) const {
        return cell[0] >= low[0] && cell[0] <= high[0] && cell[1] >= low[1] && cell[1] <= high[1] && cell[2] >= low[2] && cell[2] <= high[2];
    }

    bool overlaps(ref const CellBox other) const {
        return low[0] <= other.high[0] && other.low[0] <= high[0] && low[1] <= other.high[1] && other.low[1] <= high[1] && low[2] <= other.high[2] && other.low[2] <= high[2];
    }
}

struct Rhythm {
    int period;
    int phase;
    int span;

    bool includes(int height) const {
        if (period == 0) {
            return true;
        } else {
            int offset = (height - phase) % period;
            if (offset < 0) {
                offset += period;
            }
            return offset < span;
        }
    }
}

enum Rhythm EVERY_HEIGHT = Rhythm(0, 0, 0);

struct Brush {
    CellBox box;
    Rhythm rhythm;
    uint line;
    Paint paint;

    bool covers(int[3] column) const {
        return box.contains(column) && rhythm.includes(column[2]);
    }
}

struct LineSpec {
    int lowest;
    int highest;
    uint node;
    Vertex lower;
    Side acrossSide;
    Side alongSide;
}

struct RouteStop {
    SiteFrame site;
    ColumnSpot spot;
}

struct SiteLine {
    SiteFrame site;
    LineTransform transform;
    uint line;
}

struct Blueprint {
    Array!LineSpec lines;
    Array!Brush brushes;
    Array!RouteStop route;
    Array!Material materials;
    RouteStop entrance;
    ubyte dimension;
    bool hasEntrance;

    static Blueprint make(ubyte chunkDimension) {
        return Blueprint(Array!LineSpec.init, Array!Brush.init, Array!RouteStop.init, Array!Material.init, RouteStop.init, chunkDimension, false);
    }

    uint lineOf(LineSpec spec) {
        uint index = 0;
        while (index < lines.length && !isSameLine(lines.ptr[index], spec)) {
            index += 1;
        }
        if (index == lines.length) {
            lines.append(spec);
        }
        return index;
    }

    ubyte paintOf(Material material) {
        uint index = 0;
        while (index < materials.length && materials.ptr[index] != material) {
            index += 1;
        }
        if (index == materials.length) {
            assert(materials.length < MAX_MATERIALS);
            materials.append(material);
        }
        return cast(ubyte)(index + 1);
    }

    void finish() {
        foreach (ref spec; lines.slice()) {
            spec.lowest = int.max;
            spec.highest = int.min;
        }
        foreach (brush; brushes.slice()) {
            LineSpec* spec = &lines.ptr[brush.line];
            spec.lowest = lowerOf(spec.lowest, lowestLevel(brush.box.low[2], dimension));
            spec.highest = higherOf(spec.highest, highestLevel(brush.box.high[2], dimension));
        }
    }

    void release() {
        lines.release();
        brushes.release();
        route.release();
        materials.release();
    }
}

struct BlueprintBuilder {
    Blueprint blueprint;
    Array!SiteLine known;
    Graph* graph;

    static BlueprintBuilder make(ref Graph target) {
        return BlueprintBuilder(Blueprint.make(target.layout.dimension), Array!SiteLine.init, &target);
    }

    SiteLine lineOf(SiteFrame site) {
        uint index = 0;
        while (index < known.length && known.ptr[index].site != site) {
            index += 1;
        }
        if (index == known.length) {
            CanonicalSite canonical = (*graph).canonicalOf(site);
            known.append(SiteLine(site, canonical.transform, blueprint.lineOf(canonical.line)));
        }
        return known.ptr[index];
    }

    void paint(SiteFrame site, CellBox box, Rhythm rhythm, Material material, bool isIntoAirOnly) {
        SiteLine found = lineOf(site);
        Brush brush = Brush(canonicalBox(box, found.transform, blueprint.dimension), canonicalRhythm(rhythm, found.transform, blueprint.dimension), found.line, Paint(blueprint.paintOf(material), isIntoAirOnly));
        blueprint.brushes.append(brush);
    }

    void stop(SiteFrame site, ColumnSpot spot) {
        blueprint.route.append(RouteStop(site, spot));
    }

    void enter(SiteFrame site, ColumnSpot spot) {
        if (!blueprint.hasEntrance) {
            blueprint.entrance = RouteStop(site, spot);
            blueprint.hasEntrance = true;
        }
    }

    Blueprint finish() {
        known.release();
        blueprint.finish();
        return blueprint;
    }

    void release() {
        known.release();
        blueprint.release();
    }
}

CellBox canonicalBox(CellBox local, LineTransform transform, ubyte dimension) {
    int[2] across = signedRange(local.low[0], local.high[0], transform.acrossSign);
    int[2] along = signedRange(local.low[1], local.high[1], transform.alongSign);
    int[2] height = heightRange(local.low[2], local.high[2], transform, dimension);
    if (transform.isSwapped) {
        return CellBox.make(along[0], along[1], across[0], across[1], height[0], height[1]);
    } else {
        return CellBox.make(across[0], across[1], along[0], along[1], height[0], height[1]);
    }
}

int[2] signedRange(int low, int high, int sign) {
    if (sign > 0) {
        return [low, high];
    } else {
        return [-1 - high, -1 - low];
    }
}

int[2] heightRange(int low, int high, LineTransform transform, ubyte dimension) {
    int offset = transform.offsetLevels * edgeCells(dimension);
    if (transform.heightSign > 0) {
        return [movedHeight(low, offset), movedHeight(high, offset)];
    } else {
        return [mirroredHeight(high, offset), mirroredHeight(low, offset)];
    }
}

int movedHeight(int height, int offset) {
    if (height == int.min || height == int.max) {
        return height;
    } else {
        return height + offset;
    }
}

int mirroredHeight(int height, int offset) {
    if (height == int.min) {
        return int.max;
    } else if (height == int.max) {
        return int.min;
    } else {
        return offset - 1 - height;
    }
}

Rhythm canonicalRhythm(Rhythm local, LineTransform transform, ubyte dimension) {
    int offset = transform.offsetLevels * edgeCells(dimension);
    if (local.period == 0) {
        return local;
    } else if (transform.heightSign > 0) {
        return Rhythm(local.period, local.phase + offset, local.span);
    } else {
        return Rhythm(local.period, offset - local.phase - local.span, local.span);
    }
}

bool isSameLine(ref const LineSpec a, ref const LineSpec b) {
    return a.node == b.node && a.lower == b.lower && a.acrossSide == b.acrossSide && a.alongSide == b.alongSide;
}

int lowestLevel(int height, ubyte dimension) {
    if (height == int.min) {
        return int.min;
    } else {
        return ceilingDivision(height - dimension + 1, edgeCells(dimension));
    }
}

int highestLevel(int height, ubyte dimension) {
    if (height == int.max) {
        return int.max;
    } else {
        return floorDivision(height + dimension, edgeCells(dimension));
    }
}

int floorDivision(int value, int divisor) {
    int quotient = value / divisor;
    if (value % divisor != 0 && value < 0) {
        quotient -= 1;
    }
    return quotient;
}

int ceilingDivision(int value, int divisor) {
    return -floorDivision(-value, divisor);
}

int lowerOf(int a, int b) {
    if (a < b) {
        return a;
    } else {
        return b;
    }
}

int higherOf(int a, int b) {
    if (a > b) {
        return a;
    } else {
        return b;
    }
}

unittest {
    assert(lowestLevel(-3, 12) == 0 && highestLevel(73, 12) == 3);
    assert(lowestLevel(-12, 12) == 0 && lowestLevel(-13, 12) == -1);
    assert(highestLevel(11, 12) == 0 && highestLevel(12, 12) == 1);
    assert(lowestLevel(int.min, 12) == int.min && highestLevel(int.max, 12) == int.max);
    LineTransform mirrored = LineTransform(2, 1, 1, -1, false);
    Rhythm local = Rhythm(8, 1, 3);
    Rhythm moved = canonicalRhythm(local, mirrored, 12);
    foreach (height; -20 .. 20) {
        assert(local.includes(height) == moved.includes(2 * 24 - 1 - height));
    }
}
