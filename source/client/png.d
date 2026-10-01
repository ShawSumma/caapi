module client.png;

import core.stdc.stdio : FILE, fclose, fopen, fwrite;
import core.stdc.stdlib : free, malloc;

enum uint CRC_POLYNOMIAL = 0xEDB88320;
enum uint CRC_TABLE_SIZE = 256;
enum uint ADLER_MODULUS = 65521;
enum uint STORED_BLOCK_LIMIT = 65535;
enum ubyte ZLIB_METHOD = 0x78;
enum ubyte ZLIB_FLAGS = 0x01;
enum ubyte FINAL_BLOCK = 1;
enum ubyte MORE_BLOCKS = 0;
enum ubyte FILTER_NONE = 0;
enum ubyte BIT_DEPTH = 8;
enum ubyte COLOR_TYPE_RGB = 2;
enum uint RGB_BYTES = 3;
enum uint RGBA_BYTES = 4;
enum uint HEADER_BYTES = 13;
enum uint STORED_BLOCK_HEADER_BYTES = 5;
enum uint ZLIB_HEADER_BYTES = 2;
enum uint ADLER_BYTES = 4;
enum uint CRC_INITIAL = 0xFFFFFFFF;
enum uint BYTE_MASK = 0xFF;
enum uint TEST_CRC_OF_IEND = 0xAE426082;
enum uint TEST_ADLER_OF_WIKIPEDIA = 0x11E60398;

immutable ubyte[8] PNG_SIGNATURE = [
    0x89,
    'P',
    'N',
    'G',
    '\r',
    '\n',
    0x1A,
    '\n',
];

uint[CRC_TABLE_SIZE] buildCrcTable() {
    uint[CRC_TABLE_SIZE] table;
    foreach (n; 0 .. CRC_TABLE_SIZE) {
        uint c = n;
        foreach (bit; 0 .. 8) {
            if ((c & 1) != 0) {
                c = CRC_POLYNOMIAL ^ (c >> 1);
            } else {
                c = c >> 1;
            }
        }
        table[n] = c;
    }
    return table;
}

immutable uint[CRC_TABLE_SIZE] CRC_TABLE = buildCrcTable();

uint crcUpdate(uint crc, const(ubyte)[] data) {
    uint c = crc;
    foreach (value; data) {
        c = CRC_TABLE[(c ^ value) & BYTE_MASK] ^ (c >> 8);
    }
    return c;
}

uint crc32(const(ubyte)[] data) {
    return crcUpdate(CRC_INITIAL, data) ^ CRC_INITIAL;
}

uint adler32(const(ubyte)[] data) {
    uint a = 1;
    uint b = 0;
    foreach (value; data) {
        a = (a + value) % ADLER_MODULUS;
        b = (b + a) % ADLER_MODULUS;
    }
    return (b << 16) | a;
}

void putBigEndian(ubyte* target, uint value) {
    target[0] = cast(ubyte)(value >> 24);
    target[1] = cast(ubyte)(value >> 16);
    target[2] = cast(ubyte)(value >> 8);
    target[3] = cast(ubyte) value;
}

bool writeChunk(FILE* file, const(char)[4] kind, const(ubyte)[] data) {
    ubyte[4] length;
    putBigEndian(length.ptr, cast(uint) data.length);
    ubyte[4] crc;
    putBigEndian(crc.ptr, crcUpdate(crcUpdate(CRC_INITIAL, cast(const(ubyte)[]) kind[]), data) ^ CRC_INITIAL);
    return fwrite(length.ptr, 1, length.length, file) == length.length && fwrite(kind.ptr, 1, kind.length, file) == kind.length && fwrite(data.ptr, 1, data.length, file) == data.length && fwrite(crc.ptr, 1, crc.length, file) == crc.length;
}

size_t storedSize(size_t raw) {
    size_t blocks = (raw + STORED_BLOCK_LIMIT - 1) / STORED_BLOCK_LIMIT;
    return ZLIB_HEADER_BYTES + raw + blocks * STORED_BLOCK_HEADER_BYTES + ADLER_BYTES;
}

size_t deflateStored(const(ubyte)[] raw, ubyte* output) {
    size_t at = 0;
    output[at] = ZLIB_METHOD;
    output[at + 1] = ZLIB_FLAGS;
    at += ZLIB_HEADER_BYTES;
    size_t consumed = 0;
    while (consumed < raw.length) {
        size_t length = raw.length - consumed;
        ubyte blockKind = FINAL_BLOCK;
        if (length > STORED_BLOCK_LIMIT) {
            length = STORED_BLOCK_LIMIT;
            blockKind = MORE_BLOCKS;
        }
        output[at] = blockKind;
        output[at + 1] = cast(ubyte) length;
        output[at + 2] = cast(ubyte)(length >> 8);
        output[at + 3] = cast(ubyte) ~length;
        output[at + 4] = cast(ubyte)(~length >> 8);
        at += STORED_BLOCK_HEADER_BYTES;
        output[at .. at + length] = raw[consumed .. consumed + length];
        at += length;
        consumed += length;
    }
    putBigEndian(output + at, adler32(raw));
    return at + ADLER_BYTES;
}

bool writePng(const(char)* path, uint width, uint height, const(ubyte)[] rgba) {
    size_t rowBytes = 1 + cast(size_t) width * RGB_BYTES;
    size_t rawBytes = rowBytes * height;
    ubyte* raw = cast(ubyte*) malloc(rawBytes);
    foreach (y; 0 .. height) {
        raw[y * rowBytes] = FILTER_NONE;
        foreach (x; 0 .. width) {
            size_t source = (cast(size_t) y * width + x) * RGBA_BYTES;
            size_t target = y * rowBytes + 1 + x * RGB_BYTES;
            raw[target .. target + RGB_BYTES] = rgba[source .. source + RGB_BYTES];
        }
    }
    ubyte* compressed = cast(ubyte*) malloc(storedSize(rawBytes));
    size_t compressedBytes = deflateStored(raw[0 .. rawBytes], compressed);
    ubyte[HEADER_BYTES] header = 0;
    putBigEndian(header.ptr, width);
    putBigEndian(header.ptr + 4, height);
    header[8] = BIT_DEPTH;
    header[9] = COLOR_TYPE_RGB;
    FILE* file = fopen(path, "wb");
    bool ok = file !is null;
    if (ok) {
        ok = fwrite(PNG_SIGNATURE.ptr, 1, PNG_SIGNATURE.length, file) == PNG_SIGNATURE.length;
        ok = ok && writeChunk(file, "IHDR", header[]);
        ok = ok && writeChunk(file, "IDAT", compressed[0 .. compressedBytes]);
        ok = ok && writeChunk(file, "IEND", null);
        ok = fclose(file) == 0 && ok;
    }
    free(raw);
    free(compressed);
    return ok;
}

unittest {
    assert(crc32(cast(const(ubyte)[]) "IEND") == TEST_CRC_OF_IEND);
    assert(adler32(cast(const(ubyte)[]) "Wikipedia") == TEST_ADLER_OF_WIKIPEDIA);
}
