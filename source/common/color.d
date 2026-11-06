module common.color;

import core.stdc.math : cosf, sinf;
import base.numbers : lowerOf, sqrtAtCompileTime;
import base.units : Angle;

enum uint COLOR_CHANNELS = 5;
enum uint SEEN_CHANNELS = 3;
enum uint CHROMA_AXES = COLOR_CHANNELS - 1;
enum uint TURN_PLANES = CHROMA_AXES * (CHROMA_AXES - 1) / 2;

alias Spectrum = float[COLOR_CHANNELS];
alias Seen = float[SEEN_CHANNELS];

struct ColorTurn {
    Angle[TURN_PLANES] angles;
}

struct TurnPlane {
    uint first;
    uint second;
}

immutable Spectrum[CHROMA_AXES] CHROMA_BASIS = chromaBasis();
immutable TurnPlane[TURN_PLANES] TURN_PLANES_OF = turnPlanes();

Spectrum[CHROMA_AXES] chromaBasis() {
    Spectrum[CHROMA_AXES] basis;
    foreach (axis; 0 .. CHROMA_AXES) {
        Spectrum vector = -1.0f / COLOR_CHANNELS;
        vector[axis] += 1;
        foreach (previous; 0 .. axis) {
            float along = dotOf(vector, basis[previous]);
            foreach (channel; 0 .. COLOR_CHANNELS) {
                vector[channel] -= along * basis[previous][channel];
            }
        }
        float length = cast(float) sqrtAtCompileTime(dotOf(vector, vector));
        foreach (channel; 0 .. COLOR_CHANNELS) {
            basis[axis][channel] = vector[channel] / length;
        }
    }
    return basis;
}

TurnPlane[TURN_PLANES] turnPlanes() {
    TurnPlane[TURN_PLANES] planes;
    uint index = 0;
    foreach (first; 0 .. CHROMA_AXES) {
        foreach (second; first + 1 .. CHROMA_AXES) {
            planes[index] = TurnPlane(first, second);
            index += 1;
        }
    }
    return planes;
}

float dotOf(Spectrum a, Spectrum b) {
    float sum = 0;
    foreach (channel; 0 .. COLOR_CHANNELS) {
        sum += a[channel] * b[channel];
    }
    return sum;
}

float grayOf(Spectrum color) {
    float sum = 0;
    foreach (channel; color) {
        sum += channel;
    }
    return sum / COLOR_CHANNELS;
}

Spectrum spectrumOf(Seen linear) {
    float gray = (linear[0] + linear[1] + linear[2]) / SEEN_CHANNELS;
    return [linear[0], linear[1], linear[2], gray, gray];
}

Spectrum turned(Spectrum color, ColorTurn turn) {
    float gray = grayOf(color);
    float[CHROMA_AXES] chroma;
    foreach (axis; 0 .. CHROMA_AXES) {
        chroma[axis] = dotOf(color, CHROMA_BASIS[axis]);
    }
    foreach (index, plane; TURN_PLANES_OF) {
        float cosine = cosf(turn.angles[index].value);
        float sine = sinf(turn.angles[index].value);
        float first = chroma[plane.first];
        float second = chroma[plane.second];
        chroma[plane.first] = cosine * first - sine * second;
        chroma[plane.second] = sine * first + cosine * second;
    }
    Spectrum result = gray;
    foreach (axis; 0 .. CHROMA_AXES) {
        foreach (channel; 0 .. COLOR_CHANNELS) {
            result[channel] += chroma[axis] * CHROMA_BASIS[axis][channel];
        }
    }
    return result;
}

Seen seenOf(Spectrum color) {
    float gray = grayOf(color);
    Seen seen = [color[0], color[1], color[2]];
    float least = lowerOf(seen[0], lowerOf(seen[1], seen[2]));
    if (least < 0) {
        float kept = gray / (gray - least);
        foreach (ref channel; seen) {
            channel = gray + (channel - gray) * kept;
        }
    }
    return seen;
}
