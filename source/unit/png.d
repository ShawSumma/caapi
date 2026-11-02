module unit.png;

import core.stdc.stdlib : free;
import client.png : PngImage, RGBA_BYTES, RGB_BYTES, adler32, crc32, decodePng, encodePng;

enum uint CRC_OF_IEND = 0xAE426082;
enum uint ADLER_OF_WIKIPEDIA = 0x11E60398;
enum uint WIDTH = 300;
enum uint HEIGHT = 250;
enum size_t PIXEL_MIX = 2654435761;

unittest {
    assert(crc32(cast(const(ubyte)[]) "IEND") == CRC_OF_IEND);
    assert(adler32(cast(const(ubyte)[]) "Wikipedia") == ADLER_OF_WIKIPEDIA);
    ubyte[WIDTH * HEIGHT * RGBA_BYTES] rgba;
    foreach (index, ref value; rgba) {
        value = cast(ubyte)(index * PIXEL_MIX);
    }
    ubyte[] encoded = encodePng(WIDTH, HEIGHT, rgba[]);
    PngImage decoded = decodePng(encoded);
    assert(decoded.isRead() && decoded.width == WIDTH && decoded.height == HEIGHT);
    foreach (pixel; 0 .. WIDTH * HEIGHT) {
        assert(decoded.pixels()[pixel * RGB_BYTES .. (pixel + 1) * RGB_BYTES] == rgba[pixel * RGBA_BYTES .. pixel * RGBA_BYTES + RGB_BYTES]);
    }
    encoded[encoded.length / 2] ^= 1;
    PngImage corrupted = decodePng(encoded);
    assert(!corrupted.isRead());
    decoded.release();
    free(encoded.ptr);
}
