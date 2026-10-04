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
enum uint CHUNK_LENGTH_BYTES = 4;
enum uint CHUNK_KIND_BYTES = 4;
enum uint CHUNK_CRC_BYTES = 4;
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

size_t chunkSize(size_t dataBytes) {
    return CHUNK_LENGTH_BYTES + CHUNK_KIND_BYTES + dataBytes + CHUNK_CRC_BYTES;
}

size_t putChunk(ubyte* target, const(char)[4] kind, const(ubyte)[] data) {
    putBigEndian(target, cast(uint) data.length);
    target[CHUNK_LENGTH_BYTES .. CHUNK_LENGTH_BYTES + CHUNK_KIND_BYTES] = cast(const(ubyte)[]) kind[];
    target[CHUNK_LENGTH_BYTES + CHUNK_KIND_BYTES .. CHUNK_LENGTH_BYTES + CHUNK_KIND_BYTES + data.length] = data[];
    putBigEndian(target + CHUNK_LENGTH_BYTES + CHUNK_KIND_BYTES + data.length, crcUpdate(crcUpdate(CRC_INITIAL, cast(const(ubyte)[]) kind[]), data) ^ CRC_INITIAL);
    return chunkSize(data.length);
}

size_t storedSize(size_t raw) {
    size_t blocks = (raw + STORED_BLOCK_LIMIT - 1) / STORED_BLOCK_LIMIT;
    return ZLIB_HEADER_BYTES + raw + blocks * STORED_BLOCK_HEADER_BYTES + ADLER_BYTES;
}

size_t blockLength(size_t remaining, bool isFinal) {
    if (isFinal) {
        return remaining;
    } else {
        return STORED_BLOCK_LIMIT;
    }
}

ubyte blockKind(bool isFinal) {
    if (isFinal) {
        return FINAL_BLOCK;
    } else {
        return MORE_BLOCKS;
    }
}

size_t deflateStored(const(ubyte)[] raw, ubyte* output) {
    size_t at = 0;
    output[at] = ZLIB_METHOD;
    output[at + 1] = ZLIB_FLAGS;
    at += ZLIB_HEADER_BYTES;
    size_t consumed = 0;
    while (consumed < raw.length) {
        immutable bool isFinal = raw.length - consumed <= STORED_BLOCK_LIMIT;
        size_t length = blockLength(raw.length - consumed, isFinal);
        output[at] = blockKind(isFinal);
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
    size_t fileBytes = PNG_SIGNATURE.length + chunkSize(header.length) + chunkSize(compressedBytes) + chunkSize(0);
    ubyte* bytes = cast(ubyte*) malloc(fileBytes);
    bytes[0 .. PNG_SIGNATURE.length] = PNG_SIGNATURE[];
    size_t at = PNG_SIGNATURE.length;
    at += putChunk(bytes + at, "IHDR", header[]);
    at += putChunk(bytes + at, "IDAT", compressed[0 .. compressedBytes]);
    putChunk(bytes + at, "IEND", null);
    free(raw);
    free(compressed);
    FILE* file = fopen(path, "wb");
    if (file is null) {
        free(bytes);
        return false;
    } else {
        immutable size_t written = fwrite(bytes, 1, fileBytes, file);
        immutable int closeStatus = fclose(file);
        free(bytes);
        return written == fileBytes && closeStatus == 0;
    }
}

unittest {
    assert(crc32(cast(const(ubyte)[]) "IEND") == TEST_CRC_OF_IEND);
    assert(adler32(cast(const(ubyte)[]) "Wikipedia") == TEST_ADLER_OF_WIKIPEDIA);
}
