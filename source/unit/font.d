module unit.font;

import core.stdc.math : fabsf;
import base.array : Array;
import client.font : Font, Outline, PLEX_MONO, PixelBox, PixelFrame, Raster, Segment, Transform, addGlyph, boundsOf, flatten, glyphOf, pixelBoxOf;

enum uint TEST_EM_PIXELS = 64;
enum float AREA_TOLERANCE = 0.01f;
enum float FULL_TEXEL = 255;
immutable string AREA_GLYPHS = "HOegM8";

unittest {
    Font font = Font.make(PLEX_MONO);
    float scale = cast(float) TEST_EM_PIXELS / font.unitsPerEm;
    assert(font.glyphOf('A') != 0);
    assert(!font.boundsOf(font.glyphOf(' ')).exists);
    Outline outline;
    Array!Segment segments;
    Raster raster;
    Array!ubyte coverage;
    foreach (character; AREA_GLYPHS) {
        ushort glyph = font.glyphOf(character);
        PixelBox box = pixelBoxOf(font.boundsOf(glyph).value, scale);
        outline.clear();
        font.addGlyph(glyph, Transform.init, outline);
        segments.clear();
        flatten(outline, PixelFrame(scale, box.left, box.top), segments);
        float enclosed = 0;
        foreach (segment; segments.slice()) {
            enclosed += (segment.from.x * segment.to.y - segment.to.x * segment.from.y) / 2;
        }
        raster.begin(box.width, box.height);
        raster.fill(segments.slice());
        coverage.resize(cast(size_t) box.width * box.height);
        raster.writeCoverage(box.width, coverage.slice(), box.width, 0);
        float covered = 0;
        foreach (texel; coverage.slice()) {
            covered += texel / FULL_TEXEL;
        }
        assert(fabsf(covered - fabsf(enclosed)) <= AREA_TOLERANCE * fabsf(enclosed));
    }
    outline.release();
    segments.release();
    raster.release();
    coverage.release();
}
