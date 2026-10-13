module plugins.tower.plugin;

import plugins.api.api : Api, ENTRY, Registry, Site;
import box = plugins.box.box;
import plugins.turtle.turtle : Turtle;

enum int HEIGHT_EDGES = 3;

void world(const(Api)* api, Site site, const(void)* data) {
    Turtle tower = Turtle(api, site).pitchUp();
    box.Palette palette = box.palette(tower);
    int top = box.top(tower, HEIGHT_EDGES);
    box.tower(tower, top, palette);
    box.door(tower);
    box.stairRoute(tower, 0, top);
    tower.entrance(-box.HALF_WIDTH, 0, 1);
}

pragma(mangle, ENTRY) void plugin(const(Registry)* registry) {
    registry.add(registry, "tower", &world);
}
