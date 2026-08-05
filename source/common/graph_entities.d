module common.graph_entities;

import common.array : Array;
import common.graph : NodeId;
import common.hash_map : HashMap;

alias Entity = ulong;

struct GraphEntities {
    HashMap!(NodeId, Array!Entity) map;

    void release() {
        foreach (ref node, ref list; map) {
            list.release();
        }
        map.release();
    }

    const(Entity)[] get(NodeId node) {
        Array!Entity* list = node in map;
        if (list is null) {
            return null;
        }
        return list.slice();
    }

    void insert(NodeId node, Entity entity) {
        Array!Entity* list = map.require(node, Array!Entity.init);
        list.push(entity);
    }

    // Order is not preserved: the last entity is swapped into the gap.
    void remove(NodeId node, Entity entity) {
        Array!Entity* list = node in map;
        assert(list !is null, "no entities at this node");
        foreach (i; 0 .. list.length()) {
            if ((*list)[i] == entity) {
                (*list)[i] = (*list)[list.length() - 1];
                list.count = list.count - 1;
                if (list.empty()) {
                    list.release();
                    map.remove(node);
                }
                return;
            }
        }
        assert(false, "no such entity at this node");
    }
}
