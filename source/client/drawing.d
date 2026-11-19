module client.drawing;

import geometry.lorentz : Motion;

enum uint MOST_VERTICES = 1 << 18;

struct ScreenPoint {
    float x;
    float y;
}

struct HudVertex {
    ScreenPoint at;
    uint color;
    uint texel;
}

struct Marker {
    Motion!float frame;
    float half;
    uint color;
}
