module common.look;

import base.maybe : Maybe, MaybeIndex;
import base.names : enumNamed;
import common.content.content : content;
import common.content.graph : ContentGraph;
import plugins.api.content : ContentRef, Holder;

enum string LOOK_KIND = "look";

enum Tint : ubyte {
    sky,
    fog,
}

struct Color {
    float red;
    float green;
    float blue;
}

struct Look {
    const(char)[] name;
    Color fog = Color(0, 0, 0);
    Tint tint;
}

Maybe!Look lookNamed(const(char)[] name) {
    const(ContentGraph)* graph = &content();
    MaybeIndex!uint node = graph.nodeNamed(name);
    if (!node.exists || !graph.isKind(node.value, LOOK_KIND)) {
        return Maybe!Look.init;
    } else {
        ContentRef at = ContentRef(node.value, Holder.node);
        Color fog = Color(graph.number(at, "red"), graph.number(at, "green"), graph.number(at, "blue"));
        return Maybe!Look.of(Look(graph.nameOf(node.value), fog, enumNamed!Tint(graph.textAt(at, "tint")).value));
    }
}
