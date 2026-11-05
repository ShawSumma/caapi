module base64;

import base.array : Array;

enum string ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
enum char PADDING = '=';
enum uint BITS_PER_LETTER = 6;
enum uint BYTES_PER_GROUP = 3;
enum uint LETTERS_PER_GROUP = 4;
enum uint LETTER_MASK = 63;
enum uint BYTE_BITS = 8;
enum uint BYTE_MASK = 255;

void encodeInto(const(ubyte)[] bytes, ref Array!ubyte output) {
    size_t at = 0;
    while (at + BYTES_PER_GROUP <= bytes.length) {
        uint group = (bytes[at] << 2 * BYTE_BITS) | (bytes[at + 1] << BYTE_BITS) | bytes[at + 2];
        foreach (letter; 0 .. LETTERS_PER_GROUP) {
            output.append(ALPHABET[(group >> (LETTERS_PER_GROUP - 1 - letter) * BITS_PER_LETTER) & LETTER_MASK]);
        }
        at += BYTES_PER_GROUP;
    }
    size_t left = bytes.length - at;
    if (left > 0) {
        uint group = 0;
        foreach (index; 0 .. left) {
            group |= bytes[at + index] << (BYTES_PER_GROUP - 1 - index) * BYTE_BITS;
        }
        foreach (letter; 0 .. LETTERS_PER_GROUP) {
            if (letter <= left) {
                output.append(ALPHABET[(group >> (LETTERS_PER_GROUP - 1 - letter) * BITS_PER_LETTER) & LETTER_MASK]);
            } else {
                output.append(PADDING);
            }
        }
    }
}

uint valueOf(char letter) {
    uint value = 0;
    while (value < ALPHABET.length && ALPHABET[value] != letter) {
        value += 1;
    }
    return value;
}

void decodeInto(const(char)[] text, ref Array!ubyte output) {
    uint group = 0;
    uint bits = 0;
    foreach (letter; text) {
        if (letter != PADDING) {
            group = (group << BITS_PER_LETTER) | valueOf(letter);
            bits += BITS_PER_LETTER;
            if (bits >= BYTE_BITS) {
                bits -= BYTE_BITS;
                output.append(cast(ubyte)((group >> bits) & BYTE_MASK));
            }
        }
    }
}
