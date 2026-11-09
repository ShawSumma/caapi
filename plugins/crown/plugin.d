module plugins.crown.plugin;

import plugins.api.api : Api, Box, Material, Registry, Rhythm, Site, Span, entryOf;
import plugins.api.content : BASE, Dependency, FIRST_VERSION, Manifest, dependencyOn;
import box = plugins.box.box;
import plugins.turtle.turtle : Along, FACE_CORNERS, Turtle, boxOf, cornersOf, upright;

enum string LOOK = "base:sky";
enum int HEIGHT_EDGES = 2;
enum int HALL_ROOF = 2 * box.STORY;
enum int HALL_WINDOW_OFFSET = 2;
enum int FIRST_BALCONY_STORY = 3;
enum int BALCONY_DEPTH = 2;
enum int BALCONY_WIDTH = 4;
enum float ARCH_STOP_CELLS = box.STORY;
enum size_t MOST_ARCH_STOPS = 16;

Box strip(Along along, int from, int to, int low, int high) {
    if (along == Along.x) {
        return boxOf(Span(from, to), Span(0, 0), Span(low, high));
    } else {
        return boxOf(Span(0, 0), Span(from, to), Span(low, high));
    }
}

void hallWall(Turtle tower, box.Palette palette, Along along) {
    int far = tower.column().high;
    int window = box.HALF_WIDTH + HALL_WINDOW_OFFSET;
    tower.paint(palette.wall, strip(along, 0, far, 0, HALL_ROOF));
    tower.paint(palette.trim, strip(along, 0, far, 0, HALL_ROOF), box.FLOORS);
    tower.paint(Material.none, strip(along, window, window + box.WINDOW_WIDTH - 1, 0, HALL_ROOF - 1), box.WINDOW_ROW);
}

void hallDoor(Turtle tower, Along along) {
    int far = tower.column().high;
    tower.paint(Material.none, strip(along, far, far, 1, box.DOOR));
}

void hall(Turtle tower, box.Palette palette) {
    Span inside = Span(0, tower.column().high);
    tower.paint(palette.wall, boxOf(inside, inside, Span(-box.FOUNDATION, -1)));
    tower.paint(palette.floor, boxOf(inside, inside, Span(0, HALL_ROOF)), box.FLOORS);
    tower.paint(Material.none, boxOf(inside, inside, Span(0, HALL_ROOF - 1)), box.ROOMS);
    hallWall(tower, palette, Along.x);
    hallWall(tower, palette, Along.y);
}

void openToHall(Turtle tower, box.Palette palette) {
    Span quarter = Span(0, box.HALF_WIDTH - 1);
    tower.paint(palette.floor, boxOf(quarter, quarter, Span(0, HALL_ROOF)), box.FLOORS);
    tower.paint(Material.none, boxOf(quarter, quarter, Span(0, HALL_ROOF - 1)), box.ROOMS);
}

void doors(Turtle tower) {
    Span face = Span(box.HALF_WIDTH - 1, box.HALF_WIDTH - 1);
    Span terrace = Span(HALL_ROOF + 1, HALL_ROOF + box.DOOR);
    Span bridge = Span(tower.edgeCells() + 1, tower.edgeCells() + box.DOOR);
    tower.paint(Material.none, boxOf(face, Span(1, 2), terrace));
    tower.paint(Material.none, boxOf(Span(1, 2), face, terrace));
    tower.paint(Material.none, boxOf(face, Span(-1, 0), bridge));
    tower.paint(Material.none, boxOf(Span(-1, 0), face, bridge));
}

Box onFace(Along along, Span outward, Span sideways, Span heights) {
    if (along == Along.x) {
        return boxOf(outward, sideways, heights);
    } else {
        return boxOf(sideways, outward, heights);
    }
}

void balcony(Turtle tower, box.Palette palette, Along along, int sideLow, int story, int top) {
    int everyOtherStory = 2 * box.STORY;
    int floor = (story % 2) * box.STORY;
    Span heights = Span(story * box.STORY, top - 1);
    Box slab = onFace(along, Span(-box.HALF_WIDTH - BALCONY_DEPTH, -box.HALF_WIDTH - 1), Span(sideLow, sideLow + BALCONY_WIDTH - 1), heights);
    Box door = onFace(along, Span(-box.HALF_WIDTH, -box.HALF_WIDTH), Span(sideLow + 1, sideLow + BALCONY_WIDTH - 2), heights);
    tower.paint(palette.floor, slab, Rhythm(everyOtherStory, floor, 1));
    tower.paint(Material.none, door, Rhythm(everyOtherStory, floor + 1, box.DOOR));
}

void balconies(Turtle tower, box.Palette palette, int top) {
    balcony(tower, palette, Along.x, -2, FIRST_BALCONY_STORY, top);
    balcony(tower, palette, Along.y, -1, FIRST_BALCONY_STORY + 1, top);
}

Turtle bridgeAhead(Turtle corner) {
    return corner.pitchUp().forward(1).pitchDown();
}

Turtle bridgeBehind(Turtle corner) {
    return bridgeAhead(corner).right();
}

void deck(Turtle bridge, box.Palette palette) {
    bridge.paint(palette.floor, boxOf(Span(-1, 0), Span(0, 0), Span(box.HALF_WIDTH, bridge.edgeCells())));
}

void archRoute(Turtle from, Turtle to) {
    float apex = from.edgeCells() - 0.5f;
    float[MOST_ARCH_STOPS] stops;
    size_t count = 0;
    float along = box.HALF_WIDTH + 0.5f;
    while (along < apex) {
        stops[count] = along;
        count += 1;
        along += ARCH_STOP_CELLS;
    }
    stops[count] = apex;
    count += 1;
    foreach (index; 0 .. count) {
        from.stop(box.ROUTE_LANE, 1, stops[index]);
    }
    foreach_reverse (index; 0 .. count) {
        to.stop(box.ROUTE_LANE, 1, stops[index]);
    }
}

void landmark(const(Api)* api, Site root, const(void)* data) {
    Turtle site = Turtle(api, root);
    box.Palette palette = box.palette(site);
    int top = box.top(site, HEIGHT_EDGES);
    int bridgeFloor = site.edgeCells();
    Turtle[FACE_CORNERS] corners = cornersOf(site);
    foreach (index, corner; corners) {
        Turtle tower = upright(corner);
        hall(tower, palette);
        if (index == 0) {
            hallDoor(tower, Along.x);
        } else if (index == 1) {
            hallDoor(tower, Along.y);
        }
        box.tower(tower, top, palette);
        openToHall(tower, palette);
        doors(tower);
        balconies(tower, palette, top);
        deck(bridgeAhead(corner), palette);
        deck(bridgeBehind(corner), palette);
    }
    Turtle first = upright(corners[0]);
    Turtle second = upright(corners[1]);
    box.stairRoute(first, 0, bridgeFloor);
    first.stop(box.HALF_WIDTH - 1.5f, box.ROUTE_LANE, bridgeFloor + 1);
    first.stop(box.HALF_WIDTH + 0.5f, box.ROUTE_LANE, bridgeFloor + 1);
    archRoute(bridgeAhead(corners[0]), bridgeBehind(corners[1]));
    second.stop(box.ROUTE_LANE, box.HALF_WIDTH - 1.5f, bridgeFloor + 1);
    second.stop(box.ROUTE_LANE, box.ROUTE_LANE, bridgeFloor + 1);
    box.stairRoute(second, bridgeFloor, top);
}

void world(const(Api)* api, Site root, const(void)* data) {
    Turtle site = Turtle(api, root);
    landmark(api, root, data);
    api.worldLook(api, LOOK);
    site.entrance(0, 1, site.edgeCells() / 2);
}

immutable Dependency[2] NEEDS = [dependencyOn(BASE), dependencyOn("box")];
immutable Manifest MANIFEST = Manifest("crown", FIRST_VERSION, NEEDS[], null, &box.resolveBox);

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
    registry.add(registry, "crown", &world);
    registry.addLandmark(registry, "crown", &landmark);
}
