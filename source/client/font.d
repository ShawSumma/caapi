module client.font;

import core.stdc.math : ceilf, fabsf, floorf, sqrtf;
import base.array : Array;
import base.maybe : Maybe;
import base.numbers : higherOf, lowerOf;

immutable ubyte[] PLEX_MONO = cast(immutable(ubyte)[]) import("IBMPlexMono-Regular.ttf");

enum uint TRUETYPE_VERSION = 0x00010000;
enum size_t DIRECTORY_TABLE_COUNT = 4;
enum size_t DIRECTORY_RECORDS = 12;
enum size_t TABLE_RECORD_SIZE = 16;
enum size_t TABLE_RECORD_OFFSET = 8;
enum size_t TAG_SIZE = 4;
enum size_t HEAD_UNITS_PER_EM = 18;
enum size_t HEAD_INDEX_TO_LOC_FORMAT = 50;
enum size_t MAXP_GLYPH_COUNT = 4;
enum size_t HHEA_ASCENDER = 4;
enum size_t HHEA_DESCENDER = 6;
enum size_t HHEA_LINE_GAP = 8;
enum size_t HHEA_HORIZONTAL_METRICS = 34;
enum size_t HORIZONTAL_METRIC_SIZE = 4;
enum size_t CMAP_TABLE_COUNT = 2;
enum size_t CMAP_RECORDS = 4;
enum size_t ENCODING_RECORD_SIZE = 8;
enum size_t ENCODING_SUBTABLE_OFFSET = 4;
enum ushort SEGMENT_FORMAT = 4;
enum size_t SEGMENT_COUNT_DOUBLED = 6;
enum size_t SEGMENT_END_CODES = 14;
enum size_t SEGMENT_RESERVED_PAD = 2;
enum size_t GLYPH_HEADER_SIZE = 10;
enum size_t GLYPH_X_MIN = 2;
enum size_t GLYPH_Y_MIN = 4;
enum size_t GLYPH_X_MAX = 6;
enum size_t GLYPH_Y_MAX = 8;
enum ubyte ON_CURVE_POINT = 0x01;
enum ubyte X_SHORT_VECTOR = 0x02;
enum ubyte Y_SHORT_VECTOR = 0x04;
enum ubyte REPEAT_FLAG = 0x08;
enum ubyte X_IS_SAME_OR_POSITIVE = 0x10;
enum ubyte Y_IS_SAME_OR_POSITIVE = 0x20;
enum ushort ARG_1_AND_2_ARE_WORDS = 0x0001;
enum ushort ARGS_ARE_XY_VALUES = 0x0002;
enum ushort WE_HAVE_A_SCALE = 0x0008;
enum ushort MORE_COMPONENTS = 0x0020;
enum ushort WE_HAVE_AN_X_AND_Y_SCALE = 0x0040;
enum ushort WE_HAVE_A_TWO_BY_TWO = 0x0080;
enum float F2DOT14_ONE = 1 << 14;
enum float FLATTEN_TOLERANCE = 0.05f;
enum uint SUMMED_COLUMNS = 2;
enum float FULL_COVERAGE = 255;

enum LocaFormat : ubyte {
    halved,
    full,
}

ushort readU16(const(ubyte)[] bytes, size_t at) {
    return cast(ushort)((bytes[at] << 8) | bytes[at + 1]);
}

short readI16(const(ubyte)[] bytes, size_t at) {
    return cast(short) readU16(bytes, at);
}

uint readU32(const(ubyte)[] bytes, size_t at) {
    return (cast(uint) bytes[at] << 24) | (cast(uint) bytes[at + 1] << 16) | (cast(uint) bytes[at + 2] << 8) | bytes[at + 3];
}

float readF2Dot14(const(ubyte)[] bytes, size_t at) {
    return readI16(bytes, at) / F2DOT14_ONE;
}

size_t tableAt(const(ubyte)[] bytes, string tag) {
    size_t count = readU16(bytes, DIRECTORY_TABLE_COUNT);
    size_t index = 0;
    while (index < count && bytes[recordAt(index) .. recordAt(index) + TAG_SIZE] != cast(const(ubyte)[]) tag) {
        index += 1;
    }
    assert(index < count);
    return readU32(bytes, recordAt(index) + TABLE_RECORD_OFFSET);
}

size_t recordAt(size_t index) {
    return DIRECTORY_RECORDS + index * TABLE_RECORD_SIZE;
}

size_t subtableAt(const(ubyte)[] bytes, size_t cmap, size_t index) {
    return cmap + readU32(bytes, cmap + CMAP_RECORDS + index * ENCODING_RECORD_SIZE + ENCODING_SUBTABLE_OFFSET);
}

size_t segmentSubtable(const(ubyte)[] bytes, size_t cmap) {
    size_t count = readU16(bytes, cmap + CMAP_TABLE_COUNT);
    size_t index = 0;
    while (index < count && readU16(bytes, subtableAt(bytes, cmap, index)) != SEGMENT_FORMAT) {
        index += 1;
    }
    assert(index < count);
    return subtableAt(bytes, cmap, index);
}

LocaFormat locaFormatOf(short stored) {
    if (stored == 0) {
        return LocaFormat.halved;
    } else {
        assert(stored == 1);
        return LocaFormat.full;
    }
}

struct GlyphBounds {
    short xMin;
    short yMin;
    short xMax;
    short yMax;
}

struct Font {
    const(ubyte)[] bytes;
    size_t glyf;
    size_t loca;
    size_t hmtx;
    size_t segments;
    ushort unitsPerEm;
    ushort glyphCount;
    ushort horizontalMetrics;
    short ascender;
    short descender;
    short lineGap;
    LocaFormat locaFormat;

    static Font make(const(ubyte)[] bytes) {
        assert(readU32(bytes, 0) == TRUETYPE_VERSION);
        size_t head = bytes.tableAt("head");
        size_t hhea = bytes.tableAt("hhea");
        size_t maxp = bytes.tableAt("maxp");
        return Font(
            bytes,
            bytes.tableAt("glyf"),
            bytes.tableAt("loca"),
            bytes.tableAt("hmtx"),
            bytes.segmentSubtable(bytes.tableAt("cmap")),
            readU16(bytes, head + HEAD_UNITS_PER_EM),
            readU16(bytes, maxp + MAXP_GLYPH_COUNT),
            readU16(bytes, hhea + HHEA_HORIZONTAL_METRICS),
            readI16(bytes, hhea + HHEA_ASCENDER),
            readI16(bytes, hhea + HHEA_DESCENDER),
            readI16(bytes, hhea + HHEA_LINE_GAP),
            locaFormatOf(readI16(bytes, head + HEAD_INDEX_TO_LOC_FORMAT)),
        );
    }
}

ushort glyphOf(ref const Font font, uint code) {
    const(ubyte)[] bytes = font.bytes;
    size_t segmentCount = readU16(bytes, font.segments + SEGMENT_COUNT_DOUBLED) / 2;
    size_t ends = font.segments + SEGMENT_END_CODES;
    size_t starts = ends + 2 * segmentCount + SEGMENT_RESERVED_PAD;
    size_t deltas = starts + 2 * segmentCount;
    size_t rangeOffsets = deltas + 2 * segmentCount;
    size_t segment = 0;
    while (segment < segmentCount && readU16(bytes, ends + 2 * segment) < code) {
        segment += 1;
    }
    assert(segment < segmentCount);
    uint start = readU16(bytes, starts + 2 * segment);
    ushort delta = readU16(bytes, deltas + 2 * segment);
    size_t rangeOffsetAt = rangeOffsets + 2 * segment;
    uint rangeOffset = readU16(bytes, rangeOffsetAt);
    if (start > code) {
        return 0;
    } else if (rangeOffset == 0) {
        return cast(ushort)(code + delta);
    } else {
        ushort found = readU16(bytes, rangeOffsetAt + rangeOffset + 2 * (code - start));
        if (found == 0) {
            return 0;
        } else {
            return cast(ushort)(found + delta);
        }
    }
}

size_t glyphStart(ref const Font font, uint glyph) {
    final switch (font.locaFormat) {
        case LocaFormat.halved:
            return 2 * cast(size_t) readU16(font.bytes, font.loca + 2 * glyph);
        case LocaFormat.full:
            return readU32(font.bytes, font.loca + 4 * glyph);
    }
}

bool hasOutline(ref const Font font, ushort glyph) {
    return font.glyphStart(glyph + 1) > font.glyphStart(glyph);
}

Maybe!GlyphBounds boundsOf(ref const Font font, ushort glyph) {
    if (font.hasOutline(glyph)) {
        size_t at = font.glyf + font.glyphStart(glyph);
        return Maybe!GlyphBounds.of(GlyphBounds(readI16(font.bytes, at + GLYPH_X_MIN), readI16(font.bytes, at + GLYPH_Y_MIN), readI16(font.bytes, at + GLYPH_X_MAX), readI16(font.bytes, at + GLYPH_Y_MAX)));
    } else {
        return Maybe!GlyphBounds.init;
    }
}

ushort advanceOf(ref const Font font, ushort glyph) {
    size_t index = lowerOf(cast(size_t) glyph, cast(size_t) font.horizontalMetrics - 1);
    return readU16(font.bytes, font.hmtx + index * HORIZONTAL_METRIC_SIZE);
}

struct Transform {
    float xFromX = 1;
    float xFromY = 0;
    float yFromX = 0;
    float yFromY = 1;
    float dx = 0;
    float dy = 0;
}

Transform after(Transform outer, Transform inner) {
    return Transform(
        outer.xFromX * inner.xFromX + outer.xFromY * inner.yFromX,
        outer.xFromX * inner.xFromY + outer.xFromY * inner.yFromY,
        outer.yFromX * inner.xFromX + outer.yFromY * inner.yFromX,
        outer.yFromX * inner.xFromY + outer.yFromY * inner.yFromY,
        outer.xFromX * inner.dx + outer.xFromY * inner.dy + outer.dx,
        outer.yFromX * inner.dx + outer.yFromY * inner.dy + outer.dy,
    );
}

struct OutlinePoint {
    float x;
    float y;
    ubyte flags;
}

bool isOnCurve(OutlinePoint point) {
    return (point.flags & ON_CURVE_POINT) != 0;
}

struct Outline {
    Array!OutlinePoint points;
    Array!uint ends;

    void clear() {
        points.clear();
        ends.clear();
    }

    void release() {
        points.release();
        ends.release();
    }
}

void addGlyph(ref const Font font, ushort glyph, Transform transform, ref Outline outline) {
    if (font.hasOutline(glyph)) {
        size_t at = font.glyf + font.glyphStart(glyph);
        short contours = readI16(font.bytes, at);
        if (contours >= 0) {
            addSimpleGlyph(font.bytes, at, contours, transform, outline);
        } else {
            font.addCompositeGlyph(at, transform, outline);
        }
    }
}

int coordinateDelta(const(ubyte)[] bytes, ref size_t cursor, ubyte flags, ubyte shortVector, ubyte sameOrPositive) {
    if ((flags & shortVector) != 0) {
        int magnitude = bytes[cursor];
        cursor += 1;
        if ((flags & sameOrPositive) != 0) {
            return magnitude;
        } else {
            return -magnitude;
        }
    } else if ((flags & sameOrPositive) != 0) {
        return 0;
    } else {
        int delta = readI16(bytes, cursor);
        cursor += 2;
        return delta;
    }
}

void addSimpleGlyph(const(ubyte)[] bytes, size_t at, short contours, Transform transform, ref Outline outline) {
    size_t endPoints = at + GLYPH_HEADER_SIZE;
    size_t pointCount = 0;
    if (contours > 0) {
        pointCount = readU16(bytes, endPoints + 2 * (contours - 1)) + 1;
    }
    size_t instructions = endPoints + 2 * contours;
    size_t cursor = instructions + 2 + readU16(bytes, instructions);
    size_t first = outline.points.length;
    outline.points.resize(first + pointCount);
    OutlinePoint[] points = outline.points.slice()[first .. $];
    size_t index = 0;
    while (index < pointCount) {
        ubyte flags = bytes[cursor];
        cursor += 1;
        size_t repeats = 0;
        if ((flags & REPEAT_FLAG) != 0) {
            repeats = bytes[cursor];
            cursor += 1;
        }
        foreach (_; 0 .. repeats + 1) {
            points[index].flags = flags;
            index += 1;
        }
    }
    int x = 0;
    foreach (ref point; points) {
        x += coordinateDelta(bytes, cursor, point.flags, X_SHORT_VECTOR, X_IS_SAME_OR_POSITIVE);
        point.x = x;
    }
    int y = 0;
    foreach (ref point; points) {
        y += coordinateDelta(bytes, cursor, point.flags, Y_SHORT_VECTOR, Y_IS_SAME_OR_POSITIVE);
        point.y = y;
    }
    foreach (ref point; points) {
        float fontX = point.x;
        float fontY = point.y;
        point.x = transform.xFromX * fontX + transform.xFromY * fontY + transform.dx;
        point.y = transform.yFromX * fontX + transform.yFromY * fontY + transform.dy;
    }
    foreach (contour; 0 .. contours) {
        outline.ends.append(cast(uint)(first + readU16(bytes, endPoints + 2 * contour) + 1));
    }
}

void addCompositeGlyph(ref const Font font, size_t at, Transform transform, ref Outline outline) {
    const(ubyte)[] bytes = font.bytes;
    size_t cursor = at + GLYPH_HEADER_SIZE;
    ushort flags;
    do {
        flags = readU16(bytes, cursor);
        ushort component = readU16(bytes, cursor + 2);
        cursor += 4;
        assert((flags & ARGS_ARE_XY_VALUES) != 0);
        Transform part;
        if ((flags & ARG_1_AND_2_ARE_WORDS) != 0) {
            part.dx = readI16(bytes, cursor);
            part.dy = readI16(bytes, cursor + 2);
            cursor += 4;
        } else {
            part.dx = cast(byte) bytes[cursor];
            part.dy = cast(byte) bytes[cursor + 1];
            cursor += 2;
        }
        if ((flags & WE_HAVE_A_SCALE) != 0) {
            part.xFromX = readF2Dot14(bytes, cursor);
            part.yFromY = part.xFromX;
            cursor += 2;
        } else if ((flags & WE_HAVE_AN_X_AND_Y_SCALE) != 0) {
            part.xFromX = readF2Dot14(bytes, cursor);
            part.yFromY = readF2Dot14(bytes, cursor + 2);
            cursor += 4;
        } else if ((flags & WE_HAVE_A_TWO_BY_TWO) != 0) {
            part.xFromX = readF2Dot14(bytes, cursor);
            part.yFromX = readF2Dot14(bytes, cursor + 2);
            part.xFromY = readF2Dot14(bytes, cursor + 4);
            part.yFromY = readF2Dot14(bytes, cursor + 6);
            cursor += 8;
        }
        font.addGlyph(component, transform.after(part), outline);
    } while ((flags & MORE_COMPONENTS) != 0);
}

struct PixelPoint {
    float x;
    float y;
}

struct Segment {
    PixelPoint from;
    PixelPoint to;
}

struct PixelBox {
    int left;
    int top;
    uint width;
    uint height;
}

PixelBox pixelBoxOf(GlyphBounds bounds, float scale) {
    int left = cast(int) floorf(bounds.xMin * scale);
    int top = cast(int) floorf(-bounds.yMax * scale);
    int right = cast(int) ceilf(bounds.xMax * scale);
    int bottom = cast(int) ceilf(-bounds.yMin * scale);
    return PixelBox(left, top, right - left, bottom - top);
}

struct PixelFrame {
    float scale;
    float left;
    float top;

    PixelPoint place(OutlinePoint point) const {
        return PixelPoint(point.x * scale - left, -point.y * scale - top);
    }
}

PixelPoint midpoint(PixelPoint a, PixelPoint b) {
    return PixelPoint((a.x + b.x) / 2, (a.y + b.y) / 2);
}

void flatten(ref const Outline outline, PixelFrame frame, ref Array!Segment segments) {
    uint first = 0;
    foreach (end; outline.ends.slice()) {
        flattenContour(outline.points.slice()[first .. end], frame, segments);
        first = end;
    }
}

void flattenContour(const(OutlinePoint)[] points, PixelFrame frame, ref Array!Segment segments) {
    size_t count = points.length;
    if (count > 1) {
        size_t startIndex = 0;
        while (startIndex < count && !points[startIndex].isOnCurve) {
            startIndex += 1;
        }
        PixelPoint start;
        size_t steps = count - 1;
        if (startIndex < count) {
            start = frame.place(points[startIndex]);
        } else {
            start = midpoint(frame.place(points[0]), frame.place(points[1]));
            startIndex = 0;
            steps = count;
        }
        PixelPoint current = start;
        Maybe!PixelPoint control;
        foreach (step; 1 .. steps + 1) {
            OutlinePoint point = points[(startIndex + step) % count];
            PixelPoint placed = frame.place(point);
            if (point.isOnCurve) {
                addCurve(segments, current, control, placed);
                current = placed;
                control = Maybe!PixelPoint.init;
            } else if (control.exists) {
                PixelPoint between = midpoint(control.value, placed);
                addCurve(segments, current, control, between);
                current = between;
                control = Maybe!PixelPoint.of(placed);
            } else {
                control = Maybe!PixelPoint.of(placed);
            }
        }
        addCurve(segments, current, control, start);
    }
}

void addCurve(ref Array!Segment segments, PixelPoint from, Maybe!PixelPoint control, PixelPoint to) {
    if (control.exists) {
        addQuadratic(segments, from, control.value, to);
    } else {
        segments.append(Segment(from, to));
    }
}

void addQuadratic(ref Array!Segment segments, PixelPoint from, PixelPoint control, PixelPoint to) {
    float bendX = from.x - 2 * control.x + to.x;
    float bendY = from.y - 2 * control.y + to.y;
    float bend = sqrtf(bendX * bendX + bendY * bendY);
    uint pieces = higherOf(1u, cast(uint) ceilf(sqrtf(bend / (4 * FLATTEN_TOLERANCE))));
    PixelPoint previous = from;
    foreach (piece; 1 .. pieces + 1) {
        float t = cast(float) piece / pieces;
        float u = 1 - t;
        PixelPoint next = PixelPoint(u * u * from.x + 2 * t * u * control.x + t * t * to.x, u * u * from.y + 2 * t * u * control.y + t * t * to.y);
        segments.append(Segment(previous, next));
        previous = next;
    }
}

struct Raster {
    Array!float accumulation;
    uint stride;
    uint height;

    void begin(uint width, uint rows) {
        stride = width + SUMMED_COLUMNS;
        height = rows;
        accumulation.resize(cast(size_t) stride * height);
        accumulation.slice()[] = 0;
    }

    void fill(const(Segment)[] segments) {
        foreach (segment; segments) {
            addSegment(segment);
        }
    }

    void addSegment(Segment segment) {
        if (segment.from.y != segment.to.y) {
            float direction = 1;
            PixelPoint upper = segment.from;
            PixelPoint lower = segment.to;
            if (segment.from.y > segment.to.y) {
                direction = -1;
                upper = segment.to;
                lower = segment.from;
            }
            float slope = (lower.x - upper.x) / (lower.y - upper.y);
            int firstRow = higherOf(cast(int) floorf(upper.y), 0);
            int endRow = lowerOf(cast(int) ceilf(lower.y), cast(int) height);
            foreach (row; firstRow .. endRow) {
                float rowTop = higherOf(cast(float) row, upper.y);
                float rowBottom = lowerOf(cast(float) row + 1, lower.y);
                if (rowBottom > rowTop) {
                    addRowPiece(row, upper.x + (rowTop - upper.y) * slope, upper.x + (rowBottom - upper.y) * slope, (rowBottom - rowTop) * direction);
                }
            }
        }
    }

    void addRowPiece(int row, float fromX, float toX, float rise) {
        float low = lowerOf(fromX, toX);
        float high = higherOf(fromX, toX);
        float span = high - low;
        int firstColumn = cast(int) floorf(low);
        int lastColumn = cast(int) floorf(high);
        if (span == 0 || firstColumn == lastColumn) {
            addCell(row, firstColumn, (low + high) / 2, rise);
        } else {
            foreach (column; firstColumn .. lastColumn + 1) {
                float left = higherOf(low, cast(float) column);
                float right = lowerOf(high, cast(float) column + 1);
                if (right > left) {
                    addCell(row, column, (left + right) / 2, rise * (right - left) / span);
                }
            }
        }
    }

    void addCell(int row, int column, float middle, float rise) {
        int cell = lowerOf(higherOf(column, 0), cast(int) stride - SUMMED_COLUMNS);
        float inside = middle - cell;
        size_t at = cast(size_t) row * stride + cell;
        accumulation.ptr[at] += rise * (1 - inside);
        accumulation.ptr[at + 1] += rise * inside;
    }

    void writeCoverage(uint width, ubyte[] target, size_t targetStride, size_t targetStart) const {
        foreach (row; 0 .. height) {
            float sum = 0;
            foreach (column; 0 .. width) {
                sum += accumulation.ptr[cast(size_t) row * stride + column];
                target[targetStart + row * targetStride + column] = cast(ubyte)(lowerOf(fabsf(sum), 1.0f) * FULL_COVERAGE + 0.5f);
            }
        }
    }

    void release() {
        accumulation.release();
    }
}
