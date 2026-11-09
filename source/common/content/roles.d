module common.content.roles;

import base.maybe : Maybe, MaybeIndex;
import base.stdio : printed;
import common.content.declarations : declare;
import common.content.graph : ContentGraph, ENGINE_OWNER, PROBLEM_CAPACITY, Standing;
import common.items : Item, ItemKind, itemOfNode;
import plugins.api.api : Material;
import plugins.api.binding : kebabOf;

enum string ROLE_KIND = "role";

enum Role : ubyte {
    beacon,
    collector,
    bench,
    mutagen,
}

enum uint ROLE_COUNT = Role.max + 1;

string[ROLE_COUNT] roleNames() {
    string[ROLE_COUNT] names;
    static foreach (index, member; __traits(allMembers, Role)) {
        names[index] = "engine:" ~ kebabOf!member;
    }
    return names;
}

immutable string[ROLE_COUNT] ROLE_NAMES = roleNames();

__gshared Maybe!Item[ROLE_COUNT] roleItems;

void defineRoles(ref ContentGraph graph) {
    foreach (name; ROLE_NAMES) {
        graph.defineNode(ROLE_KIND, name);
    }
}

enum string ROLE_DECLARATIONS = "content/roles.decl";

void declareRoles(ref ContentGraph graph) {
    declare(graph, import(ROLE_DECLARATIONS), ROLE_DECLARATIONS);
}

void buildRoles(ref ContentGraph graph) {
    char[PROBLEM_CAPACITY] buffer;
    foreach (index, ref edge; graph.edges.slice()) {
        if (edge.standing == Standing.kept && graph.isEdgeKind(cast(uint) index, "fills")) {
            MaybeIndex!uint known = roleNamed(graph.nameOf(edge.to));
            const(char)[] name = graph.nameOf(edge.to);
            if (!known.exists) {
                graph.report(edge.owner, printed(buffer[], "fills '%.*s', which no engine system uses", cast(int) name.length, name.ptr));
            } else if (roleItems[known.value].exists) {
                graph.report(edge.owner, printed(buffer[], "'%.*s' is filled twice", cast(int) name.length, name.ptr));
            } else {
                roleItems[known.value] = itemOfNode(edge.from);
            }
        }
    }
    foreach (role, item; roleItems) {
        if (!item.exists) {
            graph.report(graph.intern(ENGINE_OWNER), printed(buffer[], "no mod fills %s", ROLE_NAMES[role].ptr));
        }
    }
}

MaybeIndex!uint roleNamed(const(char)[] name) {
    uint index = 0;
    while (index < ROLE_COUNT && ROLE_NAMES[index] != name) {
        index += 1;
    }
    if (index < ROLE_COUNT) {
        return MaybeIndex!uint.of(index);
    } else {
        return MaybeIndex!uint.init;
    }
}

Material roleBlock(Role role) {
    if (roleItems[role].exists && roleItems[role].value.kind == ItemKind.block) {
        return roleItems[role].value.block;
    } else {
        return Material.none;
    }
}

Item roleItem(Role role) {
    if (roleItems[role].exists) {
        return roleItems[role].value;
    } else {
        return Item.init;
    }
}
