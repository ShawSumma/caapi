module client.images;

import core.stdc.string : memcpy;
import base.numbers : higherOf, lowerOf;

enum int CHANGE_THRESHOLD = 8;
enum int DIFFERENCE_GAIN = 4;
enum uint COMPARED_CHANNELS = 3;
enum uint RGBA_BYTES = 4;
enum ubyte OPAQUE = 255;
enum size_t TEST_PIXELS = 4;

struct ImageDifference {
    double changed = 0;
    double meanDelta = 0;
    int largestDelta;
}

int channelDelta(ubyte a, ubyte b) {
    if (a > b) {
        return a - b;
    } else {
        return b - a;
    }
}

// Each pixel takes `stride` bytes in both images, of which the first three (red, green, blue) are compared. A pixel
// counts as changed when any of them moves by more than CHANGE_THRESHOLD.
ImageDifference differenceOf(const(ubyte)[] first, const(ubyte)[] second, uint stride, size_t pixels) {
    ImageDifference difference;
    size_t changed = 0;
    ulong total = 0;
    foreach (pixel; 0 .. pixels) {
        int largest = 0;
        foreach (channel; 0 .. COMPARED_CHANNELS) {
            int delta = channelDelta(first[pixel * stride + channel], second[pixel * stride + channel]);
            total += delta;
            largest = higherOf(delta, largest);
        }
        if (largest > CHANGE_THRESHOLD) {
            changed += 1;
        }
        difference.largestDelta = higherOf(largest, difference.largestDelta);
    }
    if (pixels > 0) {
        difference.changed = cast(double) changed / pixels;
        difference.meanDelta = cast(double) total / (pixels * COMPARED_CHANNELS);
    }
    return difference;
}

void writeDifference(ubyte[] rgba, const(ubyte)[] first, const(ubyte)[] second, uint stride, size_t pixels) {
    foreach (pixel; 0 .. pixels) {
        foreach (channel; 0 .. COMPARED_CHANNELS) {
            int delta = channelDelta(first[pixel * stride + channel], second[pixel * stride + channel]);
            rgba[pixel * RGBA_BYTES + channel] = cast(ubyte) lowerOf(delta * DIFFERENCE_GAIN, int(OPAQUE));
        }
        rgba[pixel * RGBA_BYTES + COMPARED_CHANNELS] = OPAQUE;
    }
}

void copyAsRgba(ubyte[] rgba, const(ubyte)[] source, bool isBgra) {
    memcpy(rgba.ptr, source.ptr, rgba.length);
    if (isBgra) {
        foreach (pixel; 0 .. rgba.length / RGBA_BYTES) {
            rgba[pixel * RGBA_BYTES] = source[pixel * RGBA_BYTES + 2];
            rgba[pixel * RGBA_BYTES + 2] = source[pixel * RGBA_BYTES];
        }
    }
}

unittest {
    ubyte[TEST_PIXELS * RGBA_BYTES] first = [10, 20, 30, 255, 0, 0, 0, 255, 200, 200, 200, 255, 50, 60, 70, 255];
    ubyte[TEST_PIXELS * RGBA_BYTES] second = [10, 20, 30, 0, 9, 0, 0, 255, 200, 100, 200, 255, 50, 60, 72, 255];
    ImageDifference difference = differenceOf(first[], second[], RGBA_BYTES, TEST_PIXELS);
    assert(difference.changed == 0.5 && difference.largestDelta == 100);
    assert(difference.meanDelta == (9.0 + 100 + 2) / (TEST_PIXELS * COMPARED_CHANNELS));
    ubyte[TEST_PIXELS * RGBA_BYTES] shown;
    writeDifference(shown[], first[], second[], RGBA_BYTES, TEST_PIXELS);
    assert(shown[4] == 36 && shown[9] == OPAQUE && shown[3] == OPAQUE && shown[0] == 0);
    ubyte[TEST_PIXELS * RGBA_BYTES] swapped;
    copyAsRgba(swapped[], first[], true);
    assert(swapped[0] == 30 && swapped[1] == 20 && swapped[2] == 10 && swapped[3] == 255);
}
