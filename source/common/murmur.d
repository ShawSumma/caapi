module common.murmur;

enum ulong MURMUR_C1 = 0x87c37b91114253d5;
enum ulong MURMUR_C2 = 0x4cf5ad432745937f;
enum ulong MURMUR_FINAL_MULTIPLIER_1 = 0xff51afd7ed558ccd;
enum ulong MURMUR_FINAL_MULTIPLIER_2 = 0xc4ceb9fe1a85ec53;
enum ulong MURMUR_H1_OFFSET = 0x52dce729;
enum ulong MURMUR_H2_OFFSET = 0x38495ab5;
enum size_t MURMUR_BLOCK_BYTES = 16;

ulong rotateLeft(ulong value, uint amount) {
    return (value << amount) | (value >> (64 - amount));
}

ulong finalMix(ulong value) {
    ulong k = value;
    k ^= k >> 33;
    k *= MURMUR_FINAL_MULTIPLIER_1;
    k ^= k >> 33;
    k *= MURMUR_FINAL_MULTIPLIER_2;
    k ^= k >> 33;
    return k;
}

ulong readLittleEndian(const(ubyte)[] data, size_t offset, size_t count) {
    ulong result = 0;
    foreach (i; 0 .. count) {
        result |= cast(ulong) data[offset + i] << (i * 8);
    }
    return result;
}

ulong mixK1(ulong value) {
    ulong k = value * MURMUR_C1;
    k = rotateLeft(k, 31);
    return k * MURMUR_C2;
}

ulong mixK2(ulong value) {
    ulong k = value * MURMUR_C2;
    k = rotateLeft(k, 33);
    return k * MURMUR_C1;
}

ulong[2] murmurHash3(const(ubyte)[] data) {
    ulong h1 = 0;
    ulong h2 = 0;
    size_t blockCount = data.length / MURMUR_BLOCK_BYTES;
    foreach (block; 0 .. blockCount) {
        size_t offset = block * MURMUR_BLOCK_BYTES;
        h1 ^= mixK1(readLittleEndian(data, offset, 8));
        h1 = rotateLeft(h1, 27);
        h1 += h2;
        h1 = h1 * 5 + MURMUR_H1_OFFSET;
        h2 ^= mixK2(readLittleEndian(data, offset + 8, 8));
        h2 = rotateLeft(h2, 31);
        h2 += h1;
        h2 = h2 * 5 + MURMUR_H2_OFFSET;
    }
    size_t tailOffset = blockCount * MURMUR_BLOCK_BYTES;
    size_t tailLength = data.length - tailOffset;
    if (tailLength > 8) {
        h2 ^= mixK2(readLittleEndian(data, tailOffset + 8, tailLength - 8));
    }
    if (tailLength > 0) {
        size_t lowLength = tailLength;
        if (lowLength > 8) {
            lowLength = 8;
        }
        h1 ^= mixK1(readLittleEndian(data, tailOffset, lowLength));
    }
    h1 ^= data.length;
    h2 ^= data.length;
    h1 += h2;
    h2 += h1;
    h1 = finalMix(h1);
    h2 = finalMix(h2);
    h1 += h2;
    h2 += h1;
    ulong[2] result = [h1, h2];
    return result;
}
