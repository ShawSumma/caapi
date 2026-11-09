module unit.binding;

import common.content.content : contentApi;
import common.content.data : loadData;
import common.content.declarations : declare;
import common.content.graph : ContentGraph;
import plugins.api.api : Material;
import plugins.api.binding : List, bound, kebabOf;
import plugins.api.content : Content;

enum string SHAPES = "
kind material {}
kind test-palette {
    wall: one -> material
    floor: optional -> material
}
kind test-style {
    size: integer 1.. = 3
    mood: \"calm\" | \"loud-noise\" = \"calm\"
    palettes: some -> test-palette
    main: one -> test-palette
}
";

enum string DATA = "
material test:air {}
material test:stone {}
material test:wood {}
test-palette test:one { wall -> test:stone }
test-palette test:two { wall -> test:wood, floor -> test:stone }
test-style test:style {
    mood: loud-noise
    palettes -> [test:one test:two test:one]
    main -> test:two
}
";

enum Material STONE = Material(1);
enum Material WOOD = Material(2);

enum Mood : ubyte {
    calm,
    loudNoise,
}

struct Palette {
    Material wall;
    Material floor;
}

struct Style {
    int size;
    Mood mood;
    List!(Palette, 2) palettes;
    Palette main;
}

struct Misnamed {
    int size;
    double colour;
}

struct Misshapen {
    Material size;
}

Content apiOver(ref ContentGraph graph) {
    Content api = contentApi();
    api.host = &graph;
    return api;
}

void define(ref ContentGraph graph) {
    graph.ownedBy("test");
    declare(graph, SHAPES, "shapes");
    loadData(graph, DATA, "data");
    graph.freeze();
    assert(graph.problems.length == 0);
}

unittest {
    static assert(kebabOf!"hallDoors" == "hall-doors");
    static assert(kebabOf!"colorTurn0" == "color-turn-0");
    static assert(kebabOf!"turn12" == "turn-12");
}

unittest {
    ContentGraph graph;
    define(graph);
    Content api = apiOver(graph);
    Style style = (&api).bound!Style("test:style");
    assert(style.size == 3);
    assert(style.mood == Mood.loudNoise);
    assert(style.palettes.count == 2);
    assert(style.palettes.items[0].wall == STONE && style.palettes.items[0].floor == Material.none);
    assert(style.palettes.items[1].wall == WOOD);
    assert(style.main.floor == STONE);
    assert(graph.problems.length == 1);
    graph.release();
}

unittest {
    ContentGraph graph;
    define(graph);
    Content api = apiOver(graph);
    Misnamed misnamed = (&api).bound!Misnamed("test:style");
    assert(misnamed.size == 3);
    assert(graph.problems.length == 1);
    (&api).bound!Misshapen("test:style");
    assert(graph.problems.length == 2);
    (&api).bound!Style("test:nothing");
    assert(graph.problems.length == 3);
    graph.release();
}
