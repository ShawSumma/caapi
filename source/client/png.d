module client.png;

import core.stdc.stdio : FILE, SEEK_END, SEEK_SET, fclose, fopen, fread, fseek, ftell, fwrite;
import core.stdc.stdlib : free, malloc;
import core.stdc.string : memcpy;

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
enum uint TEST_WIDTH = 300;
enum uint TEST_HEIGHT = 250;
enum size_t TEST_PIXEL_MIX = 2654435761;

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
        foreach (_; 0 .. 8) {
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
    memcpy(target + CHUNK_LENGTH_BYTES, kind.ptr, CHUNK_KIND_BYTES);
    memcpy(target + CHUNK_LENGTH_BYTES + CHUNK_KIND_BYTES, data.ptr, data.length);
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
        bool isFinal = raw.length - consumed <= STORED_BLOCK_LIMIT;
        size_t length = blockLength(raw.length - consumed, isFinal);
        output[at] = blockKind(isFinal);
        output[at + 1] = cast(ubyte) length;
        output[at + 2] = cast(ubyte)(length >> 8);
        output[at + 3] = cast(ubyte) ~length;
        output[at + 4] = cast(ubyte)(~length >> 8);
        at += STORED_BLOCK_HEADER_BYTES;
        memcpy(output + at, raw.ptr + consumed, length);
        at += length;
        consumed += length;
    }
    putBigEndian(output + at, adler32(raw));
    return at + ADLER_BYTES;
}

struct PngImage {
    ubyte* rgb;
    uint width;
    uint height;

    bool isRead() const {
        return rgb !is null;
    }

    const(ubyte)[] pixels() const {
        return rgb[0 .. cast(size_t) width * height * RGB_BYTES];
    }

    void release() {
        free(rgb);
        rgb = null;
    }
}

bool writePng(const(char)* path, uint width, uint height, const(ubyte)[] rgba) {
    ubyte[] bytes = encodePng(width, height, rgba);
    FILE* file = fopen(path, "wb");
    if (file is null) {
        free(bytes.ptr);
        return false;
    } else {
        size_t written = fwrite(bytes.ptr, 1, bytes.length, file);
        int closeStatus = fclose(file);
        free(bytes.ptr);
        return written == bytes.length && closeStatus == 0;
    }
}

PngImage readPng(const(char)* path) {
    FILE* file = fopen(path, "rb");
    if (file is null) {
        return PngImage.init;
    } else {
        fseek(file, 0, SEEK_END);
        long length = ftell(file);
        fseek(file, 0, SEEK_SET);
        ubyte* bytes = cast(ubyte*) malloc(cast(size_t) length + 1);
        size_t read = fread(bytes, 1, cast(size_t) length, file);
        fclose(file);
        PngImage image;
        if (length > 0 && read == cast(size_t) length) {
            image = decodePng(bytes[0 .. read]);
        }
        free(bytes);
        return image;
    }
}

uint getBigEndian(const(ubyte)* source) {
    return (cast(uint) source[0] << 24) | (cast(uint) source[1] << 16) | (cast(uint) source[2] << 8) | source[3];
}

PngImage decodePng(const(ubyte)[] bytes) {
    PngImage image;
    size_t at = PNG_SIGNATURE.length;
    ubyte* deflated = cast(ubyte*) malloc(bytes.length);
    size_t deflatedBytes = 0;
    bool isValid = bytes.length >= PNG_SIGNATURE.length && bytes[0 .. PNG_SIGNATURE.length] == PNG_SIGNATURE[];
    bool isEnded = false;
    while (isValid && !isEnded && at + chunkSize(0) <= bytes.length) {
        size_t length = getBigEndian(bytes.ptr + at);
        const(char)[] kind = cast(const(char)[]) bytes[at + CHUNK_LENGTH_BYTES .. at + CHUNK_LENGTH_BYTES + CHUNK_KIND_BYTES];
        size_t data = at + CHUNK_LENGTH_BYTES + CHUNK_KIND_BYTES;
        isValid = data + length + CHUNK_CRC_BYTES <= bytes.length;
        if (isValid && kind == "IHDR") {
            isValid = length == HEADER_BYTES && bytes[data + 8] == BIT_DEPTH && bytes[data + 9] == COLOR_TYPE_RGB;
            image.width = getBigEndian(bytes.ptr + data);
            image.height = getBigEndian(bytes.ptr + data + 4);
        } else if (isValid && kind == "IDAT") {
            memcpy(deflated + deflatedBytes, bytes.ptr + data, length);
            deflatedBytes += length;
        } else if (isValid && kind == "IEND") {
            isEnded = true;
        }
        at = data + length + CHUNK_CRC_BYTES;
    }
    size_t rowBytes = 1 + cast(size_t) image.width * RGB_BYTES;
    size_t rawBytes = rowBytes * image.height;
    ubyte* raw = cast(ubyte*) malloc(rawBytes + 1);
    isValid = isValid && isEnded && image.width > 0 && image.height > 0 && inflateStored(deflated[0 .. deflatedBytes], raw[0 .. rawBytes]);
    if (isValid) {
        image.rgb = cast(ubyte*) malloc(rawBytes - image.height);
        size_t row = 0;
        while (isValid && row < image.height) {
            isValid = raw[row * rowBytes] == FILTER_NONE;
            memcpy(image.rgb + row * (rowBytes - 1), raw + row * rowBytes + 1, rowBytes - 1);
            row += 1;
        }
        if (!isValid) {
            image.release();
        }
    }
    free(raw);
    free(deflated);
    return image;
}

bool inflateStored(const(ubyte)[] deflated, ubyte[] raw) {
    size_t at = ZLIB_HEADER_BYTES;
    size_t produced = 0;
    bool isValid = deflated.length >= ZLIB_HEADER_BYTES + ADLER_BYTES && deflated[0] == ZLIB_METHOD;
    bool isFinal = false;
    while (isValid && !isFinal) {
        isValid = at + STORED_BLOCK_HEADER_BYTES <= deflated.length && (deflated[at] & ~FINAL_BLOCK) == 0;
        if (isValid) {
            isFinal = deflated[at] == FINAL_BLOCK;
            size_t length = deflated[at + 1] | (cast(size_t) deflated[at + 2] << 8);
            at += STORED_BLOCK_HEADER_BYTES;
            isValid = at + length <= deflated.length && produced + length <= raw.length;
            if (isValid) {
                memcpy(raw.ptr + produced, deflated.ptr + at, length);
                produced += length;
                at += length;
            }
        }
    }
    return isValid && produced == raw.length && at + ADLER_BYTES <= deflated.length && getBigEndian(deflated.ptr + at) == adler32(raw);
}

ubyte[] encodePng(uint width, uint height, const(ubyte)[] rgba) {
    size_t rowBytes = 1 + cast(size_t) width * RGB_BYTES;
    size_t rawBytes = rowBytes * height;
    ubyte* raw = cast(ubyte*) malloc(rawBytes);
    foreach (y; 0 .. height) {
        raw[y * rowBytes] = FILTER_NONE;
        foreach (x; 0 .. width) {
            size_t source = (cast(size_t) y * width + x) * RGBA_BYTES;
            size_t target = y * rowBytes + 1 + x * RGB_BYTES;
            memcpy(raw + target, rgba.ptr + source, RGB_BYTES);
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
    memcpy(bytes, PNG_SIGNATURE.ptr, PNG_SIGNATURE.length);
    size_t at = PNG_SIGNATURE.length;
    at += putChunk(bytes + at, "IHDR", header[]);
    at += putChunk(bytes + at, "IDAT", compressed[0 .. compressedBytes]);
    putChunk(bytes + at, "IEND", null);
    free(raw);
    free(compressed);
    return bytes[0 .. fileBytes];
}

unittest {
    assert(crc32(cast(const(ubyte)[]) "IEND") == TEST_CRC_OF_IEND);
    assert(adler32(cast(const(ubyte)[]) "Wikipedia") == TEST_ADLER_OF_WIKIPEDIA);
    ubyte[TEST_WIDTH * TEST_HEIGHT * RGBA_BYTES] rgba;
    foreach (index, ref value; rgba) {
        value = cast(ubyte)(index * TEST_PIXEL_MIX);
    }
    ubyte[] encoded = encodePng(TEST_WIDTH, TEST_HEIGHT, rgba[]);
    PngImage decoded = decodePng(encoded);
    assert(decoded.isRead() && decoded.width == TEST_WIDTH && decoded.height == TEST_HEIGHT);
    foreach (pixel; 0 .. TEST_WIDTH * TEST_HEIGHT) {
        assert(decoded.pixels()[pixel * RGB_BYTES .. (pixel + 1) * RGB_BYTES] == rgba[pixel * RGBA_BYTES .. pixel * RGBA_BYTES + RGB_BYTES]);
    }
    encoded[encoded.length / 2] ^= 1;
    PngImage corrupted = decodePng(encoded);
    assert(!corrupted.isRead());
    decoded.release();
    free(encoded.ptr);
}
