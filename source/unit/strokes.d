module unit.strokes;

import core.stdc.math : acoshf, fabsf;
import common.worldgen.strokes : Nearest, Stroke, StrokeForm;
import geometry.lorentz : Motion, Point, Vec4;
import plugins.api.api : Material;

enum double LENGTH = 0.8;
enum double SIDE = 0.3;
enum float TOLERANCE = 1e-4f;

unittest {
    Motion!double start = Motion!double.shift([0.2, -0.1, 0.3]);
    Stroke stroke = Stroke.make(start, LENGTH, 0.1f, 0.05f, Material.oakWood, StrokeForm.solid);
    Vec4!float beside = (start * Motion!double.shift([0, 0, LENGTH / 2]) * Motion!double.shift([SIDE, 0, 0]) * Point!double.origin()).v.as!float();
    Nearest middle = stroke.nearest(beside);
    assert(fabsf(acoshf(middle.coshDistance) - SIDE) < TOLERANCE && fabsf(middle.along - LENGTH / 2) < TOLERANCE);
    Vec4!float past = (start * Motion!double.shift([0, 0, LENGTH + SIDE]) * Point!double.origin()).v.as!float();
    Nearest end = stroke.nearest(past);
    assert(fabsf(acoshf(end.coshDistance) - SIDE) < TOLERANCE && end.along == stroke.length);
    Vec4!float behind = (start * Motion!double.shift([0, 0, -SIDE]) * Point!double.origin()).v.as!float();
    assert(fabsf(acoshf(stroke.nearest(behind).coshDistance) - SIDE) < TOLERANCE);
    assert(stroke.holds((start * Motion!double.shift([0.05, 0, 0.1]) * Point!double.origin()).v.as!float(), 0));
    assert(!stroke.holds(beside, 0));
}
