module common.graph_entities;

import common.graph : NodeId;

alias Entity = ulong;

struct GraphEntities {
    Entity[][NodeId] map;

    Entity[] get(NodeId node) {
        if (Entity[]* p = node in map) {
            return *p;
        }
        return [];
    }

    void insert(NodeId node, Entity entity) {
        map.require(node) ~= entity;
    }

    void remove(NodeId node, Entity entity) {
        Entity[]* p = node in map;
        assert(p !is null);
        Entity[] vec = *p;
        foreach (i, e; vec) {
            if (e == entity) {
                vec[i] = vec[$ - 1];
                (*p) = vec[0 .. $ - 1];
                if ((*p).length == 0) {
                    map.remove(node);
                }
                return;
            }
        }
        assert(false, "no such entity at this node");
    }
}
