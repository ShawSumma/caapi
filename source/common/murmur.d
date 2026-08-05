module common.murmur;

// MurmurHash3 x64 128-bit. This is not a swappable hash: node ids are derived
// from it, so its exact output defines the shape of the world. It replaces
// std.digest.murmurhash and is pinned by test vectors captured from that
// implementation.
struct MurmurHash3x64 {
    enum ulong C1 = 0x87C37B91114253D5;
    enum ulong C2 = 0x4CF5AD432745937F;

    ulong h1;
    ulong h2;
    ubyte[16] tail;
    size_t tailLength;
    size_t totalLength;

    static MurmurHash3x64 withSeed(uint seed) {
        MurmurHash3x64 h;
        h.h1 = seed;
        h.h2 = seed;
        return h;
    }

    void putByte(ubyte b) {
        tail[tailLength] = b;
        tailLength = tailLength + 1;
        totalLength = totalLength + 1;
        if (tailLength == 16) {
            mixBlock(tail);
            tailLength = 0;
        }
    }

    void put(const(ubyte)[] bytes) {
        foreach (b; bytes) {
            putByte(b);
        }
    }

    void mixBlock(const ref ubyte[16] block) {
        ulong k1 = readLittleEndian(block, 0);
        ulong k2 = readLittleEndian(block, 8);

        k1 = k1 * C1;
        k1 = rotateLeft(k1, 31);
        k1 = k1 * C2;
        h1 = h1 ^ k1;

        h1 = rotateLeft(h1, 27);
        h1 = h1 + h2;
        h1 = h1 * 5 + 0x52DCE729;

        k2 = k2 * C2;
        k2 = rotateLeft(k2, 33);
        k2 = k2 * C1;
        h2 = h2 ^ k2;

        h2 = rotateLeft(h2, 31);
        h2 = h2 + h1;
        h2 = h2 * 5 + 0x38495AB5;
    }

    ubyte[16] finish() const {
        ulong f1 = h1;
        ulong f2 = h2;

        ulong k1 = 0;
        ulong k2 = 0;
        // Canonical fallthrough tail, written out so each byte's shift is
        // explicit rather than relying on switch fallthrough.
        foreach (i; 0 .. tailLength) {
            if (i < 8) {
                k1 = k1 | (cast(ulong) tail[i] << (8 * i));
            } else {
                k2 = k2 | (cast(ulong) tail[i] << (8 * (i - 8)));
            }
        }
        if (tailLength > 8) {
            k2 = k2 * C2;
            k2 = rotateLeft(k2, 33);
            k2 = k2 * C1;
            f2 = f2 ^ k2;
        }
        if (tailLength > 0) {
            k1 = k1 * C1;
            k1 = rotateLeft(k1, 31);
            k1 = k1 * C2;
            f1 = f1 ^ k1;
        }

        f1 = f1 ^ totalLength;
        f2 = f2 ^ totalLength;
        f1 = f1 + f2;
        f2 = f2 + f1;
        f1 = mix64(f1);
        f2 = mix64(f2);
        f1 = f1 + f2;
        f2 = f2 + f1;

        ubyte[16] result;
        foreach (i; 0 .. 8) {
            result[i] = cast(ubyte)(f1 >> (8 * i));
            result[i + 8] = cast(ubyte)(f2 >> (8 * i));
        }
        return result;
    }
}

ulong rotateLeft(ulong x, uint r) {
    return (x << r) | (x >> (64 - r));
}

ulong readLittleEndian(const ref ubyte[16] block, size_t offset) {
    ulong v = 0;
    foreach (i; 0 .. 8) {
        v = v | (cast(ulong) block[offset + i] << (8 * i));
    }
    return v;
}

ulong mix64(ulong k) {
    k = k ^ (k >> 33);
    k = k * 0xFF51AFD7ED558CCD;
    k = k ^ (k >> 33);
    k = k * 0xC4CEB9FE1A85EC53;
    k = k ^ (k >> 33);
    return k;
}

ubyte[16] murmurBytes(const(ubyte)[] data) {
    MurmurHash3x64 h;
    h.put(data);
    return h.finish();
}

unittest {
    // Vectors captured from std.digest.murmurhash's MurmurHash3!128 before it
    // was removed. Node ids are derived from this, so a mismatch here means
    // the world layout changed.
    static immutable ubyte[16] EMPTY = [
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
    ];
    assert(murmurBytes([]) == EMPTY);

    // The exact shape graph.d hashes: a 16-byte NodeId followed by one side
    // byte, which straddles the block boundary and exercises the tail path.
    ubyte[17] rootAndSide = [
        1, 0, 0, 0, 0, 0, 0, 0,
        1, 0, 0, 0, 0, 0, 0, 0,
        0,
    ];
    static immutable ubyte[16] ROOT_SIDE_A = [
        0x02, 0x63, 0xA9, 0x5B, 0xA9, 0xF1, 0x78, 0xEA,
        0x76, 0x12, 0x24, 0xE7, 0x30, 0xEA, 0x50, 0xAE,
    ];
    assert(murmurBytes(rootAndSide[]) == ROOT_SIDE_A);

    // Exactly one full block, so the tail path is skipped entirely.
    ubyte[16] exact16 = [
        9, 8, 7, 6, 5, 4, 3, 2,
        1, 2, 3, 4, 5, 6, 7, 8,
    ];
    static immutable ubyte[16] EXACT16 = [
        0xC2, 0xB0, 0xB9, 0xD0, 0x6F, 0x7D, 0x20, 0x0D,
        0x1B, 0x19, 0x9D, 0x75, 0x7E, 0xAD, 0x36, 0x40,
    ];
    assert(murmurBytes(exact16[]) == EXACT16);

    // Short tail: fewer than 8 bytes, so only k1 is mixed.
    ubyte[3] tiny = [1, 2, 3];
    static immutable ubyte[16] TINY3 = [
        0xA9, 0x37, 0x13, 0x0E, 0xEF, 0x3E, 0x64, 0x1A,
        0x65, 0x9A, 0x23, 0x3C, 0x40, 0x4A, 0x4E, 0x49,
    ];
    assert(murmurBytes(tiny[]) == TINY3);
}
