module client.graphics.png_loader;

import std.zlib;
import std.stdio;
import std.file : read;

ubyte[] loadPngRgba(string path) {
    ubyte[] fileData;
    try {
        fileData = cast(ubyte[]) read(path);
    } catch (Exception e) {
        return null;
    }
    return decodePng(fileData);
}

ubyte[] decodePng(ubyte[] data) {
    if (data.length < 8) {
        return null;
    }
    static immutable ubyte[8] sig = [137, 80, 78, 71, 13, 10, 26, 10];
    if (data[0 .. 8] != sig) {
        return null;
    }

    uint width, height;
    ubyte bitDepth, colorType;
    ubyte[] idatData;
    size_t pos = 8;

    while (pos + 12 <= data.length) {
        uint chunkLen = bigEndian32(data[pos .. pos + 4]);
        ubyte[] chunkType = data[pos + 4 .. pos + 8];
        ubyte[] chunkData = data[pos + 8 .. pos + 8 + chunkLen];

        if (chunkType == cast(ubyte[]) "IHDR") {
            width = bigEndian32(chunkData[0 .. 4]);
            height = bigEndian32(chunkData[4 .. 8]);
            bitDepth = chunkData[8];
            colorType = chunkData[9];
        } else if (chunkType == cast(ubyte[]) "IDAT") {
            idatData ~= chunkData;
        } else if (chunkType == cast(ubyte[]) "IEND") {
            break;
        }

        pos += 12 + chunkLen;
    }

    if (width == 0 || height == 0 || idatData.length == 0) {
        return null;
    }

    uint bpp;
    if (colorType == 6) {
        bpp = 4;
    } else if (colorType == 2) {
        bpp = 3;
    } else {
        writefln("Unsupported PNG color type: %d", colorType);
        return null;
    }

    if (bitDepth != 8) {
        writefln("Unsupported PNG bit depth: %d", bitDepth);
        return null;
    }

    size_t rawSize = height * (1 + width * bpp);
    ubyte[] raw;
    try {
        raw = cast(ubyte[]) uncompress(idatData, rawSize);
    } catch (Exception e) {
        writefln("PNG zlib decompress failed: %s", e.msg);
        return null;
    }

    if (raw.length != rawSize) {
        return null;
    }

    uint stride = width * bpp;
    ubyte[] pixels = new ubyte[](width * height * bpp);

    for (uint y = 0; y < height; y++) {
        size_t rowStart = y * (1 + stride);
        ubyte filterType = raw[rowStart];
        ubyte[] rowData = raw[rowStart + 1 .. rowStart + 1 + stride];
        ubyte[] outRow = pixels[y * stride .. (y + 1) * stride];
        ubyte[] prevRow = (y > 0) ? pixels[(y - 1) * stride .. y * stride] : null;

        applyFilter(filterType, rowData, outRow, prevRow, bpp);
    }

    if (bpp == 4) {
        return pixels;
    }

    ubyte[] rgba = new ubyte[](width * height * 4);
    for (uint i = 0; i < width * height; i++) {
        rgba[i * 4 + 0] = pixels[i * 3 + 0];
        rgba[i * 4 + 1] = pixels[i * 3 + 1];
        rgba[i * 4 + 2] = pixels[i * 3 + 2];
        rgba[i * 4 + 3] = 255;
    }
    return rgba;
}

void applyFilter(ubyte filterType, ubyte[] rowData, ubyte[] outRow, ubyte[] prevRow, uint bpp) {
    for (uint i = 0; i < cast(uint) rowData.length; i++) {
        ubyte x = rowData[i];
        ubyte a = (i >= bpp) ? outRow[i - bpp] : 0;
        ubyte b = (prevRow !is null) ? prevRow[i] : cast(ubyte) 0;
        ubyte c = (prevRow !is null && i >= bpp) ? prevRow[i - bpp] : cast(ubyte) 0;

        switch (filterType) {
        case 0:
            outRow[i] = x;
            break;
        case 1:
            outRow[i] = cast(ubyte)(x + a);
            break;
        case 2:
            outRow[i] = cast(ubyte)(x + b);
            break;
        case 3:
            outRow[i] = cast(ubyte)(x + ((cast(int) a + cast(int) b) / 2));
            break;
        case 4:
            outRow[i] = cast(ubyte)(x + paethPredictor(a, b, c));
            break;
        default:
            outRow[i] = x;
            break;
        }
    }
}

ubyte paethPredictor(ubyte a, ubyte b, ubyte c) {
    int p = cast(int) a + cast(int) b - cast(int) c;
    int pa = p > a ? p - a : a - p;
    int pb = p > b ? p - b : b - p;
    int pc = p > c ? p - c : c - p;
    if (pa <= pb && pa <= pc) {
        return a;
    }
    if (pb <= pc) {
        return b;
    }
    return c;
}

uint bigEndian32(ubyte[] b) {
    return (cast(uint) b[0] << 24) | (cast(uint) b[1] << 16) | (cast(uint) b[2] << 8) | cast(uint) b[3];
}
