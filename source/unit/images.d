module unit.images;

import client.images : COMPARED_CHANNELS, ImageDifference, OPAQUE, RGBA_BYTES, copyAsRgba, differenceOf, writeDifference;

enum size_t PIXELS = 4;

unittest {
    ubyte[PIXELS * RGBA_BYTES] first = [10, 20, 30, 255, 0, 0, 0, 255, 200, 200, 200, 255, 50, 60, 70, 255];
    ubyte[PIXELS * RGBA_BYTES] second = [10, 20, 30, 0, 9, 0, 0, 255, 200, 100, 200, 255, 50, 60, 72, 255];
    ImageDifference difference = differenceOf(first[], second[], RGBA_BYTES, PIXELS);
    assert(difference.changed == 0.5 && difference.largestDelta == 100);
    assert(difference.meanDelta == (9.0 + 100 + 2) / (PIXELS * COMPARED_CHANNELS));
    ubyte[PIXELS * RGBA_BYTES] shown;
    writeDifference(shown[], first[], second[], RGBA_BYTES, PIXELS);
    assert(shown[4] == 36 && shown[9] == OPAQUE && shown[3] == OPAQUE && shown[0] == 0);
    ubyte[PIXELS * RGBA_BYTES] swapped;
    copyAsRgba(swapped[], first[], true);
    assert(swapped[0] == 30 && swapped[1] == 20 && swapped[2] == 10 && swapped[3] == 255);
}
