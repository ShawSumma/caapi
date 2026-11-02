module plugins.tower.plugin;

import plugins.api.api : Api, ENTRY, Look, NO_KIND, Registry, Site;
import box = plugins.box.box;
import plugins.turtle.turtle : Turtle;

enum int HEIGHT_EDGES = 3;
immutable Look LOOK = Look("tower");

void landmark(const(Api)* api, Site site, const(void)* data) {
    Turtle tower = Turtle(api, site).pitchUp();
    box.Palette palette = box.palette(tower);
    int top = box.top(tower, HEIGHT_EDGES);
    box.tower(tower, top, palette);
    box.door(tower);
    box.stairRoute(tower, 0, top);
}

void world(const(Api)* api, Site site, const(void)* data) {
    landmark(api, site, data);
    api.look(api, NO_KIND, &LOOK);
    Turtle(api, site).pitchUp().entrance(-box.HALF_WIDTH, 0, 1);
}

pragma(mangle, ENTRY) void plugin(const(Registry)* registry) {
    registry.add(registry, "tower", &world);
    registry.addLandmark(registry, "tower", &landmark);
}
