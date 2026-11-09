module unit.data;

import base.maybe : MaybeIndex;
import common.content.data : loadData;
import common.content.declarations : declare;
import common.content.graph : ContentGraph;
import plugins.api.content : ContentRef, Holder;

enum string SHAPES = "
kind item {
    label: text?
    weight: number = 1
}
kind recipe {
    seconds: number 0..
    produces: one -> item {
        yield: integer 1.. = 1
    }
    consumes: some -> item
}
";

enum string DATA = "
item base:log { label: \"oak log\", weight: 2.5e1 }
item base:plank {}
item base:stick { weight: 0.5 }
item base:spare {}
remove base:spare
recipe base:planks {
    seconds: 3
    produces -> base:plank { yield: 4 }
    consumes -> [base:log base:stick base:spare]
}
unlink base:planks consumes -> base:spare
recipe base:dream {
    seconds: 1
    produces -> base:plank
    consumes ?-> more:stardust
}
";

enum string BROKEN = "
item base:log {}
item base:plank {
    weight 2
}
";

ContentRef nodeOf(ref ContentGraph graph, const(char)[] name) {
    MaybeIndex!uint found = graph.nodeNamed(name);
    return ContentRef(found.value, Holder.node);
}

unittest {
    ContentGraph graph;
    graph.ownedBy("base");
    declare(graph, SHAPES, "shapes");
    loadData(graph, DATA, "data");
    graph.freeze();
    assert(graph.problems.length == 0);
    assert(graph.countOf("item") == 3 && graph.countOf("recipe") == 1);
    assert(graph.textAt(graph.nodeOf("base:log"), "label") == "oak log");
    assert(graph.number(graph.nodeOf("base:log"), "weight") == 25);
    assert(graph.number(graph.nodeOf("base:plank"), "weight") == 1);
    ContentRef planks = graph.nodeOf("base:planks");
    assert(graph.number(planks, "seconds") == 3);
    const(uint)[] leaving = graph.edgesFrom(planks.index);
    assert(leaving.length == 3);
    assert(graph.number(ContentRef(leaving[0], Holder.edge), "yield") == 4);
    graph.release();
}

unittest {
    ContentGraph graph;
    graph.ownedBy("base");
    declare(graph, SHAPES, "shapes");
    loadData(graph, BROKEN, "broken");
    assert(graph.problems.length == 1);
    assert(graph.problems.ptr[0].message == "broken, line 4: an entry is 'key: value' or 'edge -> target'");
    graph.release();
}
