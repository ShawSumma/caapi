module plugins.crafting.roles;

import base.maybe : Maybe;
import base.stdio : printed;
import common.content.graph : ContentGraph, PROBLEM_CAPACITY;
import plugins.crafting.items : Item, itemOfNode;

enum string ROLE_KIND = "role";
enum string FILLS = "fills";

Item fillerOf(ref ContentGraph graph, const(char)[] role) {
    Item filler;
    uint fillers = 0;
    foreach (edge; graph.edgesTo(graph.nodeNamed(role).value)) {
        Maybe!Item item = itemOfNode(graph.edges.ptr[edge].from);
        if (graph.isEdgeKind(edge, FILLS) && item.exists) {
            filler = item.value;
            fillers += 1;
        }
    }
    if (fillers != 1) {
        char[PROBLEM_CAPACITY] buffer;
        graph.report(graph.owner, printed(buffer[], "%u items fill '%.*s', and exactly one must", fillers, cast(int) role.length, role.ptr));
    }
    return filler;
}
