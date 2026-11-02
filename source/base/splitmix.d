module base.splitmix;

enum ulong SPLITMIX_INCREMENT = 0x9e3779b97f4a7c15;
enum ulong SPLITMIX_MULTIPLIER_1 = 0xbf58476d1ce4e5b9;
enum ulong SPLITMIX_MULTIPLIER_2 = 0x94d049bb133111eb;
enum uint ROLL_DISCARDED_BITS = 40;
enum float ROLL_RANGE = 1 << 24;
enum uint UNIT_DISCARDED_BITS = 11;
enum double UNIT_SCALE = 1.0 / (1UL << 53);

struct SplitMix {
    ulong state;

    ulong next() {
        state += SPLITMIX_INCREMENT;
        ulong z = state;
        z = (z ^ (z >> 30)) * SPLITMIX_MULTIPLIER_1;
        z = (z ^ (z >> 27)) * SPLITMIX_MULTIPLIER_2;
        return z ^ (z >> 31);
    }

    float roll() {
        return cast(float)(next() >> ROLL_DISCARDED_BITS) / ROLL_RANGE;
    }

    double unit() {
        return unitOf(next());
    }
}

double unitOf(ulong bits) {
    return cast(double)(bits >> UNIT_DISCARDED_BITS) * UNIT_SCALE;
}
