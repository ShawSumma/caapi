module plugins.tower.plugin;

import plugins.api.api : Api, Registry, Site, entryOf;
import plugins.api.content : BASE, Dependency, FIRST_VERSION, Manifest, dependencyOn;
import box = plugins.box.box;
import plugins.turtle.turtle : Turtle;

enum int HEIGHT_EDGES = 3;
enum string LOOK = "base:sky";

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
    api.worldLook(api, LOOK);
    Turtle(api, site).pitchUp().entrance(-box.HALF_WIDTH, 0, 1);
}

immutable Dependency[2] NEEDS = [dependencyOn(BASE), dependencyOn("box")];
immutable Manifest MANIFEST = Manifest("tower", FIRST_VERSION, NEEDS[], null, &box.resolveBox);

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
    registry.addDebug(registry, "tower", &world);
    registry.addLandmark(registry, "tower", &landmark);
}
