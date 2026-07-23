module client.graphics.screenshot;

import std.stdio;
import std.format : format;
import std.string : toStringz;
import core.stdc.stdlib : system;

/// Writes BGRA pixels as a BMP, then converts to PNG via macOS `sips`.
void writePngScreenshot(string path, uint width, uint height, const(ubyte)[] bgra) {
    string bmpPath = path ~ ".bmp";
    uint dataSize = width * height * 4;
    uint fileSize = 54 + dataSize;

    ubyte[54] header = 0;
    header[0] = 'B';
    header[1] = 'M';
    putU32(header[], 2, fileSize);
    putU32(header[], 10, 54);
    putU32(header[], 14, 40);
    putU32(header[], 18, width);
    // Negative height marks the bitmap as top-down
    putU32(header[], 22, cast(uint) (-cast(int) height));
    header[26] = 1;
    header[28] = 32;
    putU32(header[], 34, dataSize);

    auto f = File(bmpPath, "wb");
    f.rawWrite(header[]);
    f.rawWrite(bgra);
    f.close();

    auto cmd = format("sips -s format png %s --out %s >/dev/null 2>&1", bmpPath, path);
    system(cmd.toStringz);
    import std.file : remove;
    remove(bmpPath);
}

private void putU32(ubyte[] buf, size_t offset, uint value) {
    buf[offset] = cast(ubyte) value;
    buf[offset + 1] = cast(ubyte) (value >> 8);
    buf[offset + 2] = cast(ubyte) (value >> 16);
    buf[offset + 3] = cast(ubyte) (value >> 24);
}
