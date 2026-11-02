module client.images;

import core.stdc.string : memcpy;
import base.numbers : higherOf, lowerOf;

enum int CHANGE_THRESHOLD = 8;
enum int DIFFERENCE_GAIN = 4;
enum uint COMPARED_CHANNELS = 3;
enum uint RGBA_BYTES = 4;
enum ubyte OPAQUE = 255;

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

enum PixelOrder : ubyte {
    rgba,
    bgra,
}

void copyAsRgba(ubyte[] rgba, const(ubyte)[] source, PixelOrder order) {
    memcpy(rgba.ptr, source.ptr, rgba.length);
    if (order == PixelOrder.bgra) {
        foreach (pixel; 0 .. rgba.length / RGBA_BYTES) {
            rgba[pixel * RGBA_BYTES] = source[pixel * RGBA_BYTES + 2];
            rgba[pixel * RGBA_BYTES + 2] = source[pixel * RGBA_BYTES];
        }
    }
}
