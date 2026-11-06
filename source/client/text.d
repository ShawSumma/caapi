module client.text;

import core.stdc.math : roundf;
import base.array : Array;
import base.maybe : Maybe;
import base.numbers : clamped, higherOf;
import client.font : Font, GlyphBounds, Outline, PLEX_MONO, PixelBox, PixelFrame, Raster, Segment, Transform, addGlyph, advanceOf, boundsOf, flatten, glyphOf, pixelBoxOf;

enum uint ATLAS_WIDTH = 1024;
enum uint ATLAS_HEIGHT = 512;
enum uint ATLAS_COLUMNS = 16;
enum char FIRST_CHARACTER = ' ';
enum char LAST_CHARACTER = '~';
enum uint GLYPH_COUNT = LAST_CHARACTER - FIRST_CHARACTER + 1;
enum uint ATLAS_ROWS = (GLYPH_COUNT + ATLAS_COLUMNS - 1) / ATLAS_COLUMNS;
enum uint GLYPH_PADDING = 1;
enum uint WHITE_BLOCK_SIDE = 2;
enum uint WHITE_BLOCK_X = ATLAS_WIDTH - WHITE_BLOCK_SIDE;
enum uint WHITE_BLOCK_Y = ATLAS_HEIGHT - WHITE_BLOCK_SIDE;
enum uint WHITE_TEXEL_X = WHITE_BLOCK_X + WHITE_BLOCK_SIDE / 2;
enum uint WHITE_TEXEL_Y = WHITE_BLOCK_Y + WHITE_BLOCK_SIDE / 2;
enum ubyte FULL_TEXEL = 255;
enum uint LEAST_EM_PIXELS = 12;
enum uint MOST_EM_PIXELS = 48;
enum float EM_SHARE_OF_HEIGHT = 0.025f;
enum char ADVANCE_CHARACTER = 'M';
enum uint TEXEL_Y_SHIFT = 16;

uint texelOf(uint x, uint y) {
    return x | (y << TEXEL_Y_SHIFT);
}

enum uint WHITE_TEXEL = texelOf(WHITE_TEXEL_X, WHITE_TEXEL_Y);

uint emPixelsFor(uint screenHeight) {
    return clamped(cast(uint) roundf(screenHeight * EM_SHARE_OF_HEIGHT), LEAST_EM_PIXELS, MOST_EM_PIXELS);
}

struct AtlasGlyph {
    PixelBox box;
    uint atlasX;
    uint atlasY;
}

struct GlyphAtlas {
    Array!ubyte pixels;
    Array!Segment segments;
    Outline outline;
    Raster raster;
    AtlasGlyph[GLYPH_COUNT] glyphs;
    uint emPixels;
    uint advance;
    uint ascent;
    uint lineHeight;
    uint revision;

    void ensure(uint wanted) {
        if (wanted != emPixels) {
            build(wanted);
        }
    }

    void build(uint chosen) {
        Font font = Font.make(PLEX_MONO);
        float scale = cast(float) chosen / font.unitsPerEm;
        ushort[GLYPH_COUNT] ids;
        uint cellWidth = 0;
        uint cellHeight = 0;
        foreach (index, ref glyph; glyphs) {
            ids[index] = font.glyphOf(FIRST_CHARACTER + cast(uint) index);
            Maybe!GlyphBounds bounds = font.boundsOf(ids[index]);
            glyph.box = PixelBox.init;
            if (bounds.exists) {
                glyph.box = pixelBoxOf(bounds.value, scale);
            }
            cellWidth = higherOf(cellWidth, glyph.box.width + 2 * GLYPH_PADDING);
            cellHeight = higherOf(cellHeight, glyph.box.height + 2 * GLYPH_PADDING);
        }
        assert(ATLAS_COLUMNS * cellWidth <= WHITE_BLOCK_X && ATLAS_ROWS * cellHeight <= WHITE_BLOCK_Y);
        pixels.resize(cast(size_t) ATLAS_WIDTH * ATLAS_HEIGHT);
        pixels.slice()[] = 0;
        foreach (index, ref glyph; glyphs) {
            glyph.atlasX = cast(uint)(index % ATLAS_COLUMNS) * cellWidth + GLYPH_PADDING;
            glyph.atlasY = cast(uint)(index / ATLAS_COLUMNS) * cellHeight + GLYPH_PADDING;
            if (glyph.box.width > 0 && glyph.box.height > 0) {
                outline.clear();
                font.addGlyph(ids[index], Transform.init, outline);
                segments.clear();
                flatten(outline, PixelFrame(scale, glyph.box.left, glyph.box.top), segments);
                raster.begin(glyph.box.width, glyph.box.height);
                raster.fill(segments.slice());
                raster.writeCoverage(glyph.box.width, pixels.slice(), ATLAS_WIDTH, cast(size_t) glyph.atlasY * ATLAS_WIDTH + glyph.atlasX);
            }
        }
        foreach (y; WHITE_BLOCK_Y .. WHITE_BLOCK_Y + WHITE_BLOCK_SIDE) {
            pixels.slice()[cast(size_t) y * ATLAS_WIDTH + WHITE_BLOCK_X .. cast(size_t) y * ATLAS_WIDTH + WHITE_BLOCK_X + WHITE_BLOCK_SIDE] = FULL_TEXEL;
        }
        advance = cast(uint) roundf(font.advanceOf(font.glyphOf(ADVANCE_CHARACTER)) * scale);
        ascent = cast(uint) roundf(font.ascender * scale);
        lineHeight = cast(uint) roundf((font.ascender - font.descender + font.lineGap) * scale);
        emPixels = chosen;
        revision += 1;
    }

    void release() {
        pixels.release();
        segments.release();
        outline.release();
        raster.release();
    }
}
