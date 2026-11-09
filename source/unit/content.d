module unit.content;

import base.maybe : MaybeIndex;
import common.content.declarations : declare;
import common.content.graph : ContentGraph;
import plugins.api.content : ContentRef, Holder, Need;

enum string CRAFTING = "
type thing = item | tool
kind item {
    label: text?
}
kind tool {}
kind recipe {
    seconds: number 0.. = 1
    method: \"hand\" | \"forge\" = \"hand\"
    produces: one -> thing {
        yield: integer 1.. = 1
    }
    consumes: some -> item
}
kind book {
    teaches: one -> recipe
}
";

enum string EXTENSION = "
extend item {
    weight: number 0..
}
";

void define(ref ContentGraph graph) {
    graph.ownedBy("base");
    declare(graph, CRAFTING, "crafting");
}

unittest {
    ContentGraph graph;
    define(graph);
    ContentRef planks = graph.defineNode("recipe", "base:planks");
    ContentRef made = graph.defineEdge("produces", "base:planks", "base:wood-planks", Need.required);
    graph.setNumber(made, "yield", 4);
    graph.defineEdge("consumes", "base:planks", "base:log", Need.required);
    graph.defineNode("item", "base:wood-planks");
    graph.defineNode("item", "base:log");
    graph.defineNode("item", "base:stick");
    graph.setText(ContentRef(graph.nodeNamed("base:log").value, Holder.node), "label", "log");
    graph.ownedBy("more");
    graph.removeNode("base:stick");
    graph.defineNode("tool", "more:axe");
    graph.defineEdge("produces", "base:planks", "more:axe", Need.required);
    graph.removeEdges("produces", "base:planks", "more:axe");
    graph.freeze();
    assert(graph.problems.length == 0);
    assert(graph.countOf("item") == 2 && graph.countOf("recipe") == 1 && graph.countOf("tool") == 1);
    assert(graph.number(planks, "seconds") == 1);
    assert(graph.textAt(planks, "method") == "hand");
    const(uint)[] leaving = graph.edgesFrom(planks.index);
    assert(leaving.length == 2);
    assert(graph.number(ContentRef(leaving[0], Holder.edge), "yield") == 4);
    graph.release();
}

unittest {
    ContentGraph graph;
    define(graph);
    graph.defineNode("item", "base:glass");
    graph.defineNode("widget", "base:gear");
    ContentRef heavy = graph.defineNode("recipe", "base:heavy");
    graph.setNumber(heavy, "seconds", -2);
    graph.setText(heavy, "colour", "red");
    graph.defineEdge("produces", "base:heavy", "base:glass", Need.required);
    graph.defineEdge("consumes", "base:heavy", "base:glass", Need.required);
    graph.defineNode("recipe", "base:empty");
    graph.defineEdge("produces", "base:empty", "base:glass", Need.required);
    graph.defineNode("book", "base:tome");
    graph.defineEdge("teaches", "base:tome", "base:glass", Need.required);
    graph.defineEdge("melts", "base:glass", "base:glass", Need.required);
    declare(graph, "extend gadget { size: number }", "broken");
    graph.freeze();
    assert(graph.problems.length == 8);
    assert(graph.countOf("recipe") == 0 && graph.countOf("book") == 0 && graph.countOf("item") == 1);
    graph.release();
}

unittest {
    ContentGraph graph;
    define(graph);
    graph.defineNode("item", "base:bar");
    graph.ownedBy("space");
    graph.defineNode("recipe", "space:smelt");
    graph.defineEdge("produces", "space:smelt", "base:bar", Need.required);
    graph.defineEdge("consumes", "space:smelt", "space:ore", Need.optional);
    graph.defineNode("book", "space:manual");
    graph.defineEdge("teaches", "space:manual", "space:smelt", Need.optional);
    graph.freeze();
    assert(graph.problems.length == 0);
    assert(graph.countOf("recipe") == 0 && graph.countOf("book") == 0 && graph.countOf("item") == 1);
    graph.release();
}

unittest {
    ContentGraph graph;
    define(graph);
    declare(graph, EXTENSION, "extension");
    graph.defineNode("item", "base:bar");
    graph.defineNode("recipe", "base:smelt");
    graph.defineEdge("produces", "base:smelt", "base:bar", Need.required);
    graph.defineEdge("consumes", "base:smelt", "base:ore", Need.optional);
    graph.defineNode("book", "base:guide");
    graph.defineEdge("teaches", "base:guide", "base:smelt", Need.required);
    graph.freeze();
    assert(graph.problems.length == 3);
    assert(graph.countOf("recipe") == 0 && graph.countOf("book") == 0);
    graph.release();
}
