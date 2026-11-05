module unit.hud;

import client.hud : DiskPoint, onDisk;
import geometry.lorentz : Vec4;

unittest {
    DiskPoint here = onDisk(Vec4!float([0, 0, 0, 1]));
    assert(here.at.x == 0 && here.at.y == 0 && here.share == 1);
    DiskPoint far = onDisk(Vec4!float([99.995f, 0, 0, 100]));
    assert(far.at.x > 0.97f && far.at.x < 1.0f);
    assert(onDisk(Vec4!float([0, 50, 0, 50])).share == 0);
    assert(onDisk(Vec4!float([500, 0, 0, 500])).share == 0);
}
