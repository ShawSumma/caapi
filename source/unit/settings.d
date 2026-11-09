module unit.settings;

import common.content.graph : ContentGraph;
import common.content.settings : MOD_KIND, parseOverrides, parseSettings;
import plugins.api.content : ContentRef;

enum string SAMPLE = "fog: 1.6\nkeep odds: [1, 0.62\n  0.72]\nlook: {\n    red: 0.035, tint: fog\n}\n# a remark\n\"quoted key\": \"a \\\"string\\\"\"\nfloor: base:silt\n";
enum string OVERRIDE = "caves: { fog: 2, look: { red: 0.5 } }\n";
enum string BROKEN = "fog: 1\nlook: { red 0.5 }\n";
enum double TOLERANCE = 1e-9;

bool isNear(double a, double b) {
    return a - b < TOLERANCE && b - a < TOLERANCE;
}

unittest {
    ContentGraph graph;
    graph.ownedBy("caves");
    ContentRef caves = graph.defineNode(MOD_KIND, "caves");
    parseSettings(graph, caves, SAMPLE, "caves");
    parseOverrides(graph, OVERRIDE, "settings.conf");
    graph.freeze();
    assert(isNear(graph.numberOf(caves, "fog").value, 2));
    assert(isNear(graph.numberOf(caves, "keep odds.1").value, 0.62));
    assert(isNear(graph.numberOf(caves, "keep odds.2").value, 0.72));
    assert(isNear(graph.numberOf(caves, "look.red").value, 0.5));
    assert(graph.textAt(caves, "look.tint") == "fog");
    assert(graph.textAt(caves, "quoted key") == "a \"string\"");
    assert(graph.textAt(caves, "floor") == "base:silt");
    graph.release();
}

unittest {
    ContentGraph graph;
    graph.ownedBy("caves");
    ContentRef caves = graph.defineNode(MOD_KIND, "caves");
    parseSettings(graph, caves, BROKEN, "caves");
    parseOverrides(graph, "nothing: { fog: 1 }", "settings.conf");
    assert(graph.problems.length == 2);
    assert(graph.problems.ptr[0].message == "caves, line 2: a setting needs a key, a colon and a value");
    graph.release();
}
